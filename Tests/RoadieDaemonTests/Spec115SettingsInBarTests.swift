import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Réglages trouvés par la barre et ⌘, (session 115).
struct Spec115SettingsInBarTests {
    @Test func roadieCategoriesAndSettingsAreFound() throws {
        let targets = LauncherSettingTargets.roadie()
        let rail = try #require(LauncherSystemCommand.matches("rail", in: targets, limit: 4).first)
        #expect(rail.id == "roadie-category:rail" && rail.detail == "Paramètres de Roadie")
        let theme = try #require(LauncherSystemCommand.matches("thème de la barre", in: targets, limit: 4).first)
        #expect(theme.id == "roadie-setting:target_mode.theme")
        #expect(theme.detail == "Paramètres de Roadie › Recherche")
        #expect(targets.count == SettingCategory.allCases.count + SettingsCatalog.all.count)
    }

    @Test func systemPanesAreNamedInTheUserLanguage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spec115-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func appex(_ name: String, id: String, point: String, names: [String: String]) throws {
            let contents = root.appendingPathComponent("\(name).appex/Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            (["CFBundleIdentifier": id, "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": point]] as NSDictionary)
                .write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
            (names.mapValues { ["CFBundleDisplayName": $0] } as NSDictionary)
                .write(to: contents.appendingPathComponent("Resources/InfoPlist.loctable"), atomically: true)
        }
        try appex("KeyboardSettings", id: "com.apple.Keyboard-Settings.extension", point: "com.apple.Settings.extension.ui",
                  names: ["fr": "Clavier", "en": "Keyboard"])
        try appex("Widget", id: "com.apple.widget", point: "com.apple.widgetkit-extension", names: ["fr": "Widget"])
        let panes = LauncherSettingTargets.systemPanes(root: root, languages: ["fr-FR"])
        #expect(panes.map(\.title) == ["Clavier"])
        #expect(panes.first?.id == "pane:com.apple.Keyboard-Settings.extension" && panes.first?.keywords == ["Keyboard"])
        #expect(LauncherSettingTargets.paneURL("com.apple.Keyboard-Settings.extension")?.absoluteString
                == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    @Test func languageFallsBackFromRegionToLanguage() {
        let table: [String: Any] = ["fr": ["CFBundleDisplayName": "Son"], "en": ["CFBundleDisplayName": "Sound"]]
        #expect(LauncherSettingTargets.localizedName(table, languages: ["fr-CA"]) == "Son")
        #expect(LauncherSettingTargets.localizedName(table, languages: ["de-DE", "en-US"]) == "Sound")
    }

    @MainActor @Test func commandCommaOpensSettings() throws {
        #expect(LauncherBarKeys.actions.contains { $0.id == "settings" && $0.defaultKey == "command+," })
        let input = try #require(SearchInputPanel.barInput("settings", selection: SelectionKeys()))
        #expect(input.kind == .openSettings)
        #expect(TargetModeConfig().settingsInSearch)
    }
}
