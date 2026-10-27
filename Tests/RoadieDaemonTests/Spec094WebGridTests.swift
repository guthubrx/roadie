import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 094 : `^` retiré de la recherche web, ordre appris dans la grille.
struct Spec094WebGridTests {
    private let google = "https://www.google.com/search?q={query}"

    @Test func caretIsRemovedBeforeSearching() throws {
        #expect(LauncherWeb.searchText("^claude") == "claude")
        #expect(LauncherWeb.searchText("  ^ claude code ") == "claude code")
        #expect(LauncherWeb.searchText("claude") == "claude")
        // Un ^ ailleurs qu'en tête reste (calcul, texte).
        #expect(LauncherWeb.searchText("2^10") == "2^10")
        let rows = LauncherWeb.fallbackRows("^claude", template: google, searches: WebSearch.defaults, fallbacks: [])
        let url = try #require(rows.first?.url)
        #expect(url.absoluteString == "https://www.google.com/search?q=claude")
        #expect(rows.first?.title.contains("« claude »") == true)
        #expect(LauncherWeb.fallbackRows("^", template: google, searches: [], fallbacks: []).isEmpty)
    }

    @Test func controlReturnSearchesWithoutTheCaret() {
        let variant = LauncherVariant.of(.url(URL(string: "https://example.com")!), modifier: .control, query: "^claude",
                                         newStageHome: (DisplayID(rawValue: "A"), DesktopID(rawValue: 1)), activeStage: nil)
        #expect(variant?.effect == .webSearch("claude"))
    }

    @Test func prependedSectionIsChosen() {
        var list = LauncherList.idle([.header("Applications"), .calc(LauncherCalculator.evaluate("1+1")!)])
        let row = LauncherWebRow(kind: .search(URL(string: "https://www.google.com/search?q=claude")!), title: "Rechercher")
        list.prependSection("Web", [.web(row)])
        #expect(list.rows.first == .header("Web"))
        #expect(list.best == LauncherList.Row.web(row).id)
    }

    @Test func gridLearnsOrderFromChoices() {
        let items = ["a", "b", "c"].map { AlfredItem(uid: $0, title: $0.uppercased()) } + [AlfredItem(title: "sans uid")]
        var ranking = LauncherRanking()
        let now = Date()
        // Choisie sans saisie : fréquence-récence ; choisie après « c » : cette saisie.
        ranking.recordVisit("wf:x:g:b", query: "", at: now)
        ranking.recordVisit("wf:x:g:c", query: "c", at: now)
        ranking.recordVisit("wf:x:g:c", query: "c", at: now)
        // Sans saisie : C (deux choix) puis B (un choix), puis l'ordre du script.
        #expect(AlfredGridView.learned(items, entryID: "wf:x:g", ranking: ranking, query: "", now: now).map(\.title) == ["C", "B", "A", "sans uid"])
        #expect(AlfredGridView.learned(items, entryID: "wf:x:g", ranking: ranking, query: "c", now: now).map(\.title) == ["C", "A", "B", "sans uid"])
        // Sans historique : l'ordre du script.
        #expect(AlfredGridView.learned(items, entryID: "wf:x:g", ranking: LauncherRanking(), query: "", now: now).map(\.title) == ["A", "B", "C", "sans uid"])
    }

    @Test func fixedOrderSettingIsRead() async throws {
        func view(_ config: [String: Any], json: String = #"{"items": [{"uid": "a", "title": "A"}]}"#) async throws -> AlfredGridView? {
            var fixture = WorkflowFixture()
            fixture.add("K", "input.keyword", ["keyword": "k"])
            fixture.add("G", "userinterface.grid", config.merging(["inputtype": 0]) { $1 })
            fixture.link("K", "G")
            let effects = RecordedEffects()
            _ = await AlfredWorkflowEngine(effects: effects).run(try fixture.write(), from: "K", arg: [json])
            return effects.lastGrid
        }
        #expect(try await view(["fixedorder": false])?.learnsOrder == true)
        #expect(try await view([:])?.learnsOrder == true)
        #expect(try await view(["fixedorder": true])?.learnsOrder == false)
        #expect(try await view(["fixedorder": false], json: #"{"skipknowledge": true, "items": []}"#)?.learnsOrder == false)
    }
}

/// Session 095 : texte d'attente de la grille.
struct Spec095GridLoadingTests {
    @Test func waitingViewThenTilesOrFailure() async throws {
        func run(_ config: [String: Any], script: String) async throws -> [AlfredGridView] {
            var fixture = WorkflowFixture()
            fixture.add("K", "input.keyword", ["keyword": "k"])
            fixture.add("G", "userinterface.grid", config.merging(["inputtype": 1, "inputfile": "t.sh"]) { $1 })
            fixture.link("K", "G")
            let effects = RecordedEffects()
            _ = await AlfredWorkflowEngine(effects: effects).run(try fixture.write(files: ["t.sh": script]), from: "K", arg: [""])
            return effects.grids
        }
        let ok = try await run(["loadingtext": "Chargement des volets"], script: "#!/bin/sh\necho '{\"items\":[{\"title\":\"A\"}]}'\n")
        #expect(ok.map(\.isWaiting) == [true, false])
        #expect(ok.first?.loadingText == "Chargement des volets" && ok.last?.loadingText == nil && ok.last?.items.count == 1)
        // Sans texte : « Loading… » ; réponse illisible : la ligne dit l'échec.
        let failed = try await run([:], script: "#!/bin/sh\necho pas du json\n")
        #expect(failed.first?.loadingText == "Loading…")
        #expect(failed.last?.loadingText == "Grille : réponse illisible" && failed.last?.isWaiting == false)
    }
}
