import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct ConfigReloadTests {
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
