import Testing
import RoadieDaemon

@Suite
struct RestoreWatcherTests {
    @Test
    func watcherRestoresOnlyWhenDaemonMissing() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let writer = PowerUserWriter(provider: provider)
        let restore = RestoreSafetyService(
            service: SnapshotService(provider: provider, frameWriter: writer),
            frameWriter: writer,
            path: tempPath("restore-watcher"),
            eventLog: EventLog(path: tempPath("restore-watcher-events"))
        )
        #expect(restore.save(restore.capture()))

        let alive = restore.restoreIfDaemonMissing(pid: 123, isAlive: { _ in true })
        let missing = restore.restoreIfDaemonMissing(pid: 123, isAlive: { _ in false })

        #expect(alive.restored == 0)
        #expect(missing.restored == 1)
    }
}
