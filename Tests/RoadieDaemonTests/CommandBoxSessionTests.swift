import CoreGraphics
import Testing
@testable import RoadieDaemon

/// Boîte de commandes dans la session de recherche (SPEC-023 T014, T014b) : aiguillage des touches et
/// mise en page, sans écran.
@Suite
struct CommandBoxSessionTests {
    private func key(_ code: Int64, _ text: String = "", shift: Bool = false, control: Bool = false, isRepeat: Bool = false) -> SearchKeyInput {
        SearchKeyInput(keyCode: code, text: text, shift: shift, command: false, control: control, isRepeat: isRepeat)
    }

    private func box(history: [String] = []) -> SlashCommandModel {
        SlashCommandModel(history: history) { input in
            ["stage", "screen", "doctor"]
                .filter { $0.hasPrefix(input) }
                .map { SlashSuggestion(text: $0 + " ", kind: .command) }
        }
    }

    @Test
    func slashInEmptyQueryEntersCommandModeAndDeletingItReturnsToSearch() {
        var search = TargetSearchModel(targets: [])
        search.type("/")
        #expect(search.isCommandMode)

        var command = box()
        #expect(command.handle(key(1, "s")) == .update)
        #expect(command.handle(key(51)) == .update)
        // Saisie vide : effacer retire le `/`.
        #expect(command.handle(key(51)) == .leave)
        search.deleteBackward()
        #expect(search.query.isEmpty)
        #expect(!search.isCommandMode)
    }

    @Test
    func shiftLetterIsUppercaseTextInCommandMode() {
        var command = box()
        _ = command.handle(key(35, "p"))
        _ = command.handle(key(1, "S", shift: true))
        _ = command.handle(key(14, "É", shift: true))
        #expect(command.input == "pSÉ")
    }

    @Test
    func tabCompletesAndShiftTabOrControlKeysMoveTheSelection() {
        var command = box()
        _ = command.handle(key(1, "s"))
        _ = command.handle(key(17, "t"))
        _ = command.handle(key(48, "\t"))
        #expect(command.input == "stage ")

        var list = box()
        _ = list.handle(key(45, "\u{0E}", control: true))
        #expect(list.selected == 0)
        #expect(list.input.isEmpty)
        _ = list.handle(key(45, "\u{0E}", control: true))
        #expect(list.selected == 1)
        _ = list.handle(key(35, "\u{10}", control: true))
        #expect(list.selected == 0)
        _ = list.handle(key(48, "\t", shift: true))
        #expect(list.selected == 2)
        #expect(list.input.isEmpty)
    }

    @Test
    func arrowsBrowseHistory() {
        var command = box(history: ["stage 2", "doctor"])
        _ = command.handle(key(126))
        #expect(command.input == "doctor")
        _ = command.handle(key(126))
        #expect(command.input == "stage 2")
        _ = command.handle(key(125))
        #expect(command.input == "doctor")
    }

    @Test
    func returnSubmitsAtOnceAndEscapeCloses() {
        var command = box()
        for character in "stage 2" {
            _ = command.handle(key(0, String(character)))
        }
        #expect(command.handle(key(36, "\r", isRepeat: true)) == .update)
        #expect(command.handle(key(36, "\r")) == .submit("stage 2"))
        #expect(command.handle(key(53)) == .close)
    }

    @Test
    func barWithoutLinesKeepsItsFormerPlace() {
        let layout = SearchBarLayout.make(bounds: CGRect(x: 0, y: 0, width: 1280, height: 720), contentWidth: 100, suggestions: 0, messageLines: 0)
        #expect(layout.bar == CGRect(x: 430, y: 48, width: 420, height: 40))
        #expect(layout.panel == nil)
    }

    @Test
    func linesStackAboveTheBarWithTheMessageNearest() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let layout = SearchBarLayout.make(bounds: bounds, contentWidth: 600, suggestions: 3, messageLines: 2)
        let panel = try #require(layout.panel)
        #expect(layout.bar.minY == 48)
        #expect(panel.minY == layout.bar.maxY + SearchBarLayout.gap)
        #expect(panel.width == layout.bar.width)
        #expect(layout.suggestionRows.count == 3)
        #expect(layout.messageRows.count == 2)
        let rows = layout.suggestionRows + layout.messageRows
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.minY > $1.minY })
        #expect(rows.allSatisfy { panel.contains($0) })
        #expect(bounds.contains(panel))
    }

    @Test
    func linesAreBoundedToEightSuggestionsTwelveMessageLinesAndTheScreen() throws {
        let tall = SearchBarLayout.make(bounds: CGRect(x: 0, y: 0, width: 1280, height: 900), contentWidth: 0, suggestions: 20, messageLines: 30)
        #expect(tall.suggestionRows.count == 8)
        #expect(tall.messageRows.count == 12)

        let short = CGRect(x: 0, y: 0, width: 1280, height: 300)
        let clipped = SearchBarLayout.make(bounds: short, contentWidth: 0, suggestions: 8, messageLines: 12)
        let panel = try #require(clipped.panel)
        #expect(panel.maxY <= short.maxY)
        #expect(clipped.messageRows.count == 8)
        #expect(clipped.suggestionRows.isEmpty)
    }

    @Test
    func visibleSuggestionsFollowTheSelection() {
        #expect(SearchBarLayout.visibleSuggestions(count: 15, selected: nil, rows: 8) == 0..<8)
        #expect(SearchBarLayout.visibleSuggestions(count: 15, selected: 10, rows: 8) == 3..<11)
        #expect(SearchBarLayout.visibleSuggestions(count: 15, selected: 14, rows: 8) == 7..<15)
        #expect(SearchBarLayout.visibleSuggestions(count: 3, selected: 2, rows: 8) == 0..<3)
        #expect(SearchBarLayout.visibleSuggestions(count: 0, selected: nil, rows: 8) == 0..<0)
    }
}
