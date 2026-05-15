import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

private final class RuleSystemSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    let display = DisplaySnapshot(
        id: DisplayID(rawValue: "display-main"),
        index: 1,
        name: "Main",
        frame: Rect(x: 0, y: 0, width: 1200, height: 800),
        visibleFrame: Rect(x: 0, y: 0, width: 1200, height: 800),
        isMain: true
    )
    let displaysOverride: [DisplaySnapshot]?
    let window: WindowSnapshot

    init(window: WindowSnapshot, displays: [DisplaySnapshot]? = nil) {
        self.window = window
        self.displaysOverride = displays
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        displaysOverride ?? [display]
    }

    func windows() -> [WindowSnapshot] {
        [window]
    }
}

private final class RuleRecordingWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var requestedFrames: [WindowID: Rect] = [:]
    private(set) var focusedWindowIDs: [WindowID] = []

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        focusedWindowIDs.append(window.id)
        return true
    }
}

@Suite
struct WindowRuleMaintainerTests {
    @Test
    func tickPublishesRuleMatchedAndAppliedEvents() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-events-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-events-stage-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let store = StageStore(path: stagePath)
        let window = ruleWindow(id: 61, appName: "Terminal", title: "roadie")
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "terminal-dev",
                    match: RuleMatch(app: "Terminal", title: "roadie", stage: "1"),
                    action: RuleAction(assignStage: "shell", scratchpad: "terminals")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.matched\""))
        #expect(events.contains("\"type\":\"rule.applied\""))
        #expect(events.contains("\"ruleID\":\"terminal-dev\""))
        #expect(events.contains("\"scratchpad\":\"terminals\""))
    }

    @Test
    func tickPublishesRuleSkippedWhenNoRuleMatches() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-skipped-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-skipped-stage-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let store = StageStore(path: stagePath)
        let window = ruleWindow(id: 62, appName: "Finder", title: "Desktop")
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "terminal-dev",
                    match: RuleMatch(app: "Terminal"),
                    action: RuleAction(assignStage: "shell")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.skipped\""))
        #expect(events.contains("\"reason\":\"no matching rule\""))
    }

    @Test
    func tickPublishesRuleFailedWhenRulesAreInvalid() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-failed-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-failed-stage-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let store = StageStore(path: stagePath)
        let window = ruleWindow(id: 63, appName: "Terminal", title: "roadie")
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "bad-regex",
                    match: RuleMatch(titleRegex: "[unterminated"),
                    action: RuleAction(assignStage: "shell")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.failed\""))
        #expect(events.contains("\"path\":\"rules[0].match.title_regex\""))
        #expect(events.contains("\"message\":\"invalid regex"))
    }

    @Test
    func tickPlacesMatchedWindowOnNamedStage() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-stage-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-stage-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let displayID = DisplayID(rawValue: "display-main")
        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: displayID,
                activeStageID: StageID(rawValue: "1"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1")),
                    PersistentStage(id: StageID(rawValue: "2"), name: "Media")
                ]
            )
        ]))
        let window = ruleWindow(id: 64, appName: "BlueJay", title: "Media")
        let writer = RuleRecordingWriter()
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: writer,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "bluejay-media",
                    match: RuleMatch(app: "BlueJay"),
                    action: RuleAction(assignStage: "Media")
                )
            ]),
            store: store
        )

        let tick = maintainer.tick()

        #expect(tick.applied == 1)
        #expect(store.state().stageScope(for: window.id) == StageScope(
            displayID: displayID,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "2")
        ))
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.placement_applied\""))
        #expect(events.contains("\"stageID\":\"2\""))
    }

    @Test
    func tickDoesNotReapplyPlacementAfterWindowWasMovedManually() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-manual-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-manual-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let displayID = DisplayID(rawValue: "display-main")
        let window = ruleWindow(id: 69, appName: "BlueJay", title: "Grayjay")
        var scope = PersistentStageScope(
            displayID: displayID,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Affinity"),
                PersistentStage(id: StageID(rawValue: "2"), name: "Manual")
            ]
        )
        scope.assign(window: window, to: StageID(rawValue: "1"))
        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [scope]))
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "bluejay-affinity",
                    match: RuleMatch(app: "BlueJay"),
                    action: RuleAction(assignStage: "1")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        var movedState = store.state()
        var movedScope = movedState.scope(displayID: displayID)
        movedScope.assign(window: window, to: StageID(rawValue: "2"))
        movedState.update(movedScope)
        store.save(movedState)

        _ = maintainer.tick()

        #expect(store.state().stageScope(for: window.id) == StageScope(
            displayID: displayID,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "2")
        ))
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.placement_skipped\""))
        #expect(events.contains("\"reason\":\"window already managed\""))
    }

    @Test
    func tickPlacesMatchedWindowOnNamedDisplay() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-display-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-display-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let main = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: Rect(x: 0, y: 0, width: 1200, height: 800),
            isMain: true
        )
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"),
            index: 2,
            name: "LG HDR 4K",
            frame: Rect(x: 1200, y: 0, width: 1600, height: 900),
            visibleFrame: Rect(x: 1200, y: 0, width: 1600, height: 900),
            isMain: false
        )
        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id),
            PersistentStageScope(displayID: external.id)
        ]))
        let window = ruleWindow(id: 65, appName: "Slack", title: "Com")
        let writer = RuleRecordingWriter()
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window, displays: [main, external]),
            frameWriter: writer,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "slack-com",
                    match: RuleMatch(app: "Slack"),
                    action: RuleAction(assignDisplay: "LG HDR 4K", assignStage: "RoadieTestCom")
                )
            ]),
            store: store
        )

        let tick = maintainer.tick()

        #expect(tick.applied == 1)
        #expect(store.state().stageScope(for: window.id) == StageScope(
            displayID: external.id,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "RoadieTestCom")
        ))
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.placement_applied\""))
        #expect(events.contains("\"displayID\":\"display-external\""))
    }

    @Test
    func tickDefersPlacementWhenDisplayIsMissing() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-deferred-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-deferred-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let store = StageStore(path: stagePath)
        let window = ruleWindow(id: 66, appName: "Word", title: "Doc")
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "word-missing-display",
                    match: RuleMatch(app: "Word"),
                    action: RuleAction(assignDisplay: "Missing Display", assignStage: "Docs")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        #expect(!eventsContainPlacementApplied(path: eventPath))
        #expect(store.state().stageScope(for: window.id)?.displayID == DisplayID(rawValue: "display-main"))
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.placement_deferred\""))
    }

    @Test
    func tickSkipsPlacementForNonTileCandidate() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-skipped-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-skipped-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let store = StageStore(path: stagePath)
        var window = ruleWindow(id: 68, appName: "System Settings", title: "Sheet")
        window.isTileCandidate = false
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window),
            frameWriter: RuleRecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "settings-dialog",
                    match: RuleMatch(app: "System Settings"),
                    action: RuleAction(assignStage: "Settings")
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.placement_skipped\""))
        #expect(events.contains("\"reason\":\"not a tile candidate\""))
    }

    @Test
    func tickFollowsPlacementWhenRuleRequestsIt() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-follow-\(UUID().uuidString).jsonl")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-placement-follow-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let main = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: Rect(x: 0, y: 0, width: 1200, height: 800),
            isMain: true
        )
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"),
            index: 2,
            name: "External",
            frame: Rect(x: 1200, y: 0, width: 1600, height: 900),
            visibleFrame: Rect(x: 1200, y: 0, width: 1600, height: 900),
            isMain: false
        )
        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id),
            PersistentStageScope(displayID: external.id)
        ]))
        let window = ruleWindow(id: 67, appName: "iTerm2", title: "dev")
        let writer = RuleRecordingWriter()
        let service = SnapshotService(
            provider: RuleSystemSnapshotProvider(window: window, displays: [main, external]),
            frameWriter: writer,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "terminal-dev-follow",
                    match: RuleMatch(app: "iTerm2"),
                    action: RuleAction(assignDisplay: "External", assignStage: "Dev", follow: true)
                )
            ]),
            store: store
        )

        _ = maintainer.tick()

        let state = store.state()
        #expect(state.activeDisplayID == external.id)
        #expect(state.stageScope(for: window.id) == StageScope(
            displayID: external.id,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "Dev")
        ))
        #expect(writer.focusedWindowIDs.contains(window.id))
    }
}

private func eventsContainPlacementApplied(path: String) -> Bool {
    ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").contains("\"type\":\"rule.placement_applied\"")
}

private func ruleWindow(id: UInt32, appName: String, title: String) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: 42,
        appName: appName,
        bundleID: "com.example.\(appName.lowercased())",
        title: title,
        frame: Rect(x: 100, y: 100, width: 500, height: 400),
        isOnScreen: true,
        isTileCandidate: true
    )
}
