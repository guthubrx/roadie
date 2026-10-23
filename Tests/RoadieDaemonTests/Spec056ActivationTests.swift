import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Spec056ActivationTests {
    @Test
    func activationJoinsOwnerDisplayAndStageWithoutChangingOwnership() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let second = powerDisplay("display-2", index: 2, x: 1000)
        let other = spec056Window(1, x: 100)
        let target = spec056Window(2, x: 1100)
        let provider = PowerUserProvider(displays: [main, second], windows: [other, target])
        provider.focusedID = other.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-activation"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: other.id, members: [spec056Member(other)]),
            ]),
            PersistentStageScope(displayID: second.id, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), members: [spec056Member(target)]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let owner = store.state().stageScope(for: target.id)
        let entry = WindowSwitcherEntry(window: target, scope: owner)

        let result = WindowSwitcherService(service: service).activate(entry)

        #expect(result.changed)
        #expect(writer.focused.last == target.id)
        #expect(store.state().stageScope(for: target.id) == owner)
        #expect(owner?.displayID == second.id)
        #expect(owner?.stageID == StageID(rawValue: "2"))
    }

    @Test
    func closedWindowIsRefusedWithoutAnyMutation() {
        let window = spec056Window(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-closed"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [spec056Member(window)]),
            ]),
        ]))
        let before = store.state()
        let service = WindowSwitcherService(service: SnapshotService(provider: provider, frameWriter: writer, stageStore: store))
        let closed = WindowSwitcherEntry(window: spec056Window(9, x: 100), scope: nil)

        let activated = service.activate(closed)
        let closedAction = service.perform(.close, on: closed)

        #expect(!activated.changed)
        #expect(!closedAction.changed)
        #expect(writer.focused.isEmpty)
        #expect(store.state() == before)
    }

    @Test
    func fullscreenIsRefusedExplicitlyWithoutAWindowIdentity() {
        let window = spec056Window(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-fullscreen"))
        let service = WindowSwitcherService(service: SnapshotService(provider: provider, frameWriter: writer, stageStore: store))

        let result = service.perform(.fullscreen, on: WindowSwitcherEntry(window: window, scope: nil))

        #expect(!result.changed)
    }

    @Test
    func persistenceFailureStopsTheFocusTransaction() throws {
        let window = spec056Window(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let good = StageStore(path: tempPath("spec056-good"))
        good.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [spec056Member(window)]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: good)
        let owner = try #require(good.state().stageScope(for: window.id))
        let corruptPath = tempPath("spec056-corrupt")
        try "{ json invalide".write(toFile: corruptPath, atomically: true, encoding: .utf8)

        let result = WindowBookmarkCommandService(service: service, store: StageStore(path: corruptPath)).focusWindow(
            window,
            in: owner,
            snapshot: service.snapshot(followFocus: false),
            generation: PlacementGeneration.shared.next(),
            label: "switcher activate",
            cause: "switcher.activate",
            eventPrefix: "window.switcher",
            details: [:]
        )

        #expect(!result.changed)
        #expect(writer.focused.isEmpty)
    }
}

private func spec056Window(_ id: UInt32, x: Double) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: getpid(),
        appName: "App \(id)",
        bundleID: "app.\(id)",
        title: "Window \(id)",
        frame: Rect(x: x, y: 100, width: 300, height: 300),
        isOnScreen: true,
        isTileCandidate: true
    )
}

private func spec056Member(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(
        windowID: window.id,
        bundleID: window.bundleID,
        title: window.title,
        frame: window.frame,
        pid: window.pid
    )
}
