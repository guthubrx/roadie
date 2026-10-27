import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

/// Vue Grille des workflows (SPEC-092).
struct Spec092GridTests {
    private static let tiles = #"{"preselect": "b", "variables": {"r": "1"}, "items": [{"uid": "a", "title": "Wi-Fi", "arg": "x-apple.systempreferences:wifi", "icon": {"path": "images/wifi.png"}}, {"uid": "b", "title": "Bluetooth", "arg": "bt"}, {"title": "", "subtitle": "System Settings", "valid": false}]}"#

    // MARK: Modèle

    @Test func tilesFromJSONKeepPreselectAndSpacers() throws {
        let response = try #require(AlfredScriptFilterResponse.parse(Data(Self.tiles.utf8)))
        #expect(response.preselect == "b")
        let items = response.items
        #expect(items.count == 3)
        #expect(AlfredGridView.isSelectable(items[0]) && AlfredGridView.isSelectable(items[1]))
        // Espaceur d'Alfred : ni titre ni icône, jamais choisi au clavier.
        #expect(!AlfredGridView.isSelectable(items[2]))
    }

    @Test func tilesFromPathsShowImagesAndFileIcons() {
        let items = AlfredGridView.fileItems(["/tmp/photo.PNG\n/tmp/notes.txt", ""])
        #expect(items.map(\.title) == ["photo.PNG", "notes.txt"])
        #expect(items[0].icon == .image("/tmp/photo.PNG"))
        #expect(items[1].icon == .fileIcon("/tmp/notes.txt"))
        #expect(items.allSatisfy { $0.isFile && $0.arg == [$0.quickLookURL ?? ""] })
    }

    @Test func columnsAreBounded() {
        #expect(AlfredGridView.columns(nil) == 5)
        #expect(AlfredGridView.columns(0) == 1)
        #expect(AlfredGridView.columns(30) == 12)
    }

    /// Rang ± 1 ou ± colonnes, espaceurs sautés, bords sans effet (research R4, A2 de l'audit).
    @Test func neighboursMoveInTwoDimensions() {
        // 3 colonnes : 0 1 2 / 3 [4 espaceur] 5 / 6
        let selectable: (Int) -> Bool = { $0 != 4 }
        func step(_ index: Int, _ delta: Int) -> Int? { AlfredGridView.neighbour(of: index, step: delta, count: 7, selectable: selectable) }
        #expect(step(0, 1) == 1)
        #expect(step(3, 1) == 5)
        #expect(step(0, -1) == nil)
        // Sous 1 : l'espaceur puis le bord ; la sélection ne bouge pas.
        #expect(step(1, 3) == nil)
        #expect(step(0, 3) == 3)
        #expect(step(2, 3) == 5)
        #expect(step(6, 3) == nil)
        #expect(step(5, -3) == 2)
    }

    // MARK: Moteur

