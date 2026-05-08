import Testing
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct WindowGroupStoreTests {
    @Test
    func persistentStageStoresGroups() {
        let path = tempPath("window-group-store")
        let store = StageStore(path: path)
        var state = PersistentStageState()
        var scope = state.scope(displayID: DisplayID(rawValue: "display-main"))
        scope.stages[0].groups = [
            WindowGroup(id: "docs", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], activeWindowID: WindowID(rawValue: 2))
        ]
        state.update(scope)

        store.save(state)
        let loaded = store.state()

        #expect(loaded.scopes.first?.stages.first?.groups.first?.id == "docs")
        #expect(loaded.scopes.first?.stages.first?.groups.first?.activeWindowID == WindowID(rawValue: 2))
    }
}
