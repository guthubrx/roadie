import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct WindowRuleMatcherTests {
    @Test
    func exactAppTitleRoleAndStageMatch() {
        let rule = WindowRule(
            id: "terminal-dev",
            match: RuleMatch(
                app: "Terminal",
                title: "roadie",
                role: "AXWindow",
                stage: "dev"
            )
        )

        let matched = WindowRuleMatcher.matches(
            rule: rule,
            window: window(appName: "Terminal", title: "roadie"),
            context: WindowRuleMatchContext(role: "AXWindow", stage: "dev")
        )

        #expect(matched)
    }

    @Test
    func regexAppAndTitleMatch() {
        let rule = WindowRule(
            id: "browser-docs",
            match: RuleMatch(
                appRegex: "Safari|Firefox|Chrome",
                titleRegex: "Docs|Documentation"
            )
        )

        let matched = WindowRuleMatcher.matches(
            rule: rule,
            window: window(appName: "Firefox", title: "Roadie Documentation")
        )

        #expect(matched)
    }

    @Test
    func stageMismatchDoesNotMatch() {
        let rule = WindowRule(
            id: "terminal-dev",
            match: RuleMatch(app: "Terminal", stage: "dev")
        )

        let matched = WindowRuleMatcher.matches(
            rule: rule,
            window: window(appName: "Terminal"),
            context: WindowRuleMatchContext(stage: "ops")
        )

        #expect(!matched)
    }

    @Test
    func disabledRuleDoesNotMatch() {
        let rule = WindowRule(
            id: "disabled",
            enabled: false,
            match: RuleMatch(app: "Terminal")
        )

        #expect(!WindowRuleMatcher.matches(rule: rule, window: window(appName: "Terminal")))
    }

    @Test
    func firstMatchUsesHighestPriorityThenId() {
        let rules = [
            WindowRule(id: "z-fallback", priority: 10, match: RuleMatch(appRegex: "Terminal|iTerm")),
            WindowRule(id: "a-specific", priority: 20, match: RuleMatch(app: "Terminal"))
        ]

        let match = WindowRuleMatcher.firstMatch(rules: rules, window: window(appName: "Terminal"))

        #expect(match?.id == "a-specific")
    }
}

private func window(appName: String = "Terminal", title: String = "Window") -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: 100),
        pid: 42,
        appName: appName,
        bundleID: "com.example.\(appName.lowercased())",
        title: title,
        frame: Rect(x: 0, y: 0, width: 800, height: 600),
        isOnScreen: true,
        isTileCandidate: true
    )
}
