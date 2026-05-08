import Testing
import RoadieDaemon

@Suite
struct LegacyQueryCompatibilityTests {
    @Test
    func legacySnapshotFormatsRemainEncodableAlongsideQueries() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))
        let snapshot = snapshotService.snapshot()

        let stateJSON = try SnapshotEncoding.json(snapshot)
        let treeJSON = try SnapshotEncoding.json(TreeDumpService(service: snapshotService).dump())
        let query = AutomationQueryService(service: snapshotService).query("windows")

        #expect(stateJSON.contains("\"windows\""))
        #expect(treeJSON.contains("\"displays\""))
        #expect(query.kind == "windows")
    }
}
