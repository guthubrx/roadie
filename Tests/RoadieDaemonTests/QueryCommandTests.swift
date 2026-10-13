import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct QueryCommandTests {
    @Test
    func queryStateAndWindowsExposeStablePayloads() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = AutomationQueryService(service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)))

        let state = service.query("state")
        let windows = service.query("windows")

        #expect(state.kind == "state")
        #expect(windows.kind == "windows")
        // Le contenu doit décrire la fenêtre réelle, pas seulement avoir la bonne forme.
        let rows = try decode([AutomationWindowSnapshot].self, from: windows.data)
        #expect(rows.count == 1)
        #expect(rows.first?.id == "1")
        #expect(rows.first?.app == "App")
        #expect(rows.first?.title == "Window 1")
        #expect(rows.first?.displayId == "display-main")
        let stateRows = try decode(RoadieStateSnapshot.self, from: state.data)
        #expect(stateRows.windows.map(\.id) == ["1"])
        #expect(stateRows.activeDisplayId == "display-main")
    }

    @Test
    func queryDisplaysDesktopsStagesGroupsAndRulesExposePayloads() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let store = StageStore(path: tempPath("query-groups"))
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = snapshotService.snapshot()
        _ = WindowGroupCommandService(service: snapshotService, store: store).create(
            id: "pair",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        )
        let query = AutomationQueryService(service: snapshotService, configPath: try fixturePath())

        // Le nom de réponse est vérifié à part : il est recopié depuis l'entrée.
        let displays = query.query("displays")
        let desktops = query.query("desktops")
        let stages = query.query("stages")
        let groups = query.query("groups")
        let rules = query.query("rules")
        #expect([displays.kind, desktops.kind, stages.kind, groups.kind, rules.kind]
            == ["displays", "desktops", "stages", "groups", "rules"])

        // Un `.null` ou un tableau vide ferait échouer les attentes ci-dessous.
        let displayRows = try decode([AutomationDisplaySnapshot].self, from: displays.data)
        #expect(displayRows.map(\.id) == ["display-main"])
        #expect(displayRows.first?.activeDesktopId == "1")

        let desktopRows = try decode([AutomationDesktopSnapshot].self, from: desktops.data)
        #expect(desktopRows.count == 1)
        #expect(desktopRows.first?.displayId == "display-main")
        #expect(desktopRows.first?.id == "1")
        #expect(desktopRows.first?.activeStageId == "1")

        let stageRows = try decode([AutomationStageSnapshot].self, from: stages.data)
        let activeStage = stageRows.first { $0.id == "1" }
        #expect(activeStage?.displayId == "display-main")
        #expect(activeStage?.desktopId == "1")
        #expect(Set(activeStage?.windowIds ?? []) == ["1", "2"])
        #expect(stageRows.allSatisfy { $0.displayId == "display-main" && $0.desktopId == "1" })

        let groupRows = try decode([AutomationGroupSnapshot].self, from: groups.data)
        #expect(groupRows.count == 1)
        #expect(groupRows.first?.id == "pair")
        #expect(groupRows.first?.memberIds == ["1", "2"])
        #expect(groupRows.first?.activeMemberId == "1")
        #expect(groupRows.first?.displayId == "display-main")
        #expect(groupRows.first?.desktopId == "1")
        #expect(groupRows.first?.stageId == "1")

        // Règles du fichier de config explicite (fixture Spec002Rules.toml), pas celles du processus.
        let ruleRows = try decode([AutomationRuleSnapshot].self, from: rules.data)
        #expect(ruleRows.map(\.id) == ["terminal-dev", "browser-docs"])
        #expect(ruleRows.map(\.priority) == [10, 20])
        #expect(ruleRows.allSatisfy { $0.enabled })
    }

    @Test
    func queryUnknownNameReturnsError() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = AutomationQueryService(service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)))

        let result = service.query("nope")

        #expect(result.kind == "nope")
        #expect(result.data == .object(["error": .string("unknown query")]))
    }

    @Test
    func passiveQueriesDoNotReadSystemSnapshot() throws {
        let provider = QueryReadCountingProvider(windows: [powerWindow(1, x: 100)])
        let eventURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-query-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: eventURL) }
        let log = EventLog(path: eventURL.path)
        log.append(RoadieEvent(type: "stage.changed"))
        let service = AutomationQueryService(
            service: SnapshotService(provider: provider, frameWriter: QueryNoopFrameWriter()),
            eventLog: log
        )

        #expect(service.query("events").kind == "events")
        #expect(service.query("event_catalog").kind == "event_catalog")
        #expect(service.query("performance").kind == "performance")
        #expect(service.query("restore").kind == "restore")
        #expect(provider.snapshotReads == 0)
    }
}

/// Relit une charge utile générique comme type métier : échoue si la forme ou le contenu est absent.
private func decode<T: Decodable>(_ type: T.Type, from payload: AutomationPayload) throws -> T {
    let data = try JSONEncoder().encode(payload)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
}

private final class QueryReadCountingProvider: SystemSnapshotProviding, @unchecked Sendable {
    var snapshotReads = 0
    let displaySnapshots: [DisplaySnapshot]
    let windowSnapshots: [WindowSnapshot]

    init(displays: [DisplaySnapshot] = [powerDisplay()], windows: [WindowSnapshot]) {
        self.displaySnapshots = displays
        self.windowSnapshots = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        snapshotReads += 1
        return displaySnapshots
    }

    func windows() -> [WindowSnapshot] {
        snapshotReads += 1
        return windowSnapshots
    }

    func focusedWindowID() -> WindowID? {
        nil
    }
}

private struct QueryNoopFrameWriter: WindowFrameWriting, Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        frame
    }
}
