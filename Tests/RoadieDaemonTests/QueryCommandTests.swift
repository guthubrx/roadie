import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct QueryCommandTests {
    @Test
    func queryStateAndWindowsExposeStablePayloads() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = AutomationQueryService(service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)))

        let state = service.query("state")
        let windows = service.query("windows")

        #expect(state.kind == "state")
        #expect(windows.kind == "windows")
        if case .array(let rows) = windows.data {
            #expect(rows.count == 1)
        } else {
            Issue.record("windows query did not return an array")
        }
    }

    @Test
    func queryDisplaysDesktopsStagesGroupsAndRulesExposePayloads() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let store = StageStore(path: tempPath("query-groups"))
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = snapshotService.snapshot()
        _ = WindowGroupCommandService(service: snapshotService, store: store).create(
            id: "pair",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        )
        let query = AutomationQueryService(service: snapshotService, configPath: try fixturePath())

        #expect(query.query("displays").kind == "displays")
        #expect(query.query("desktops").kind == "desktops")
        #expect(query.query("stages").kind == "stages")
        #expect(query.query("groups").kind == "groups")
        #expect(query.query("rules").kind == "rules")
    }

    @Test
    func queryConfigReloadExposesState() {
        let service = AutomationQueryService()
        let result = service.query("config_reload")

        #expect(result.kind == "config_reload")
        if case .object(let object) = result.data {
            #expect(object["lastValidation"] != nil)
        } else {
            Issue.record("config_reload query did not return an object")
        }
    }
}
