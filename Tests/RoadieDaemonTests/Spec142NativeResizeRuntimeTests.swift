import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

private final class Native142Backend: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    private let lock = NSLock()
    let screen: DisplaySnapshot
    private var entries: [WindowSnapshot]
    private var writes: [(WindowID, CGRect)] = []
    private var missingReads = 0
    private var skipped = 0
    var blockedPID: Int32?
    let gate = DispatchSemaphore(value: 0)
    init(screen: DisplaySnapshot, windows: [WindowSnapshot]) { self.screen = screen; entries = windows }
    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [screen] }
    func windows() -> [WindowSnapshot] { lock.withLock { entries } }
    func readFrame(of window: WindowSnapshot) -> CGRect? {
        lock.withLock {
            if missingReads > 0 { missingReads -= 1; skipped += 1; return nil }
            return entries.first { $0.id == window.id }?.frame.cgRect
        }
    }
    func skipReads(_ count: Int) { lock.withLock { missingReads = count } }
    var skippedReadCount: Int { lock.withLock { skipped } }
    func move(_ id: WindowID, to frame: CGRect) {
        lock.withLock { if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].frame = Rect(frame) } }
    }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if window.pid == blockedPID { gate.wait() }
        lock.withLock {
            writes.append((window.id, frame))
            if let i = entries.firstIndex(where: { $0.id == window.id }) { entries[i].frame = Rect(frame) }
        }
        return frame
    }
    var requests: [(WindowID, CGRect)] { lock.withLock { writes } }
}

