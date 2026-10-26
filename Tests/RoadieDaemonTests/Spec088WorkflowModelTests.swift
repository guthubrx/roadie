import Foundation
import Testing
@testable import RoadieDaemon

struct Spec088WorkflowModelTests {
    @Test func loadsObjectsConnectionsAndSettings() throws {
        var fixture = WorkflowFixture()
        fixture.add("SF", "input.scriptfilter", ["keyword": "{var:kw}", "withspace": true, "argumenttype": 1, "title": "Émojis",
                                                  "subtext": "chercher", "type": 0, "script": "echo", "scriptargtype": 1])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}", "autopaste": false])
        fixture.add("IF", "utility.conditional", ["conditions": [["uid": "C1", "matchmode": 0, "matchstring": "a"]]])
        fixture.link("SF", "CB")
        fixture.link("SF", "CB", modifiers: 1_048_576)
        fixture.link("IF", "CB", branch: "C1")
        fixture.variables = ["kw": "emo", "langue": "fr"]
        fixture.settings = [["variable": "teinte", "type": "popupbutton", "config": ["default": "0"]]]
        fixture.prefs = ["teinte": "3", "kw": "emoji"]
        let workflow = try fixture.write()
        #expect(workflow.objects["SF"]?.type == "input.scriptfilter")
        #expect(workflow.objects["SF"]?.bool("withspace") == true)
        #expect(workflow.connections["SF"]?.map(\.modifiers) == [0, 1_048_576])
        #expect(workflow.connections["IF"]?.first?.branch == "C1")
        // Variables du workflow, puis défauts des réglages, puis valeurs de l'utilisateur.
        #expect(workflow.configuredVariables == ["kw": "emoji", "langue": "fr", "teinte": "3"])
        let entry = try #require(AlfredWorkflowIndex.entries([workflow]).first)
        #expect(entry.keyword == "emoji" && entry.title == "Émojis" && entry.kind == .scriptFilter && entry.argument == .optional)
    }

    @Test func keywordMatching() {
        func entry(_ argument: AlfredEntry.Argument, space: Bool = true) -> AlfredEntry {
            AlfredEntry(workflowID: "w", workflowName: "W", objectUID: "o", kind: .scriptFilter, keyword: "emoji", withSpace: space,
                        argument: argument, title: "Emoji search", subtitle: "", icon: nil)
        }
        #expect(entry(.optional).match("emoji") == .run(""))
        #expect(entry(.optional).match("Emoji heart") == .run("heart"))
        #expect(entry(.optional).match("emojiheart") == .none)
        #expect(entry(.optional).match("em") == .suggest)
        #expect(entry(.optional).match("search") == .suggest) // par le titre
        #expect(entry(.optional).match("z") == .none)
        #expect(entry(.required).match("emoji") == .suggest)
        #expect(entry(.required).match("emoji  heart ") == .run("heart"))
        #expect(entry(.none).match("emoji") == .run(""))
        #expect(entry(.none).match("emoji x") == .none)
        #expect(entry(.optional, space: false).match("emojiheart") == .run("heart"))
    }

    @Test func placeholdersAndPlistValues() {
        let text = AlfredPlaceholders.expand("{query}/{var:a}/{const:c}/{var:absent}/{inconnu}", query: "q", variables: ["a": "1"], constants: ["c": "k"])
        #expect(text == "q/1/k//{inconnu}")
        #expect(AlfredPlaceholders.expand("{allvars}", query: "", variables: ["b": "2", "a": "1"]) == #"{"a":"1","b":"2"}"#)
        #expect(AlfredPlaceholders.expand("x={query}", query: "a b", variables: [:], encode: { $0.replacingOccurrences(of: " ", with: "+") }) == "x=a+b")
        #expect(PlistValue(true as NSNumber) == .bool(true))
        #expect(PlistValue(3 as NSNumber) == .int(3))
        #expect(PlistValue(1.5 as NSNumber) == .double(1.5))
    }

    @Test func alfredPreferencesFollowTheSyncedFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-088-home-\(UUID().uuidString)")
        let support = home.appendingPathComponent("Library/Application Support/Alfred")
        let synced = home.appendingPathComponent("Nuage/Alfred.alfredpreferences")
        try FileManager.default.createDirectory(at: synced, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try #"{"current": "\#(synced.path)"}"#.write(to: support.appendingPathComponent("prefs.json"), atomically: true, encoding: .utf8)
        #expect(AlfredWorkflowIndex.alfredPreferences(home: home.path)?.path == synced.path)
    }

    @Test func indexSkipsDisabledAndRereadsChanges() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-088-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "kw", "text": "Mot"])
        let workflow = try fixture.write(in: parent)
        let index = AlfredWorkflowIndex()
        let folders = AlfredWorkflowIndex.children(of: parent).map { ($0, AlfredWorkflow.Source.roadie) }
        #expect(index.workflows(in: folders).map(\.name) == ["Essai"])
        var plist = try #require(NSDictionary(contentsOf: workflow.folder.appendingPathComponent("info.plist")) as? [String: Any])
        plist["disabled"] = true
        Thread.sleep(forTimeInterval: 1.1) // date de modification à la seconde
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: workflow.folder.appendingPathComponent("info.plist"))
        #expect(index.workflows(in: folders).isEmpty)
    }
}
