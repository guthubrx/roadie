import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
struct InterfaceFontConfigTests {
    private func load(_ raw: String) throws -> RoadieConfig {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("interface-fonts-\(UUID().uuidString).toml")
        try raw.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = RoadieConfigLoader.validate(path: url.path)
        #expect(!report.hasErrors)
        #expect(!report.items.contains { $0.message.contains("inconnue") })
        return try RoadieConfigLoader.load(from: url.path)
    }

    @Test
    func oldFilesKeepPredictableIndependentDefaults() throws {
        let config = try load("""
        [experimental.target_mode]
        label_font_size = 24
        """)
        #expect(config.interface == InterfaceConfig())
        #expect(config.interface.settingsTextFontSize == 16)
        #expect(config.interface.settingsHelpFontSize == 14)
        #expect(config.interface.settingsTitleFontSize == 22)
        #expect(config.experimental.targetMode.labelFontSize == 24)
        #expect(config.experimental.targetMode.searchLabelFontSize == 13)
        #expect(config.experimental.targetMode.searchTextFontSize == 15)
        #expect(config.experimental.targetMode.commandTextFontSize == 13)
    }

    @Test
    func separateSizesDecodeIntegersAndDecimalsAndSurviveSerialization() throws {
        let config = try load("""
        [interface]
        settings_text_font_size = 20
        settings_help_font_size = 17.5
        settings_title_font_size = 30
        [experimental.target_mode]
        label_font_size = 12
        search_label_font_size = 18
        search_text_font_size = 26.5
        command_text_font_size = 21
        [experimental.target_grid]
        label_font_size = 32
        """)
        #expect(config.interface == InterfaceConfig(settingsTextFontSize: 20, settingsHelpFontSize: 17.5, settingsTitleFontSize: 30))
        let mode = config.experimental.targetMode
        #expect(TargetOverlayStyle.labels(mode).labelFontSize == 12)
        let search = TargetOverlayStyle.search(mode)
        #expect(search.labelFontSize == 18)
        #expect(search.searchTextFontSize == 26.5)
        #expect(search.commandTextFontSize == 21)
        #expect(TargetOverlayStyle.grid(config.experimental.targetGrid).labelFontSize == 32)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(RoadieConfig.self, from: data) == config)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let interface = try #require(json["interface"] as? [String: Any])
        #expect(interface["settings_text_font_size"] as? Double == 20)
    }

    @Test
    func outOfRangeSizesAreClampedBeforeRendering() throws {
        let config = try load("""
        [interface]
        settings_text_font_size = 4
        settings_help_font_size = 100
        settings_title_font_size = 200
        [experimental.target_mode]
        search_label_font_size = 4
        search_text_font_size = 100
        command_text_font_size = 200
        """)
        #expect(config.interface == InterfaceConfig(settingsTextFontSize: 8, settingsHelpFontSize: 32, settingsTitleFontSize: 48))
        let search = TargetOverlayStyle.search(config.experimental.targetMode)
        #expect(search.labelFontSize == 8)
        #expect(search.searchTextFontSize == 48)
        #expect(search.commandTextFontSize == 48)
    }

    @Test
    func settingsPersistIndependentSizesRejectInvalidValuesAndReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("font-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        let service = SettingsService(configPath: path, eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path), afterWrite: {})
        let changes: [(String, Double, Double)] = [
            ("interface.settings_text_font_size", 20, 16),
            ("interface.settings_help_font_size", 18, 14),
            ("interface.settings_title_font_size", 32, 22),
            ("target_mode.search_label_font_size", 24, 13),
            ("target_mode.search_text_font_size", 28, 15),
            ("target_mode.command_text_font_size", 30, 13),
        ]
        for (id, value, initial) in changes {
            #expect(service.set(id, to: String(value)) == .applied(old: .double(initial), new: .double(value)))
        }
        let beforeInvalid = try String(contentsOfFile: path, encoding: .utf8)
        if case .rejected = service.set("interface.settings_text_font_size", to: "33") {} else {
            Issue.record("La plage des paramètres doit être validée avant écriture")
        }
        if case .rejected = service.set("target_mode.command_text_font_size", to: "7") {} else {
            Issue.record("La plage des commandes doit être validée avant écriture")
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == beforeInvalid)
        let config = try RoadieConfigLoader.load(from: path)
        #expect(config.interface == InterfaceConfig(settingsTextFontSize: 20, settingsHelpFontSize: 18, settingsTitleFontSize: 32))
        #expect(config.experimental.targetMode.searchTextFontSize == 28)
        #expect(config.experimental.targetMode.labelFontSize == 13)
        #expect(config.experimental.targetGrid.labelFontSize == 13)
        #expect(service.reset("target_mode.search_text_font_size") == .applied(old: .double(28), new: .double(15)))
        let reset = try RoadieConfigLoader.load(from: path)
        #expect(reset.experimental.targetMode.searchTextFontSize == 15)
        #expect(reset.experimental.targetMode.commandTextFontSize == 30)
        #expect(reset.interface.settingsTextFontSize == 20)
    }

    @Test
    func largerCommandFontsIncreaseRowsAndStayInsideTheScreen() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let original = SearchBarLayout.make(bounds: bounds, suggestions: 3, messageLines: 2)
        let large = SearchBarLayout.make(bounds: bounds, suggestions: 3, messageLines: 2,
                                         searchTextFontSize: 48, commandTextFontSize: 48)
        #expect(large.bar.height == 128)
        #expect(large.bar.height > original.bar.height)
        let panel = try #require(large.panel)
        #expect(panel.maxY <= bounds.maxY)
        #expect(large.messageRows.count == 2)
        #expect(large.suggestionRows.count == 3)
        #expect(large.messageRows[0].height > original.messageRows[0].height)
        // Une taille de commande ne change pas la saisie ; une taille de saisie ne change pas les lignes.
        let commandsOnly = SearchBarLayout.make(bounds: bounds, suggestions: 3, messageLines: 2,
                                                commandTextFontSize: 48)
        #expect(commandsOnly.bar == original.bar)
        #expect(commandsOnly.messageRows[0].height == large.messageRows[0].height)
        let inputOnly = SearchBarLayout.make(bounds: bounds, suggestions: 3, messageLines: 2,
                                             searchTextFontSize: 48)
        #expect(inputOnly.bar == large.bar)
        #expect(inputOnly.messageRows[0].height == original.messageRows[0].height)
    }

    @Test
    func largeFontsOnShortScreensReserveMessageSpace() throws {
        let bounds = CGRect(x: -1280, y: -500, width: 1280, height: 300)
        let layout = SearchBarLayout.make(bounds: bounds, suggestions: 8, messageLines: 12,
                                          searchTextFontSize: 48, commandTextFontSize: 48)
        #expect(bounds.contains(layout.bar))
        let panel = try #require(layout.panel)
        #expect(bounds.contains(panel))
        #expect(layout.suggestionRows.isEmpty)
        #expect(layout.messageRows.count == 1)
    }
}
