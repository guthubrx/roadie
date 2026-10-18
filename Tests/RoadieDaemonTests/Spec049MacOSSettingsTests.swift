import Foundation
import Testing
@testable import RoadieDaemon

/// SPEC-049 : la santé signale les réglages macOS qui déplacent les fenêtres à la place de Roadie.
@Suite
struct Spec049MacOSSettingsTests {
    private func setting(_ key: String) -> MacOSWindowSetting {
        MacOSWindowSetting.all.first { $0.key == key }!
    }

    @Test func absentKeyFollowsTheMacOSDefault() {
        #expect(!setting("GloballyEnabled").isEnabled(value: nil, osMajorVersion: 26))
        #expect(setting("EnableTilingByEdgeDrag").isEnabled(value: nil, osMajorVersion: 15))
        #expect(!setting("EnableTilingByEdgeDrag").isEnabled(value: nil, osMajorVersion: 14))
        #expect(setting("EnableStandardClickToShowDesktop").isEnabled(value: nil, osMajorVersion: 14))
    }

    @Test func explicitValueWins() {
        #expect(!setting("EnableTilingByEdgeDrag").isEnabled(value: NSNumber(value: 0), osMajorVersion: 26))
        #expect(setting("GloballyEnabled").isEnabled(value: NSNumber(value: 1), osMajorVersion: 26))
    }

    @Test func activeSettingsGiveAWarningWithLabelsAndLocations() {
        let values: [String: Any] = ["GloballyEnabled": NSNumber(value: 1), "EnableTopTilingByEdgeDrag": NSNumber(value: 0),
                                     "EnableStandardClickToShowDesktop": NSNumber(value: 0)]
        let check = DaemonHealthService.macOSWindowSettingsCheck(read: { _, key in values[key] }, osMajorVersion: 26)
        #expect(check.name == "macos-window-settings")
        #expect(check.level == .warn)
        #expect(check.message.contains("Stage Manager"))
        #expect(check.message.contains("Réglages Système > Bureau et Dock"))
        // Clé absente sur macOS 26 : la juxtaposition par glisser vers un bord est active par défaut.
        #expect(check.message.contains("bord de l'écran"))
        #expect(!check.message.contains("barre des menus"))
    }

    @Test func noDisturbingSettingIsOk() {
        let values: [String: Any] = Dictionary(uniqueKeysWithValues: MacOSWindowSetting.all.map { ($0.key, NSNumber(value: 0)) })
        let check = DaemonHealthService.macOSWindowSettingsCheck(read: { _, key in values[key] }, osMajorVersion: 26)
        #expect(check.level == .ok)
    }

    @Test func warningNeverFailsTheHealthReport() {
        let report = DaemonHealthReport(checks: [
            DaemonHealthService.macOSWindowSettingsCheck(read: { _, _ in NSNumber(value: 1) }, osMajorVersion: 26)
        ])
        #expect(!report.failed)
    }
}
