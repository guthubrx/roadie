import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct WindowRuleValidationTests {
    @Test
    func validRulesReturnNoValidationErrors() throws {
        let url = try #require(Bundle.module.url(forResource: "Spec002Rules", withExtension: "toml"))
        let config = try RoadieConfigLoader.load(from: url.path)

        let items = WindowRuleValidator.validate(config.rules)

        #expect(items.isEmpty)
    }

    @Test
    func missingMatchReturnsValidationError() {
        let rules = [
            WindowRule(
                id: "missing-match",
                action: RuleAction(layout: "tile")
            )
        ]

        let items = WindowRuleValidator.validate(rules)

        #expect(items.containsError(path: "rules[0].match", message: "at least one matcher"))
    }

    @Test
    func duplicateIdsReturnValidationError() {
        let rules = [
            WindowRule(id: "terminal", match: RuleMatch(app: "Terminal")),
            WindowRule(id: "terminal", match: RuleMatch(app: "iTerm2"))
        ]

        let items = WindowRuleValidator.validate(rules)

        #expect(items.containsError(path: "rules[1].id", message: "duplicate rule id 'terminal'"))
    }

    @Test
    func invalidRegexReturnsValidationError() {
        let rules = [
            WindowRule(
                id: "bad-regex",
                match: RuleMatch(titleRegex: "[unterminated"),
                action: RuleAction(floating: true)
            )
        ]

        let items = WindowRuleValidator.validate(rules)

        #expect(items.containsError(path: "rules[0].match.title_regex", message: "invalid regex"))
    }

    @Test
    func excludeWithLayoutActionReturnsValidationError() {
        let rules = [
            WindowRule(
                id: "conflicting-actions",
                match: RuleMatch(app: "System Settings"),
                action: RuleAction(exclude: true, layout: "tile")
            )
        ]

        let items = WindowRuleValidator.validate(rules)

        #expect(items.containsError(path: "rules[0].action", message: "exclude cannot be combined"))
    }

    @Test
    func excludeWithPlacementActionReturnsValidationError() {
        let rules = [
            WindowRule(
                id: "conflicting-placement",
                match: RuleMatch(app: "Slack"),
                action: RuleAction(exclude: true, assignDisplay: "LG HDR 4K")
            )
        ]

        let items = WindowRuleValidator.validate(rules)

        #expect(items.containsError(path: "rules[0].action", message: "exclude cannot be combined"))
    }
}

private extension Array where Element == ConfigValidationItem {
    func containsError(path: String, message: String) -> Bool {
        contains {
            $0.level == .error &&
                $0.path == path &&
                $0.message.contains(message)
        }
    }
}
