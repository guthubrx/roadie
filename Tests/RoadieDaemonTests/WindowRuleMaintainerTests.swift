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
    let window: WindowSnapshot

    init(window: WindowSnapshot) {
        self.window = window
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        [display]
    }

    func windows() -> [WindowSnapshot] {
        [window]
    }
}

@Suite
struct WindowRuleMaintainerTests {
    @Test
    func tickPublishesRuleMatchedAndAppliedEvents() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rule-events-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: eventPath) }

        let window = ruleWindow(id: 61, appName: "Terminal", title: "roadie")
        let service = SnapshotService(provider: RuleSystemSnapshotProvider(window: window))
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "terminal-dev",
                    match: RuleMatch(app: "Terminal", title: "roadie", stage: "1"),
                    action: RuleAction(assignStage: "shell", scratchpad: "terminals")
                )
            ])
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
        defer { try? FileManager.default.removeItem(atPath: eventPath) }

        let window = ruleWindow(id: 62, appName: "Finder", title: "Desktop")
        let service = SnapshotService(provider: RuleSystemSnapshotProvider(window: window))
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "terminal-dev",
                    match: RuleMatch(app: "Terminal"),
                    action: RuleAction(assignStage: "shell")
                )
            ])
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
        defer { try? FileManager.default.removeItem(atPath: eventPath) }

        let window = ruleWindow(id: 63, appName: "Terminal", title: "roadie")
        let service = SnapshotService(provider: RuleSystemSnapshotProvider(window: window))
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(
                    id: "bad-regex",
                    match: RuleMatch(titleRegex: "[unterminated"),
                    action: RuleAction(assignStage: "shell")
                )
            ])
        )

        _ = maintainer.tick()

        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"rule.failed\""))
        #expect(events.contains("\"path\":\"rules[0].match.title_regex\""))
        #expect(events.contains("\"message\":\"invalid regex"))
    }
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
