import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Audit035ConfigTests {
    @Test(arguments: [false, true])
    func olderAutomaticLoadCannotOverwriteANewerPublication(explicitReload: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.toml")
        let second = directory.appendingPathComponent("second.toml")
        try "[tiling]\ngaps_inner = 11\n".write(to: first, atomically: true, encoding: .utf8)
        try "[tiling]\ngaps_inner = 29\n".write(to: second, atomically: true, encoding: .utf8)
        let gate = ConfigLoadGate()
        let service = ConfigReloadService(
            activePath: first.path,
            eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path),
            now: { gate.now() }
        )
        let completed = DispatchSemaphore(value: 0)
        Thread {
            _ = service.currentConfig()
            completed.signal()
        }.start()
        defer { gate.resume.signal() }
        try #require(gate.entered.wait(timeout: .now() + 3) == .success)
        if explicitReload {
            #expect(service.reload(path: second.path).status == .applied)
        } else {
            // A second caller publishes a newer version of the same path.
            try "[tiling]\ngaps_inner = 37\n".write(to: first, atomically: true, encoding: .utf8)
            #expect(service.currentConfig().tiling.gapsInner == 37)
        }
        let publishedAt = service.state.lastAppliedAt
        gate.resume.signal()
        try #require(completed.wait(timeout: .now() + 3) == .success)
        #expect(service.activeConfig.tiling.gapsInner == (explicitReload ? 29 : 37))
        #expect(service.state.activePath == (explicitReload ? second.path : first.path))
        #expect(service.state.lastAppliedAt == publishedAt)
    }
}

private final class ConfigLoadGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var first = true

    func now() -> Date {
        let date = Date()
        let suspend = lock.withLock {
            let value = first
            first = false
            return value
        }
        if suspend {
            entered.signal()
            _ = resume.wait(timeout: .now() + 5)
        }
        return date
    }
}
