import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
struct Spec043ResizeSettingsTests {
    @Test @MainActor
    func togglingHandlesDoesNotRetileOrInvalidateIntents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "[tiling]\nresize_handles = true\n".write(toFile: path, atomically: true, encoding: .utf8)
        let events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        let config = ConfigReloadService(activeConfig: try RoadieConfigLoader.load(from: path), activePath: path, eventLog: events)
        var retiles = 0
        let controller = SettingsLiveApplyController(configService: config,
            stageStore: StageStore(path: directory.appendingPathComponent("stages.json").path),
            events: events, onLayoutChange: { _ in retiles += 1 })
        try "[tiling]\nresize_handles = false\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = config.reload(path: path)
        controller.applyChange(configPath: path, settingID: "tiling.resize_handles")
        #expect(retiles == 0)
        #expect(!config.currentConfig().tiling.resizeHandles)
    }

    @Test
    func defaultAndPersistedToggleAreAvailableInSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        try "[tiling]\ndefault_strategy = \"spatialBsp\"\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(try RoadieConfigLoader.load(from: config.path).tiling.resizeHandles)
        let settings = SettingsService(
            configPath: config.path,
            eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path),
            afterWrite: {}
        )
        let descriptor = try #require(SettingsCatalog.all.first { $0.id == "tiling.resize_handles" })
        _ = settings.set(descriptor.id, to: "false")
        #expect(try !RoadieConfigLoader.load(from: config.path).tiling.resizeHandles)
        _ = settings.reset(descriptor.id)
        #expect(try RoadieConfigLoader.load(from: config.path).tiling.resizeHandles)
    }
}
