import AppKit
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
@testable import RoadieDaemon

// Reproduction d'audit V15 (session 050), hors dépôt audité : copie du harnais de Spec029ResizeTests.
// Hypothèse : la maximisation Roadie écrite pendant la session de geste du second clic d'un
// double-clic est adoptée par le tiler comme un redimensionnement manuel de l'arbre.
private let repro050First = WindowID(rawValue: 1)
private let repro050Second = WindowID(rawValue: 2)
private let repro050Left = Rect(x: 0, y: 0, width: 500, height: 500)
private let repro050Right = Rect(x: 500, y: 0, width: 500, height: 500)
private let repro050Tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
                                         first: .leaf(repro050First), second: .leaf(repro050Second))

private final class Repro050Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Frontières système simulées : relevé global, lecture AX fraîche et écritures réelles du maintainer.
private final class Repro050World: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    let display = DisplaySnapshot(id: DisplayID(rawValue: "repro050"), index: 1, name: "Test",
        frame: Rect(x: 0, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
    var frames = [repro050First: repro050Left, repro050Second: repro050Right]
    var laggedFrames: [WindowID: Rect] = [:]
    var pids: [WindowID: Int32] = [:]
    var nativeFullscreen = Set<WindowID>()
    var minimums: [WindowID: CGSize] = [:]
    var writes: [WindowID: [Rect]] = [:]
    var freshReads = 0
    var physicalMouseButtonsPressed = false
    var snapshotDelay: TimeInterval = 0
    let registry = WrittenFrameRegistry()
    let clock = Repro050Clock()

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func focusedWindowID() -> WindowID? { nil }
    func windows() -> [WindowSnapshot] {
        clock.advance(snapshotDelay)
        return frames.keys.sorted().map { id in
            WindowSnapshot(id: id, pid: pids[id] ?? Int32(id.rawValue + 100), appName: "Test",
                bundleID: "test.resize.\(id.rawValue)", title: "Test", frame: laggedFrames[id] ?? frames[id]!,
                isOnScreen: true, isTileCandidate: true,
                furniture: nativeFullscreen.contains(id) ? WindowFurniture(
                    hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true,
                    hasMinimizeButton: true, hasZoomButton: true, isNativeFullscreen: true) : nil)
        }
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        writes[window.id, default: []].append(Rect(frame))
        let minimum = minimums[window.id] ?? .zero
        let actual = CGRect(x: frame.minX, y: frame.minY,
                            width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
        frames[window.id] = Rect(actual)
        return actual
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var result: [WindowID: CGRect?] = [:]
        for update in updates {
            let actual = setFrame(update.frame, of: update.window)
            result[update.window.id] = actual
            registry.record(windowID: update.window.id.rawValue, requested: update.frame, readBack: actual,
                            generation: generation, at: clock.now)
        }
        return result
    }
}

@MainActor
private final class Repro050Harness {
    let world: Repro050World
    let input: UserInputActivity
    let store: StageStore
    let service: SnapshotService
    let maintainer: LayoutMaintainer
    let scope: StageScope
    let eventsPath: String
    let root: URL
    let dragActivity: WindowDragActivity
    let commandActivity: LayoutCommandActivity

    init(mode: WindowManagementMode = .spatialBsp) throws {
        let world = Repro050World()
        let input = UserInputActivity()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-repro050-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let eventsPath = root.appendingPathComponent("events.jsonl").path
        let scope = StageScope(displayID: world.display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: root.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: scope.displayID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: mode, members: world.frames.keys.sorted().map {
                PersistentStageMember(windowID: $0, bundleID: "test.resize.\($0.rawValue)", title: "Test",
                                      frame: world.frames[$0]!, pid: Int32($0.rawValue + 100))
            }, bspTree: repro050Tree)])], activeDisplayID: scope.displayID))
        let replay = ReplayableSnapshotProvider(base: world)
        let service = SnapshotService(provider: replay, frameWriter: world,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0, gapsInner: 0)),
            intentStore: LayoutIntentStore(path: root.appendingPathComponent("intents.json").path),
            stageStore: store, clock: { world.clock.now }, frameRegistry: world.registry)
        // Le booléen est partagé sans capturer self avant la fin de l'initialisation.
        let probe = Repro050Probe()
        let dragActivity = WindowDragActivity(path: root.appendingPathComponent("drag.json").path)
        let commandActivity = LayoutCommandActivity(path: root.appendingPathComponent("command-activity.json").path)
        let maintainer = LayoutMaintainer(service: service, scanReplay: replay, events: EventLog(path: eventsPath),
            store: store, dragActivity: dragActivity, commandActivity: commandActivity,
            mouseButtonsPressed: { input.blocksLayout(mouseButtonsPressed: world.physicalMouseButtonsPressed, now: world.clock.now) },
            writtenFrames: world.registry,
            takeGesture: input.takeGesture, spaceProbe: { _ in probe.value },
            readFrame: { window in world.freshReads += 1; return world.frames[window.id]?.cgRect },
            now: { world.clock.now })
        self.world = world
        self.input = input
        self.root = root
        self.eventsPath = eventsPath
        self.scope = scope
        self.store = store
        self.service = service
        self.probe = probe
        self.maintainer = maintainer
        self.dragActivity = dragActivity
        self.commandActivity = commandActivity
        input.observeGestures(target: { [service] point in
            FocusFollowsMousePicker.gestureTargetWindow(at: point, in: service.sharedSnapshot())
                .map { ($0.window.id.rawValue, $0.window.frame.cgRect) }
        }, onRelease: { _ in })
        _ = maintainer.tick(cause: "command:startup")
        // Le compteur du parcours mesure les relectures du geste, après la résolution initiale.
        world.freshReads = 0
        world.clock.advance(5)
    }

    private let probe: Repro050Probe
    func setUserSpace(_ value: Bool) { probe.value = value }
    var events: String { (try? String(contentsOfFile: eventsPath, encoding: .utf8)) ?? "" }
    var manualGestures: Int { events.components(separatedBy: "\"type\":\"layout_manual_gesture\"").count - 1 }

    func drag(_ id: WindowID = repro050First, publishing frame: Rect? = nil) {
        let initial = world.frames[id]!.cgRect
        input.mouseDown(at: CGPoint(x: initial.maxX - 1, y: initial.midY), now: world.clock.now)
        #expect(input.currentGesture?.windowID == id.rawValue)
        #expect(input.currentGesture?.startFrame == initial)
        #expect(world.display.frame.cgRect.contains(CGPoint(x: initial.midX, y: initial.midY)))
        input.mouseDragged()
        if let frame { world.frames[id] = frame }
        input.mouseUp(leftButton: true, now: world.clock.now)
    }

    func dispose() { try? FileManager.default.removeItem(at: root) }
}