@MainActor private final class Native142Fixture {
    let directory: URL
    let store: StageStore
    let backend: Native142Backend
    let service: SnapshotService
    let input = UserInputActivity()
    let generations = PlacementGeneration()
    let scope: StageScope
    let tree: BSPTree
    let snapshot: DaemonSnapshot
    let source: WindowSnapshot
    var runtime: NativeResizeRuntime!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("native142-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screen = powerDisplay("native142")
        let scope = StageScope(displayID: screen.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        self.scope = scope
        tree = .split(orientation: .vertical, ratio: 0.5, first: .leaf(WindowID(rawValue: 1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 2)), second: .leaf(WindowID(rawValue: 3))))
        let windows = tree.place(in: screen.visibleFrame.cgRect, innerGap: 10).sorted { $0.key < $1.key }.map { id, frame -> WindowSnapshot in
            var window = powerWindow(id.rawValue, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
            window.pid = Int32(id.rawValue + 100)
            return window
        }
        source = windows[0]
        backend = Native142Backend(screen: screen, windows: windows)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: screen.id,
            activeStageID: scope.stageID, stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame) }, bspTree: tree)])],
            activeDisplayID: screen.id))
        var display = DisplayState(id: screen.id, currentDesktopID: scope.desktopID)
        display.desktops[scope.desktopID]?.stages[scope.stageID] = StageState(id: scope.stageID, name: "Test", mode: .spatialBsp, windowIDs: windows.map(\.id))
        snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [screen],
            windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope, pin: nil, isNewlyScoped: false) },
            state: RoadieState(displays: [screen.id: display]))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10))
        service = SnapshotService(provider: backend, frameWriter: backend, config: config, railSettings: RailSettings.load(raw: ""),
            railRuntimeStateStore: RailRuntimeStateStore(path: directory.appendingPathComponent("rail.json").path),
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path), stageStore: store,
            events: EventLog(path: directory.appendingPathComponent("service.jsonl").path), userInput: input,
            frameRegistry: WrittenFrameRegistry(), treeScopeApplications: TreeScopeApplicationCenter())
        let backend = backend
        runtime = NativeResizeRuntime(service: service, input: input, generations: generations, automaticCadence: false,
            readFrame: { backend.readFrame(of: $0) }, events: EventLog(path: directory.appendingPathComponent("events.jsonl").path))
        input.observeGestures(target: { [source] _ in (source.id.rawValue, source.frame.cgRect) }, onRelease: { [weak runtime] _ in runtime?.end() })
    }
    func begin() throws {
        input.mouseDown(at: CGPoint(x: source.frame.cgRect.maxX - 1, y: source.frame.cgRect.midY))
        input.mouseDragged()
        #expect(runtime.begin(try #require(input.currentGesture), snapshot: snapshot))
    }
    func frame(wider: CGFloat) -> CGRect { var f = source.frame.cgRect; f.size.width += wider; return f }
    func clean() { runtime.cancel(); backend.gate.signal(); backend.gate.signal(); try? FileManager.default.removeItem(at: directory) }
    func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if condition() { return true }
            runtime.pulse()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@Suite @MainActor struct Spec142NativeResizeRuntimeTests {
    @Test func liveNeighborsMoveWithoutWritingNativeSourceOrPersistingEachFrame() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        _ = f.service.sharedSnapshot(followFocus: false)
        try f.begin()
        let before = try Data(contentsOf: f.store.fileURL)
        f.backend.move(f.source.id, to: f.frame(wider: 100))
        #expect(await f.waitFor { f.backend.requests.count >= 2 })
        #expect(f.runtime.isConfirmed)
        #expect(f.backend.requests.allSatisfy { $0.0 != f.source.id })
        #expect(f.service.cachedGestureSnapshot()?.windows.first { $0.window.id == f.source.id }?.window.frame.cgRect == f.frame(wider: 100))
        #expect(try Data(contentsOf: f.store.fileURL) == before)
        #expect(f.input.currentGesture != nil)
        f.input.mouseUp(leftButton: true)
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.store.state().bspTree(for: f.scope) != f.tree)
        #expect(f.input.takeGesture() == nil)
    }

    @Test func titleDragAndContentSelectionKeepOrdinaryGesture() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.source.frame.cgRect.offsetBy(dx: 30, dy: 20))
        f.input.mouseUp(leftButton: true)
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.backend.requests.isEmpty)
        #expect(f.store.state().bspTree(for: f.scope) == f.tree)
        #expect(f.input.takeGesture()?.windowID == f.source.id.rawValue)
    }

    @Test func externalGenerationCancelsWithoutPersistingStaleRatios() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 80))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.generations.next()
        f.runtime.pulse()
        #expect(!f.runtime.isHoldingLayout)
        #expect(f.store.state().bspTree(for: f.scope) == f.tree)
    }

    @Test func finalFrameAfterMouseUpIsUsedForPersistence() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 40))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.input.mouseUp(leftButton: true)
        // Le cadre change après mouseUp, avant l'observation finale. Aucun délai de
        // lancement dépendant de la disponibilité du MainActor de toute la suite.
        f.backend.move(f.source.id, to: f.frame(wider: 120))
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        let saved = try #require(f.store.state().bspTree(for: f.scope))
        #expect(saved.place(in: f.backend.screen.visibleFrame.cgRect, innerGap: 10)[f.source.id]?.width == f.frame(wider: 120).width)
    }

    @Test func slowNeighborDoesNotBlockOtherPIDAndPendingFramesAreCoalesced() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        f.backend.blockedPID = 102
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 20))
        #expect(await f.waitFor { f.backend.requests.contains { $0.0.rawValue == 3 } })
        for amount in [40, 60, 80, 100] {
            f.backend.move(f.source.id, to: f.frame(wider: CGFloat(amount)))
            f.runtime.pulse()
            try? await Task.sleep(for: .milliseconds(15))
        }
        f.backend.gate.signal()
        f.backend.gate.signal()
        #expect(await f.waitFor { f.backend.requests.filter { $0.0.rawValue == 2 }.count >= 2 })
        #expect(f.backend.requests.filter { $0.0.rawValue == 2 }.count == 2)
        #expect(f.backend.requests.allSatisfy { $0.0 != f.source.id })
    }
    @Test func returningToStartWhileWriteIsBusyQueuesRestoration() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        f.backend.blockedPID = 102
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 80))
        #expect(await f.waitFor { f.backend.requests.contains { $0.0.rawValue == 3 } })
        f.backend.move(f.source.id, to: f.source.frame.cgRect)
        for _ in 0..<5 { f.runtime.pulse(); try? await Task.sleep(for: .milliseconds(5)) }
        f.backend.gate.signal(); f.backend.gate.signal()
        #expect(await f.waitFor { f.backend.requests.filter { $0.0.rawValue == 2 }.count >= 2 })
        let second = try #require(f.backend.requests.last { $0.0.rawValue == 2 })
        #expect(second.1 == f.snapshot.windows.first { $0.window.id.rawValue == 2 }?.window.frame.cgRect)
    }

    @Test(arguments: ["mode", "tree", "stage", "desktop", "zoom"])
    func changedContextCancelsSession(reason: String) async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 60))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        if reason == "zoom" {
            f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source.id], placements: [:],
                source: .command, zoomedWindowID: f.source.id))
        } else {
            f.store.mutate { state in
                switch reason {
                case "mode": state.scopes[0].stages[0].mode = .float
                case "tree": state.setBSPTree(.split(orientation: .vertical, ratio: 0.7,
                    first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))), for: f.scope)
                case "stage": state.scopes[0].activeStageID = StageID(rawValue: "other")
                default: state.desktopSelections.append(PersistentDesktopSelection(displayID: f.scope.displayID,
                    currentDesktopID: DesktopID(rawValue: 2)))
                }
            }
        }
        let expected = f.store.state()
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.store.state() == expected)
    }

    @Test func newClickWhileEndingDoesNotCommitOldTree() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        f.backend.blockedPID = 102
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 60))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.input.mouseUp(leftButton: true)
        f.input.mouseDown(at: f.source.frame.center)
        f.backend.gate.signal()
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.store.state().bspTree(for: f.scope) == f.tree)
    }

    @Test(arguments: [true, false]) func contentAndTitleDragsNeverStartNativeCadence(title: Bool) throws {
        let f = try Native142Fixture(); defer { f.clean() }
        let frame = f.source.frame.cgRect
        f.input.mouseDown(at: CGPoint(x: frame.midX, y: title ? frame.minY + 15 : frame.midY))
        f.input.mouseDragged()
        #expect(!f.runtime.begin(try #require(f.input.currentGesture), snapshot: f.snapshot))
        #expect(!f.runtime.isHoldingLayout)
        f.input.mouseUp(leftButton: true)
        #expect(f.input.takeGesture()?.windowID == f.source.id.rawValue)
    }

    @Test func endingWatchdogReleasesLayoutWithoutAcceptingOldObservation() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 60))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.runtime.end(at: Date().addingTimeInterval(-3))
        #expect(!f.runtime.isHoldingLayout)
        #expect(f.store.state().bspTree(for: f.scope) == f.tree)
        f.input.mouseUp(leftButton: true)
        #expect(f.input.takeGesture()?.windowID == f.source.id.rawValue)
        #expect(f.input.takeGesture() == nil)
    }

    @Test func oneMissingObservationDoesNotLoseNativeResize() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 40))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.backend.skipReads(1)
        f.runtime.pulse()
        #expect(await f.waitFor { f.backend.skippedReadCount == 1 })
        #expect(f.runtime.isHoldingLayout)
        f.backend.move(f.source.id, to: f.frame(wider: 100))
        #expect(await f.waitFor { f.backend.requests.contains { $0.1.minX == f.frame(wider: 100).maxX + 10 } })
        f.input.mouseUp(leftButton: true)
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.store.state().bspTree(for: f.scope) != f.tree)
    }

    @Test func persistentMissingObservationFallsBackToOrdinaryGestureExactlyOnce() async throws {
        let f = try Native142Fixture(); defer { f.clean() }
        try f.begin()
        f.backend.move(f.source.id, to: f.frame(wider: 60))
        #expect(await f.waitFor { f.runtime.isConfirmed })
        f.backend.skipReads(3)
        #expect(await f.waitFor { !f.runtime.isHoldingLayout })
        #expect(f.store.state().bspTree(for: f.scope) == f.tree)
        f.input.mouseUp(leftButton: true)
        #expect(f.input.takeGesture()?.windowID == f.source.id.rawValue)
        #expect(f.input.takeGesture() == nil)
    }

    @Test func absentPointerLocationCannotStartNativeSession() throws {
        let f = try Native142Fixture(); defer { f.clean() }
        #expect(!f.runtime.begin(GestureSession(windowID: f.source.id.rawValue,
            startFrame: f.source.frame.cgRect, startedAt: Date(), didDrag: true), snapshot: f.snapshot))
    }

}
