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

    /// Lot D : `cachedSnapshot` renvoie immédiatement l'instantané pré-calculé sans I/O disque,
    /// `refreshAsync` coalesce les appels concurrents, et `changedWorkflowIDs` / `invalidate`
    /// détectent un changement interne de script même à métadonnées d'entrée identiques.
    @Test func workflowIndexCachesCoalescesAndInvalidatesModifiedWorkflows() throws {
        let index = AlfredWorkflowIndex()
        #expect(index.cachedSnapshot(alfred: false, roadie: false) == nil)

        var fixture1 = WorkflowFixture(name: "Alpha")
        fixture1.add("SF", "input.scriptfilter", ["keyword": "al", "withspace": true, "argumenttype": 1, "type": 0, "script": "echo v1"])
        let wfV1 = try fixture1.write()

        var fixture2 = WorkflowFixture(name: "Alpha")
        fixture2.add("SF", "input.scriptfilter", ["keyword": "al", "withspace": true, "argumenttype": 1, "type": 0, "script": "echo v2"])
        let wfV2Raw = try fixture2.write()
        // Même identifiant de workflow, même mot-clé/titre, mais script modifié.
        let wfV2 = AlfredWorkflow(
            id: wfV1.id, bundleID: wfV1.bundleID, name: wfV1.name, description: wfV1.description,
            version: wfV1.version, folder: wfV1.folder, source: wfV1.source, disabled: false,
            objects: wfV2Raw.objects, connections: wfV2Raw.connections, variables: wfV2Raw.variables,
            userSettings: wfV2Raw.userSettings, prefs: wfV2Raw.prefs
        )

        // Coalescence de deux rafraîchissements concurrents sur la même clé : un seul chargement.
        let counter = CounterBox()
        let results = ResultsBox()
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        group.enter()
        index.refreshAsync(key: "test-coalesce", loader: {
            counter.increment()
            entered.signal()
            gate.wait()
            return AlfredWorkflowIndex.PreparedSnapshot.build(from: [wfV1])
        }) { snapshot in
            results.append(snapshot)
            group.leave()
        }
        try #require(entered.wait(timeout: .now() + 5) == .success)
        group.enter()
        index.refreshAsync(key: "test-coalesce", loader: {
            counter.increment()
            return AlfredWorkflowIndex.PreparedSnapshot.build(from: [wfV1])
        }) { snapshot in
            results.append(snapshot)
            group.leave()
        }
        gate.signal()
        try #require(group.wait(timeout: .now() + 5) == .success)
        let snapshots = results.all
        #expect(counter.value == 1)
        #expect(snapshots.count == 2)
        #expect(snapshots[0] == snapshots[1])
        #expect(snapshots[0].entries.count == 1)

        // Changement interne de script : entrées égales mais `changedWorkflowIDs` détecte le workflow
        // et `AlfredScriptFilterCache.invalidate` purge uniquement ses réponses.
        #expect(AlfredWorkflowIndex.entries([wfV1]) == AlfredWorkflowIndex.entries([wfV2]))
        let changed = AlfredWorkflowIndex.changedWorkflowIDs(from: [wfV1], to: [wfV2])
        #expect(changed == [wfV1.id])

        let cache = AlfredScriptFilterCache()
        let cachedResponse = AlfredScriptFilterResponse(items: [AlfredItem(title: "v1")], cacheSeconds: 60)
        let modifiedKey = "wf:\(wfV1.id):SF\u{1F}q"
        let untouchedKey = "wf:other-wf:SF\u{1F}q"
        cache.store(cachedResponse, for: modifiedKey)
        cache.store(cachedResponse, for: untouchedKey)
        cache.invalidate(workflowIDs: changed)
        #expect(cache.response(for: modifiedKey) == nil)
        #expect(cache.response(for: untouchedKey) != nil)

        // Garde de génération : une réponse ou un `rerun` d'une ancienne génération à argument
        // identique est rejeté et ne peut pas repeupler `AlfredScriptFilterCache`.
        let sessionStore = TargetModeRuntimeController.WorkflowSessionStore([wfV1])
        let runV1 = try #require(sessionStore.snapshotForRun(workflowID: wfV1.id))
        #expect(sessionStore.isCurrent(runV1.generation))
        let replaced = sessionStore.replace(with: [wfV2])
        #expect(replaced == [wfV1.id])
        #expect(!sessionStore.isCurrent(runV1.generation))
        if sessionStore.isCurrent(runV1.generation) {
            cache.store(cachedResponse, for: modifiedKey)
        }
        #expect(cache.response(for: modifiedKey) == nil)

        // Même argument "q", génération courante incrémentée après rafraîchissement -> rejeté.
        #expect(!WorkflowCallbackGuard.acceptsResponse(
            currentGeneration: 2, callbackGeneration: 1, currentArgument: "q", callbackArgument: "q"
        ))
        #expect(WorkflowCallbackGuard.acceptsResponse(
            currentGeneration: 2, callbackGeneration: 2, currentArgument: "q", callbackArgument: "q"
        ))
        // `rerun` après retrait du workflow ou changement de génération -> rejeté.
        let entryV1 = try #require(AlfredWorkflowIndex.entries([wfV1]).first)
        #expect(!WorkflowCallbackGuard.acceptsRerun(
            currentGeneration: 2, rerunGeneration: 1, currentQuery: "al q", rerunQuery: "al q",
            activeEntries: [entryV1], entryID: entryV1.id
        ))
        #expect(!WorkflowCallbackGuard.acceptsRerun(
            currentGeneration: 1, rerunGeneration: 1, currentQuery: "al q", rerunQuery: "al q",
            activeEntries: [], entryID: entryV1.id
        ))
        #expect(WorkflowCallbackGuard.acceptsRerun(
            currentGeneration: 1, rerunGeneration: 1, currentQuery: "al q", rerunQuery: "al q",
            activeEntries: [entryV1], entryID: entryV1.id
        ))
    }
}

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class ResultsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AlfredWorkflowIndex.PreparedSnapshot] = []
    var all: [AlfredWorkflowIndex.PreparedSnapshot] { lock.withLock { items } }
    func append(_ snapshot: AlfredWorkflowIndex.PreparedSnapshot) { lock.withLock { items.append(snapshot) } }
}
