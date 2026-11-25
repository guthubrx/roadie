import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 167 — Onglets universels par slot (`scrolling`, `masterStack`, `bsp`) & fiabilisation
/// du premier placement pré-AX des applications lentes.
@Suite(.serialized)
struct Spec167UniversalTabsTests {
    private final class SpyWriter: WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        var writtenFrames: [WindowID: CGRect] = [:]
        var focusedWindowIDs: [WindowID] = []
        var unreadableIDs: Set<WindowID> = []
        var failWriteIDs: Set<WindowID> = []
        var onWrite: (@Sendable (WindowID, CGRect) -> Void)?

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            let callback: (@Sendable (WindowID, CGRect) -> Void)? = lock.withLock {
                if failWriteIDs.contains(window.id) { return nil }
                writtenFrames[window.id] = frame
                return onWrite
            }
            if lock.withLock({ failWriteIDs.contains(window.id) }) { return nil }
            callback?(window.id, frame)
            return frame
        }

        func readFrame(of window: WindowSnapshot) -> CGRect? {
            lock.withLock {
                if unreadableIDs.contains(window.id) { return nil }
                return writtenFrames[window.id] ?? window.frame.cgRect
            }
        }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock { focusedWindowIDs.append(window.id) }
            return true
        }

        func lastFocused() -> WindowID? {
            lock.withLock { focusedWindowIDs.last }
        }

        func lastFrame(for id: WindowID) -> CGRect? {
            lock.withLock { writtenFrames[id] }
        }
    }

    private final class MutableProvider: SystemSnapshotProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var displaysStorage: [DisplaySnapshot]
        private var windowsStorage: [WindowSnapshot]
        private var focusedStorage: WindowID?

        init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID?) {
            self.displaysStorage = displays
            self.windowsStorage = windows
            self.focusedStorage = focused
        }

        func setFocused(_ id: WindowID?) { lock.withLock { focusedStorage = id } }
        func setWindows(_ windows: [WindowSnapshot]) { lock.withLock { windowsStorage = windows } }
        func updateFrame(_ id: WindowID, to rect: Rect) {
            lock.withLock {
                if let idx = windowsStorage.firstIndex(where: { $0.id == id }) {
                    windowsStorage[idx].frame = rect
                }
            }
        }

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }

        func displays() -> [DisplaySnapshot] { lock.withLock { displaysStorage } }
        func windows() -> [WindowSnapshot] { lock.withLock { windowsStorage } }
        func focusedWindowID() -> WindowID? { lock.withLock { focusedStorage } }
    }

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec167-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func display(_ id: String = "d1", x: Double = 0, y: Double = 0, width: Double = 1600, height: Double = 900) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: 1,
            name: "Display \(id)",
            frame: Rect(x: x, y: y, width: width, height: height),
            visibleFrame: Rect(x: x, y: y + 30, width: width, height: height - 30),
            isMain: id == "d1"
        )
    }

    private func window(_ id: UInt32, app: String = "App", title: String = "Win", x: Double = 100, y: Double = 60, width: Double = 600, height: Double = 600) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: Int32(500 + id),
            appName: app,
            bundleID: "com.example.\(app.lowercased())",
            title: title,
            frame: Rect(x: x, y: y, width: width, height: height),
            isOnScreen: true,
            isTileCandidate: true,
            furniture: nil
        )
    }

    // MARK: - 1. LayoutTabSlots pur (`scrolling`, `masterStack`, `bsp`)

    @Test func layoutTabSlotsSupportsScrollingMasterStackAndBspWithBarReserve() throws {
        let scope = StageScope(displayID: DisplayID(rawValue: "d1"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let w1 = WindowID(rawValue: 1)
        let w2 = WindowID(rawValue: 2)
        let w3 = WindowID(rawValue: 3)
        let container = CGRect(x: 0, y: 30, width: 1600, height: 870)
        let group = LayoutTabGroup(windowIDs: [w1, w2], activeWindowID: w2)

        for mode in [WindowManagementMode.scrolling, .masterStack, .bsp] {
            let req = LayoutRequest(
                scope: scope,
                mode: mode,
                container: container,
                windowIDs: [w1, w2, w3],
                outerGaps: Insets(top: 8, right: 8, bottom: 8, left: 150),
                innerGap: 8,
                focusedWindowID: w2,
                tabbedBarHeight: 28,
                scrollingColumnWidth: 0.65,
                scrollingClipsLeft: false,
                scrollingClipsRight: true,
                tabGroups: [group]
            )
            let plan = LayoutPlanner.plan(req)
            let f1 = try #require(plan.placements[w1])
            let f2 = try #require(plan.placements[w2])
            let f3 = try #require(plan.placements[w3])

            // Les 2 onglets du groupe partagent exactement le même cadre contenu, décalé de barHeight + 4 pt
            #expect(f1 == f2)
            #expect(f1.minY == f3.minY + 32)
            #expect(f1.height == f3.height - 32)

            // Barre d'onglets alignée au-dessus du groupe et respectant la jointure droite en scrolling
            let bars = LayoutTabSlots.tabBarFrames(for: req)
            #expect(bars.count == 1)
            let bar = try #require(bars.first)
            #expect(bar.windowIDs == [w1, w2])
            #expect(bar.active == w2)
            #expect(bar.barFrame.minX == f1.minX)
            #expect(bar.barFrame.width == f1.width)
            #expect(bar.barFrame.maxY <= f1.minY)
            if mode == .scrolling {
                #expect(f1.maxX <= container.maxX - 8)
                #expect(f3.maxX <= container.maxX - 8)
                #expect(bar.barFrame.maxX <= container.maxX - 8)
            }
        }

        // Repli automatique 2 -> 1 quand un seul onglet du groupe est vivant
        let collapsedSlots = LayoutTabSlots.resolve(
            windowIDs: [w1, w3],
            tabGroups: [group],
            focusedWindowID: w1
        )
        #expect(collapsedSlots.count == 2)
        #expect(!collapsedSlots[0].isTabGroup)
        #expect(!collapsedSlots[1].isTabGroup)
    }

    // MARK: - 2. Commandes d'onglets (`tabStack`, `tabCycle`, `tabMove`, `tabReorder`, `tabUnstack`) sur tous les modes

    @Test @MainActor func tabCommandsWorkAcrossScrollingMasterStackAndBsp() throws {
        for mode in [WindowManagementMode.scrolling, .masterStack, .bsp] {
            let dir = try tempDir("cmd-\(mode.rawValue)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
            let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
            let d = display("d1")
            let w1 = window(11, app: "Notes", title: "One", x: 100)
            let w2 = window(12, app: "Terminal", title: "Two", x: 600)
            let w3 = window(13, app: "Safari", title: "Three", x: 1100)

            let provider = MutableProvider(displays: [d], windows: [w1, w2, w3], focused: w1.id)
            let spy = SpyWriter()
            let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: mode))
            let service = SnapshotService(provider: provider, frameWriter: spy, config: config, stageStore: stageStore, events: eventLog)
            _ = service.snapshot()

            let commands = WindowCommandService(service: service, stageStore: stageStore, events: eventLog)

            // Directions disponibles pour empiler w1
            let dirs = commands.availableTabStackDirections(for: w1.id, in: service.snapshot())
            #expect(dirs.contains(.right))

            // 1. Empiler w1 sur la tuile/colonne de droite (w2)
            let stacked = commands.tabStack(.right)
            #expect(stacked.changed)
            let scope = try #require(service.snapshot().state.activeScope(on: d.id))
            let groupAfterStack = try #require(stageStore.state().tabbedGroup(containing: w1.id, in: scope))
            #expect(groupAfterStack.windowIDs == [w2.id, w1.id])
            #expect(groupAfterStack.activeWindowID == w1.id)

            // Mettre à jour les frames observées depuis le SpyWriter pour la suite
            for id in [w1.id, w2.id, w3.id] {
                if let f = spy.lastFrame(for: id) {
                    provider.updateFrame(id, to: Rect(f))
                }
            }

            // 2. Barre d'onglets rendue par StageTabBarController.computeTargets
            let targets = StageTabBarController.computeTargets(
                snapshot: service.snapshot(followFocus: false),
                config: config,
                outerGapsProvider: { count, disp in service.effectiveOuterGaps(windowCount: count, display: disp) },
                frameTransform: { $0 }
            )
            #expect(targets.count == 1)
            #expect(targets[0].isTileGroup)
            #expect(targets[0].tabs.map(\.windowID) == [w2.id, w1.id])

            // 3. Cycle d'onglets (w1 -> w2 -> w1)
            provider.setFocused(w1.id)
            let cycled = commands.tabCycle(delta: 1)
            #expect(cycled.changed)
            #expect(spy.lastFocused() == w2.id)
            #expect(stageStore.state().tabbedGroup(containing: w2.id, in: scope)?.activeWindowID == w2.id)

            // 4. Réordonnancement dans la barre (tabMove / tabReorder)
            provider.setFocused(w2.id)
            let moved = commands.tabMove(delta: 1)
            #expect(moved.changed)
            #expect(stageStore.state().tabbedGroup(containing: w2.id, in: scope)?.windowIDs == [w1.id, w2.id])

            let reordered = commands.tabReorder(windowID: w2.id, toIndex: 0)
            #expect(reordered.changed)
            #expect(stageStore.state().tabbedGroup(containing: w2.id, in: scope)?.windowIDs == [w2.id, w1.id])

            // 5. Navigation directionnelle saute l'onglet caché et atteint directement w3
            provider.setFocused(w2.id)
            let focusedRight = commands.focus(.right)
            #expect(focusedRight.changed)
            #expect(spy.lastFocused() == w3.id)

            // 6. Détachement (tabUnstack) : le groupe < 2 disparaît automatiquement
            provider.setFocused(w1.id)
            let unstacked = commands.tabUnstack(.right)
            #expect(unstacked.changed)
            #expect(stageStore.state().tabbedGroups(for: scope).isEmpty)
        }
    }

    // MARK: - 3. DropPreviewEngine : empilement `⌥ Option` et dépôt sur barre en mode `.scrolling`

    @Test @MainActor func dropPreviewSupportsOptionStackAndTabBarDropInScrolling() throws {
        let dir = try tempDir("drop-scrolling")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let d = display("d1", x: 0, y: 0, width: 1600, height: 900)
        let w1 = window(21, app: "Notes", title: "One", x: 100, y: 60, width: 700, height: 800)
        let w2 = window(22, app: "Terminal", title: "Two", x: 820, y: 60, width: 700, height: 800)

        let provider = MutableProvider(displays: [d], windows: [w1, w2], focused: w1.id)
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .scrolling))
        let service = SnapshotService(provider: provider, config: config, stageStore: stageStore, events: eventLog)
        let snapshot = service.snapshot()
        let context = DropPreviewContext(snapshot: snapshot, persistedStateBeforeSnapshot: stageStore.state())
        let engine = DropPreviewEngine(service: service)

        // Dépôt de w1 au centre de w2 avec Option maintenu -> .stackTab avec groupMutation
        let centerOfW2 = CGPoint(x: w2.frame.cgRect.midX, y: w2.frame.cgRect.midY)
        let cand = try #require(engine.candidate(sourceWindowID: w1.id, atAXPoint: centerOfW2, context: context, optionHeld: true))
        #expect(cand.operation == .stackTab)
        #expect(cand.targetWindowID == w2.id)
        #expect(cand.groupMutation != nil)
        #expect(cand.isTreeMode)
        // L'aperçu d'un empilement en onglet englobe la barre d'onglets au-dessus du contenu
        let placedContent = try #require(cand.placements[w1.id])
        #expect(cand.frame.minY < CGFloat(placedContent.y))

        // Cas réel scrolling : cible partiellement hors écran à gauche (x = -352, width = 1068)
        // 1. Avec Option n'importe où sur la bande visible (même près du bord droit/haut) -> .stackTab
        let offscreenTarget = window(23, app: "Teams", title: "Chat", x: -352, y: 46, width: 1068, height: 840)
        let draggedRight = window(24, app: "iTerm2", title: "zsh", x: 724, y: 46, width: 1068, height: 840)
        let provider2 = MutableProvider(displays: [d], windows: [offscreenTarget, draggedRight], focused: draggedRight.id)
        let stageStore2 = StageStore(path: dir.appendingPathComponent("stages-offscreen.json").path)
        let service2 = SnapshotService(provider: provider2, config: config, stageStore: stageStore2, events: eventLog)
        let snapshot2 = service2.snapshot()
        let context2 = DropPreviewContext(snapshot: snapshot2, persistedStateBeforeSnapshot: stageStore2.state())
        let engine2 = DropPreviewEngine(service: service2)

        // Point à x = 550, y = 100 : proche du haut et à 84 % de la largeur brute (aurait donné insertRight/insertUp avant)
        let edgePoint = CGPoint(x: 550, y: 100)
        let optEdgeCand = try #require(engine2.candidate(sourceWindowID: draggedRight.id, atAXPoint: edgePoint, context: context2, optionHeld: true))
        #expect(optEdgeCand.operation == .stackTab)
        #expect(optEdgeCand.targetWindowID == offscreenTarget.id)

        // 2. Sans Option au centre de la bande visible (x = 358, y = 100) : en scrolling 1D, le haut ne déclenche PAS insertUp ni split vertical
        let visibleCenterNearTop = CGPoint(x: 358, y: 100)
        let noOptCand = try #require(engine2.candidate(sourceWindowID: draggedRight.id, atAXPoint: visibleCenterNearTop, context: context2, optionHeld: false))
        #expect(noOptCand.operation == .swap)
        for rect in noOptCand.placements.values {
            #expect(rect.height > 800)
        }
    }

    // MARK: - 4. Premier placement pré-AX d'une app lente en mode `.scrolling` (anti-vol multi-écrans)

    @Test func slowAppPreAXFailureInScrollingArmsQuickRetryAndResistsDriftSteal() throws {
        let dir = try tempDir("slow-app-scrolling")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)

        let leftDisp = DisplaySnapshot(
            id: DisplayID(rawValue: "retina"),
            index: 1,
            name: "Built-in Retina Display",
            frame: Rect(x: 0, y: 0, width: 1800, height: 1169),
            visibleFrame: Rect(x: 0, y: 38, width: 1800, height: 1131),
            isMain: false
        )
        let rightDisp = DisplaySnapshot(
            id: DisplayID(rawValue: "lg4k"),
            index: 2,
            name: "LG HDR 4K",
            frame: Rect(x: 1800, y: -1266, width: 3840, height: 2160),
            visibleFrame: Rect(x: 1800, y: -1236, width: 3840, height: 2130),
            isMain: true
        )
        let existing = window(401, app: "Teams", title: "Chat", x: 150, y: 46, width: 1068, height: 1115)
        let slowITerm = window(402, app: "iTerm2", title: "zsh", x: 3797, y: -1228, width: 570, height: 436)

        let provider = MutableProvider(displays: [leftDisp, rightDisp], windows: [existing], focused: existing.id)
        let spy = SpyWriter()
        spy.onWrite = { id, frame in provider.updateFrame(id, to: Rect(frame)) }
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .scrolling))
        let service = SnapshotService(
            provider: provider,
            frameWriter: spy,
            config: config,
            stageStore: stageStore,
            events: eventLog
        )

        var clock = Date(timeIntervalSince1970: 1_000_000)
        let maintainer = LayoutMaintainer(
            service: service,
            events: eventLog,
            store: stageStore,
            readFrame: { spy.readFrame(of: $0) },
            now: { clock }
        )
        // Initialisation : Retina possède `existing` (stage active en scrolling)
        _ = maintainer.tick(cause: "startup")
        let leftScope = try #require(service.snapshot().state.activeScope(on: leftDisp.id))

        // iTerm2 démarre à froid : sa fenêtre brute apparaît sur LG 4K mais AX n'est pas encore prêt
        spy.unreadableIDs = [slowITerm.id]
        spy.failWriteIDs = [slowITerm.id]
        provider.setWindows([existing, slowITerm])

        // Tick 1 : découverte + 1er placement réel vers le Retina échoue pré-AX
        _ = maintainer.tick(cause: "deadline:window_discovery")
        #expect(stageStore.state().stageScope(for: slowITerm.id) == leftScope)

        // Une reprise rapide `ax_ready_retry` doit être armée (<= 0.25 s)
        let retryDeadline = try #require(maintainer.nextDeadline(now: clock))
        #expect(retryDeadline.timeIntervalSince(clock) <= 0.25)

        // Même après 6 s (> newWindowDriftGrace = 5 s) pendant que AX reste indisponible,
        // `reconcileStableVisibleDisplayDrift` ne doit PAS voler iTerm2 vers le LG 4K !
        clock = clock.addingTimeInterval(6.0)
        _ = maintainer.tick(cause: "safety")
        #expect(stageStore.state().stageScope(for: slowITerm.id) == leftScope)

        // Dès que AX répond enfin, la passe suivante purge `failedFrames` et rapatrie iTerm2 sur le Retina !
        spy.unreadableIDs.remove(slowITerm.id)
        spy.failWriteIDs.remove(slowITerm.id)
        clock = clock.addingTimeInterval(0.2)
        _ = maintainer.tick(cause: "deadline")

        let placedFrame = try #require(spy.lastFrame(for: slowITerm.id))
        #expect(placedFrame.maxX <= leftDisp.frame.cgRect.maxX)
        #expect(stageStore.state().stageScope(for: slowITerm.id) == leftScope)
    }
}
