import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// SPEC-050 : double-clic sur la barre de titre, seulement si macOS ne fait rien de ce double-clic.
@Suite
struct Spec050TitlebarDoubleClickTests {
    private func action(_ values: [String: Any]) -> MacOSDoubleClickAction {
        MacOSWindowSetting.doubleClickAction(read: { _, key in values[key] })
    }

    @Test func macOSActionIsReadFromGlobalPreferences() {
        #expect(action(["AppleActionOnDoubleClick": "None"]) == .none)
        #expect(action(["AppleActionOnDoubleClick": "Minimize"]) == .minimize)
        #expect(action(["AppleActionOnDoubleClick": "Maximize"]) == .zoom)
        #expect(action(["AppleActionOnDoubleClick": "Fill"]) == .zoom)
    }

    @Test func absentActionFollowsTheLegacyMinimizeFlag() {
        #expect(action([:]) == .zoom)
        #expect(action(["AppleMiniaturizeOnDoubleClick": NSNumber(value: 1)]) == .minimize)
        #expect(action(["AppleMiniaturizeOnDoubleClick": NSNumber(value: 0)]) == .zoom)
    }

    @Test func roadieActsOnlyOnADoubleClickThatMacOSIgnores() {
        #expect(TitlebarContextMenuController.handlesDoubleClick(clickCount: 2, enabled: true, macOSAction: .none))
        #expect(!TitlebarContextMenuController.handlesDoubleClick(clickCount: 1, enabled: true, macOSAction: .none))
        #expect(!TitlebarContextMenuController.handlesDoubleClick(clickCount: 3, enabled: true, macOSAction: .none))
        #expect(!TitlebarContextMenuController.handlesDoubleClick(clickCount: 2, enabled: false, macOSAction: .none))
        #expect(!TitlebarContextMenuController.handlesDoubleClick(clickCount: 2, enabled: true, macOSAction: .zoom))
    }

    @Test func settingDefaultsToEnabledAndDecodes() throws {
        #expect(TitlebarContextMenuConfig().doubleClickMaximize)
        let path = tempPath("spec050-config.toml")
        try "[experimental.titlebar_context_menu]\ndouble_click_maximize = false\n"
            .write(toFile: path, atomically: true, encoding: .utf8)
        let config = try RoadieConfigLoader.load(from: path)
        #expect(!config.experimental.titlebarContextMenu.doubleClickMaximize)
    }

    @Test func healthWarnsWhenMacOSAlsoHandlesTheDoubleClick() {
        let quiet = Dictionary(uniqueKeysWithValues: MacOSWindowSetting.all.map { ($0.key, NSNumber(value: 0) as Any) })
        let conflict = DaemonHealthService.macOSWindowSettingsCheck(
            read: { _, key in quiet[key] }, osMajorVersion: 26, roadieDoubleClickMaximize: true)
        #expect(conflict.level == .warn)
        #expect(conflict.message.contains("Ne rien faire"))

        var none = quiet
        none["AppleActionOnDoubleClick"] = "None"
        let aligned = DaemonHealthService.macOSWindowSettingsCheck(
            read: { _, key in none[key] }, osMajorVersion: 26, roadieDoubleClickMaximize: true)
        #expect(aligned.level == .ok)

        let disabled = DaemonHealthService.macOSWindowSettingsCheck(
            read: { _, key in quiet[key] }, osMajorVersion: 26, roadieDoubleClickMaximize: false)
        #expect(disabled.level == .ok)
    }
}
