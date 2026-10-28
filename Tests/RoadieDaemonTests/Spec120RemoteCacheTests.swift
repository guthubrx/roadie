import Foundation
import Testing
@testable import RoadieDaemon

/// Boutons Remote et cache des Script Filters (session 120).
struct Spec120RemoteCacheTests {
    @Test func remoteButtonIsAnEntryCalledLikeAnExternalTrigger() async throws {
        var fixture = WorkflowFixture()
        fixture.add("R", "trigger.remote", ["triggerid": "audio.out1", "triggername": "Sortie 1", "argumenttype": 3, "argument": "0"])
        fixture.add("C", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("R", "C")
        let workflow = try fixture.write()
        let remote = try #require(AlfredWorkflowEngine.externalTrigger("audio.out1", in: workflow))
        #expect(remote.uid == "R" && AlfredWorkflowEngine.remoteArgument(remote) == ["0"])
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).start(workflow, at: "R", arg: AlfredWorkflowEngine.remoteArgument(remote))
        #expect(effects.calls == ["copy:0"])
        let report = AlfredCompatibility.report(workflow)
        #expect(report.missing.isEmpty)
    }

    @Test func cacheKeepsAResponseUntilItExpires() throws {
        let json = #"{"cache": {"seconds": 2, "loosereload": true}, "items": [{"title": "A"}]}"#
        let response = try #require(AlfredScriptFilterResponse.parse(Data(json.utf8)))
        #expect(response.cacheSeconds == 5)
        let cache = AlfredScriptFilterCache()
        let now = Date()
        cache.store(response, for: "k", now: now)
        #expect(cache.response(for: "k", now: now.addingTimeInterval(4))?.items.first?.title == "A")
        #expect(cache.response(for: "k", now: now.addingTimeInterval(6)) == nil)
        cache.store(AlfredScriptFilterResponse(items: [AlfredItem(title: "B")]), for: "sans-cache", now: now)
        #expect(cache.response(for: "sans-cache", now: now) == nil)
    }
}
