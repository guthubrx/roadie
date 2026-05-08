import Foundation
import RoadieAX
import RoadieCore

public struct RuleExplanation: Equatable, Codable, Sendable {
    public var matchedRuleID: String?
    public var evaluations: [RuleEvaluation]

    public init(matchedRuleID: String?, evaluations: [RuleEvaluation]) {
        self.matchedRuleID = matchedRuleID
        self.evaluations = evaluations
    }
}

public struct RulesCommandService: Sendable {
    public var configPath: String?

    public init(configPath: String? = nil) {
        self.configPath = configPath
    }

    public func validate() -> ConfigValidationReport {
        do {
            let config = try RoadieConfigLoader.load(from: configPath)
            let items = WindowRuleValidator.validate(config.rules)
            if items.isEmpty {
                return ConfigValidationReport(items: [
                    ConfigValidationItem(level: .ok, path: "rules", message: "rules are valid")
                ])
            }
            return ConfigValidationReport(items: items)
        } catch {
            return ConfigValidationReport(items: [
                ConfigValidationItem(level: .error, path: configPath ?? RoadieConfigLoader.defaultConfigPath(), message: "rules decode failed: \(error)")
            ])
        }
    }

    public func list() throws -> [WindowRule] {
        try RoadieConfigLoader.load(from: configPath).rules
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.id < rhs.id
                }
                return lhs.priority > rhs.priority
            }
    }

    public func explain(window: WindowSnapshot, context: WindowRuleMatchContext = WindowRuleMatchContext()) throws -> RuleExplanation {
        let rules = try list()
        var matchedRuleID: String?
        var evaluations: [RuleEvaluation] = []

        for rule in rules {
            let matched = WindowRuleMatcher.matches(rule: rule, window: window, context: context)
            if matched, matchedRuleID == nil {
                matchedRuleID = rule.id
            }
            evaluations.append(RuleEvaluation(
                ruleId: rule.id,
                windowId: String(window.id.rawValue),
                matched: matched,
                actionsApplied: matched ? rule.action.names : [],
                reason: matched ? "matched" : "criteria did not match"
            ))
        }

        return RuleExplanation(matchedRuleID: matchedRuleID, evaluations: evaluations)
    }
}

private extension RuleAction {
    var names: [String] {
        var result: [String] = []
        if manage != nil { result.append("manage") }
        if exclude != nil { result.append("exclude") }
        if assignDesktop != nil { result.append("assign_desktop") }
        if assignStage != nil { result.append("assign_stage") }
        if floating != nil { result.append("floating") }
        if layout != nil { result.append("layout") }
        if gapOverride != nil { result.append("gap_override") }
        if scratchpad != nil { result.append("scratchpad") }
        if emitEvent != nil { result.append("emit_event") }
        return result
    }
}
