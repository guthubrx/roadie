import AppKit
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 105 : fonctions d'Alfred qui n'étaient qu'en partie reprises.
@Suite(.serialized)
@MainActor
struct Spec105PartialFeaturesTests {
    private func key(_ code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }

    @Test func systemCommandsAreFoundAndHeavyOnesConfirm() {
        let commands = LauncherSystemCommand.all()
        #expect(LauncherSystemCommand.matches("verr", in: commands).first?.id == "lock")
        #expect(LauncherSystemCommand.matches("tout q", in: commands).first?.id == "quit-all")
        #expect(LauncherSystemCommand.matches("corb", in: commands).map(\.id).contains("empty-trash"))
        #expect(LauncherSystemCommand.matches("v", in: commands).isEmpty)
        #expect(commands.first { $0.id == "shutdown" }?.confirms == true)
        #expect(LauncherSystemCommand.all(confirmQuitAll: false).first { $0.id == "quit-all" }?.confirms == false)
        #expect(LauncherList.Row.system(commands[0]).id == "system:lock")
        let pids = LauncherSystemCommand.quitAllTargets([("com.apple.finder", true, 1), ("org.mozilla.firefox", true, 2),
                                                         ("com.roadie", true, 3), (nil, false, 4)], ownPID: 3)
        #expect(pids == [2])
        #expect(LauncherVerb.forceQuit.title == "Forcer à quitter")
    }

    @Test func backspaceAtTheEndOfAFolderGoesUp() {
        #expect(LauncherPathRules.parent("~/Documents/Projets/") == "~/Documents/")
        #expect(LauncherPathRules.parent("/Users/moi/") == "/Users/")
        #expect(LauncherPathRules.parent("/Users/") == "/")
        #expect(LauncherPathRules.parent("~/") == nil)
        #expect(LauncherPathRules.parent("/") == nil)
        #expect(LauncherPathRules.parent("~/Documents/rap") == nil)
    }

    @Test func folderListingSortsByDateWhenAsked() {
        let names: [(name: String, isFolder: Bool)] = [("ancien.txt", false), ("récent.txt", false), ("Dossier", true)]
        let query = LauncherPathRules.parts("/tmp/", home: "/none")
        #expect(LauncherPathRules.filter(names, query: query).map(\.name) == ["Dossier", "ancien.txt", "récent.txt"])
        let dates = ["ancien.txt": Date(timeIntervalSince1970: 1), "récent.txt": Date(timeIntervalSince1970: 100)]
        #expect(LauncherPathRules.filter(names, query: query, dates: dates).map(\.name) == ["Dossier", "récent.txt", "ancien.txt"])
    }

    @Test func newKeysReachTheBar() throws {
        #expect(SearchInputPanel.navigation(try key(53, flags: .command))?.kind == .closeAll)
        #expect(SearchInputPanel.navigation(try key(53))?.kind == .escape)
        _ = NSApplication.shared
        let panel = SearchInputPanel()
        panel.update(text: "", frame: CGRect(x: 300, y: 100, width: 560, height: 28), font: .systemFont(ofSize: 15))
        panel.beginEditing()
        defer { panel.endEditing() }
        var keys: [SearchKeyInput.Kind] = []
        panel.onKey = { keys.append($0.kind) }
        #expect(panel.performKeyEquivalent(with: try key(37, text: "l", flags: .command)))
        // ⌫ en fin de `~/Documents/` : le dossier parent, seulement en navigation de chemin.
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        editor.insertText("~/Documents/", replacementRange: NSRange(location: 0, length: 0))
        panel.pathNavigation = true
        panel.sendEvent(try key(51))
        panel.pathNavigation = false
        #expect(keys == [.largeType, .parentFolder])
    }

    @Test func calculatorKnowsTheRestOfAlfredsFunctions() throws {
        #expect(try #require(LauncherCalculator.evaluate("=rtod(pi)")).text == "180")
        #expect(try #require(LauncherCalculator.evaluate("=trunc(-2.7)")).text == "-2")
        #expect(LauncherCalculator.evaluate("=tanh(0)")?.text == "0")
        #expect(LauncherCalculator.functions["atanh"] != nil && LauncherCalculator.functions["dtor"] != nil)
    }

    @Test func settingsAreValidated() {
        #expect(TargetModeConfig(pathSort: "size").pathSort == "name")
        #expect(TargetModeConfig(learningEnabled: false).learningEnabled == false)
        #expect(TargetModeConfig(appSearchPaths: ["~/Apps"]).appSearchPaths == ["~/Apps"])
        #expect(LauncherAppCatalog().setExtraRoots(["~/Apps"]))
    }
}
