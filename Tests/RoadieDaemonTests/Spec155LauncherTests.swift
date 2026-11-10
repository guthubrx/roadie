import Foundation
import Testing
import TOMLKit
import RoadieCore
@testable import RoadieDaemon

@Suite struct Spec155LauncherTests {
    private func config(_ text: String) throws -> RoadieConfig {
        try TOMLDecoder().decode(RoadieConfig.self, from: text)
    }

    @Test func oldAndNewSectionsHaveTheSameMeaning() throws {
        let body = "\nvisible_results = 7\nshow_scrollbar = true\nbookmark_browsers = [\"firefox\"]\n"
        #expect(try config("[launcher]" + body) == config("[experimental.target_mode]" + body))
    }

    @Test func newValuesWinPerKeyAndMissingValuesAreInherited() throws {
        let text = """
        [experimental.target_mode]
        theme = "alfred"
        visible_results = 7
        copy_key = "command+k"
        preview_key = "command+j"
        [launcher]
        theme = "roadie"
        copy_key = "command+l"
        web_searches = []
        """
        let value = try config(text).experimental.targetMode
        #expect(value.theme == "roadie")
        #expect(value.visibleResults == 7)
        #expect(value.barKeys["copy"] == "command+l")
        #expect(value.barKeys["preview"] == "command+j")
        #expect(value.webSearches == [])
        #expect(ConfigFileEditor.readLiteral(text, table: "experimental.target_mode", key: "theme") == "\"roadie\"")
        #expect(ConfigFileEditor.literal(in: ConfigFileEditor.literalIndex(text), table: "experimental.target_mode", key: "theme") == "\"roadie\"")
    }

    @Test func editingAndResetDoNotResurrectALegacyValue() throws {
        let text = """
        # Keep this comment
        [experimental.target_mode]
        visible_results = 7 # chosen
        theme = "alfred"
        [launcher]
        visible_results = 9
        [tiling]
        gaps_outer = 11
        """
        let edited = try ConfigFileEditor.edit(text, table: "experimental.target_mode", key: "visible_results", value: "5").get()
        #expect(try config(edited).experimental.targetMode.visibleResults == 5)
        #expect(edited.contains("# chosen"))
        #expect(edited.contains("theme = \"alfred\""))
        #expect(edited.contains("gaps_outer = 11"))
        #expect(edited.components(separatedBy: "[launcher]").count == 2)
        let reset = try ConfigFileEditor.edit(edited, table: "experimental.target_mode", key: "visible_results", value: nil).get()
        #expect(try config(reset).experimental.targetMode.visibleResults == TargetModeConfig().visibleResults)
        #expect(!reset.contains("visible_results ="))
    }

    @Test func structuredListsUseTheEffectiveSectionAndResetBothForms() throws {
        let text = """
        [experimental.target_mode]
        bookmark_browsers = ["safari"]
        [launcher]
        bookmark_browsers = [
          "firefox", # keep
        ]
        """
        #expect(ConfigFileEditor.readRawValue(text, table: "experimental.target_mode", key: "bookmark_browsers")?.contains("firefox") == true)
        let descriptor = try #require(SettingsCatalog.find(id: "target_mode.bookmark_browsers"))
        #expect(try SettingsCollectionCodec.read(descriptor, text: text) == .list([.string("firefox")]))
        let edited = try SettingsCollectionWriter.edit(text, descriptor: descriptor, value: .list([.string("chrome")]))
        #expect(try config(edited).experimental.targetMode.bookmarkBrowsers == ["chrome"])
        #expect(edited.contains("# keep"))
        let reset = try SettingsCollectionWriter.edit(edited, descriptor: descriptor, value: nil)
        #expect(try config(reset).experimental.targetMode.bookmarkBrowsers == TargetModeConfig().bookmarkBrowsers)
    }

    @Test func nestedTableArraysFollowTheNewSection() throws {
        let text = """
        [[experimental.target_mode.web_searches]]
        keyword = "old"
        title = "Old"
        url = "https://example.invalid/old?q={query}"
        [[launcher.web_searches]]
        keyword = "new"
        title = "New"
        url = "https://example.invalid/new?q={query}"
        """
        #expect(try config(text).experimental.targetMode.webSearches?.first?.keyword == "new")
        let root = try TOMLTable(string: text)
        let rows = SettingsCollectionCodec.node(root, path: ["experimental", "target_mode", "web_searches"])?.array
        #expect(rows?.count == 1)
        #expect(rows?.first?.table?["keyword"]?.string == "new")

    }

    @Test func validatorAcceptsLauncherAndFindsItsMisspelledKeys() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-\(UUID()).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[launcher]\nvisible_results = 7\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: file.path).items.allSatisfy { $0.level == .ok })
        try "[launcher]\nvisble_results = 7\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: file.path).items.contains { $0.path == "launcher.visble_results" })
        #expect(RoadieConfigLoader.knownScalarKeys()["launcher"] == nil, "Pas de deuxième catalogue de réglages")
    }
    @Test func settingsServiceWritesReloadableCanonicalValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-settings-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roadies.toml")
        try "[experimental.target_mode]\nvisible_results = 7\n[launcher]\nvisible_results = 9\n".write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, afterWrite: {})
        #expect(service.set("target_mode.visible_results", to: "5") == .applied(old: .int(9), new: .int(5)))
        #expect(try RoadieConfigLoader.load(from: file.path).experimental.targetMode.visibleResults == 5)
        let reset = service.reset("target_mode.visible_results")
        #expect(reset == .applied(old: .int(5), new: .int(TargetModeConfig().visibleResults)))
        #expect(try RoadieConfigLoader.load(from: file.path).experimental.targetMode.visibleResults == TargetModeConfig().visibleResults)
        #expect(service.validity().isValid)
    }

}
