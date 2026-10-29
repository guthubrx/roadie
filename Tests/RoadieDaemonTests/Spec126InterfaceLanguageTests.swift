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
        #expect(UILanguage.detect(["fr-FR", "en-US"], environment: [:]) == .fr)
        #expect(UILanguage.detect(["en-GB", "fr-FR"], environment: [:]) == .en)
        #expect(UILanguage.detect(["de-DE"], environment: [:]) == .en)
        #expect(UILanguage.detect([], environment: [:]) == .en)
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
