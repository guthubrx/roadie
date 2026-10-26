import Foundation
import Testing
@testable import RoadieDaemon

struct Spec089WorkflowsTests {
    @Test func externalTriggersReachThisOrAnotherWorkflow() async throws {
        var other = WorkflowFixture()
        other.bundleID = "test.autre"
        other.add("EXT", "trigger.external", ["triggerid": "copier"])
        other.add("CB", "output.clipboard", ["clipboardtext": "{query}/{var:v}"])
        other.link("EXT", "CB")
        let target = try other.write()
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("ARG", "utility.argument", ["argument": "{query}", "variables": ["v": "1"]])
        fixture.add("CALL", "output.callexternaltrigger", ["externaltriggerid": "copier", "workflowbundleid": "test.autre",
                                                           "passinputasargument": true, "passvariables": true])
        fixture.add("SELF", "trigger.external", ["triggerid": "moi"])
        fixture.add("NT", "output.notification", ["title": "moi", "text": "{query}"])
        fixture.link("K", "ARG")
        fixture.link("ARG", "CALL")
        fixture.link("SELF", "NT")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let engine = AlfredWorkflowEngine(effects: effects, workflows: [workflow, target])
        _ = await engine.run(workflow, from: "K", arg: ["x"])
        // `roadie workflow trigger` : depuis le déclencheur ; `run` sur un objet l'exécute lui-même.
        let trigger = try #require(AlfredWorkflowEngine.externalTrigger("moi", in: workflow))
        _ = await engine.run(workflow, from: trigger.uid, arg: ["y"])
        _ = await engine.start(workflow, at: "NT", arg: ["z"])
        #expect(effects.calls == ["copy:x/1", "notify:moi|y", "notify:moi|z"])
    }

    @Test func triggersAreIndexedWithTheirKeysAndAcceptedTypes() throws {
        var fixture = WorkflowFixture()
        fixture.add("HK", "trigger.hotkey", ["hotmod": 1_572_864, "hotstring": "g", "argument": 3, "argumenttext": "0"])
        fixture.add("FA", "trigger.action", ["name": "Partager", "filetypes": ["public.image"], "acceptsmulti": 1])
        fixture.add("UA", "trigger.universalaction", ["name": "Demander", "acceptstext": true])
        fixture.add("FB", "trigger.fallback", ["text": "Chercher « {query} »"])
        let workflow = try fixture.write()
        let triggers = AlfredWorkflowIndex.triggers([workflow])
        let hotkey = try #require(triggers.first { $0.kind == .hotkey })
        #expect(hotkey.keys == "⌥⌘G" && hotkey.hotkeyArgument == 3 && hotkey.hotkeyText == "0")
        let action = try #require(triggers.first { $0.kind == .fileAction })
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-089-\(UUID().uuidString).png")
        let text = image.deletingPathExtension().appendingPathExtension("txt")
        try Data().write(to: image)
        try Data().write(to: text)
        defer { try? FileManager.default.removeItem(at: image); try? FileManager.default.removeItem(at: text) }
        #expect(AlfredWorkflowIndex.accepts(action, path: image.path))
        #expect(!AlfredWorkflowIndex.accepts(action, path: text.path))
        let universal = try #require(triggers.first { $0.kind == .universalAction })
        #expect(universal.acceptsText && !AlfredWorkflowIndex.accepts(universal, path: image.path))
        #expect(triggers.first { $0.kind == .fallback }?.title == "Chercher « {query} »")
        #expect(AlfredWorkflowIndex.keys(modifiers: 262_144 + 131_072, key: "k") == "⌃⇧K")
    }

