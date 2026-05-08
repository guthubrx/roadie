import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct WindowRuleScratchpadTests {
    @Test
    func matchedScratchpadActionIsStoredAndExposed() {
        let window = makeWindow(id: 44, appName: "Firefox", title: "Roadie Documentation")
        let engine = WindowRuleEngine(rules: [
            WindowRule(
                id: "browser-docs",
                priority: 10,
                match: RuleMatch(appRegex: "Firefox|Safari", titleRegex: "Docs|Documentation"),
                action: RuleAction(assignDesktop: "docs", scratchpad: "research")
            )
        ])

        let application = engine.evaluate(window: window)

        #expect(application.matchedRuleID == "browser-docs")
        #expect(application.scratchpad == "research")
        #expect(application.evaluations.first?.actionsApplied.contains("scratchpad") == true)
        #expect(engine.scratchpad(for: window.id) == "research")
        #expect(engine.scratchpadMarkersSnapshot() == [window.id: "research"])
    }

    @Test
    func unmatchedRuleDoesNotCreateScratchpadMarker() {
        let window = makeWindow(id: 45, appName: "Terminal")
        let engine = WindowRuleEngine(rules: [
            WindowRule(
                id: "browser-docs",
                match: RuleMatch(app: "Firefox"),
                action: RuleAction(scratchpad: "research")
            )
        ])

        let application = engine.evaluate(window: window)

        #expect(application.matchedRuleID == nil)
        #expect(application.scratchpad == nil)
        #expect(engine.scratchpad(for: window.id) == nil)
    }
}

private func makeWindow(id: UInt32, appName: String, title: String = "Window") -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: 42,
        appName: appName,
        bundleID: "com.example.\(appName.lowercased())",
        title: title,
        frame: Rect(x: 0, y: 0, width: 800, height: 600),
        isOnScreen: true,
        isTileCandidate: true
    )
}
