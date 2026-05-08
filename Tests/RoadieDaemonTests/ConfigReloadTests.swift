import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct ConfigReloadTests {
    @Test
    func reloadAppliesValidConfig() throws {
        let url = try #require(Bundle.module.url(forResource: "control-safety-valid", withExtension: "toml"))
        let eventPath = tempPath("config-reload-events")
        let service = ConfigReloadService(activeConfig: RoadieConfig(), activePath: url.path, eventLog: EventLog(path: eventPath))

        let result = service.reload(path: url.path)

        #expect(result.status == .applied)
        #expect(service.state.lastValidation == .success)
        #expect(service.activeConfig.configReload.debounceMS == 250)
        #expect(service.state.activeVersion != nil)
    }

    @Test
    func reloadKeepsPreviousConfigWhenValidationFails() throws {
        let valid = try #require(Bundle.module.url(forResource: "control-safety-valid", withExtension: "toml"))
        let invalid = try #require(Bundle.module.url(forResource: "control-safety-invalid", withExtension: "toml"))
        let initial = try RoadieConfigLoader.load(from: valid.path)
        let service = ConfigReloadService(activeConfig: initial, activePath: valid.path, eventLog: EventLog(path: tempPath("config-reload-failed-events")))

        let result = service.reload(path: invalid.path)

        #expect(result.status == .failedKeepingPrevious)
        #expect(service.state.lastValidation == .failed)
        #expect(service.activeConfig == initial)
        #expect(result.activeVersion == service.state.activeVersion)
    }
}
