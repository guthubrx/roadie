import AppKit
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
@testable import RoadieDaemon

private let resize029First = WindowID(rawValue: 1)
private let resize029Second = WindowID(rawValue: 2)
private let resize029Left = Rect(x: 0, y: 0, width: 500, height: 500)
private let resize029Right = Rect(x: 500, y: 0, width: 500, height: 500)
private let resize029Tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
                                         first: .leaf(resize029First), second: .leaf(resize029Second))

private final class Resize029Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Frontières système simulées : relevé global, lecture AX fraîche et écritures réelles du maintainer.
private final class Resize029World: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    let display = DisplaySnapshot(id: DisplayID(rawValue: "spec029-resize"), index: 1, name: "Test",
        frame: Rect(x: 0, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
    var frames = [resize029First: resize029Left, resize029Second: resize029Right]
    var laggedFrames: [WindowID: Rect] = [:]
    var pids: [WindowID: Int32] = [:]
    var nativeFullscreen = Set<WindowID>()
    var minimums: [WindowID: CGSize] = [:]
    var writes: [WindowID: [Rect]] = [:]
    var freshReads = 0
    var physicalMouseButtonsPressed = false
    var snapshotDelay: TimeInterval = 0
    let registry = WrittenFrameRegistry()
    let clock = Resize029Clock()

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
private final class Resize029Harness {
    let world: Resize029World
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
        let world = Resize029World()
        let input = UserInputActivity()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-spec029-resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let eventsPath = root.appendingPathComponent("events.jsonl").path
        let scope = StageScope(displayID: world.display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: root.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: scope.displayID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: mode, members: world.frames.keys.sorted().map {
                PersistentStageMember(windowID: $0, bundleID: "test.resize.\($0.rawValue)", title: "Test",
                                      frame: world.frames[$0]!, pid: Int32($0.rawValue + 100))
            }, bspTree: resize029Tree)])], activeDisplayID: scope.displayID))
        let replay = ReplayableSnapshotProvider(base: world)
        let service = SnapshotService(provider: replay, frameWriter: world,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0, gapsInner: 0)),
            intentStore: LayoutIntentStore(path: root.appendingPathComponent("intents.json").path),
            stageStore: store, clock: { world.clock.now }, frameRegistry: world.registry)
        // Le booléen est partagé sans capturer self avant la fin de l'initialisation.
        let probe = Resize029Probe()
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

    private let probe: Resize029Probe
    func setUserSpace(_ value: Bool) { probe.value = value }
    var events: String { (try? String(contentsOfFile: eventsPath, encoding: .utf8)) ?? "" }
    var manualGestures: Int { events.components(separatedBy: "\"type\":\"layout_manual_gesture\"").count - 1 }

    func drag(_ id: WindowID = resize029First, publishing frame: Rect? = nil) {
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

private final class Resize029Probe { var value = true }

@Suite @MainActor
struct Spec029ResizeTests {
    @Test
    func delayedMouseUpWithinGraceKeepsItsRealReleaseTime() {
        let input = UserInputActivity()
        let start = Date(timeIntervalSince1970: 100)
        var releases: [Bool] = []
        input.observeGestures(target: { _ in (7, CGRect(x: 0, y: 0, width: 500, height: 500)) },
                              onRelease: { releases.append($0) })
        input.mouseDown(at: .zero, now: start)
        input.mouseDragged()
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start))
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.2)))
        input.mouseUp(leftButton: true, now: start.addingTimeInterval(0.25))

        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.25)))
        #expect(input.takeGesture()?.endedAt == start.addingTimeInterval(0.25))
        #expect(releases == [true])
        #expect(input.takeGesture() == nil)
    }

    @Test
    func lostMouseUpRecoversTheResizeOnceAndIgnoresALateCallback() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.input.mouseDown(at: CGPoint(x: 499, y: 250), now: h.world.clock.now)
        h.input.mouseDragged()
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        #expect(h.maintainer.tick(cause: "ax:AXWindowResized").commands == 0)
        h.world.clock.advance(0.31)
        _ = h.maintainer.tick(cause: "ax:AXWindowResized")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.world.frames[resize029Second]?.x == 700)
        #expect(h.input.currentGesture == nil)
        #expect(h.input.takeGesture() == nil)
        h.input.mouseUp(leftButton: true, now: h.world.clock.now)
        _ = h.maintainer.tick(cause: "drag")
        #expect(h.manualGestures == 1)
        #expect(h.world.writes[resize029First] == nil)
    }

    @Test
    func lostMouseUpWithoutTargetUnblocksWithoutCreatingAGesture() {
        let input = UserInputActivity()
        let start = Date(timeIntervalSince1970: 100)
        input.observeGestures(target: { _ in nil }, onRelease: { _ in })
        input.mouseDown(at: .zero, now: start)
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start))
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.31)))
        #expect(input.currentGesture == nil)
        #expect(input.takeGesture() == nil)
    }

    @Test
    func pressedPhysicalButtonsKeepBlockingAndRestartTheReleaseGrace() {
        let input = UserInputActivity()
        let start = Date(timeIntervalSince1970: 100)
        input.observeGestures(target: { _ in (7, .zero) }, onRelease: { _ in })
        input.mouseDown(at: .zero, now: start)
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start))
        #expect(input.blocksLayout(mouseButtonsPressed: true, now: start.addingTimeInterval(100)))
        #expect(input.blocksLayout(mouseButtonsPressed: true, now: start.addingTimeInterval(1000)))
        #expect(input.currentGesture != nil)
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(1000.1)))
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(1000.3)))
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(1000.41)))
        #expect(input.takeGesture()?.endedAt == start.addingTimeInterval(1000.1))
    }

    @Test
    func aNewMouseDownStartsItsOwnRecoveryGrace() {
        let input = UserInputActivity()
        let start = Date(timeIntervalSince1970: 100)
        input.observeGestures(target: { _ in (7, .zero) }, onRelease: { _ in })
        input.mouseDown(at: .zero, now: start)
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start))
        input.mouseDown(at: .zero, now: start.addingTimeInterval(0.25))
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.26)))
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.51)))
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.57)))
        let recovered = input.takeGesture()
        #expect(recovered?.startedAt == start.addingTimeInterval(0.25))
        #expect(recovered?.endedAt == start.addingTimeInterval(0.26))
    }

    @Test
    func recoveredGesturesKeepTheExistingSameWindowCoalescence() {
        let input = UserInputActivity()
        let start = Date(timeIntervalSince1970: 100)
        var frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        input.observeGestures(target: { _ in (7, frame) }, onRelease: { _ in })
        input.mouseDown(at: .zero, now: start)
        input.mouseDragged()
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start))
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.31)))
        frame.size.width = 600
        input.mouseDown(at: .zero, now: start.addingTimeInterval(0.5))
        input.mouseDragged()
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.5)))
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: start.addingTimeInterval(0.81)))
        let recovered = input.takeGesture()
        #expect(recovered?.startFrame?.width == 500)
        #expect(recovered?.startedAt == start)
        #expect(recovered?.endedAt == start.addingTimeInterval(0.5))
        #expect(recovered?.didDrag == true)
        #expect(input.takeGesture() == nil)
    }

    @Test
    func physicalReleaseBeforeMouseUpDoesNotOverwriteTheLiveResize() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.world.physicalMouseButtonsPressed = true
        h.input.mouseDown(at: CGPoint(x: 499, y: 250), now: h.world.clock.now)
        h.input.mouseDragged()
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        // AX annonce la taille avant que le callback global mouseUp ait fermé la session.
        h.world.physicalMouseButtonsPressed = false
        let beforeCallback = h.maintainer.tick(cause: "ax:AXWindowResized")

        #expect(beforeCallback.commands == 0)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.input.currentGesture?.windowID == resize029First.rawValue)
        h.input.mouseUp(leftButton: true, now: h.world.clock.now)
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.world.frames[resize029Second]?.x == 700)
        #expect(h.world.writes[resize029First] == nil)
    }

    @Test
    func mouseDownWithoutTargetStillBlocksUntilItsReleaseCallback() {
        let input = UserInputActivity()
        input.observeGestures(target: { _ in nil }, onRelease: { _ in })
        input.mouseDown(at: CGPoint(x: 10, y: 10))

        #expect(input.currentGesture != nil)
        #expect(input.currentGesture?.windowID == nil)
        #expect(input.blocksLayout(mouseButtonsPressed: false))
        input.mouseUp(leftButton: true)
        #expect(!input.blocksLayout(mouseButtonsPressed: false))
        #expect(input.takeGesture() == nil)
        #expect(input.blocksLayout(mouseButtonsPressed: true))
    }

    @Test
    func lateSizeAfterReleaseStillMovesFence() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        let first = h.maintainer.tick(cause: "drag")
        #expect(first.commands == 0)
        #expect(h.maintainer.nextDeadline(now: h.world.clock.now) != nil)

        h.world.clock.advance(0.05)
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.world.frames[resize029Second] == Rect(x: 700, y: 0, width: 300, height: 500))
        #expect(h.world.writes[resize029First] == nil)
    }

    @Test
    func freshAXSizeCanArriveBeforeTheGlobalSnapshot() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        _ = h.maintainer.tick(cause: "drag")
        h.world.clock.advance(0.05)
        h.world.laggedFrames[resize029First] = resize029Left
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 650, height: 500)

        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029Second]?.x == 650)
        #expect(h.world.writes[resize029First] == nil)
    }

    @Test
    func gestureDuringSettlingScopeIsKept() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.world.nativeFullscreen.insert(resize029Second)
        h.world.frames[resize029Second] = Rect(x: 0, y: 0, width: 1000, height: 500)
        _ = h.maintainer.tick(cause: "ax:AXWindowResized")
        h.world.clock.advance(5)
        h.world.nativeFullscreen.remove(resize029Second)
        h.world.frames[resize029Second] = resize029Right
        h.world.frames[resize029First] = resize029Left
        h.setUserSpace(false)
        h.drag(publishing: Rect(x: 0, y: 0, width: 700, height: 500))

        #expect(h.maintainer.tick(cause: "drag").commands == 0)
        h.world.clock.advance(0.05)
        h.setUserSpace(true)
        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.world.frames[resize029Second]?.x == 700)
    }

    @Test
    func simpleClickDoesNotPollOrChangeTheTree() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.input.mouseDown(at: CGPoint(x: 200, y: 200), now: h.world.clock.now)
        h.input.mouseUp(leftButton: true, now: h.world.clock.now)
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.maintainer.nextDeadline(now: h.world.clock.now) == nil)
        #expect(h.world.freshReads == 0)
        #expect(h.store.state().bspTree(for: h.scope) == resize029Tree)
    }

    @Test
    func gestureWithoutSizeChangeExpiresWithoutFurtherPolling() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        _ = h.maintainer.tick(cause: "drag")
        for _ in 0..<8 {
            h.world.clock.advance(0.05)
            _ = h.maintainer.tick(cause: "deadline")
        }
        let reads = h.world.freshReads
        h.world.clock.advance(5)
        _ = h.maintainer.tick(cause: "safety")

        #expect(h.manualGestures == 0)
        #expect(h.maintainer.nextDeadline(now: h.world.clock.now) == nil)
        #expect(reads <= 7)
        #expect(h.world.freshReads == reads)
    }

    @Test
    func guardTimeDoesNotConsumeTheShortActiveObservationWindow() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.world.nativeFullscreen.insert(resize029Second)
        h.world.frames[resize029Second] = Rect(x: 0, y: 0, width: 1000, height: 500)
        _ = h.maintainer.tick(cause: "ax:AXWindowResized")
        h.world.clock.advance(5)
        h.world.nativeFullscreen.remove(resize029Second)
        h.world.frames[resize029Second] = resize029Right
        h.world.frames[resize029First] = resize029Left
        h.setUserSpace(false)
        h.drag()
        _ = h.maintainer.tick(cause: "drag")
        h.world.clock.advance(0.8)
        h.setUserSpace(true)
        _ = h.maintainer.tick(cause: "deadline")
        h.world.clock.advance(0.05)
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029Second]?.x == 700)
    }

    @Test(arguments: [false, true])
    func resizeObservationStartedOnTimeSurvivesASlowSnapshot(pendingPoll: Bool) throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        if pendingPoll {
            _ = h.maintainer.tick(cause: "drag")
            h.world.clock.advance(0.05)
        }
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        h.world.snapshotDelay = 3
        _ = h.maintainer.tick(cause: "drag")
        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 700)
        #expect(h.world.frames[resize029Second]?.x == 700)
    }

    @Test
    func anOldReleaseCannotBeReplayedAfterTheAbsoluteLimit() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        // Le maintainer peut être retenu par une suspension globale : la borne reste le relâchement.
        h.world.clock.advance(2.1)
        h.world.frames[resize029First] = Rect(x: 0, y: 0, width: 700, height: 500)
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.manualGestures == 0)
        #expect(h.store.state().bspTree(for: h.scope) == resize029Tree)
    }

    @Test(arguments: ["pid", "missing", "scope", "fullscreen"])
    func invalidIdentityOrScopeCancelsThePendingGesture(change: String) throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        _ = h.maintainer.tick(cause: "drag")
        h.world.clock.advance(0.05)
        switch change {
        case "pid": h.world.pids[resize029First] = 999
        case "missing": h.world.frames[resize029First] = nil
        case "scope":
            h.store.mutate { state in
                var old = state.scopes[0].stages[0]
                let member = old.members.first { $0.windowID == resize029First }
                old.members.removeAll { $0.windowID == resize029First }
                state.scopes[0].stages[0] = old
                state.scopes[0].stages.append(PersistentStage(id: StageID(rawValue: "2"), mode: .spatialBsp,
                    members: member.map { [$0] } ?? [], bspTree: .leaf(resize029First)))
            }
        default: h.world.nativeFullscreen.insert(resize029First)
        }
        _ = h.maintainer.tick(cause: "deadline")
        h.world.clock.advance(3)
        _ = h.maintainer.tick(cause: "safety")

        #expect(h.manualGestures == 0)
    }

    @Test
    func outerEdgeStillSnapsBackToTheTiledContainer() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag(publishing: Rect(x: 80, y: 0, width: 420, height: 500))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.manualGestures == 0)
        #expect(h.world.frames[resize029First] == resize029Left)
        #expect(h.store.state().bspTree(for: h.scope) == resize029Tree)
    }

    @Test
    func newerGestureReplacesTheWaitingWindow() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag()
        _ = h.maintainer.tick(cause: "drag")
        h.world.clock.advance(0.05)
        h.drag(resize029Second, publishing: Rect(x: 600, y: 0, width: 400, height: 500))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.manualGestures == 1)
        #expect(h.world.frames[resize029First]?.width == 600)
        #expect(h.world.frames[resize029Second]?.width == 400)
    }

    @Test
    func recognizedDropStillConsumesTheGesture() throws {
        let h = try Resize029Harness()
        defer { h.dispose() }
        h.drag(publishing: Rect(x: 0, y: 0, width: 700, height: 500))
        h.dragActivity.finish(now: h.world.clock.now, droppedWindowID: resize029First)
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.manualGestures == 0)
        #expect(h.store.state().bspTree(for: h.scope) == resize029Tree)
    }

    @Test
    func positionOnlyGestureHeldByACommandRearmsAFutureDeadlineThenExpires() throws {
        let h = try Resize029Harness(mode: .bsp)
        defer { h.dispose() }
        h.commandActivity.markActive(reason: "test_position", scopes: [h.scope], now: h.world.clock.now, holdSeconds: 4)
        h.drag(publishing: Rect(x: 40, y: 0, width: 500, height: 500))
        _ = h.maintainer.tick(cause: "drag")

        let deadline = try #require(h.maintainer.nextDeadline(now: h.world.clock.now))
        #expect(deadline > h.world.clock.now)
        #expect(deadline <= h.world.clock.now.addingTimeInterval(0.051))
        h.world.clock.advance(2.1)
        _ = h.maintainer.tick(cause: "deadline")
        let afterExpiry = try #require(h.maintainer.nextDeadline(now: h.world.clock.now))
        #expect(afterExpiry > h.world.clock.now.addingTimeInterval(1))
        #expect(h.manualGestures == 0)
    }
}
