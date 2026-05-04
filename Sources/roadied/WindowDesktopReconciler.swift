import Foundation
import CoreGraphics
import AppKit
import RoadieCore
import RoadieDesktops
import RoadieStagePlugin
import RoadieTiler

/// SPEC-022 — Integrity checker périodique. Refactor de l'ancien
/// `WindowDesktopReconciler` (SPEC-021 T046) qui faisait un re-étiquetage
/// SkyLight automatique → contredisait le modèle utilisateur (étiquette
/// pilotée par actions explicites). Cette nouvelle version :
///
/// - NE re-étiquette PAS via SkyLight (= pas d'effet de bord parasite)
/// - Détecte et auto-corrige les drifts purement techniques :
///   1. Frame degenerate (height ou width < 100) — AX a reporté une valeur
///      absurde. Retry CGWindowList et corriger ; sinon laisser tel quel.
///   2. Wid avec scope actif mais frame offscreen — applyAll a probablement
///      raté son setBounds. Re-trigger applyLayout pour corriger.
///   3. BSP tree leaf dans un display tree ≠ son scope.displayUUID — la wid
///      a glissé. Remove du mauvais tree, insert dans le bon.
///
/// Tick : `pollIntervalMs` ms (default 2000). Chaque drift détecté est loggué
/// (compteur + premier exemple). Au boot, un check initial est lancé.
@MainActor
public final class WindowDesktopReconciler {
    private weak var registry: WindowRegistry?
    private weak var desktopRegistry: DesktopRegistry?
    private weak var stageManager: StageManager?
    private weak var layoutEngine: LayoutEngine?
    private weak var displayRegistry: DisplayRegistry?
    private let pollIntervalMs: Int
    private var task: Task<Void, Never>?
    /// Closure pour déclencher applyLayout sans dépendance circulaire vers Daemon.
    public var applyLayoutCallback: (@MainActor () -> Void)?

    public init(
        registry: WindowRegistry,
        desktopRegistry: DesktopRegistry,
        stageManager: StageManager,
        layoutEngine: LayoutEngine? = nil,
        displayRegistry: DisplayRegistry? = nil,
        pollIntervalMs: Int
    ) {
        self.registry = registry
        self.desktopRegistry = desktopRegistry
        self.stageManager = stageManager
        self.layoutEngine = layoutEngine
        self.displayRegistry = displayRegistry
        self.pollIntervalMs = pollIntervalMs
    }

