import Foundation
import Testing
@testable import RoadieDaemon

/// Session 129 : corrections de l'audit V15 du 29 octobre 2026.
struct Spec129AuditFixesTests {
    /// Run Script, Run NSAppleScript et tâche d'automatisation vont au-delà du délai des filtres (10 s),
    /// comme dans Alfred. Les trois tournent en même temps : le test dure environ 10,5 s.
    @Test func workflowActionsOutliveTheFilterDelay() async throws {
        let duration = AlfredScriptRunner.defaultTimeout + 0.5
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("K2", "input.keyword", ["keyword": "k2"])
        fixture.add("SH", "action.script", ["type": 0, "scriptargtype": 1, "script": "sleep \(duration); printf fini"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("AS", "action.applescript", ["applescript": "on alfred_script(q)\ndelay \(duration)\nreturn \"apple\"\nend alfred_script"])
        fixture.add("CB2", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("K", "SH")
        fixture.link("SH", "CB")
        fixture.link("K2", "AS")
        fixture.link("AS", "CB2")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let task = AlfredAutomationTask(uid: "long", name: "Longue", folder: workflow.folder, script: "sleep \(duration); printf tache",
                                        scriptType: 0, defaults: [:], inputOverride: nil)
        async let chain = AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["x"])
        async let apple = AlfredWorkflowEngine(effects: effects).run(workflow, from: "K2", arg: ["x"])
        async let automation = AlfredAutomationTasks.run(task, settings: [:], input: [], workflow: workflow, variables: [:])
        let (outcome, appleOutcome, taskResult) = await (chain, apple, automation)
        #expect(outcome.errors.isEmpty && appleOutcome.errors.isEmpty)
        #expect(Set(effects.calls) == ["copy:fini", "copy:apple"])
        #expect(taskResult.succeeded && taskResult.text == "tache")
    }

    /// Sans délai, seul le script décide de sa fin ; les filtres gardent leur délai.
    @Test func noTimeoutMeansNoTimer() async throws {
        let workflow = try WorkflowFixture().write()
        let result = await AlfredScriptRunner.run(AlfredScript(language: 0, source: "sleep 0.2; printf ok"), query: "", arguments: [],
                                                  workflow: workflow, variables: [:], timeout: nil)
        #expect(result.succeeded && !result.timedOut && result.text == "ok")
        #expect(AlfredScriptRunner.defaultTimeout == 10)
    }

    /// Commandes système : le script gardé rend « ok » ou son numéro d'erreur ; l'annulation (-128) est muette.
    @Test func systemCommandFailuresAreReported() async {
        #expect(LauncherSystemCommand.scriptTimeout >= 600)
        #expect(LauncherSystemCommand.failureMessage("Éteindre", answer: "ok\n") == nil)
        #expect(LauncherSystemCommand.failureMessage("Éteindre", answer: "-128") == nil)
        #expect(LauncherSystemCommand.failureMessage("Éteindre", answer: "-1743") == "Éteindre : échec (-1743)")
        #expect(LauncherSystemCommand.failureMessage("Éteindre", answer: nil) == "Éteindre : échec")
        let success = await LauncherBrowsers.run(LauncherSystemCommand.guarded("set x to 1"), timeout: 5)
        let failure = await LauncherBrowsers.run(LauncherSystemCommand.guarded("error number 42"), timeout: 5)
        let cancelled = await LauncherBrowsers.run(LauncherSystemCommand.guarded("error number -128"), timeout: 5)
        #expect(LauncherSystemCommand.failureMessage("X", answer: success) == nil)
        #expect(LauncherSystemCommand.failureMessage("X", answer: failure) == "X : échec (42)")
        #expect(LauncherSystemCommand.failureMessage("X", answer: cancelled) == nil)
    }
}
