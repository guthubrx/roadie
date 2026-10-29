import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec077FileRulesTests {
    private let home = "/Users/x"

    @Test func quickSearchAndThresholds() {
        #expect(LauncherFileRules.filesOnly(" rap") && LauncherFileRules.filesOnly("'rap") && !LauncherFileRules.filesOnly("rap"))
        #expect(LauncherFileRules.needle(" rapport ") == "rapport")
        #expect(!LauncherFileRules.shouldSearch("ra") && LauncherFileRules.shouldSearch("rap"))
        #expect(LauncherFileRules.shouldSearch(" ra") && !LauncherFileRules.shouldSearch(" r"))
    }

    @Test func onlyTheHomeOutsideLibraryHiddenAndDependencies() {
        #expect(LauncherFileRules.isShown("/Users/x/Documents/a.pdf", home: home))
        #expect(!LauncherFileRules.isShown("/Users/x/Library/Caches/a.txt", home: home))
        #expect(!LauncherFileRules.isShown("/Users/x/projet/.build/a.txt", home: home))
        #expect(!LauncherFileRules.isShown("/Users/x/projet/node_modules/a/readme.md", home: home))
        #expect(!LauncherFileRules.isShown("/Applications/A.app", home: home))
        // Même règle pour la stage d'un dossier : un fichier temporaire n'en crée pas (audit V15 F4).
        #expect(!LauncherFileRules.isShown("/private/tmp/roadie-077/essai.txt", home: home))
    }

    @Test func mostRecentlyUsedFirst() {
        let old = LauncherFile(path: "/Users/x/a", name: "b", isFolder: false, lastUsed: Date(timeIntervalSince1970: 1))
        let new = LauncherFile(path: "/Users/x/b", name: "a", isFolder: false, lastUsed: Date(timeIntervalSince1970: 2))
        let never = LauncherFile(path: "/Users/x/c", name: "c", isFolder: false, lastUsed: nil)
        #expect(LauncherFileRules.ordered([never, old, new]).map(\.name) == ["a", "b", "c"])
    }
}

struct Spec077FileListTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let rapporteur = LauncherApp(bundleID: "a.rapporteur", path: "/Applications/Rapporteur.app", name: "Rapporteur", alternateNames: [])
    private let report = LauncherFile(path: "/Users/x/Documents/rapport.pdf", name: "rapport.pdf", isFolder: false, lastUsed: nil)
    private let notes = LauncherFile(path: "/Users/x/Notes/rapport notes.md", name: "rapport notes.md", isFolder: false, lastUsed: nil)

    private func headers(_ list: LauncherList) -> [String] {
        list.rows.compactMap { if case .header(let title) = $0 { return title } else { return nil } }
    }

    @Test func filesHaveTheirSectionAfterWindowsAndKeepSpotlightOrder() {
        let window = RoadieTarget(id: "window:1", kind: .window, title: "Rapporteur", source: .roadie, actions: [.focus])
        let list = LauncherList(query: "rap", apps: [rapporteur], details: [:], targets: [window], ranking: LauncherRanking(), now: now, files: [notes, report])
        #expect(headers(list) == ["Applications", "Fenêtres", "Fichiers"])
        let files = list.rows.compactMap { if case .file(let file) = $0 { return file.name } else { return nil } }
        #expect(files == ["rapport notes.md", "rapport.pdf"])
    }

    @Test func aLeadingSpaceKeepsOnlyFiles() {
        let list = LauncherList(query: " rap", apps: [rapporteur], details: [:], targets: [], ranking: LauncherRanking(), now: now, files: [report])
        #expect(headers(list) == ["Fichiers"])
        #expect(list.best == report.rankingKey)
    }

    @Test func fileVerbsAndVariants() throws {
        let subject = LauncherSubject.file(report)
        // Session 131 : les actions d'Alfred suivent les verbes de la SPEC-077.
        #expect(LauncherVerb.verbs(for: subject).prefix(6) == [.open, .openIn, .bringHere, .reveal, .quickLook, .copyPath])
        let home = (DisplayID(rawValue: "A"), DesktopID(rawValue: 1))
        let active = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        guard case .action(let command)? = LauncherVariant.of(subject, modifier: .command, query: "rap", newStageHome: home, activeStage: active)?.effect,
              case .action(let option)? = LauncherVariant.of(subject, modifier: .option, query: "rap", newStageHome: home, activeStage: active)?.effect else {
            Issue.record("variantes attendues"); return
        }
        #expect(command.verb == .openIn && option.verb == .bringHere)
    }
}

struct Spec077FolderStageTests {
    @Test func aRankingIdentityFindsItsStageAgain() {
        let display = DisplayID(rawValue: "A")
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Perso"), PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2"),
            ]),
        ])
        let perso = StageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "1"))
        let anonymous = StageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "2"))
        #expect(LauncherSearchContext.stage(for: "stage:perso", in: state) == perso)
        // « Stage 2 » est un nom généré : la stage est reconnue par sa place, pas par ce nom répété ailleurs.
        #expect(LauncherSearchContext.rankingContext(anonymous, stage: state.scopes[0].stages[1]) == "scope:\(anonymous.description)")
        #expect(LauncherSearchContext.stage(for: "scope:\(anonymous.description)", in: state) == anonymous)
        #expect(LauncherSearchContext.stage(for: "stage:absente", in: state) == nil)
    }
}

@MainActor
struct Spec077KeyboardTests {
    @Test func commandCCopiesTheRowOnlyWithoutSelectionAndCommandYPreviews() throws {
        _ = NSApplication.shared
        let panel = SearchInputPanel()
        panel.update(text: "rap", frame: CGRect(x: 300, y: 100, width: 560, height: 28), font: .systemFont(ofSize: 15))
        panel.beginEditing()
        defer { panel.endEditing() }
        var received: [SearchKeyInput.Kind] = []
        panel.onKey = { received.append($0.kind) }
        func key(_ code: UInt16, _ text: String) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
                                          context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        }
        #expect(panel.performKeyEquivalent(with: try key(8, "c")))
        #expect(panel.performKeyEquivalent(with: try key(16, "y")))
        #expect(received == [.copy, .preview])
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        _ = panel.performKeyEquivalent(with: try key(8, "c"))
        #expect(received == [.copy, .preview])
    }
}
