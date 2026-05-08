import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct Spec002RegressionTests {
    @Test
    func spec002CoreSurfacesRemainAvailableTogether() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))
        let snapshot = snapshotService.snapshot()

        #expect(!AutomationEventCatalog.minimumEventTypes.isEmpty)
        #expect(snapshot.automationSnapshot().windows.count == 2)
        #expect(AutomationQueryService(service: snapshotService).query("state").kind == "state")
        #expect(WindowRuleValidator.validate((try RoadieConfigLoader.load(from: fixturePath())).rules).isEmpty)
    }
}
