import Foundation
import Testing
@testable import RoadieDaemon

struct Spec088ResponseTests {
    @Test func jsonItemsWithModsIconsAndVariables() throws {
        let json = #"""
        {"variables": {"a": "1"}, "rerun": 9, "items": [
          {"uid": "u1", "title": "Cœur", "subtitle": "copier", "arg": ["x", 2], "valid": "no", "autocomplete": "coeur",
           "icon": {"type": "fileicon", "path": "/Applications"}, "text": {"copy": "♥"}, "type": "file:skipcheck",
           "mods": {"alt": {"arg": ":coeur:", "subtitle": "code"}, "cmd+alt": {"valid": false}, "hyper": {}},
           "variables": {"b": "2"}},
          {"title": 42}
        ]}
        """#
        let response = try #require(AlfredScriptFilterResponse.parse(Data(json.utf8)))
        #expect(response.variables == ["a": "1"] && response.rerun == 5)
        let item = try #require(response.items.first)
        #expect(item.uid == "u1" && item.arg == ["x", "2"] && !item.valid && item.autocomplete == "coeur" && item.isFile)
        #expect(item.icon == .fileIcon("/Applications") && item.copyText == "♥" && item.variables == ["b": "2"])
        #expect(item.mods[524_288]?.arg == [":coeur:"] && item.mods[524_288]?.subtitle == "code")
        #expect(item.mods[1_048_576 + 524_288]?.valid == false)
        #expect(item.mods.count == 2) // « hyper » inconnu ignoré
        #expect(response.items[1].title == "42")
    }

    @Test func legacyXMLItems() throws {
        let xml = #"<?xml version="1.0"?><items><item uid="a" arg="b" valid="no" autocomplete="c"><title>T</title><subtitle>S</subtitle><subtitle mod="cmd">SC</subtitle><icon type="filetype">public.folder</icon></item></items>"#
        let item = try #require(AlfredScriptFilterResponse.parse(Data(xml.utf8))?.items.first)
        #expect(item.title == "T" && item.subtitle == "S" && item.arg == ["b"] && !item.valid && item.autocomplete == "c")
        #expect(item.mods[1_048_576]?.subtitle == "SC" && item.icon == .fileType("public.folder"))
        #expect(AlfredScriptFilterResponse.parse(Data("pas du json".utf8)) == nil)
    }

    @Test func barFiltersWhenTheWorkflowAsksIt() {
        let items = ["My Family Photos", "Photos", "Family"].map { AlfredItem(title: $0) }
        #expect(AlfredScriptFilterResponse.filter(items, query: "pho", mode: 0).map(\.title) == ["My Family Photos", "Photos"])
        #expect(AlfredScriptFilterResponse.filter(items, query: "my fa", mode: 1).map(\.title) == ["My Family Photos"])
        #expect(AlfredScriptFilterResponse.filter(items, query: "ph fa", mode: 2).map(\.title) == ["My Family Photos"])
        #expect(AlfredScriptFilterResponse.filter(items, query: "ph fa", mode: 3).isEmpty)
        #expect(AlfredScriptFilterResponse.filter(items, query: "", mode: 0).count == 3)
    }

    @Test func runScriptOutput() {
        let json = AlfredRunScriptOutput.parse(#"{"alfredworkflow": {"arg": "a", "variables": {"v": "1"}}}"#)
        #expect(json.arg == ["a"] && json.variables == ["v": "1"])
        #expect(AlfredRunScriptOutput.parse("texte\n").arg == ["texte"])
    }
}
