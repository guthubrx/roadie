import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct LayoutPersistenceV2Tests {
    @Test
    func dryRunReportsIdentityMatches() {
        let live = powerWindow(99, x: 100, app: "Terminal")
        let provider = PowerUserProvider(windows: [live])
        let writer = PowerUserWriter(provider: provider)
        let restore = RestoreSafetyService(
            service: SnapshotService(provider: provider, frameWriter: writer),
            frameWriter: writer,
            path: tempPath("layout-v2"),
            eventLog: EventLog(path: tempPath("layout-v2-events"))
        )
        let saved = RestoreWindowState(
            windowID: 1,
            identity: WindowIdentityV2(bundleID: live.bundleID, appName: live.appName, title: live.title),
            frame: live.frame,
            visibleFrame: powerDisplay().visibleFrame
        )
        #expect(restore.save(RestoreSafetySnapshot(windows: [saved])))

        let report = LayoutPersistenceV2Service(
            service: SnapshotService(provider: provider, frameWriter: writer),
            restore: restore
        ).dryRun()

        #expect(report.applied == false)
        #expect(report.matches.first?.accepted == true)
        #expect(report.matches.first?.liveWindowID == 99)
    }
}