    @Test func gridFromAScriptOpensTheBarAndStops() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "sse"])
        fixture.add("G", "userinterface.grid", ["inputtype": 1, "inputfile": "tiles.sh", "columncount": 3, "filterable": true,
                                                "showtitles": true, "showsubtitles": true, "subtitlesinfooter": true])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("K", "G")
        fixture.link("G", "CB")
        let script = "#!/bin/sh\ncat <<'EOF'\n\(Self.tiles)\nEOF\n"
        let workflow = try fixture.write(files: ["tiles.sh": script])
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: [""], variables: ["v": "2"])
        // Texte d'attente d'abord (session 095), puis les tuiles.
        #expect(effects.calls == ["grid:0:3", "grid:3:3"])
        let view = try #require(effects.lastGrid)
        #expect(view.loadingText == nil && !view.isWaiting)
        #expect(view.entry.kind == .grid && view.entry.objectUID == "G" && view.entry.workflowID == workflow.id)
        #expect(view.preselect == "b")
        #expect(view.subtitlesInFooter && view.filterable && view.showTitles)
        // Variables du schéma et de la réponse, gardées pour Retour.
        #expect(view.variables["v"] == "2" && view.variables["r"] == "1")
    }

    @Test func jsonConfigOverridesTheNextObject() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("J", "utility.json", ["json": #"{"alfredworkflow": {"config": {"columncount": "{var:cols}"}}}"#])
        fixture.add("G", "userinterface.grid", ["inputtype": 0, "columncount": 6])
        fixture.link("K", "J")
        fixture.link("J", "G")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["/tmp/a.png\n/tmp/b.pdf"], variables: ["cols": "4"])
        // Liste de chemins reçue (source 0), colonnes surchargées par la brique JSON.
        #expect(effects.calls == ["grid:2:4"])
    }

    @Test func unknownSourceIsAMissingObject() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("G", "userinterface.grid", ["inputtype": 7])
        fixture.link("K", "G")
        let workflow = try fixture.write()
        let outcome = await AlfredWorkflowEngine(effects: RecordedEffects()).run(workflow, from: "K", arg: [""])
        #expect(outcome.missing == ["userinterface.grid:inputtype:7"])
    }

    /// Déclencheur externe porté par une brique quelconque (`inboundconfig.externalid`, research R7).
    @Test func externalTriggerReachesAnObjectByItsExternalID() async throws {
        var fixture = WorkflowFixture()
        fixture.add("H", "trigger.hotkey")
        fixture.add("ARG", "utility.argument", ["argument": "", "variables": ["submenu": "{query}"]])
        fixture.add("CALL", "output.callexternaltrigger", ["externaltriggerid": "listSettings", "workflowbundleid": "self",
                                                           "passinputasargument": false, "passvariables": true])
        fixture.add("J", "utility.json", ["json": #"{"alfredworkflow": {"config": {"columncount": "2"}}}"#], externalID: "listSettings")
        fixture.add("G", "userinterface.grid", ["inputtype": 0])
        fixture.link("H", "ARG")
        fixture.link("ARG", "CALL")
        fixture.link("J", "G")
        let workflow = try fixture.write()
        #expect(AlfredWorkflowEngine.externalTrigger("listSettings", in: workflow)?.uid == "J")
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "H", arg: ["general"])
        #expect(effects.calls == ["grid:0:2"])
        #expect(effects.lastGrid?.variables["submenu"] == "general")
    }

    @Test func gridIsSupportedByTheReport() throws {
        #expect(AlfredWorkflowEngine.supportedTypes.contains("userinterface.grid"))
        func report(_ grid: [String: Any], files: [String: String] = [:]) throws -> AlfredCompatibilityReport {
            var fixture = WorkflowFixture()
            fixture.add("K", "input.keyword", ["keyword": "k"])
            fixture.add("G", "userinterface.grid", grid)
            fixture.link("K", "G")
            return AlfredCompatibility.report(try fixture.write(files: files))
        }
        #expect(try report(["inputtype": 1, "inputfile": "tiles.sh"], files: ["tiles.sh": "#!/bin/sh\necho '{}'\n"]).state == .complete)
        #expect(try report(["inputtype": 0]).state == .complete)
        // Source inconnue ou script absent : nommés dans la fiche (FR-002).
        #expect(try report(["inputtype": 3]).missing == ["userinterface.grid:inputtype:3"])
        #expect(try report(["inputtype": 1, "inputfile": "absent.sh"]).state == .unusable)
    }

    // MARK: Barre

    @Test func gridLayoutKeepsTheSelectionVisibleAndMapsClicks() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 500)
        let layout = SearchBarLayout.makeGrid(bounds: bounds, count: 40, columns: 5, selected: 0, footer: true)
        let rows = layout.suggestionRows.count / 5
        #expect(rows >= 1 && layout.suggestionRows.count % 5 == 0)
        #expect(layout.firstVisible == 0)
        // Première rangée en haut, de gauche à droite.
        #expect(layout.suggestionRows[0].minX < layout.suggestionRows[1].minX)
        #expect(layout.suggestionRows[0].maxY > layout.suggestionRows[5].maxY)
        #expect(layout.messageRows.count == 1)
        // Dernière tuile choisie : la grille défile par rangées entières.
        let end = SearchBarLayout.makeGrid(bounds: bounds, count: 40, columns: 5, selected: 39, footer: false)
        let first = try #require(end.firstVisible)
        #expect(first % 5 == 0 && first <= 39 && 39 < first + end.suggestionRows.count)
        let tile = end.suggestionRows[end.suggestionRows.count - 1]
        #expect(end.suggestionIndex(at: CGPoint(x: tile.midX, y: tile.midY), count: 40, selected: 39) == 39)
    }

    @MainActor @Test func leftAndRightMoveOnlyInAGrid() throws {
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        #expect(SearchInputPanel.navigation(try key(123), text: "wi", grid: true)?.kind == .move(-1))
        #expect(SearchInputPanel.navigation(try key(124), text: "wi", grid: true)?.kind == .move(1))
        #expect(SearchInputPanel.navigation(try key(123), text: "wi") == nil)
        #expect(SearchInputPanel.navigation(try key(125), text: "", grid: true)?.kind == .next)
    }
}
