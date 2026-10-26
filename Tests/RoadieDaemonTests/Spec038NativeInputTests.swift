import AppKit
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite(.serialized)
@MainActor
struct Spec038NativeInputTests {
    private func key(_ code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = [], window: Int = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }

    private func panel(_ text: String) -> SearchInputPanel {
        _ = NSApplication.shared
        let panel = SearchInputPanel()
        panel.update(text: text, frame: CGRect(x: 300, y: 100, width: 560, height: 28), font: .systemFont(ofSize: 15))
        panel.beginEditing()
        return panel
    }

    @Test
    func commandASelectsTheNativeTextAndAnInsertionReplacesIt() throws {
        let panel = panel("/settings navrail")
        defer { panel.endEditing() }
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        #expect(panel.performKeyEquivalent(with: try key(0, text: "a", flags: .command, window: panel.windowNumber)))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 17))
        editor.insertText("élève 🚂", replacementRange: editor.selectedRange())
        #expect(editor.string == "élève 🚂")
        #expect(panel.field.stringValue == "élève 🚂")
    }

    @Test
    func nativeWordDeletionAndMiddleSelectionKeepTheRestOfTheLine() throws {
        let panel = panel("alpha beta")
        defer { panel.endEditing() }
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        editor.deleteWordBackward(nil)
        #expect(editor.string == "alpha ")
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        editor.insertText("X", replacementRange: editor.selectedRange())
        #expect(editor.string == "aXa ")
    }

    @Test
    func targetRefreshDoesNotEraseNativeSelectionOrEditingPosition() throws {
        let panel = panel("/settings navrail")
        defer { panel.endEditing() }
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        let range = NSRange(location: 10, length: 7)
        editor.setSelectedRange(range)
        for _ in 0..<5 {
            panel.update(text: "/settings navrail", frame: panel.frame, font: .systemFont(ofSize: 15))
        }
        #expect(editor.selectedRange() == range)
        #expect(panel.field.currentEditor() === editor)
    }

    @Test(arguments: [NSEvent.ModifierFlags.option, .shift, .command, [.option, .shift]])
    func modifiedArrowsRemainNativeTextNavigation(flags: NSEvent.ModifierFlags) throws {
        #expect(SearchInputPanel.navigation(try key(123, flags: flags)) == nil)
        #expect(SearchInputPanel.navigation(try key(126, flags: flags)) == nil)
        #expect(SearchInputPanel.navigation(try key(51, flags: flags)) == nil)
    }

    @Test
    func plainArrowsAndValidationAreTheOnlyNavigationTakenFromText() throws {
        #expect(SearchInputPanel.navigation(try key(125)) == SearchKeyInput(kind: .next, navigationSource: .arrow))
        #expect(SearchInputPanel.navigation(try key(126)) == SearchKeyInput(kind: .previous, navigationSource: .arrow))
        #expect(SearchInputPanel.navigation(try key(36, flags: .command))?.kind == .confirm(shift: false, command: true, isRepeat: false))
        #expect(SearchInputPanel.navigation(try key(0, text: "A", flags: .shift)) == nil)
        // Lettre affichée en pastille (SPEC-084) : Maj + lettre choisit sa ligne, sans écrire de majuscule.
        #expect(SearchInputPanel.navigation(try key(0, text: "A", flags: .shift), labels: ["a"])?.kind == .labelCharacter("a"))
        #expect(SearchInputPanel.navigation(try key(0, text: "a"), labels: ["a"]) == nil)
    }

    @Test
    func replacingAQueryAfterSelectionRefreshesMatchesAndCancelsPendingReturn() {
        let target = RoadieTarget(id: "a", label: "A", kind: .appElement, title: "alpha", source: .app,
            frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: [.click])
        var model = TargetSearchModel(targets: [target])
        model.type("alpha")
        _ = model.pressReturn(shift: false, command: false, at: Date())
        model.replaceQuery("AL")
        #expect(model.query == "AL")
        #expect(model.highlighted?.id == "a")
        #expect(!model.isAwaitingSecondReturn)
        model.replaceQuery("")
        #expect(model.highlighted == nil)
    }
}

@Suite
struct Spec038SuggestionsTests {
    private func model(_ input: String = "settings ") -> SlashCommandModel {
        SlashCommandModel(input: input, history: ["stage 2"]) { _ in
            ["tiling", "navrail", "target_mode"].map { SlashSuggestion(text: $0, kind: .argument) }
        }
    }

    @Test
    func arrowsSelectSuggestionsAndReturnSubmitsTheChosenCategory() {
        var model = model()
        _ = model.handle(SearchKeyInput(kind: .next, navigationSource: .arrow))
        _ = model.handle(SearchKeyInput(kind: .next, navigationSource: .arrow))
        #expect(model.selected == 1)
        #expect(model.input == "settings ")
        #expect(model.handle(SearchKeyInput(kind: .confirm(shift: false, command: false, isRepeat: false))) == .submit("settings navrail"))
    }

    @Test
    func upwardNavigationAndExplicitMouseChoiceDoNotAdvanceAgain() {
        var model = model()
        _ = model.handle(SearchKeyInput(kind: .previous, navigationSource: .arrow))
        #expect(model.selected == 2)
        model.selectSuggestion(at: 1)
        model.acceptSelectedSuggestion()
        #expect(model.input == "settings navrail")
    }

    @Test
    func emptyInputKeepsHistoryAndReplacementLeavesHistory() {
        var model = model("")
        _ = model.handle(SearchKeyInput(kind: .previous, navigationSource: .arrow))
        #expect(model.input == "stage 2")
        model.replaceInput("settings ")
        #expect(model.historyCursor == nil)
        #expect(model.selected == nil)
        #expect(model.input == "settings ")
    }

    @Test
    func hitTestingUsesTheScrolledSuggestionIndicesAndRejectsTheInputBar() throws {
        let layout = SearchBarLayout.make(bounds: CGRect(x: -1600, y: -300, width: 1600, height: 1000), suggestions: 20, messageLines: 0)
        let visible = SearchBarLayout.visibleSuggestions(count: 20, selected: 16, rows: layout.suggestionRows.count)
        for (offset, row) in layout.suggestionRows.enumerated() {
            #expect(layout.suggestionIndex(at: CGPoint(x: row.midX, y: row.midY), count: 20, selected: 16) == visible.lowerBound + offset)
        }
        #expect(layout.suggestionIndex(at: CGPoint(x: layout.bar.midX, y: layout.bar.midY), count: 20, selected: 16) == nil)
    }
}
