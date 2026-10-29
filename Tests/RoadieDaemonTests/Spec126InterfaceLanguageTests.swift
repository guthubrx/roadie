import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 126 : interface en anglais ou en français selon macOS, mots tapés acceptés dans les deux langues.
/// Ces tests ne changent pas `UILanguage.current` : la suite tourne en français (`scripts/test`).
struct Spec126InterfaceLanguageTests {
    private let display = DisplayID(rawValue: "A")
    private let safari = LauncherSubject.app(LauncherApp(bundleID: "com.apple.Safari", path: "/Applications/Safari.app",
                                                         name: "Safari", alternateNames: []))

    @Test func languageFollowsMacOSAndTheEnvironmentWins() {
        #expect(UILanguage.detect(["fr-FR", "en-US"], environment: [:], configText: nil) == .fr)
        #expect(UILanguage.detect(["en-GB", "fr-FR"], environment: [:], configText: nil) == .en)
        #expect(UILanguage.detect(["de-DE"], environment: [:], configText: nil) == .en)
        #expect(UILanguage.detect([], environment: [:], configText: nil) == .en)
        #expect(UILanguage.detect(["fr-FR"], environment: ["ROADIE_LANGUAGE": "en"]) == .en)
        #expect(UILanguage.detect(["en-US"], environment: ["ROADIE_LANGUAGE": "xx"]) == .en)
        #expect(tr("Fenêtres", "Windows") == (UILanguage.current == .fr ? "Fenêtres" : "Windows"))
    }

    @Test func verbsAreFoundInBothLanguages() {
        #expect(LauncherVerb.close.matches("close", app: "Safari"))
        #expect(LauncherVerb.close.matches("fermer", app: "Safari"))
        #expect(LauncherVerb.floatAlways.matches("always float", app: "Safari"))
        #expect(!LauncherVerb.close.matches("quit", app: "Safari"))
        let rows = LauncherActionList.verbs(for: safari, query: "quit", destinations: [], newStageHome: (display, DesktopID(rawValue: 1))).rows
        let verbs = rows.compactMap { row -> LauncherVerb? in if case .verb(let verb) = row { verb } else { nil } }
        #expect(verbs.contains(.quit) && verbs.contains(.forceQuit))
    }

    @Test func desktopsAreFoundInBothLanguages() {
        var desktop = LauncherDestination(kind: .desktop(display, DesktopID(rawValue: 2)), title: tr("Bureau 2", "Desktop 2"), detail: "")
        desktop.aliases = ["Bureau 2", "Desktop 2"]
        for query in ["bureau 2", "desktop 2"] {
            let rows = LauncherActionList.destinations(for: .project("Notes"), verb: .moveTo, query: query, destinations: [desktop],
                                                       newStageHome: (display, DesktopID(rawValue: 1))).rows
            #expect(rows.contains(.destination(.moveTo, desktop)), "\(query)")
        }
    }

    @Test func systemCommandsKeepBothNamesAsKeywords() {
        let commands = LauncherSystemCommand.all()
        for query in ["verrouiller", "lock screen", "vider la corbeille", "empty trash", "redémarrer", "restart"] {
            #expect(!LauncherSystemCommand.matches(query, in: commands).isEmpty, "\(query)")
        }
    }
}

/// Session 127 : la langue se choisit aussi dans la configuration, avant celle de macOS.
struct Spec127InterfaceLanguageSettingTests {
    @Test func configChoiceWinsOverMacOSButNotOverTheEnvironment() {
        let french = "[tiling]\ngaps_inner = 4\n\n[interface]\nsettings_text_font_size = 16\nlanguage = \"fr\" # choix\n"
        #expect(UILanguage.configured(french) == .fr)
        #expect(UILanguage.configured("[interface]\nlanguage = \"auto\"\n") == nil)
        #expect(UILanguage.configured("[other]\nlanguage = \"fr\"\n") == nil)
        #expect(UILanguage.detect(["en-US"], environment: [:], configText: french) == .fr)
        #expect(UILanguage.detect(["fr-FR"], environment: [:], configText: "[interface]\nlanguage = \"en\"\n") == .en)
        #expect(UILanguage.detect(["en-US"], environment: ["ROADIE_LANGUAGE": "en"], configText: french) == .en)
        #expect(UILanguage.detect(["fr-FR"], environment: [:], configText: nil) == .fr)
    }

    @Test func settingIsOfferedWithItsThreeChoices() throws {
        let descriptor = try #require(SettingsCatalog.find(id: "interface.language"))
        #expect(descriptor.kind == .choice(["auto", "fr", "en"]))
        #expect(descriptor.defaultValue == .string("auto"))
        #expect(descriptor.choiceLabel("fr") == "Français" && descriptor.choiceLabel("en") == "English")
        #expect(InterfaceConfig(language: "de").language == "auto")
    }
}
