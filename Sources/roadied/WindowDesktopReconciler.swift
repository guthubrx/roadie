import Foundation
import CoreGraphics
import RoadieCore
import RoadieDesktops
import RoadieStagePlugin

/// SPEC-021 T046 — Tracker périodique du desktop macOS courant des wids tileables.
/// Détecte les déplacements via Mission Control natif (Cmd+drag) qui ne génèrent
/// pas d'event AX dédié. Réattribue la wid au scope correct si drift détecté.
/// Pattern : poll toutes les `pollIntervalMs` ms (default 2000, configurable).
/// Debounce : exige 2 polls consécutifs avec le même osScope divergent avant d'agir.
/// Note : DesktopRegistry est un actor — tous les accès à scopeForSpaceID sont await.

@MainActor
public final class WindowDesktopReconciler {
    private weak var registry: WindowRegistry?
    private weak var desktopRegistry: DesktopRegistry?
    private weak var stageManager: StageManager?
    private let pollIntervalMs: Int
    private var task: Task<Void, Never>?

    /// Debounce : wid → scope OS observé lors du dernier poll divergent.
    private var pendingMigrations: [WindowID: (displayUUID: String, desktopID: Int)] = [:]

    public init(
        registry: WindowRegistry,
        desktopRegistry: DesktopRegistry,
        stageManager: StageManager,
        pollIntervalMs: Int
    ) {
        self.registry = registry
        self.desktopRegistry = desktopRegistry
        self.stageManager = stageManager
        self.pollIntervalMs = pollIntervalMs
    }

    public func start() {
        guard pollIntervalMs > 0 else {
            logInfo("window_desktop_reconciler_disabled", ["reason": "poll_ms_zero"])
            return
        }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollIntervalMs) * 1_000_000)
                await self.tick()
            }
        }
        logInfo("window_desktop_reconciler_started", ["poll_ms": String(pollIntervalMs)])
    }

    public func stop() {
        task?.cancel()
        task = nil
        logInfo("window_desktop_reconciler_stopped")
    }

    private func tick() async {
        guard let registry = registry,
              let desktopRegistry = desktopRegistry,
              let stageManager = stageManager else { return }

        let windows = registry.allWindows.filter { $0.isTileable && !$0.isMinimized }
        for state in windows {
            await processWindow(state, desktopRegistry: desktopRegistry, stageManager: stageManager)
        }
    }

    private func processWindow(
        _ state: WindowState,
        desktopRegistry: DesktopRegistry,
        stageManager: StageManager
    ) async {
        let wid = state.cgWindowID
        guard let osSpaceID = SkyLightBridge.currentSpaceID(for: wid) else {
            pendingMigrations.removeValue(forKey: wid)
            return
        }
        // DesktopRegistry est un actor : await obligatoire.
        guard let osScope = await desktopRegistry.scopeForSpaceID(osSpaceID) else { return }
        guard let persistedScope = stageManager.scopeOf(wid: wid) else { return }

        let driftDetected = osScope.displayUUID != persistedScope.displayUUID
            || osScope.desktopID != persistedScope.desktopID
        guard driftDetected else {
            pendingMigrations.removeValue(forKey: wid)
            return
        }
        // Debounce : confirmer sur 2 cycles consécutifs avant de migrer.
        if let pending = pendingMigrations[wid],
           pending.displayUUID == osScope.displayUUID && pending.desktopID == osScope.desktopID {
            let targetScope = StageScope(
                displayUUID: osScope.displayUUID,
                desktopID: osScope.desktopID,
                stageID: persistedScope.stageID
            )
            stageManager.assign(wid: wid, to: targetScope)
            pendingMigrations.removeValue(forKey: wid)
            logInfo("wid_desktop_migrated", [
                "wid": String(wid),
                "from": "\(persistedScope.displayUUID):\(persistedScope.desktopID)",
                "to": "\(osScope.displayUUID):\(osScope.desktopID)",
            ])
        } else {
            pendingMigrations[wid] = (osScope.displayUUID, osScope.desktopID)
        }
    }
}
