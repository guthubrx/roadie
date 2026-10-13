import Foundation
import Testing
import RoadieDaemon

@Suite
struct SlashCommandModelTests {
    private static let commands = ["stage", "screen", "send", "set", "settings", "split"]
    private static let stageArguments = ["1", "2", "travail"]

    /// Fournisseur factice : commandes avant le premier espace, arguments de `stage` après.
    private static let provider: @Sendable (String) -> [SlashSuggestion] = { input in
        guard let space = input.lastIndex(of: " ") else {
            return commands.filter { $0.hasPrefix(input) }
                .map { SlashSuggestion(text: $0 + " ", detail: "commande", kind: .command) }
        }
        guard input.hasPrefix("stage ") else { return [] }
        let word = String(input[input.index(after: space)...])
        return stageArguments.filter { $0.hasPrefix(word) }
            .map { SlashSuggestion(text: $0, detail: "stage", kind: .argument) }
    }

    private func model(_ input: String = "", history: [String] = []) -> SlashCommandModel {
        SlashCommandModel(input: input, history: history, suggestionProvider: Self.provider)
    }

    private func texts(_ model: SlashCommandModel) -> [String] { model.suggestions.map(\.text) }

    @Test
    func startsActiveAndDeletingTheSlashDeactivates() {
        var m = model()
        #expect(m.isActive)
        m.type("ab")
        m.deleteBackward()
        m.deleteBackward()
        #expect(m.input.isEmpty)
        #expect(m.isActive)
        m.deleteBackward()
        #expect(!m.isActive)
    }

    @Test
    func typingRecomputesSuggestionsAndResetsSelection() {
        var m = model()
        #expect(m.suggestions.count == Self.commands.count)
        m.type("s")
        m.nextSuggestion()
        #expect(m.selected == 0)
        m.type("e")
        #expect(texts(m) == ["send ", "set ", "settings "])
        #expect(m.selected == nil)
        m.deleteBackward()
        #expect(m.suggestions.count == 6)
        #expect(m.selected == nil)
    }

    @Test
    func tabCompletesTheOnlySuggestion() {
        var m = model()
        m.type("st")
        m.complete()
        #expect(m.input == "stage ")
        // Les suggestions suivantes sont celles des arguments.
        #expect(texts(m) == Self.stageArguments)
        #expect(m.selected == nil)
    }

    @Test
    func tabCompletesTheCurrentWordOfAnArgument() {
        var m = model()
        m.type("stage t")
        m.complete()
        #expect(m.input == "stage travail")
    }

    @Test
    func tabWithoutSuggestionsChangesNothing() {
        var m = model()
        m.type("stage 9")
        let before = m
        m.complete()
        #expect(m == before)
        #expect(m.input == "stage 9")
    }

    @Test
    func tabAdvancesThroughSeveralSuggestionsAndCycles() {
        var m = model()
        m.type("se")
        m.complete()
        #expect(m.selected == 0)
        #expect(m.input == "send ")
        m.complete()
        #expect(m.input == "set ")
        m.complete()
        #expect(m.input == "settings ")
        m.complete()
        #expect(m.selected == 0)
        #expect(m.input == "send ")
        // La liste ne change pas pendant le cycle.
        #expect(texts(m) == ["send ", "set ", "settings "])
    }

    @Test
    func tabCyclesArgumentsAfterASpace() {
        var m = model()
        m.type("stage ")
        m.complete()
        #expect(m.input == "stage 1")
        m.complete()
        #expect(m.input == "stage 2")
        m.complete()
        m.complete()
        #expect(m.input == "stage 1")
    }

    @Test
    func controlNAndPCycleWithoutChangingTheInput() {
        var m = model()
        m.type("se")
        m.nextSuggestion()
        #expect(m.selected == 0)
        m.nextSuggestion()
        m.nextSuggestion()
        #expect(m.selected == 2)
        m.nextSuggestion()
        #expect(m.selected == 0)
        m.previousSuggestion()
        #expect(m.selected == 2)
        #expect(m.input == "se")
        var fresh = model()
        fresh.type("se")
        fresh.previousSuggestion()
        #expect(fresh.selected == 2)
    }

    @Test
    func navigationWithoutSuggestionsIsIgnored() {
        var m = model()
        m.type("zz")
        m.nextSuggestion()
        m.previousSuggestion()
        #expect(m.selected == nil)
    }

    @Test
    func messageIsClearedByTheNextEdit() {
        var m = model()
        m.setMessage(.error("Inconnue", usage: "/stage N"))
        #expect(m.message == .error("Inconnue", usage: "/stage N"))
        m.type("a")
        #expect(m.message == nil)
        m.setMessage(.info(["ok"]))
        m.deleteBackward()
        #expect(m.message == nil)
        m.setMessage(.info(["ok"]))
        _ = m.submit()
        #expect(m.message == .info(["ok"]))
        m.historyUp()
        #expect(m.message == nil)
    }

    @Test
    func submitTrimsAndRecordsHistoryWithoutDuplicatesInARow() {
        var m = model()
        m.type("  stage 2 ")
        #expect(m.submit() == "stage 2")
        #expect(m.submit() == "stage 2")
        #expect(m.history == ["stage 2"])
        m = model(history: ["stage 2"])
        m.type("screen droite")
        _ = m.submit()
        m = model(history: m.history)
        m.type("stage 2")
        _ = m.submit()
        #expect(m.history == ["stage 2", "screen droite", "stage 2"])
    }

    @Test
    func submitIgnoresEmptyInput() {
        var m = model()
        m.type("   ")
        #expect(m.submit().isEmpty)
        #expect(m.history.isEmpty)
    }

    @Test
    func historyIsCappedAtFifty() {
        var m = model()
        for index in 1...51 {
            m = model(history: m.history)
            m.type("cmd \(index)")
            _ = m.submit()
        }
        #expect(m.history.count == 50)
        #expect(m.history.first == "cmd 2")
        #expect(m.history.last == "cmd 51")
    }

    @Test
    func historyProvidedAtInitIsKeptAndTruncatedToFifty() {
        #expect(model(history: ["a", "b"]).history == ["a", "b"])
        let long = (1...60).map { "cmd \($0)" }
        let m = model(history: long)
        #expect(m.history.count == 50)
        #expect(m.history.first == "cmd 11")
        #expect(m.history.last == "cmd 60")
    }

    @Test
    func historyUpAndDownWalkThroughAndBackToEmpty() {
        var m = model(history: ["un", "deux", "trois"])
        m.historyDown()
        #expect(m.input.isEmpty)
        m.historyUp()
        #expect(m.input == "trois")
        m.historyUp()
        #expect(m.input == "deux")
        m.historyUp()
        m.historyUp()
        #expect(m.input == "un")
        m.historyDown()
        #expect(m.input == "deux")
        m.historyDown()
        #expect(m.input == "trois")
        m.historyDown()
        #expect(m.input.isEmpty)
        #expect(m.historyCursor == nil)
        // Après le retour à vide, Flèche haut repart de la plus récente.
        m.historyUp()
        #expect(m.input == "trois")
    }

    @Test
    func historyRecallRecomputesSuggestionsAndTypingLeavesTheWalk() {
        var m = model(history: ["stage "])
        m.historyUp()
        #expect(texts(m) == Self.stageArguments)
        m.type("t")
        #expect(m.historyCursor == nil)
        #expect(m.input == "stage t")
    }

    @Test
    func historyUpOnEmptyHistoryDoesNothing() {
        var m = model()
        m.historyUp()
        #expect(m.input.isEmpty)
        #expect(m.historyCursor == nil)
    }
}
