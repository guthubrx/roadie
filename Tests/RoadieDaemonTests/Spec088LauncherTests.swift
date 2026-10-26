import Foundation
import Testing
@testable import RoadieDaemon

struct Spec088LauncherTests {
    private func entry(_ keyword: String = "emoji") -> AlfredEntry {
        AlfredEntry(workflowID: "w", workflowName: "Emoji search", objectUID: "SF", kind: .scriptFilter, keyword: keyword,
                    withSpace: true, argument: .optional, title: "Emoji", subtitle: "", icon: nil)
    }

    @Test func workflowRowsHaveStableIdentities() {
        let item = AlfredItem(uid: "smile", title: "😀")
        #expect(LauncherList.Row.workflowKeyword(entry()).id == "wfk:wf:w:SF")
        #expect(LauncherList.Row.workflowItem(entry(), item, index: 3).id == "wfi:wf:w:SF:smile")
        #expect(LauncherList.Row.workflowItem(entry(), AlfredItem(title: "x"), index: 3).id == "wfi:wf:w:SF:3")
        #expect(LauncherList.Row.workflowItem(entry(), item, index: 0).rankingKey == "wf:w:SF:smile")
        #expect(LauncherList.Row.workflowItem(entry(), AlfredItem(title: "x"), index: 0).rankingKey == nil)
    }

    @Test func keywordSuggestionsGoAfterTheFirstSectionWithoutTakingTheSelection() {
        var list = LauncherList.idle([.header("Applications"), .calc(LauncherCalculation(expression: "1+1", value: 2, text: "2")),
                                      .header("Fenêtres")])
        let before = list.best
        list.insertSection("Workflows", [.workflowKeyword(entry())])
        #expect(list.rows.map(\.id) == [nil, "calc", nil, "wfk:wf:w:SF", nil])
        #expect(list.best == before)
        var empty = LauncherList.empty
        empty.insertSection("Workflows", [.workflowKeyword(entry())])
        #expect(empty.best == "wfk:wf:w:SF")
    }

    /// De bout en bout, sans écran : le Script Filter d'un workflow d'essai répond, la ligne choisie
    /// avec ⌥ suit la flèche sans modificateur avec l'argument de ⌥ (comme Emoji search).
    @Test func scriptFilterAnswerThenReturnWithOption() async throws {
        var fixture = WorkflowFixture()
        fixture.add("SF", "input.scriptfilter", ["keyword": "emoji", "withspace": true, "argumenttype": 1, "type": 0, "scriptargtype": 1,
                                                  "script": #"printf '{"items":[{"uid":"c","title":"coeur %s","arg":"♥","mods":{"alt":{"arg":":coeur:","subtitle":"code"}}}]}' "$1""#])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("SF", "CB")
        let workflow = try fixture.write()
        let entry = try #require(AlfredWorkflowIndex.entries([workflow]).first)
        #expect(entry.match("emoji rouge") == .run("rouge"))
        let object = try #require(workflow.objects["SF"])
        let script = try #require(AlfredScript(object: object))
        let result = await AlfredScriptRunner.run(script, query: "rouge", arguments: ["rouge"], workflow: workflow, variables: [:])
        let item = try #require(AlfredScriptFilterResponse.parse(result.output)?.items.first)
        #expect(item.title == "coeur rouge" && item.mods[524_288]?.subtitle == "code")
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "SF", arg: item.mods[524_288]?.arg ?? item.arg, modifiers: 524_288)
        #expect(effects.calls == ["copy::coeur:"])
    }
}