    @Test func listAndFileFilters() throws {
        var fixture = WorkflowFixture()
        fixture.add("LF", "input.listfilter", ["keyword": "fmt", "withspace": true, "argumenttype": 1, "matchmode": 0,
                                               "items": #"[{"title":"mov","arg":"mov"},{"title":"mp4","arg":"mp4"},{"title":"gif","arg":"gif"}]"#])
        let workflow = try fixture.write()
        let entry = try #require(AlfredWorkflowIndex.entries([workflow]).first)
        #expect(entry.kind == .listFilter && entry.filtersResults && entry.listItems.map(\.arg) == [["mov"], ["mp4"], ["gif"]])
        #expect(AlfredScriptFilterResponse.filter(entry.listItems, query: "m", mode: entry.filterMode).map(\.title) == ["mov", "mp4"])
        let filter = AlfredObject(uid: "FF", type: "input.filefilter", config: [
            "scopes": .array([.string("~/Documents")]), "types": .array([.string("public.image")]), "limit": .int(5),
            "fields": .array([.dict(["field": .string("kMDItemDisplayName"), "value": .string("{query}"), "words": .bool(true)])])])
        #expect(AlfredFileFilter.query(filter, argument: #"a"b"#) == #"(kMDItemDisplayName == "*a\"b*"cdw) && (kMDItemContentTypeTree == "public.image")"#)
        let script = try #require(AlfredFileFilter.script(filter, argument: "chat"))
        #expect(script.source.contains("-onlyin '\(NSHomeDirectory())/Documents'") && script.source.hasSuffix("head -n 5"))
        #expect(AlfredFileFilter.script(filter, argument: "  ") == nil)
        let items = AlfredFileFilter.response("/Users/x/a.png\nbruit\n/Users/x/b.jpg\n").items
        #expect(items.map(\.title) == ["a.png", "b.jpg"] && items[0].isFile && items[0].arg == ["/Users/x/a.png"])
    }

    @Test func automationTasksRunWithTheirSettingsInTheirFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-089-tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Tasks/test.core/essai/argument.dire")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let task: [String: Any] = [
            "taskName": "Dire", "scriptType": 0, "inputOverride": "cible",
            "script": #"printf '{"alfredworkflow":{"arg":"%s|%s|%s|%s"}}' "$1" "$ton" "$fort" "$(basename "$PWD")""#,
            "configurableConfig": [["variable": "ton", "type": "textfield", "config": ["default": "doux"]],
                                   ["variable": "fort", "type": "checkbox", "config": ["default": false]],
                                   ["variable": "cible", "type": "filepicker", "config": ["default": ""]]]]
        try JSONSerialization.data(withJSONObject: task).write(to: folder.appendingPathComponent("alfredtask.json"))
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("T", "automation.task", ["taskuid": "test.core/essai/argument.dire", "tasksettings": ["fort": true, "ton": "{var:t}"]])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("T2", "automation.task", ["taskuid": "test.core/absente"])
        fixture.link("K", "T")
        fixture.link("T", "CB")
        fixture.link("K", "T2")
        fixture.variables = ["t": "vif"]
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let engine = AlfredWorkflowEngine(effects: effects)
        engine.tasksRoot = root
        let outcome = await engine.run(workflow, from: "K", arg: ["salut"])
        #expect(effects.calls.first == "copy:salut|vif|1|argument.dire")
        #expect(outcome.missing.count == 1 && outcome.missing[0].hasPrefix("tâche absente"))
        #expect(AlfredCompatibility.report(workflow, tasksRoot: root).missing.count == 1)
    }

    @Test func dialogsAndOtherBricks() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("DLG", "utility.dialog", ["title": "Sûr ?", "button1": "Oui", "button2": "Non"])
        fixture.add("OUI", "output.largetype", ["largetypetext": "oui {query}"])
        fixture.add("NON", "output.dispatchkeycombo", ["keycode": -1, "keychar": "n", "keymod": 1_048_576, "count": 2])
        fixture.add("TERM", "action.terminalcommand", ["script": "man {query}", "escaping": 1])
        fixture.add("SC", "automation.runshortcut", ["shortcut": "Raccourci", "inputmode": 1, "outputmode": 0])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.add("BR", "action.browseinalfred", ["path": "\(NSHomeDirectory())/Documents"])
        fixture.link("K", "DLG")
        fixture.link("DLG", "OUI", branch: "_button1")
        fixture.link("DLG", "NON", branch: "_button2")
        fixture.link("K", "TERM")
        fixture.link("K", "SC")
        fixture.link("SC", "CB")
        fixture.link("K", "BR")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["a b"])
        #expect(effects.calls == ["dialog:Sûr ?", "large:oui a b", "terminal:man a\\ b", "shortcut:Raccourci:a b", "copy:sortie", "bar:~/Documents"])
        let second = RecordedEffects()
        second.dialogChoice = 2
        _ = await AlfredWorkflowEngine(effects: second).run(workflow, from: "K", arg: ["x"])
        #expect(second.calls.prefix(2) == ["dialog:Sûr ?", "keys:-1:n:1048576:2"])
    }
}
