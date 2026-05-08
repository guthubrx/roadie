import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct RulesCommandTests {
    @Test
    func rulesValidateAcceptsFixture() throws {
        let service = RulesCommandService(configPath: try fixturePath())

        let report = service.validate()

        #expect(!report.hasErrors)
        #expect(report.items.contains(ConfigValidationItem(
            level: .ok,
            path: "rules",
            message: "rules are valid"
        )))
    }

    @Test
    func rulesValidateReportsConflicts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rules-conflict-\(UUID().uuidString).toml")
        try """
        [[rules]]
        id = "conflict"

        [rules.match]
        app = "System Settings"

        [rules.action]
        exclude = true
        layout = "tile"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = RulesCommandService(configPath: url.path).validate()

        #expect(report.hasErrors)
        #expect(report.items.contains { $0.path == "rules[0].action" })
    }

    @Test
    func rulesListReturnsPriorityOrder() throws {
        let rules = try RulesCommandService(configPath: try fixturePath()).list()

        #expect(rules.map(\.id) == ["browser-docs", "terminal-dev"])
    }

    @Test
    func rulesExplainReturnsMatchedRule() throws {
        let explanation = try RulesCommandService(configPath: try fixturePath()).explain(
            window: WindowSnapshot(
                id: WindowID(rawValue: 7),
                pid: 42,
                appName: "Terminal",
                bundleID: "com.apple.Terminal",
                title: "roadie",
                frame: Rect(x: 0, y: 0, width: 800, height: 600),
                isOnScreen: true,
                isTileCandidate: true
            ),
            context: WindowRuleMatchContext(role: "AXWindow", stage: "dev")
        )

        #expect(explanation.matchedRuleID == "terminal-dev")
        #expect(explanation.evaluations.first { $0.ruleId == "terminal-dev" }?.actionsApplied.contains("gap_override") == true)
    }
}

private func fixturePath() throws -> String {
    try #require(Bundle.module.url(forResource: "Spec002Rules", withExtension: "toml")).path
}