private final class Repro050Probe { var value = true }


@Suite @MainActor
struct Repro050DoubleClickGestureTests {
    private func command(_ h: Repro050Harness) -> WindowCommandService {
        WindowCommandService(service: h.service, stageStore: h.store,
                             events: EventLog(path: h.root.appendingPathComponent("cmd-events.jsonl").path),
                             commandActivity: h.commandActivity)
    }

    /// Témoin : maximisation sans clic en cours (commande clavier). Arbre attendu inchangé.
    @Test func controlMaximizeWithoutGestureKeepsTheTree() throws {
        let h = try Repro050Harness()
        defer { h.dispose() }
        let tree = h.store.state().bspTree(for: h.scope)
        let on = command(h).toggleMaximize(windowID: repro050First)
        h.world.clock.advance(0.2)
        _ = h.maintainer.tick(cause: "ax:AXWindowResized")
        print("REPRO050 control on=\(on.message) frames=\(h.world.frames) manual=\(h.manualGestures) tree=\(String(describing: h.store.state().bspTree(for: h.scope)))")
        #expect(h.store.state().bspTree(for: h.scope) == tree)
        #expect(h.manualGestures == 0)
    }

    /// Double-clic : le second appui ouvre une session de geste, Roadie maximise pendant l'appui,
    /// puis le relâchement déclenche la passe « drag » du tiler.
    @Test func maximizeDuringTheSecondClickIsNotAdoptedAsAManualResize() throws {
        let h = try Repro050Harness()
        defer { h.dispose() }
        let tree = h.store.state().bspTree(for: h.scope)
        let point = CGPoint(x: 250, y: 10)
        h.input.mouseDown(at: point, now: h.world.clock.now)
        h.input.mouseUp(leftButton: true, now: h.world.clock.now)
        h.world.clock.advance(0.15)
        h.input.mouseDown(at: point, now: h.world.clock.now)
        // Le second appui ouvre bien une session de geste sur la fenêtre 1, cadre tuilé de départ.
        #expect(h.input.currentGesture?.windowID == repro050First.rawValue)
        #expect(h.input.currentGesture?.startFrame == repro050Left.cgRect)
        let on = command(h).toggleMaximize(windowID: repro050First)
        let maximized = h.world.frames[repro050First]
        h.input.mouseUp(leftButton: true, now: h.world.clock.now)
        h.world.clock.advance(0.1)
        _ = h.maintainer.tick(cause: "drag")
        let after = h.store.state().bspTree(for: h.scope)
        print("REPRO050 doubleclick on=\(on.message) maximized=\(String(describing: maximized)) frames=\(h.world.frames) manual=\(h.manualGestures) treeBefore=\(String(describing: tree)) treeAfter=\(String(describing: after))")
        h.world.clock.advance(1)
        let off = command(h).toggleMaximize(windowID: repro050First)
        h.world.clock.advance(0.2)
        _ = h.maintainer.tick(cause: "command:window.toggle_maximize")
        print("REPRO050 restore off=\(off.message) frames=\(h.world.frames) tree=\(String(describing: h.store.state().bspTree(for: h.scope)))")
        #expect(h.manualGestures == 0)
        #expect(after == tree)
        #expect(h.world.frames[repro050First]?.width == 500)
    }
}
