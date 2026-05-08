import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct ControlCenterStateTests {
    @Test
    func stateReportsRunningDaemonConfigAndWindowContext() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))
        let state = ControlCenterStateService(service: service, configPath: nil, eventLog: EventLog(path: tempPath("control-events"))).state()

        #expect([DaemonStatus.running, .degraded].contains(state.daemonStatus))
        #expect(state.configStatus == .valid)
        #expect(state.windowCount == 1)
        #expect(state.actions.canReloadConfig)
        #expect(state.activeDesktop == "1")
    }
}
