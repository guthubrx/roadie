import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct ConfigReloadTests {
    @Test func aBlockedReloadJournalLeavesTheActiveConfigReadable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        try "[tiling]\ngaps_inner = 27".write(to: file, atomically: true, encoding: .utf8)
        let events = dir.appendingPathComponent("events.jsonl")
        let lock = FileLock(path: FileLock.lockPath(for: events))
        try lock.acquire()
        defer { lock.release() }
        let started = DispatchSemaphore(value: 0)
        let reloaded = DispatchSemaphore(value: 0)
        let read = DispatchSemaphore(value: 0)
        let service = ConfigReloadService(activeConfig: RoadieConfig(), activePath: file.path,
            eventLog: EventLog(path: events.path), now: { started.signal(); return Date() })
        Thread {
            _ = service.reload(path: file.path)
            reloaded.signal()
        }.start()
        try #require(started.wait(timeout: .now() + 3) == .success)
        Thread {
            let before = ProcessInfo.processInfo.systemUptime
            _ = service.currentConfig()
            print("session158 reader_ms=\((ProcessInfo.processInfo.systemUptime - before) * 1000)")
            read.signal()
        }.start()
        let readBeforeUnlock = read.wait(timeout: .now() + 0.25) == .success
        lock.release()
        try #require(reloaded.wait(timeout: .now() + 3) == .success)
        #expect(readBeforeUnlock)
        #expect(service.activeConfig.tiling.gapsInner == 27)
    }

    @Test func replacingTheFileDuringReloadKeepsThePreviousPublication() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        let original = "[tiling]\ngaps_inner = 11"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        var calls = 0
        let previous = RoadieConfig()
        let service = ConfigReloadService(activeConfig: previous, activePath: file.path,
            eventLog: EventLog(path: dir.appendingPathComponent("events.jsonl").path), now: {
                calls += 1
                if calls == 2 {
                    do {
                        try original.replacingOccurrences(of: "11", with: "29").write(to: file, atomically: true, encoding: .utf8)
                        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
                    } catch { Issue.record("Remplacement du fichier de test impossible : \(error)") }
                }
                return Date()
            })
        let result = service.reload(path: file.path)
        #expect(result.status == .failedKeepingPrevious)
        #expect(service.activeConfig == previous)
        #expect(service.currentConfig().tiling.gapsInner == 29)
    }

    @Test
    func reloadAppliesValidConfig() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-valid-reload-\(UUID().uuidString).toml")
        try """
        [tiling]
        gaps_inner = 12
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let eventPath = tempPath("config-reload-events")
        let service = ConfigReloadService(activeConfig: RoadieConfig(), activePath: url.path, eventLog: EventLog(path: eventPath))

        let result = service.reload(path: url.path)

        #expect(result.status == .applied)
        #expect(service.state.lastValidation == .success)
        #expect(service.activeConfig.tiling.gapsInner == 12)
        #expect(service.state.activeVersion != nil)
    }

    @Test
    func reloadKeepsPreviousConfigWhenValidationFails() throws {
        let valid = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-valid-previous-\(UUID().uuidString).toml")
        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-invalid-reload-\(UUID().uuidString).toml")
        try """
        [tiling]
        gaps_inner = 10
        """.write(to: valid, atomically: true, encoding: .utf8)
        try """
        [tiling]
        gaps_inner = "not-a-number"
        """.write(to: invalid, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: valid)
            try? FileManager.default.removeItem(at: invalid)
        }

        let initial = try RoadieConfigLoader.load(from: valid.path)
        let service = ConfigReloadService(
            activeConfig: initial,
            activePath: valid.path,
            eventLog: EventLog(path: tempPath("config-reload-failed-events"))
        )

        let result = service.reload(path: invalid.path)

        #expect(result.status == .failedKeepingPrevious)
        #expect(service.state.lastValidation == .failed)
        #expect(service.activeConfig == initial)
        #expect(result.activeVersion == service.state.activeVersion)
    }
}
