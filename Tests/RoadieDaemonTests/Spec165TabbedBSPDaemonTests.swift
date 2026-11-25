import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 165 — Tuiles à onglets intégrées dans `spatialBsp` (daemon, drop preview, barre multi-tuiles, CLI, lanceur, menu).
@Suite(.serialized)
struct Spec165TabbedBSPDaemonTests {
    private final class MutableProvider: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var displaysStorage: [DisplaySnapshot]
        private var windowsStorage: [WindowSnapshot]
        private var focusedStorage: WindowID?
        private var writtenFramesStorage: [(WindowID, CGRect)] = []

        init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID? = nil) {
            self.displaysStorage = displays
            self.windowsStorage = windows
            self.focusedStorage = focused ?? windows.first?.id
        }

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }

        func displays() -> [DisplaySnapshot] { lock.withLock { displaysStorage } }
        func windows() -> [WindowSnapshot] { lock.withLock { windowsStorage } }
        func focusedWindowID() -> WindowID? { lock.withLock { focusedStorage } }

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            lock.withLock {
                writtenFramesStorage.append((window.id, frame))
                if let index = windowsStorage.firstIndex(where: { $0.id == window.id }) {
                    windowsStorage[index].frame = Rect(frame)
                }
            }
            return frame
        }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock { focusedStorage = window.id }
            return true
        }
    }

    @MainActor
    private final class SpyTabBarRenderer: StageTabBarRendering {
        var renderedTargets: [[StageTabBarTarget]] = []
        var hideAllCalls = 0
        func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void) {
            renderedTargets.append(targets)
        }
        func render(_ targets: [StageTabBarTarget], callbacks: StageTabBarCallbacks) {
            renderedTargets.append(targets)
        }
        func hideAll() {
            hideAllCalls += 1
        }
    }

    private func tempDir(_ suffix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec165-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func display(_ id: String = "display-1", width: Double = 1440, height: Double = 900) -> DisplaySnapshot {
        let rect = Rect(x: 0, y: 0, width: width, height: height)
        return DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: 1,
            name: "Main",
            frame: rect,
            visibleFrame: rect,
            isMain: true
        )
    }

    private func window(_ raw: UInt32, app: String, title: String, frame: Rect = Rect(x: 0, y: 0, width: 600, height: 800)) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: raw),
            pid: Int32(1000 + raw),
            appName: app,
            bundleID: "com.example.\(app.lowercased())",
            title: title,
            frame: frame,
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            furniture: nil
        )
    }

    @Test func tabCommandsStackCycleFocusUnstackMoveAndReorder() throws {
        let dir = try tempDir("commands")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(101, app: "Notes", title: "Spec")
        let w2 = window(102, app: "Terminal", title: "Build")
        let w3 = window(103, app: "Safari", title: "Docs")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2, w3], focused: w3.id)
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10, tabbedBarHeight: 28))
        let service = SnapshotService(provider: provider, frameWriter: provider, config: config, stageStore: stageStore, events: eventLog)

        let snap = service.snapshot()
        let scope = try #require(snap.windows.first?.scope)
        // Arbre connu : w1 à gauche | (w2 en haut / w3 en bas) à droite
        let initialTree: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1.id),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(w2.id), second: .leaf(w3.id))
        )
        try stageStore.mutateChecked { $0.setBSPTree(initialTree, for: scope) }

        let cmds = WindowCommandService(service: service, stageStore: stageStore, events: eventLog)

        // 1. Empiler w3 sur w2 (au-dessus)
        let stacked = cmds.tabStack(.up)
        #expect(stacked.changed)
        let treeAfterStack = try #require(stageStore.state().bspTree(for: scope))
        #expect(treeAfterStack.tabGroup(containing: w2.id)?.windowIDs == [w2.id, w3.id])
        #expect(treeAfterStack.tabGroup(containing: w2.id)?.active == w3.id)

        // 2. Focus left saute directement sur w1 (non piégé dans le groupe d'onglets)
        let leftFocus = cmds.focus(.left)
        #expect(leftFocus.changed)
        #expect(provider.focusedWindowID() == w1.id)

        // 3. Focus right depuis w1 atterrit sur l'onglet ACTIF (w3) de la tuile droite
        let rightFocus = cmds.focus(.right)
        #expect(rightFocus.changed)
        #expect(provider.focusedWindowID() == w3.id)

        // 4. tab next / prev fait défiler les onglets et met à jour `active`
        let nextTab = cmds.tabCycle(delta: 1)
        #expect(nextTab.changed)
        #expect(provider.focusedWindowID() == w2.id)
        #expect(stageStore.state().bspTree(for: scope)?.tabGroup(containing: w2.id)?.active == w2.id)

        // 5. tab move right / tabReorder réordonne les onglets dans la tuile
        let moved = cmds.tabMove(delta: 1)
        #expect(moved.changed)
        #expect(stageStore.state().bspTree(for: scope)?.tabGroup(containing: w2.id)?.windowIDs == [w3.id, w2.id])

        let reordered = cmds.tabReorder(windowID: w2.id, toIndex: 0)
        #expect(reordered.changed)
        #expect(stageStore.state().bspTree(for: scope)?.tabGroup(containing: w2.id)?.windowIDs == [w2.id, w3.id])

        // 6. tab unstack détache w2 dans sa propre tuile et replie le tabGroup
        let unstacked = cmds.tabUnstack(.right)
        #expect(unstacked.changed)
        let treeAfterUnstack = try #require(stageStore.state().bspTree(for: scope))
        #expect(treeAfterUnstack.tabGroups.isEmpty)
        #expect(treeAfterUnstack.contains(w1.id) && treeAfterUnstack.contains(w2.id) && treeAfterUnstack.contains(w3.id))
    }

    @Test func dropPreviewSupportsOptionStackTabBarDropAndDetachEdges() throws {
        let dir = try tempDir("drop")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(201, app: "Notes", title: "Left")
        let w2 = window(202, app: "Terminal", title: "Tab1")
        let w3 = window(203, app: "Safari", title: "Tab2")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2, w3], focused: w1.id)
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10, tabbedBarHeight: 28))
        let service = SnapshotService(provider: provider, frameWriter: provider, config: config, stageStore: stageStore, events: eventLog)

        let snap = service.snapshot()
        let scope = try #require(snap.windows.first?.scope)
        let tree: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1.id),
            second: .tabGroup(windowIDs: [w2.id, w3.id], active: w3.id)
        )
        try stageStore.mutateChecked { $0.setBSPTree(tree, for: scope) }

        let engine = DropPreviewEngine(service: service)
        let context = engine.makeContext()
        let geometry = try #require(service.commandTreeGeometry(for: scope, tree: tree, in: context.snapshot))
        let frames = geometry.frames(of: tree)
        let bars = geometry.tabBarFrames(of: tree)
        let rightBar = try #require(bars.first)
        let rightContent = try #require(frames[w3.id])

        // 1. Dépôt de w1 sur le centre de la tuile droite SANS Option -> swap classique
        let centerPoint = CGPoint(x: rightContent.midX, y: rightContent.midY)
        let swapCand = try #require(engine.candidate(sourceWindowID: w1.id, atAXPoint: centerPoint, context: context, optionHeld: false))
        #expect(swapCand.operation == .swap)
        #expect(swapCand.isTreeMode)

        // 2. Dépôt de w1 sur le centre de la tuile droite AVEC Option -> stackTab
        let optStackCand = try #require(engine.candidate(sourceWindowID: w1.id, atAXPoint: centerPoint, context: context, optionHeld: true))
        #expect(optStackCand.operation == .stackTab)
        let optMutated = try #require(optStackCand.treeMutation?(tree))
        #expect(optMutated.tabGroup(containing: w1.id)?.windowIDs == [w2.id, w3.id, w1.id])
        #expect(optMutated.tabGroup(containing: w1.id)?.active == w1.id)

        // 3. Dépôt de w1 directement sur la BARRE D'ONGLETS SANS Option -> stackTab
        let barPoint = CGPoint(x: rightBar.barFrame.midX, y: rightBar.barFrame.midY)
        let barStackCand = try #require(engine.candidate(sourceWindowID: w1.id, atAXPoint: barPoint, context: context, optionHeld: false))
        #expect(barStackCand.operation == .stackTab)

        // 4. Glisser-sortir de w3 sur le bord droit de sa PROPRE tuile -> insertRight (détachement)
        let ownRightEdge = CGPoint(x: rightContent.maxX - 20, y: rightContent.midY)
        let detachCand = try #require(engine.candidate(sourceWindowID: w3.id, atAXPoint: ownRightEdge, context: context, optionHeld: false))
        #expect(detachCand.operation == .insertRight)
        let detachedTree = try #require(detachCand.treeMutation?(tree))
        #expect(detachedTree.tabGroups.isEmpty)

        // 5. Relâcher w3 au centre de sa PROPRE tuile -> nil (annulation propre)
        let ownCenter = engine.candidate(sourceWindowID: w3.id, atAXPoint: centerPoint, context: context, optionHeld: false)
        #expect(ownCenter == nil)
    }

    @Test @MainActor func stageTabBarControllerRendersMultipleBarsInSpatialBsp() async throws {
        let dir = try tempDir("multibar")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(301, app: "Notes", title: "A")
        let w2 = window(302, app: "Terminal", title: "B")
        let w3 = window(303, app: "Safari", title: "C")
        let w4 = window(304, app: "Mail", title: "D")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2, w3, w4], focused: w2.id)
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10, tabbedBarHeight: 28))
        let service = SnapshotService(provider: provider, frameWriter: provider, config: config, stageStore: stageStore, events: eventLog)

        let snap = service.snapshot()
        let scope = try #require(snap.windows.first?.scope)
        // Deux tuiles à onglets simultanées dans la même stage spatialBsp
        let tree: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .tabGroup(windowIDs: [w1.id, w2.id], active: w2.id),
            second: .tabGroup(windowIDs: [w3.id, w4.id], active: w4.id)
        )
        try stageStore.mutateChecked { $0.setBSPTree(tree, for: scope) }
        _ = service.snapshot()

        let spy = SpyTabBarRenderer()
        let controller = StageTabBarController(snapshotService: service, configLoader: { config }, renderer: spy)
        await controller.refresh()

        let targets = try #require(spy.renderedTargets.last)
        #expect(targets.count == 2)
        #expect(targets[0].isTileGroup && targets[1].isTileGroup)
        #expect(targets[0].barID != targets[1].barID)
        #expect(targets[0].tabs.map(\.windowID) == [w1.id, w2.id])
        #expect(targets[0].tabs[1].isFocused)
        #expect(targets[1].tabs.map(\.windowID) == [w3.id, w4.id])
        #expect(targets[1].tabs[1].isFocused)
    }

    @Test func stageProjectPreservesTabGroupAndCLIAndLauncherWork() throws {
        // 1. StageProject capture + restore avec tabGroup
        let w1 = WindowID(rawValue: 10)
        let w2 = WindowID(rawValue: 20)
        let w3 = WindowID(rawValue: 30)
        let pw1 = ProjectWindow(bundleID: "a", appPath: "/A.app", document: nil, url: nil, title: "A")
        let pw2 = ProjectWindow(bundleID: "b", appPath: "/B.app", document: nil, url: nil, title: "B")
        let pw3 = ProjectWindow(bundleID: "c", appPath: "/C.app", document: nil, url: nil, title: "C")
        let tree: BSPTree = .split(orientation: .vertical, ratio: 0.5, first: .leaf(w1), second: .tabGroup(windowIDs: [w2, w3], active: w3))
        let project = StageProject.capture(
            name: "work",
            members: [w1, w2, w3],
            windows: [w1: pw1, w2: pw2, w3: pw3],
            tree: tree,
            at: Date()
        )
        let reopened = project.tree(for: [WindowID(rawValue: 100), WindowID(rawValue: 200), WindowID(rawValue: 300)])
        #expect(reopened == .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(WindowID(rawValue: 100)),
            second: .tabGroup(windowIDs: [WindowID(rawValue: 200), WindowID(rawValue: 300)], active: WindowID(rawValue: 300))
        ))

        // 2. Commandes lanceur & routage daemon CLI
        let allCommands = LauncherSystemCommand.all()
        #expect(allCommands.contains { $0.id == "roadie-tab-next" })
        #expect(allCommands.contains { $0.id == "roadie-tab-prev" })
        #expect(allCommands.contains { $0.id == "roadie-tab-stack-right" })
        #expect(allCommands.contains { $0.id == "roadie-tab-unstack" })
        #expect(CLICommandRouter.isDaemonRouted(["tab", "next"]))
        #expect(CLICommandRouter.isDaemonRouted(["tab", "stack", "right"]))
    }

    @Test @MainActor func cliRouterDispatchesTabCommandsAndValidatesUsage() throws {
        let dir = try tempDir("cli")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(401, app: "Notes", title: "One")
        let w2 = window(402, app: "Terminal", title: "Two")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2], focused: w1.id)
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 8, tabbedBarHeight: 28))
        let service = SnapshotService(provider: provider, frameWriter: provider, config: config, stageStore: stageStore, events: eventLog)

        let router = CLICommandRouter(makeService: { _ in service })
        #expect(router.run(["tab"]).exitCode == 64)
        #expect(router.run(["tab", "stack", "diagonal"]).exitCode == 64)
        #expect(router.run(["tab", "move", "up"]).exitCode == 64)

        let stackRes = router.run(["tab", "stack", "right"])
        #expect(stackRes.exitCode == 0)
        let nextRes = router.run(["tab", "next"])
        #expect(nextRes.exitCode == 0)
        #expect(provider.focusedWindowID() == w2.id)
        let unstackRes = router.run(["tab", "unstack"])
        #expect(unstackRes.exitCode == 0)
    }
}
