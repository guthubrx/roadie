import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

final class Drag143Backend: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    let screen: DisplaySnapshot
    private let lock = NSLock()
    private var entries: [WindowSnapshot]
    private var written: [(WindowID, CGRect)] = []
    private var updates: [WindowFrameUpdate] = []
    var blockedPID: Int32?
    let gate = DispatchSemaphore(value: 0)
    init(screen: DisplaySnapshot, windows: [WindowSnapshot]) { self.screen = screen; entries = windows }
    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [screen] }
    func windows() -> [WindowSnapshot] { lock.withLock { entries } }
    func setFrames(_ batch: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        lock.withLock { updates.append(contentsOf: batch) }
        var result: [WindowID: CGRect?] = [:]
        for update in batch { result[update.window.id] = setFrame(update.frame, of: update.window) }
        return result
    }
    var frameUpdates: [WindowFrameUpdate] { lock.withLock { updates } }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if window.pid == blockedPID { gate.wait() }
        return lock.withLock {
            written.append((window.id, frame))
            if let i = entries.firstIndex(where: { $0.id == window.id }) { entries[i].frame = Rect(frame) }
            return frame
        }
    }
    var writes: [(WindowID, CGRect)] { lock.withLock { written } }
    func frame(_ id: WindowID) -> CGRect? { lock.withLock { entries.first { $0.id == id }?.frame.cgRect } }
}

@MainActor final class Drag143Fixture {
    let directory: URL
    let store: StageStore
    let backend: Drag143Backend
    let service: SnapshotService
    let configService: ConfigReloadService
    let generations = PlacementGeneration()
    let context: DropPreviewContext
    let source = WindowID(rawValue: 1)
    let neighbor = WindowID(rawValue: 2)
    let third = WindowID(rawValue: 3)
    let scope: StageScope
    let live: LiveDropPreview
    let target = Rect(x: 600, y: 20, width: 300, height: 400)

