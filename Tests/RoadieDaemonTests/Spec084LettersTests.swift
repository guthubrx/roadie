import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@MainActor
struct Spec084LettersTests {
    private func target(_ id: String) -> RoadieTarget {
        RoadieTarget(id: id, kind: .window, title: id, source: .roadie, actions: [.focus])
    }

    @Test func lettersAreTheSingleDistinctLettersOfTheAlphabet() {
        #expect(LauncherList.letters("asdfghjkl") == ["a", "s", "d", "f", "g", "h", "j", "k", "l"])
        #expect(LauncherList.letters("aZa1q ") == ["a", "z", "q"])
    }

    @Test func shownTargetRowsGetLettersInDisplayOrder() {
        let app = LauncherApp(bundleID: "b", path: "/Applications/Finder.app", name: "Finder", alternateNames: [])
        let list = LauncherList.idle([.header("Fenêtres"), .app(app, detail: ""), .target(target("A")), .target(target("B")),
                                      .target(target("C")), .target(target("D"))])
        let found = list.letterRows(visible: 0..<5, letters: ["a", "s"])
        #expect(found.map { $0.letter } == ["a", "s"])
        #expect(found.map { $0.index } == [2, 3])
        #expect(found.map { $0.target.id } == ["A", "B"])
        // Une ligne hors de l'écran n'a pas de lettre.
        #expect(list.letterRows(visible: 0..<4, letters: ["a", "s", "d"]).map { $0.target.id } == ["A", "B"])
    }

    @Test func onlyWindowsOfAShownStageGetABadgeOnScreen() {
        var context = LauncherSearchContext.disabled
        context.shownStages = [StageScope(displayID: DisplayID(rawValue: "LG"), desktopID: DesktopID(rawValue: 3), stageID: StageID(rawValue: "2"))]
        func window(_ display: String, _ desktop: Int, _ stage: String) -> RoadieTarget {
            RoadieTarget(id: "window:1", kind: .window, title: "Teams", source: .roadie,
                         scope: TargetScopeSnapshot(displayId: display, desktopId: desktop, stageId: stage, windowId: 1), actions: [.focus])
        }
        #expect(context.isOnScreen(window("LG", 3, "2")))
        // Autre bureau de l'écran interne, ou stage cachée : pas de badge.
        #expect(!context.isOnScreen(window("Interne", 1, "8")))
        #expect(!context.isOnScreen(window("LG", 3, "5")))
        #expect(context.isOnScreen(RoadieTarget(id: "stage:2", kind: .stage, title: "Com", source: .roadie, actions: [.switch])))
    }

    @Test func onlyAShownLetterIsTakenFromTheText() throws {
        func shift(_ text: String) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: text, charactersIgnoringModifiers: text,
                                          isARepeat: false, keyCode: 40))
        }
        #expect(SearchInputPanel.navigation(try shift("K"), labels: ["k", "a"])?.kind == .labelCharacter("k"))
        // Lettre sans pastille : la majuscule s'écrit dans le champ.
        #expect(SearchInputPanel.navigation(try shift("K"), labels: ["a"]) == nil)
        #expect(SearchInputPanel.navigation(try shift("K")) == nil)
    }

    @Test func theLetterIsDrawnAsAChipOnTheRight() throws {
        func render(letter: String) throws -> Data {
            var row = SlashSuggestion(text: "Firefox", detail: "Perso", kind: .result, icon: .symbol("macwindow"))
            row.shortcut = "⌘2"
            row.letter = letter
            let bar = TargetSearchBar(query: "fi", matchCount: 1, properties: nil, isLoading: false,
                                      suggestions: [row], selectedSuggestion: nil, richRows: true)
            let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            SearchBarRenderer.draw(bar, in: bounds, style: TargetOverlayStyle())
            image.unlockFocus()
            return try #require(image.tiffRepresentation)
        }
        #expect(try render(letter: "⇧K") != render(letter: ""))
    }
}
