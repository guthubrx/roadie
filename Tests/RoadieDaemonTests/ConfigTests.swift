import Foundation
import Testing
import RoadieCore

@Suite
struct ConfigTests {
    @Test
    func borderConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-config-\(UUID().uuidString).toml")
        try """
        [fx.borders]
        enabled = true
        thickness = 3
        corner_radius = 12
        active_color = "#7AA2F7"
        inactive_color = "#414868"
        pulse_on_focus = true

        [[fx.borders.stage_overrides]]
        stage_id = "2"
        active_color = "#F7768E"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.fx.borders.enabled)
        #expect(config.fx.borders.thickness == 3)
        #expect(config.fx.borders.cornerRadius == 12)
        #expect(config.fx.borders.activeColor == "#7AA2F7")
        #expect(config.fx.borders.stageOverrides == [
            BorderStageOverride(stageID: "2", activeColor: "#F7768E")
        ])
    }
}