    public func start() {
        guard pollIntervalMs > 0 else {
            logInfo("integrity_checker_disabled", ["reason": "poll_ms_zero"])
            return
        }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollIntervalMs) * 1_000_000)
                await self.tick(autoFix: true)
            }
        }
        logInfo("integrity_checker_started", ["poll_ms": String(pollIntervalMs)])
    }

    public func stop() {
        task?.cancel()
        task = nil
        logInfo("integrity_checker_stopped")
    }

    /// Exposé pour `daemon audit --fix` ou tests. Retourne le nb de drifts
    /// détectés (et corrigés si autoFix=true).
    @discardableResult
    public func runIntegrityCheck(autoFix: Bool) async -> IntegrityReport {
        return await tick(autoFix: autoFix)
    }

    public struct IntegrityReport: Sendable {
        public var degenerateFrames: Int = 0
        public var offscreenWithActiveScope: Int = 0
        public var treeLeafWrongDisplay: Int = 0
        /// SPEC-025 BUG-002 — wid member d'une stage du display A mais sa frame
        /// physique est on-screen sur le display B. Drift causé typiquement
        /// par un cross-display warp qui ne met pas à jour le memberWindows.
        public var memberOnWrongDisplay: Int = 0
        public var fixedCount: Int { degenerateFrames + offscreenWithActiveScope + treeLeafWrongDisplay + memberOnWrongDisplay }
    }

    @discardableResult
    private func tick(autoFix: Bool) async -> IntegrityReport {
        var report = IntegrityReport()
        guard let registry = registry,
              let stageManager = stageManager else { return report }

        let windows = registry.allWindows
        let displays: [Display] = await {
            guard let dReg = displayRegistry else { return [] }
            return await dReg.displays
        }()

        // CHECK 1 — frame degenerate (height ou width < 100).
        let minDim = WindowState.minimumUsefulDimension
        for state in windows {
            let frame = state.frame
            guard frame.size.height < minDim || frame.size.width < minDim else { continue }
            // Ignorer les wids floating (NSPanel, popovers, dialogs natifs).
            guard !state.isFloating else { continue }
            report.degenerateFrames += 1
            if autoFix, let cg = liveCGBoundsLocal(for: state.cgWindowID),
               cg.size.height >= minDim && cg.size.width >= minDim {
                registry.updateFrame(state.cgWindowID, frame: cg)
                logInfo("integrity_fix_degenerate_frame", [
                    "wid": String(state.cgWindowID),
                    "old": "\(Int(frame.size.width))x\(Int(frame.size.height))",
                    "new": "\(Int(cg.size.width))x\(Int(cg.size.height))",
                ])
            }
        }

        // CHECK 2 — wids scope-actives mais physiquement offscreen.
        // Pour chaque wid, son scope dit (display, desktop, stage). Si stage
        // est l'active du (display, desktop), la wid devrait être visible sur
        // ce display. Si frame est offscreen → drift, re-trigger applyAll.
        var displayNeedsRetile = Set<CGDirectDisplayID>()
        for state in windows {
            guard state.isTileable, !state.isMinimized else { continue }
            guard let scope = stageManager.scopeOf(wid: state.cgWindowID) else { continue }
            // Stage active de ce scope ?
            let key = DesktopKey(displayUUID: scope.displayUUID, desktopID: scope.desktopID)
            guard let activeStage = stageManager.activeStageByDesktop[key],
                  activeStage == scope.stageID else { continue }
            // Display match ?
            guard let display = displays.first(where: { $0.uuid == scope.displayUUID }) else { continue }
            // La frame est-elle dans la zone visible de ce display ?
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            let onTargetDisplay = display.frame.contains(center)
            if !onTargetDisplay {
                report.offscreenWithActiveScope += 1
                displayNeedsRetile.insert(display.id)
                logInfo("integrity_drift_offscreen_active", [
                    "wid": String(state.cgWindowID),
                    "scope": "\(scope.displayUUID):\(scope.desktopID):\(scope.stageID.value)",
                    "frame_center": "\(Int(center.x)),\(Int(center.y))",
                ])
            }
        }
        if autoFix && !displayNeedsRetile.isEmpty {
            applyLayoutCallback?()
        }

        // CHECK 3 — leafs de tree dans le mauvais display.
        if let engine = layoutEngine {
            for (key, root) in engine.workspace.rootsByStageDisplay {
                for leaf in root.allLeaves {
                    let wid = leaf.windowID
                    guard let scope = stageManager.scopeOf(wid: wid) else { continue }
                    // Compare leaf's display avec wid's scope.displayUUID
                    guard let display = displays.first(where: { $0.id == key.displayID }),
                          display.uuid != scope.displayUUID else { continue }
                    // Mismatch
                    report.treeLeafWrongDisplay += 1
                    logInfo("integrity_drift_leaf_wrong_display", [
                        "wid": String(wid),
                        "tree_display": String(key.displayID),
                        "scope_display_uuid": scope.displayUUID,
                        "tree_stage": key.stageID.value,
                    ])
                    if autoFix {
                        engine.removeWindow(wid)
                        // Trouver le display ID cible depuis displayUUID
                        if let target = displays.first(where: { $0.uuid == scope.displayUUID }) {
                            engine.insertWindow(wid, focusedID: nil, displayID: target.id)
                        }
                    }
                }
            }
        }

        // CHECK 4 (SPEC-025 BUG-002) — wid member d'une stage du display A
        // mais frame physique on-screen sur le display B. Cas observé avec le
        // bug warp_cross_display_edge où LayoutEngine.warp ne met pas à jour
        // stageManager.memberWindows. Différent du CHECK 2 (qui détecte les
        // frames OFFSCREEN) : ici la frame est ON-screen, juste sur le mauvais
        // display. Fix : ré-étiqueter le scope vers le display physique.
        if let dReg = desktopRegistry, !displays.isEmpty {
            for state in windows {
                guard state.isTileable, !state.isMinimized else { continue }
                guard let scope = stageManager.scopeOf(wid: state.cgWindowID) else { continue }
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                // Display physique : celui qui contient le centre de la frame.
                guard let physicalDisplay = displays.first(where: { $0.frame.contains(center) }) else {
                    continue  // frame offscreen : déjà géré par CHECK 2
                }
                guard physicalDisplay.uuid != scope.displayUUID else { continue }
                report.memberOnWrongDisplay += 1
                logInfo("integrity_drift_member_wrong_display", [
                    "wid": String(state.cgWindowID),
                    "scope_display_uuid": scope.displayUUID,
                    "physical_display_uuid": physicalDisplay.uuid,
                    "frame_center": "\(Int(center.x)),\(Int(center.y))",
                ])
                if autoFix {
                    let mode = await dReg.mode
                    let targetDeskID: Int = (mode == .perDisplay)
                        ? await dReg.currentID(for: physicalDisplay.id)
                        : await dReg.currentID
                    let key = DesktopKey(displayUUID: physicalDisplay.uuid,
                                          desktopID: targetDeskID)
                    let activeStage = stageManager.activeStageByDesktop[key] ?? StageID("1")
                    let targetScope = StageScope(displayUUID: physicalDisplay.uuid,
                                                  desktopID: targetDeskID,
                                                  stageID: activeStage)
                    if stageManager.stagesV2[targetScope] == nil {
                        _ = stageManager.createStage(id: activeStage,
                                                     displayName: activeStage.value,
                                                     scope: targetScope)
                    }
                    stageManager.assign(wid: state.cgWindowID, to: targetScope)
                    registry.update(state.cgWindowID) { $0.desktopID = targetDeskID }
                    try? await dReg.updateWindowDisplayUUID(
                        cgwid: UInt32(state.cgWindowID),
                        desktopID: targetDeskID,
                        displayUUID: physicalDisplay.uuid)
                    EventBus.shared.publish(DesktopEvent(
                        name: "window_assigned",
                        payload: ["wid": String(state.cgWindowID),
                                  "stage_id": activeStage.value,
                                  "display_uuid": physicalDisplay.uuid,
                                  "desktop_id": String(targetDeskID),
                                  "source": "integrity_check"]))
                }
            }
        }

        if report.fixedCount > 0 {
            logInfo("integrity_check_summary", [
                "degenerate_frames": String(report.degenerateFrames),
                "offscreen_active": String(report.offscreenWithActiveScope),
                "leaf_wrong_display": String(report.treeLeafWrongDisplay),
                "member_wrong_display": String(report.memberOnWrongDisplay),
                "auto_fix": String(autoFix),
            ])
        }
        return report
    }

    /// Helper : query CGWindowList pour les bounds réels d'une wid.
    /// Coords système (origin top-left), on les retourne telles quelles
    /// — match les coords AX de `state.frame`.
    private func liveCGBoundsLocal(for wid: WindowID) -> CGRect? {
        guard let arr = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in arr {
            guard let n = info[kCGWindowNumber as String] as? WindowID, n == wid else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
        return nil
    }
}
