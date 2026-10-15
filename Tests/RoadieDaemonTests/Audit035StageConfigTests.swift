import Foundation
import Testing
import RoadieCore
import RoadieDaemon

struct Audit035StageConfigTests {
    @Test(arguments: ["nan", "+inf", "-inf"])
    func nonFiniteGeometryIsRejectedBeforeItCanReachAX(literal: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        try "[tiling]\ngaps_inner = \(literal)\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: url.path).hasErrors)
        var rejected = false
        do {
            let config = try RoadieConfigLoader.load(from: url.path)
            #expect(config.tiling.gapsInner.isFinite, "Geometry loaded from TOML must be finite")
        } catch { rejected = true }
        #expect(rejected)
    }

    @Test(arguments: ["default", "workspace"])
    func emptyConfiguredStageIDsFailAtTheFileBoundary(variant: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        let invalid = variant == "default"
            ? "[stage_manager]\ndefault_stage = \"\"\n"
            : "[[stage_manager.workspaces]]\nid = \"\"\ndisplay_name = \"Invalid\"\n"
        try invalid.write(to: url, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: url.path).hasErrors)
        var rejected = false
        do { _ = try RoadieConfigLoader.load(from: url.path) } catch { rejected = true }
        #expect(rejected, "No empty identifier may reach StageID's precondition from TOML")
        if rejected {
            let service = ConfigReloadService(activePath: url.path, eventLog: EventLog(path: directory.appendingPathComponent("events").path))
            #expect(service.currentConfig().stageManager.defaultStage == "1")
            #expect(service.state.lastValidation == .failed)
        }
    }

    @Test
    func validNamedStagesAndDefaultsRemainReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        try "[[stage_manager.workspaces]]\nid = \"Work\"\ndisplay_name = \"Travail\"\n".write(to: url, atomically: true, encoding: .utf8)
        let config = try RoadieConfigLoader.load(from: url.path)
        #expect(config.stageManager.defaultStage == "1")
        #expect(config.stageManager.workspaces == [StageDefinition(id: "Work", displayName: "Travail")])
        #expect(!RoadieConfigLoader.validate(path: url.path).hasErrors)
    }
}
