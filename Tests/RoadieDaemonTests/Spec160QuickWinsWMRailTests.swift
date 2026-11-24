import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 160 — Quick Wins WM & NavRail : BSPTree rotate/mirror, window close/gather-app,
/// mouse_follows_focus sur bascule stage/écran et survol des icônes d'application du NavRail.
@Suite(.serialized)
struct Spec160QuickWinsWMRailTests {
    private final class SpyWriter: WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        var closedWindowIDs: [WindowID] = []
        var focusedWindowIDs: [WindowID] = []
        var writtenFrames: [WindowID: CGRect] = [:]
        var closeResult = true

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            lock.withLock { writtenFrames[window.id] = frame }
            return frame
        }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock { focusedWindowIDs.append(window.id) }
            return true
        }

        func close(_ window: WindowSnapshot) -> Bool {
            lock.withLock { closedWindowIDs.append(window.id) }
            return closeResult
        }
    }

    private struct StaticProvider: SystemSnapshotProviding {
        var displaysList: [DisplaySnapshot]
        var windowsList: [WindowSnapshot]
        var focusedID: WindowID?

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }
        func displays() -> [DisplaySnapshot] { displaysList }
        func windows() -> [WindowSnapshot] { windowsList }
        func focusedWindowID() -> WindowID? { focusedID }
    }

    private func display(_ id: String = "d1", index: Int = 1, x: Double = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: index,
            name: "Display \(index)",
            frame: Rect(x: x, y: 0, width: 1600, height: 900),
            visibleFrame: Rect(x: x, y: 30, width: 1600, height: 870),
            isMain: index == 1
        )
    }

    private func window(
        _ id: UInt32,
        bundleID: String = "com.example.app",
        title: String = "Win",
        frame: Rect = Rect(x: 20, y: 40, width: 700, height: 600),
        nativeFullscreen: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 500,
            appName: "App",
            bundleID: bundleID,
            title: "\(title) \(id)",
            frame: frame,
            isOnScreen: true,
            isTileCandidate: true,
            furniture: nativeFullscreen
                ? WindowFurniture(
                    hasCloseButton: true,
                    hasFullscreenButton: true,
                    fullscreenButtonEnabled: true,
                    hasMinimizeButton: true,
                    hasZoomButton: true,
                    isResizable: true,
                    isNativeFullscreen: true
                )
                : nil
        )
    }

    private func bspConfig() -> RoadieConfig {
        var config = RoadieConfig()
        config.tiling.defaultStrategy = .spatialBsp
        return config
    }

    // MARK: - BSPTree rotate & mirror

    @Test func bspTreeRotateAndMirrorSatisfyGeometricInvariants() throws {
        let w1 = WindowID(rawValue: 1)
        let w2 = WindowID(rawValue: 2)
        let w3 = WindowID(rawValue: 3)
        let tree = BSPTree.split(
            orientation: .vertical,
            ratio: 0.4,
            first: .leaf(w1),
            second: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(w2), second: .leaf(w3))
        )

        // 4 rotations de 90° = identité (à précision flottante près).
        let r90 = try #require(tree.rotated(degrees: 90))
        let r180 = try #require(tree.rotated(degrees: 180))
        let r270 = try #require(tree.rotated(degrees: 270))
        #expect(tree.rotated(degrees: 45) == nil)

        // 90° transforme vertical(0.4, w1, horizontal(0.3, w2, w3)) en horizontal(0.4, w1, vertical(0.7, w3, w2)).
        let container = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let f0 = tree.place(in: container, innerGap: 0)
        let f90 = r90.place(in: container, innerGap: 0)
        let f0w1 = try #require(f0[w1])
        let f0w2 = try #require(f0[w2])
        let f90w1 = try #require(f90[w1])
        let f90w2 = try #require(f90[w2])
        let f90w3 = try #require(f90[w3])
        #expect(f0w1.maxX <= f0w2.minX + 1)
        #expect(f90w1.maxY <= f90w2.minY + 1)
        #expect(f90w3.maxX <= f90w2.minX + 1)
        #expect(r270.rotated(degrees: 90)?.place(in: container, innerGap: 0)[w1] == f0[w1])

        // 90° puis 270° revient aux mêmes cadres que l'original.
        let back = try #require(r90.rotated(degrees: 270)).place(in: container, innerGap: 0)
        for id in [w1, w2, w3] {
            let b = try #require(back[id])
            let orig = try #require(f0[id])
            #expect(abs(b.minX - orig.minX) < 1)
            #expect(abs(b.minY - orig.minY) < 1)
            #expect(abs(b.width - orig.width) < 1)
            #expect(abs(b.height - orig.height) < 1)
        }

        // Miroirs X et Y sont involutifs et mirror(x) + mirror(y) == rotate(180°).
        let mx = tree.mirrored(.x)
        let my = tree.mirrored(.y)
        let fmx = mx.place(in: container, innerGap: 0)
        let fmxw1 = try #require(fmx[w1])
        let fmxw2 = try #require(fmx[w2])
        #expect(fmxw1.minX > fmxw2.maxX - 1)
        let f180 = r180.place(in: container, innerGap: 0)
        let fmxy = mx.mirrored(.y).place(in: container, innerGap: 0)
        for id in [w1, w2, w3] {
            let r = try #require(f180[id])
            let m = try #require(fmxy[id])
            #expect(abs(r.minX - m.minX) < 1)
            #expect(abs(r.minY - m.minY) < 1)
        }
        let mx2 = mx.mirrored(.x).place(in: container, innerGap: 0)
        let my2 = my.mirrored(.y).place(in: container, innerGap: 0)
        for id in [w1, w2, w3] {
            let orig = try #require(f0[id])
            let rx = try #require(mx2[id])
            let ry = try #require(my2[id])
            #expect(abs(rx.minX - orig.minX) < 1)
            #expect(abs(ry.minY - orig.minY) < 1)
        }
    }

    // MARK: - LayoutCommandService & CLI rotate / mirror

    @Test @MainActor func layoutRotateAndMirrorMutateTreeAndRejectInvalidArgs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec160-layout-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let d1 = display()
        let w1 = window(1)
        let w2 = window(2)
        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let scopeKey = StageScope(displayID: d1.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let initialTree = BSPTree.split(orientation: .vertical, ratio: 0.4, first: .leaf(w1.id), second: .leaf(w2.id))
        try store.mutateChecked { state in
            var scope = state.scope(displayID: d1.id, desktopID: DesktopID(rawValue: 1))
            if let idx = scope.stages.firstIndex(where: { $0.id == StageID(rawValue: "1") }) {
                scope.stages[idx].mode = .spatialBsp
            }
            scope.assign(window: w1, to: StageID(rawValue: "1"), defaultMode: .spatialBsp)
            scope.assign(window: w2, to: StageID(rawValue: "1"), defaultMode: .spatialBsp)
            state.update(scope)
            state.setBSPTree(initialTree, for: scopeKey)
        }

        let writer = SpyWriter()
        let service = SnapshotService(
            provider: StaticProvider(displaysList: [d1], windowsList: [w1, w2], focusedID: w1.id),
            frameWriter: writer,
            config: bspConfig(),
            intentStore: LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path),
            stageStore: store
        )
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let commands = LayoutCommandService(service: service, events: events)

        let rotated = commands.rotate(90)
        #expect(rotated.changed)
        #expect(store.state().bspTree(for: scopeKey) == initialTree.rotated(degrees: 90))

        let mirrored = commands.mirror("y")
        #expect(mirrored.changed)
        #expect(store.state().bspTree(for: scopeKey) == initialTree.rotated(degrees: 90)?.mirrored(.y))

        #expect(!commands.rotate(45).changed)
        #expect(!commands.mirror("z").changed)

        let router = CLICommandRouter(makeService: { _ in service })
        #expect(router.run(["layout", "rotate", "45"]).exitCode == 64)
        #expect(router.run(["layout", "mirror", "z"]).exitCode == 64)
        #expect(router.run(["layout", "rotate", "90"]).exitCode == 0)
        #expect(router.run(["layout", "mirror", "x"]).exitCode == 0)
    }

    // MARK: - Window close & gather-app

    @Test @MainActor func windowCloseCallsAXCloseAndWorksViaCLI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec160-close-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let d1 = display()
        let w1 = window(10, bundleID: "com.example.editor")
        let writer = SpyWriter()
        let service = SnapshotService(
            provider: StaticProvider(displaysList: [d1], windowsList: [w1], focusedID: w1.id),
            frameWriter: writer,
            config: bspConfig(),
            intentStore: LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path),
            stageStore: StageStore(path: dir.appendingPathComponent("stages.json").path)
        )

        let router = CLICommandRouter(makeService: { _ in service })
        let response = router.run(["window", "close"])
        #expect(response.exitCode == 0)
        #expect(writer.closedWindowIDs == [w1.id])

        #expect(router.run(["window", "close", "not-a-number"]).exitCode == 64)
        #expect(CLICommandRouter.commandTable.contains { $0.usage == "window close [WINDOW_ID]" && $0.implemented })
    }

    @Test func windowGatherAppMovesSameBundleWindowsAndSkipsNativeFullscreen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec160-gather-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let d1 = display()
        let w1 = window(1, bundleID: "com.example.browser")
        let w2 = window(2, bundleID: "com.example.browser", frame: Rect(x: -2000, y: 40, width: 700, height: 600))
        let w3 = window(3, bundleID: "com.example.browser", nativeFullscreen: true)
        let w4 = window(4, bundleID: "com.example.notes")
        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let stage1 = StageID(rawValue: "1")
        let stage2 = StageID(rawValue: "2")

        try store.mutateChecked { state in
            var scope = state.scope(displayID: d1.id, desktopID: DesktopID(rawValue: 1))
            scope.assign(window: w1, to: stage1, defaultMode: .spatialBsp)
            scope.assign(window: w2, to: stage2, defaultMode: .spatialBsp)
            scope.assign(window: w3, to: stage2, defaultMode: .spatialBsp)
            scope.assign(window: w4, to: stage2, defaultMode: .spatialBsp)
            scope.activeStageID = stage1
            state.update(scope)
        }

        let writer = SpyWriter()
        let service = SnapshotService(
            provider: StaticProvider(displaysList: [d1], windowsList: [w1, w2, w3, w4], focusedID: w1.id),
            frameWriter: writer,
            config: bspConfig(),
            intentStore: LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path),
            stageStore: store
        )
        let commands = WindowCommandService(
            service: service,
            stageStore: store,
            events: EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        )

        let result = commands.gatherApp()
        #expect(result.changed)
        #expect(result.message.contains("gathered=1"))

        var afterState = store.state()
        let afterScope = afterState.scope(displayID: d1.id, desktopID: DesktopID(rawValue: 1))
        let s1Members = Set(afterScope.memberIDs(in: stage1))
        let s2Members = Set(afterScope.memberIDs(in: stage2))
        #expect(s1Members.contains(w1.id))
        #expect(s1Members.contains(w2.id))
        #expect(!s1Members.contains(w3.id))
        #expect(!s1Members.contains(w4.id))
        #expect(s2Members.contains(w3.id))
        #expect(s2Members.contains(w4.id))
    }

    // MARK: - MouseFollower étendu aux bascules de stage et d'écran

    @Test func mouseFollowerWarpsOnStageSwitchAndDisplayFocusWhenEnabled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec160-warp-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let d1 = display("d1", index: 1, x: 0)
        let d2 = display("d2", index: 2, x: 1600)
        let w1 = window(1, frame: Rect(x: 100, y: 100, width: 600, height: 400))
        let w2 = window(2, frame: Rect(x: 1800, y: 120, width: 500, height: 400))
        let w3 = window(3, frame: Rect(x: 200, y: 140, width: 600, height: 400))
        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        try store.mutateChecked { state in
            var s1 = state.scope(displayID: d1.id, desktopID: DesktopID(rawValue: 1))
            s1.assign(window: w1, to: StageID(rawValue: "1"), defaultMode: .spatialBsp)
            s1.assign(window: w3, to: StageID(rawValue: "2"), defaultMode: .spatialBsp)
            s1.activeStageID = StageID(rawValue: "1")
            state.update(s1)
            var s2 = state.scope(displayID: d2.id, desktopID: DesktopID(rawValue: 1))
            s2.assign(window: w2, to: StageID(rawValue: "1"), defaultMode: .spatialBsp)
            state.update(s2)
        }

        let writer = SpyWriter()
        let service = SnapshotService(
            provider: StaticProvider(displaysList: [d1, d2], windowsList: [w1, w2, w3], focusedID: w1.id),
            frameWriter: writer,
            config: bspConfig(),
            intentStore: LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path),
            stageStore: store
        )

        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            var points: [CGPoint] = []
            func append(_ p: CGPoint) { lock.withLock { points.append(p) } }
        }
        let enabledRecorder = Recorder()
        let disabledRecorder = Recorder()

        let displayCmdEnabled = DisplayCommandService(
            service: service,
            store: store,
            events: EventLog(path: dir.appendingPathComponent("events.jsonl").path),
            mouseFollower: MouseFollower(isEnabled: { true }, move: { enabledRecorder.append($0) })
        )
        _ = displayCmdEnabled.focus(index: 2)
        #expect(enabledRecorder.points == [w2.frame.center])

        let stageCmdEnabled = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: dir.appendingPathComponent("events.jsonl").path),
            config: bspConfig(),
            mouseFollower: MouseFollower(isEnabled: { true }, move: { enabledRecorder.append($0) })
        )
        _ = stageCmdEnabled.switchTo("2", displayID: d1.id)
        #expect(enabledRecorder.points.count == 2)

        let displayCmdDisabled = DisplayCommandService(
            service: service,
            store: store,
            events: EventLog(path: dir.appendingPathComponent("events.jsonl").path),
            mouseFollower: MouseFollower(isEnabled: { false }, move: { disabledRecorder.append($0) })
        )
        _ = displayCmdDisabled.focus(index: 1)
        #expect(disabledRecorder.points.isEmpty)
    }

    // MARK: - Survol d'icône d'application dans StageCardView

    @Test @MainActor func stageCardViewHoverUpdatesIconStateAndToolTip() throws {
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        config.mode = .parallax
        config.parallaxRotation = 45
        config.showAppIconsRow = true

        let memberA = PersistentStageMember(
            windowID: WindowID(rawValue: 101),
            bundleID: "com.example.Browser",
            title: "Documentation",
            frame: Rect(x: 0, y: 0, width: 600, height: 400)
        )
        let stage = PersistentStage(id: StageID(rawValue: "1"), name: "Travail", members: [memberA])
        let card = StageCardView(
            stage: stage,
            displayLabel: "Travail",
            isActive: true,
            accent: .systemGreen,
            config: config,
            presentationStates: [:],
            thumbnails: [:]
        )
        card.setStageToolTip("1 — Travail")
        #expect(card.toolTip == "1 — Travail")

        let layout = try #require(card.appIconsRowLayout())
        let firstItem = try #require(layout.items.first)
        let centerInCard = CGPoint(x: firstItem.rect.midX, y: firstItem.rect.midY).applying(layout.transform)

        #expect(card.updateHoveredAppIcon(at: centerInCard))
        #expect(card.hoveredAppIconWindowID == memberA.windowID)
        #expect(card.toolTip?.contains("Documentation") == true)

        // Même point : aucun changement inutile.
        #expect(!card.updateHoveredAppIcon(at: centerInCard))

        // Sortie du survol : restauration de l'infobulle de la stage.
        #expect(card.updateHoveredAppIcon(at: nil))
        #expect(card.hoveredAppIconWindowID == nil)
        #expect(card.toolTip == "1 — Travail")
    }
}