    init(enabled: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("drag143-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screen = powerDisplay("drag143")
        let scope = StageScope(displayID: screen.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        self.scope = scope
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(source),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(neighbor), second: .leaf(third)))
        let windows = tree.place(in: screen.visibleFrame.cgRect, innerGap: 10).sorted { $0.key < $1.key }.map { id, frame in
            var window = powerWindow(id.rawValue, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
            window.pid = Int32(id.rawValue + 100)
            return window
        }
        backend = Drag143Backend(screen: screen, windows: windows)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let persistent = PersistentStageState(scopes: [PersistentStageScope(displayID: screen.id,
            activeStageID: scope.stageID, stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame) }, bspTree: tree)])], activeDisplayID: screen.id)
        store.save(persistent)
        var display = DisplayState(id: screen.id, currentDesktopID: scope.desktopID)
        display.desktops[scope.desktopID]?.stages[scope.stageID] = StageState(id: scope.stageID, name: "Test", mode: .spatialBsp, windowIDs: windows.map(\.id))
        let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [screen],
            windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope) }, state: RoadieState(displays: [screen.id: display]))
        context = DropPreviewContext(snapshot: snapshot, persistedStateBeforeSnapshot: persistent)
        let path = directory.appendingPathComponent("config.toml").path
        try "[tiling]\nlive_drag_preview = \(enabled)\n".write(toFile: path, atomically: true, encoding: .utf8)
        configService = ConfigReloadService(activeConfig: try RoadieConfigLoader.load(from: path), activePath: path,
            eventLog: EventLog(path: directory.appendingPathComponent("config.jsonl").path))
        service = SnapshotService(provider: backend, frameWriter: backend,
            railSettings: RailSettings.load(raw: ""),
            railRuntimeStateStore: RailRuntimeStateStore(path: directory.appendingPathComponent("rail.json").path),
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path), stageStore: store,
            events: EventLog(path: directory.appendingPathComponent("service.jsonl").path),
            frameRegistry: WrittenFrameRegistry(), treeScopeApplications: TreeScopeApplicationCenter(), configService: configService)
        live = LiveDropPreview(service: service, generations: generations, activity: WindowDragActivity(enabled: false))
        live.begin(context)
    }
    func candidate(_ placements: [WindowID: Rect]? = nil) -> DropPreviewCandidate {
        DropPreviewCandidate(sourceWindowID: source, displayID: scope.displayID, scope: scope,
            orderedWindowIDs: [neighbor, source, third], placements: placements ?? [source: target, neighbor: target],
            frame: target.cgRect, operation: .insertRight, targetWindowID: neighbor)
    }
    func toggle(_ enabled: Bool) throws {
        let path = try #require(configService.state.activePath)
        try "[tiling]\nlive_drag_preview = \(enabled)\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = configService.reload(path: path)
    }
    func original(_ id: WindowID) -> CGRect { context.snapshot.windows.first { $0.window.id == id }!.window.frame.cgRect }
    func clean() { live.invalidate(); for _ in 0..<5 { backend.gate.signal() }; try? FileManager.default.removeItem(at: directory) }
    func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<150 { if condition() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

@Suite @MainActor struct Spec143LiveDragTests {
    @Test func liveNeighborsMoveWithoutWritingSourceOrPersistingPreview() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let before = try Data(contentsOf: f.store.fileURL)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        #expect(f.backend.writes.allSatisfy { $0.0 != f.source })
        #expect(try Data(contentsOf: f.store.fileURL) == before)
    }
    @Test func disabledDoesNotWriteAndToggleRestoresImmediately() async throws {
        let f = try Drag143Fixture(enabled: false); defer { f.clean() }
        f.live.update(f.candidate())
        #expect(f.backend.writes.isEmpty)
        try f.toggle(true); f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        try f.toggle(false); f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.original(f.neighbor) })
    }
    @Test func leavingCandidateRestoresAndDoesNotPersist() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let before = f.store.state()
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        f.live.update(nil)
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.original(f.neighbor) })
        #expect(f.store.state() == before)
    }
    @Test func changedCandidateRestoresPreviousNeighbors() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        f.live.update(f.candidate([f.source: f.target, f.third: f.target]))
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.original(f.neighbor) && f.backend.frame(f.third) == f.target.cgRect })
    }
    @Test func cancellationRestoresButCommitDoesNotBounceNeighborsBack() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        var committed = false
        f.live.finish { committed = true }
        #expect(await f.waitFor { committed })
        #expect(f.backend.frame(f.neighbor) == f.target.cgRect)
        f.live.begin(f.context)
        f.live.update(f.candidate([f.neighbor: Rect(x: 200, y: 0, width: 400, height: 400)]))
        #expect(await f.waitFor { f.backend.frame(f.neighbor)?.minX == 200 })
        f.live.finish()
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.original(f.neighbor) })
    }
    @Test func externalCommandAndStageChangeSuppressStaleDrop() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        f.generations.next()
        var committed = false
        f.live.finish { committed = true }
        #expect(!committed)
        let count = f.backend.writes.count
        f.live.update(f.candidate())
        #expect(f.backend.writes.count == count)
        f.live.begin(f.context)
        f.store.mutate { $0.setBSPTree(.leaf(f.source), for: f.scope) }
        f.live.update(f.candidate())
        f.live.finish { committed = true }
        #expect(!committed)
    }
    @Test func slowApplicationDoesNotBlockOthersAndNewClickCancelsDeferredDrop() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.backend.blockedPID = 102
        f.live.update(f.candidate([f.source: f.target, f.neighbor: f.target, f.third: f.target]))
        #expect(await f.waitFor { f.backend.frame(f.third) == f.target.cgRect })
        var committed = false
        f.live.finish { committed = true }
        f.live.begin(f.context)
        f.backend.gate.signal()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!committed)
    }
    @Test func settingPersistsAndDoesNotRetileOrClearIntents() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        #expect(TilingConfig().liveDragPreview)
        let path = try #require(f.configService.state.activePath)
        let settings = SettingsService(configPath: path, eventLog: EventLog(path: f.directory.appendingPathComponent("settings.jsonl").path), afterWrite: {})
        let descriptor = try #require(SettingsCatalog.all.first { $0.id == "tiling.live_drag_preview" })
        #expect(descriptor.category == .tuilage)
        var retiles = 0
        let controller = SettingsLiveApplyController(configService: f.configService, stageStore: f.store,
            events: EventLog(path: f.directory.appendingPathComponent("live.jsonl").path), onLayoutChange: { _ in retiles += 1 })
        _ = settings.set(descriptor.id, to: "false")
        _ = f.configService.reload(path: path)
        controller.applyChange(configPath: path, settingID: descriptor.id)
        #expect(retiles == 0)
        #expect(try !RoadieConfigLoader.load(from: path).tiling.liveDragPreview)
        _ = settings.reset(descriptor.id)
        #expect(try RoadieConfigLoader.load(from: path).tiling.liveDragPreview)
    }
}
