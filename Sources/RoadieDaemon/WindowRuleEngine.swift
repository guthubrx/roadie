import Foundation
import RoadieAX
import RoadieCore

public struct WindowRuleApplication: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var matchedRuleID: String?
    public var evaluations: [RuleEvaluation]
    public var excluded: Bool
    public var assignDesktop: String?
    public var assignDisplay: String?
    public var assignStage: String?
    public var follow: Bool?
    public var floating: Bool?
    public var layout: String?
    public var gapOverride: Int?
    public var scratchpad: String?

    public init(
        windowID: WindowID,
        matchedRuleID: String?,
        evaluations: [RuleEvaluation],
        excluded: Bool = false,
        assignDesktop: String? = nil,
        assignDisplay: String? = nil,
        assignStage: String? = nil,
        follow: Bool? = nil,
        floating: Bool? = nil,
        layout: String? = nil,
        gapOverride: Int? = nil,
        scratchpad: String? = nil
    ) {
        self.windowID = windowID
        self.matchedRuleID = matchedRuleID
        self.evaluations = evaluations
        self.excluded = excluded
        self.assignDesktop = assignDesktop
        self.assignDisplay = assignDisplay
        self.assignStage = assignStage
        self.follow = follow
        self.floating = floating
        self.layout = layout
        self.gapOverride = gapOverride
        self.scratchpad = scratchpad
    }
}

public final class WindowRuleEngine {
    private let rules: [WindowRule]
    private var scratchpadMarkers: [WindowID: String] = [:]
    public let validationErrors: [ConfigValidationItem]

    public init(rules: [WindowRule]) {
        self.rules = rules.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.id < rhs.id
            }
            return lhs.priority > rhs.priority
        }
        self.validationErrors = WindowRuleValidator.validate(rules)
    }

    public func evaluate(
        window: WindowSnapshot,
        context: WindowRuleMatchContext = WindowRuleMatchContext()
    ) -> WindowRuleApplication {
        var evaluations: [RuleEvaluation] = []
        var application = WindowRuleApplication(
            windowID: window.id,
            matchedRuleID: nil,
            evaluations: []
        )

        for rule in rules where rule.enabled {
            let matched = WindowRuleMatcher.matches(rule: rule, window: window, context: context)
            evaluations.append(RuleEvaluation(
                ruleId: rule.id,
                windowId: String(window.id.rawValue),
                matched: matched,
                actionsApplied: matched ? rule.action.names : [],
                reason: matched ? "matched" : "criteria did not match"
            ))
            guard matched else { continue }

            if application.matchedRuleID == nil {
                application = application.applying(rule.action, ruleID: rule.id)
            }
            if rule.stopProcessing {
                break
            }
        }

        application.evaluations = evaluations
        if let scratchpad = application.scratchpad {
            scratchpadMarkers[window.id] = scratchpad
        }
        return application
    }

    public func scratchpad(for windowID: WindowID) -> String? {
        scratchpadMarkers[windowID]
    }

    public func scratchpadMarkersSnapshot() -> [WindowID: String] {
        scratchpadMarkers
    }
}

private extension WindowRuleApplication {
    func applying(_ action: RuleAction, ruleID: String) -> WindowRuleApplication {
        WindowRuleApplication(
            windowID: windowID,
            matchedRuleID: ruleID,
            evaluations: evaluations,
            excluded: action.exclude ?? false,
            assignDesktop: action.assignDesktop,
            assignDisplay: action.assignDisplay,
            assignStage: action.assignStage,
            follow: action.follow,
            floating: action.floating,
            layout: action.layout,
            gapOverride: action.gapOverride,
            scratchpad: action.scratchpad
        )
    }
}

extension RuleAction {
    var names: [String] {
        var result: [String] = []
        if manage != nil { result.append("manage") }
        if exclude != nil { result.append("exclude") }
        if assignDesktop != nil { result.append("assign_desktop") }
        if assignDisplay != nil { result.append("assign_display") }
        if assignStage != nil { result.append("assign_stage") }
        if follow != nil { result.append("follow") }
        if floating != nil { result.append("floating") }
        if layout != nil { result.append("layout") }
        if gapOverride != nil { result.append("gap_override") }
        if scratchpad != nil { result.append("scratchpad") }
        if emitEvent != nil { result.append("emit_event") }
        return result
    }
}
