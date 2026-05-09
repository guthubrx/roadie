import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct RestoreSafetyTests {
    @Test
    func restoreSnapshotEncodesAndDecodes() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let writer = PowerUserWriter(provider: provider)
        let path = tempPath("restore-safety")
        let restore = RestoreSafetyService(
            service: SnapshotService(provider: provider, frameWriter: writer),
            frameWriter: writer,
            path: path,
            eventLog: EventLog(path: tempPath("restore-events"))
        )

        let snapshot = restore.capture()
        #expect(restore.save(snapshot))

        let loaded = try #require(restore.load())
        #expect(loaded.windows.count == 1)
        #expect(loaded.windows.first?.identity.title == "Window 1")
    }

    @Test
    func saveSuppressesUnchangedSnapshotEvents() {
        let eventLog = EventLog(path: tempPath("restore-unchanged-events"))
        let restore = RestoreSafetyService(
            path: tempPath("restore-unchanged"),
            eventLog: eventLog
        )
        let window = RestoreWindowState(
            windowID: 1,
            identity: WindowIdentityV2(bundleID: "com.apple.Terminal", appName: "Terminal", title: "shell"),
            frame: Rect(x: 10, y: 20, width: 500, height: 400),
            visibleFrame: powerDisplay().visibleFrame
        )
        let first = RestoreSafetySnapshot(
            createdAt: Date(timeIntervalSince1970: 1),
            daemonPID: 1234,
            windows: [window],
            activeDisplayID: "display-1",
            activeDesktop: "1",
            activeStage: "1"
        )
        let sameStateLater = RestoreSafetySnapshot(
            createdAt: Date(timeIntervalSince1970: 2),
            daemonPID: 1234,
            windows: [window],
            activeDisplayID: "display-1",
            activeDesktop: "1",
            activeStage: "1"
        )
        let changed = RestoreSafetySnapshot(
            createdAt: Date(timeIntervalSince1970: 3),
            daemonPID: 1234,
            windows: [window],
            activeDisplayID: "display-1",
            activeDesktop: "1",
            activeStage: "2"
        )

        #expect(restore.save(first))
        #expect(restore.save(sameStateLater))
        #expect(eventLog.envelopes(limit: 10).filter { $0.type == "restore.snapshot_written" }.count == 1)

        #expect(restore.save(changed))
        #expect(eventLog.envelopes(limit: 10).filter { $0.type == "restore.snapshot_written" }.count == 2)
    }

    @Test
    func restoreUsesStableIdentityWhenWindowIDChanged() {
        let live = WindowSnapshot(
            id: WindowID(rawValue: 99),
            pid: 99,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "shell",
            frame: Rect(x: 700, y: 100, width: 300, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let provider = PowerUserProvider(windows: [live])
        let writer = PowerUserWriter(provider: provider)
        let restore = RestoreSafetyService(
            service: SnapshotService(provider: provider, frameWriter: writer),
            frameWriter: writer,
            path: tempPath("restore-identity"),
            eventLog: EventLog(path: tempPath("restore-identity-events"))
        )
        let saved = RestoreWindowState(
            windowID: 1,
            identity: WindowIdentityV2(bundleID: "com.apple.Terminal", appName: "Terminal", title: "shell"),
            frame: Rect(x: 10, y: 20, width: 500, height: 400),
            visibleFrame: powerDisplay().visibleFrame
        )

        let result = restore.restore(RestoreSafetySnapshot(windows: [saved]))

        #expect(result.restored == 1)
        #expect(writer.frames[WindowID(rawValue: 99)] == saved.frame)
    }
}
