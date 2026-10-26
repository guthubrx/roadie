import Foundation
import Testing
@testable import RoadieDaemon

struct Spec088EngineTests {
    private let cmd = 1_048_576, alt = 524_288

    @Test func modifiersFollowTheirArrowOrTheDefault() async throws {
        var fixture = WorkflowFixture()
        fixture.add("SF", "input.scriptfilter", ["keyword": "e"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("NT", "output.notification", ["title": "Titre", "text": "{query}"])
        fixture.link("SF", "CB")
        fixture.link("SF", "NT", modifiers: cmd)
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let engine = AlfredWorkflowEngine(effects: effects)
        _ = await engine.run(workflow, from: "SF", arg: ["♥"])
        _ = await engine.run(workflow, from: "SF", arg: ["⌘"], modifiers: cmd)
        // ⌥ sans flèche propre : la flèche sans modificateur (research R6).
        _ = await engine.run(workflow, from: "SF", arg: [":coeur:"], modifiers: alt)
        #expect(effects.calls == ["copy:♥", "notify:Titre|⌘", "copy::coeur:"])
    }

    @Test func conditionsArgumentsAndScripts() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("ARG", "utility.argument", ["argument": "{query}!", "variables": ["nom": "{query}"]])
        fixture.add("IF", "utility.conditional", ["conditions": [["uid": "OUI", "inputstring": "{var:nom}", "matchmode": 4, "matchstring": "^a"]]])
        fixture.add("SH", "action.script", ["type": 0, "scriptargtype": 1, "script": #"printf '{"alfredworkflow":{"arg":"%s-%s","variables":{"x":"1"}}}' "$1" "$nom""#])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}/{var:x}"])
        fixture.add("NON", "output.notification", ["title": "sinon", "text": "{query}"])
        fixture.link("K", "ARG")
        fixture.link("ARG", "IF")
        fixture.link("IF", "SH", branch: "OUI")
        fixture.link("IF", "NON")
        fixture.link("SH", "CB")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["abc"])
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["zz"])
        #expect(effects.calls == ["copy:abc!-abc/1", "notify:sinon|zz!"])
    }

    @Test func utilities() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("SP", "utility.split", ["delimiter": ",", "trimarguments": true, "variableprefix": "p"])
        fixture.add("JN", "utility.joinargs", ["delimiter": "+"])
        fixture.add("RP", "utility.replace", ["matchmode": 1, "matchstring": "\\+", "replacestring": " et "])
        fixture.add("FI", "utility.filter", ["inputstring": "{var:p2}", "matchmode": 0, "matchstring": "b"])
        fixture.add("EX", "utility.expression", ["expression": "{var:p1} * 60"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("CB2", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("JS", "utility.json", ["json": #"{"alfredworkflow": {"variables": {"q": "{query}"}}}"#])
        fixture.add("CB3", "output.clipboard", ["clipboardtext": "{var:q}"])
        fixture.link("K", "SP")
        fixture.link("SP", "JN")
        fixture.link("JN", "RP")
        fixture.link("RP", "CB")
        fixture.link("SP", "FI")
        fixture.link("FI", "CB2")
        fixture.link("SP", "EX")
        fixture.link("EX", "CB2")
        fixture.link("K", "JS")
        fixture.link("JS", "CB3")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: [#"2 , b, "c""#])
        // Découpe : arguments séparés (tabulation dans `{query}`) et variables p1, p2… pour la suite de
        // sa branche seulement ; le JSON reçoit la saisie d'origine.
        #expect(effects.calls == ["copy:2 et b et \"c\"", "copy:2\tb\t\"c\"", "copy:120", "copy:2 , b, \"c\""])
        // Accolades d'un texte JSON : seuls les vrais remplacements sont touchés.
        #expect(AlfredPlaceholders.expand(#"{"a": {"b": "{query}"}}"#, query: "x", variables: [:]) == #"{"a": {"b": "x"}}"#)
    }

    @Test func missingBrickStopsAndLoopsAreBounded() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("TV", "userinterface.text", [:])
        fixture.add("J1", "utility.junction")
        fixture.add("J2", "utility.junction")
        fixture.link("K", "TV")
        fixture.link("K", "J1")
        fixture.link("J1", "J2")
        fixture.link("J2", "J1")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let outcome = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["x"])
        #expect(outcome.missing == ["userinterface.text"])
        #expect(outcome.steps == AlfredWorkflowEngine.maxSteps)
    }

    @Test func writeFileOverwritesOrAppends() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-088-write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("W1", "output.writefile", ["filename": dir.path + "/a/note.txt", "filetext": "{query}", "type": 1])
        fixture.add("W2", "output.writefile", ["filename": dir.path + "/a/note.txt", "filetext": "+{query}", "type": 2])
        fixture.link("K", "W1")
        fixture.link("W1", "W2")
        let workflow = try fixture.write()
        _ = await AlfredWorkflowEngine(effects: RecordedEffects()).run(workflow, from: "K", arg: ["x"])
        // W2 reçoit le chemin écrit par W1 comme argument.
        #expect(try String(contentsOfFile: dir.path + "/a/note.txt", encoding: .utf8) == "x+\(dir.path)/a/note.txt")
    }

    @Test func compatibilityReport() throws {
        var fixture = WorkflowFixture()
        fixture.add("SF", "input.scriptfilter", ["keyword": "ok", "type": 0, "script": "echo"])
        fixture.add("CB", "output.clipboard")
        fixture.add("K2", "input.keyword", ["keyword": "vue"])
        fixture.add("TV", "userinterface.text")
        fixture.link("SF", "CB")
        fixture.link("K2", "TV")
        let report = AlfredCompatibility.report(try fixture.write())
        #expect(report.state == .partial && report.missing == ["userinterface.text"] && report.keywords == ["ok", "vue"])
        var whole = WorkflowFixture()
        whole.add("SF", "input.scriptfilter", ["keyword": "ok", "type": 0, "script": "echo"])
        #expect(AlfredCompatibility.report(try whole.write()).state == .complete)
        var bad = WorkflowFixture()
        bad.add("SF", "input.scriptfilter", ["keyword": "x", "type": 10, "script": "echo"])
        let badReport = AlfredCompatibility.report(try bad.write())
        #expect(badReport.state == .unusable && badReport.missing == ["langage inconnu : 10"])
    }
}
