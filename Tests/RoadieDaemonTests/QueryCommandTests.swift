import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct QueryCommandTests {
    @Test
    func queryStateAndWindowsExposeStablePayloads() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = AutomationQueryService(service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)))

        let state = service.query("state")
        let windows = service.query("windows")

        #expect(state.kind == "state")
        #expect(windows.kind == "windows")
        if case .array(let rows) = windows.data {
            #expect(rows.count == 1)
        } else {
            Issue.record("windows query did not return an array")
        }
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

        #expect(query.query("displays").kind == "displays")
        #expect(query.query("desktops").kind == "desktops")
        #expect(query.query("stages").kind == "stages")
        #expect(query.query("groups").kind == "groups")
        #expect(query.query("rules").kind == "rules")
    }

    @Test
    func passiveQueriesDoNotReadSystemSnapshot() throws {
        let provider = CountingProvider(windows: [powerWindow(1, x: 100)])
        let eventURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-query-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: eventURL) }
        let log = EventLog(path: eventURL.path)
        log.append(RoadieEvent(type: "stage.changed"))
        let service = AutomationQueryService(
            service: SnapshotService(provider: provider, frameWriter: CountingWriter()),
            eventLog: log
        )

        #expect(service.query("events").kind == "events")
        #expect(service.query("event_catalog").kind == "event_catalog")
        #expect(service.query("performance").kind == "performance")
        #expect(service.query("restore").kind == "restore")
        #expect(provider.snapshotReads == 0)
    }
}

final class CountingProvider: SystemSnapshotProviding, @unchecked Sendable {
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

struct CountingWriter: WindowFrameWriting, Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        frame
    }
}
