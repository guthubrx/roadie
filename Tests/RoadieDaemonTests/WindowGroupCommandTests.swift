import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct WindowGroupCommandTests {
    @Test
    func groupCommandsCreateAddFocusRemoveAndDissolve() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500), powerWindow(3, x: 700)])
        let store = StageStore(path: tempPath("window-group-commands"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        let groups = WindowGroupCommandService(service: service, store: store)

        #expect(groups.create(id: "terminals", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]).changed)
        #expect(groups.add(windowID: WindowID(rawValue: 3), to: "terminals").changed)
        #expect(groups.focus(windowID: WindowID(rawValue: 3), in: "terminals").changed)
        #expect(groups.remove(windowID: WindowID(rawValue: 2), from: "terminals").changed)
        #expect(groups.dissolve(id: "terminals").changed)
    }
}
