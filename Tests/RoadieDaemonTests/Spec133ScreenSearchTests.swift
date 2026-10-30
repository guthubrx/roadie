import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 133 : raccourci de la recherche à l'écran, séparé du lanceur.
struct Spec133ScreenSearchTests {
    @Test func screenSearchHotkeyIsReadAndValidated() throws {
        #expect(TargetModeConfig().screenSearchHotkey.isEmpty)
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: """
            [experimental.target_mode]
            search_hotkey = "command+space"
            screen_search_hotkey = "hyper+f"
            """)
        #expect(config.experimental.targetMode.screenSearchHotkey == "command+control+alt+f")
        #expect(config.experimental.targetMode.searchHotkey == "command+space")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("spec133-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[experimental.target_mode]\nscreen_search_hotkey = \"f\"\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: file.path).items.contains {
            $0.level == .error && $0.path == "experimental.target_mode.screen_search_hotkey" })
        #expect(SettingsCatalog.find(id: "target_mode.screen_search_hotkey")?.category == .raccourcis)
    }

    /// Session 134 : le lanceur peut ne plus lire l'écran, la recherche à l'écran ayant son raccourci.
    @Test func launcherCanSkipOnScreenElements() throws {
        #expect(TargetModeConfig().launcherOnScreen)
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: "[experimental.target_mode]\nlauncher_on_screen = false\n")
        #expect(!config.experimental.targetMode.launcherOnScreen)
        #expect(SettingsCatalog.find(id: "target_mode.launcher_on_screen")?.category == .recherche)
    }
}
