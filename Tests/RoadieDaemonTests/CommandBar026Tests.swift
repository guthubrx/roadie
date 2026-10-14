import AppKit
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
struct CommandBar026Tests {
    @Test
    func inputFrameDoesNotMoveWithTextSuggestionsOrMessages() {
        let screen = CGRect(x: 100, y: 50, width: 1280, height: 720)
        let empty = SearchBarLayout.make(bounds: screen, suggestions: 0, messageLines: 0)
        let long = SearchBarLayout.make(bounds: screen, suggestions: 8, messageLines: 12)
        #expect(empty.bar == long.bar)
        #expect(empty.bar.width == 640)
        #expect(empty.bar.midX == screen.midX)
    }

    @Test
    func tabAcceptsTheAlreadySelectedCommandBeforeCycling() {
        var model = SlashCommandModel(input: "s") { _ in
            [SlashSuggestion(text: "stage ", kind: .command), SlashSuggestion(text: "screen ", kind: .command)]
        }
        model.nextSuggestion()
        model.nextSuggestion()
        model.complete()
        #expect(model.input == "screen ")
        model.complete()
        #expect(model.input == "stage ")
    }

    @Test
    func tabAcceptsTheAlreadySelectedArgument() {
        var model = SlashCommandModel(input: "stage t") { _ in
            [SlashSuggestion(text: "travail", kind: .argument), SlashSuggestion(text: "test", kind: .argument)]
        }
        model.previousSuggestion()
        model.complete()
        #expect(model.input == "stage test")
    }

    @Test(arguments: [SearchKeyInput.Kind.next, .previous])
    func tabAfterControlNavigationAcceptsTheNewSelection(kind: SearchKeyInput.Kind) {
        var model = SlashCommandModel(input: "s") { _ in
            [SlashSuggestion(text: "stage ", kind: .command), SlashSuggestion(text: "screen ", kind: .command)]
        }
        model.complete()
        _ = model.handle(SearchKeyInput(kind: kind, navigationSource: .control))
        model.complete()
        #expect(model.input == "screen ")
    }

    @Test
    func tabAfterSelectionWrapAcceptsTheCurrentSelectionWithoutAdvancing() {
        var model = SlashCommandModel(input: "s") { _ in
            [SlashSuggestion(text: "stage ", kind: .command), SlashSuggestion(text: "screen ", kind: .command)]
        }
        model.complete()
        model.nextSuggestion()
        model.nextSuggestion()
        model.complete()
        #expect(model.input == "stage ")
        #expect(model.selected == 0)
    }

    private func target(_ id: String, title: String) -> RoadieTarget {
        RoadieTarget(id: id, label: "", kind: .appElement, title: title, source: .app,
                    frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: [.click])
    }

    @Test
    func searchTabCompletesTheSelectedTitleAndKeepsThatTarget() {
        var model = TargetSearchModel(targets: [target("first", title: "Watch Later"), target("second", title: "Watch List")])
        model.type("watch")
        model.next()
        model.handleNavigation(SearchKeyInput(keyCode: 48, text: "\t", shift: false, command: false, control: false, isRepeat: false))
        #expect(model.query == "Watch List")
        #expect(model.highlighted?.id == "second")
        #expect(!model.isAwaitingSecondReturn)
    }

    @Test(arguments: ["zzz", "", "*"])
    func searchTabWithoutACompletableTargetChangesNothing(query: String) {
        var model = TargetSearchModel(targets: [target("empty", title: "")])
        model.type(query)
        let before = model
        model.completeHighlighted()
        #expect(model == before)
    }

    @Test
    func searchCompletionDoesNotEnterCommandModeForASlashTitle() {
        var model = TargetSearchModel(targets: [target("slash", title: "/settings")])
        model.type("sett")
        model.completeHighlighted()
        #expect(model.query == " /settings")
        #expect(!model.isCommandMode)
        #expect(model.highlighted?.id == "slash")
    }

    @Test
    func completionCannotDropATargetWithCustomSearchText() {
        var custom = target("custom", title: "Zone de grille")
        custom.matchText = "ASD"
        var model = TargetSearchModel(targets: [custom])
        model.type("as")
        let before = model
        model.completeHighlighted()
        #expect(model == before)
        #expect(model.highlighted?.id == "custom")
    }

    @Test(arguments: [SearchKeyInput.NavigationSource.arrow, .control])
    func forwardNavigationStillMovesWithoutCompleting(source: SearchKeyInput.NavigationSource) {
        var model = TargetSearchModel(targets: [target("first", title: "Watch Later"), target("second", title: "Watch List")])
        model.type("watch")
        model.handleNavigation(SearchKeyInput(kind: .next, navigationSource: source))
        #expect(model.highlighted?.id == "second")
        #expect(model.query == "watch")
    }

    @Test
    func countIsSeparateFromTheSearchTextAndAbsentInCommandMode() {
        var bar = TargetSearchBar(query: "watch", matchCount: 12, properties: nil, isLoading: false)
        #expect(bar.inputText == "watch▏")
        #expect(bar.counterText == "12")
        bar.commandInput = "stage t"
        #expect(bar.inputText == "/stage t▏")
        #expect(bar.counterText == nil)
    }

    @Test(arguments: [CGSize(width: 1280, height: 720), CGSize(width: 320, height: 300), CGSize(width: 120, height: 80)])
    func largeFontsAndCounterStayInsideTheAvailableScreen(size: CGSize) throws {
        let bounds = CGRect(origin: CGPoint(x: -1280, y: -300), size: size)
        let layout = SearchBarLayout.make(bounds: bounds, suggestions: 0, messageLines: 0,
                                          searchTextFontSize: 48, commandTextFontSize: 48)
        let content = SearchBarContentLayout.make(bar: layout.bar, counterSize: CGSize(width: 95, height: 55))
        let counter = try #require(content.counter)
        #expect(bounds.contains(layout.bar))
        #expect(layout.bar.contains(content.input))
        #expect(layout.bar.contains(counter))
        #expect(content.input.maxX <= counter.minX)
        #expect(content.input.width >= 0)
    }
}
