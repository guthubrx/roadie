import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 131 : ⌘, ⌥ et ⌃ + Retour réglables, comme les listes « Action Modifiers » d'Alfred.
struct Spec131ReturnModifiersTests {
    private let home = (DisplayID(rawValue: "main"), DesktopID(rawValue: 1))
    private let file = LauncherFile(path: "/tmp/a.txt", name: "a.txt", isFolder: false, lastUsed: nil)

    @Test func defaultsKeepTheSession075Behaviour() throws {
        let config = TargetModeConfig()
        #expect(config.returnCommand == "new-stage" && config.returnOption == "here" && config.returnControl == "web")
        #expect(LauncherReturnEffect(config: "inconnu", modifier: .option) == .here)
        let command = LauncherVariant.of(.file(file), modifier: .command, query: "a", newStageHome: home, activeStage: nil)
        guard case .action(let action)? = command?.effect else { Issue.record("⌘ sans action"); return }
        #expect(action.verb == .openIn)
        let control = LauncherVariant.of(.file(file), modifier: .control, query: "rapport", newStageHome: home, activeStage: nil)
        #expect(control?.effect == .webSearch("rapport"))
    }

    @Test func chosenEffectsApply() {
        let copy = LauncherVariant.of(.file(file), modifier: .command, query: "", newStageHome: home, activeStage: nil, effect: .copy)
        #expect(copy?.effect == .copy("/tmp/a.txt") && copy?.title.contains("⌘") == true)
        let reveal = LauncherVariant.of(.file(file), modifier: .option, query: "", newStageHome: home, activeStage: nil, effect: .reveal)
        guard case .action(let action)? = reveal?.effect else { Issue.record("⌥ sans action"); return }
        #expect(action.verb == .reveal)
        #expect(LauncherVariant.of(.file(file), modifier: .control, query: "", newStageHome: home, activeStage: nil, effect: .verbs)?.effect
                == .verbs(.file(file)))
        #expect(LauncherVariant.of(.file(file), modifier: .control, query: "", newStageHome: home, activeStage: nil, effect: .none) == nil)
        // Un effet sans objet pour cette ligne laisse Retour faire l'action normale.
        #expect(LauncherVariant.of(.text("x"), modifier: .command, query: "", newStageHome: home, activeStage: nil, effect: .quicklook) == nil)
    }

    @Test func configAndSettingsAcceptTheChoices() throws {
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: "[experimental.target_mode]\nreturn_cmd = \"copy\"\nreturn_alt = \"bizarre\"\n")
        #expect(config.experimental.targetMode.returnCommand == "copy")
        #expect(config.experimental.targetMode.returnOption == "here")
        let descriptor = try #require(SettingsCatalog.find(id: "target_mode.return_ctrl"))
        #expect(descriptor.choiceLabel("quicklook") == "Aperçu (Quick Look)")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("spec131-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[experimental.target_mode]\nreturn_ctrl = \"verbs\"\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: file.path).items.allSatisfy { $0.level != .error })
    }
}
