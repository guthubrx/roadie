import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite struct Spec037WindowDragTests {
    @Test func expirationIsReadOnlyAndExpiredDropIsIgnored() throws {
        let path = tempPath("drag037-expiry")
        let now = Date(timeIntervalSince1970: 1000)
        let activity = WindowDragActivity(path: path)
        activity.finish(now: now, graceSeconds: 1, droppedWindowID: WindowID(rawValue: 7))
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(!activity.isActive(now: now.addingTimeInterval(2)))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
        #expect(activity.lastDrop(now: now.addingTimeInterval(2)) == nil)
        #expect(activity.lastDrop(now: now.addingTimeInterval(0.5))?.windowID == WindowID(rawValue: 7))
    }

    @Test(arguments: ["mark", "finish", "release", "reset"])
    func sharedMutationsRespectTheFileTransaction(operation: String) throws {
        let path = tempPath("drag037-lock-\(operation)")
        let activity = WindowDragActivity(path: path)
        let fileLock = FileLock(path: path + ".lock")
        try fileLock.acquire()
        defer { fileLock.release() }
        let started = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        Thread {
            started.signal()
            switch operation {
            case "mark": activity.markActive(windowID: WindowID(rawValue: 7))
            case "finish": activity.finish(droppedWindowID: WindowID(rawValue: 7))
            case "release": activity.release()
            default: activity.reset()
            }
            completed.signal()
        }.start()
        #expect(started.wait(timeout: .now() + 1) == .success)
        #expect(completed.wait(timeout: .now() + 0.05) == .timedOut)
        fileLock.release()
        #expect(completed.wait(timeout: .now() + 2) == .success)
    }

    @Test func disabledResetDoesNotDeleteSharedState() throws {
        let path = tempPath("drag037-disabled")
        try "sentinel".write(toFile: path, atomically: true, encoding: .utf8)
        WindowDragActivity(path: path, enabled: false).reset()
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "sentinel")
    }
}
