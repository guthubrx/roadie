import Foundation
import RoadieCore

public enum WindowRuleValidator {
    public static func validate(_ rules: [WindowRule]) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        var seenIDs: Set<String> = []

        for (index, rule) in rules.enumerated() {
            let path = "rules[\(index)]"

            if rule.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(error(path: "\(path).id", message: "rule id must not be empty"))
            } else if seenIDs.contains(rule.id) {
                items.append(error(path: "\(path).id", message: "duplicate rule id '\(rule.id)'"))
            } else {
                seenIDs.insert(rule.id)
            }

            if rule.match.isEmpty {
                items.append(error(path: "\(path).match", message: "rule must define at least one matcher"))
            }

            items.append(contentsOf: regexErrors(rule: rule, path: path))

            if rule.action.exclude == true && rule.action.hasLayoutEffect {
                items.append(error(
                    path: "\(path).action",
                    message: "exclude cannot be combined with layout or placement actions"
                ))
            }
        }

        return items
    }

    private static func regexErrors(rule: WindowRule, path: String) -> [ConfigValidationItem] {
        [
            ("app_regex", rule.match.appRegex),
            ("title_regex", rule.match.titleRegex)
        ].compactMap { key, pattern -> ConfigValidationItem? in
            guard let pattern else { return nil }
            do {
                _ = try NSRegularExpression(pattern: pattern)
                return nil
            } catch {
                return Self.error(path: "\(path).match.\(key)", message: "invalid regex '\(pattern)'")
            }
        }
    }

    private static func error(path: String, message: String) -> ConfigValidationItem {
        ConfigValidationItem(level: .error, path: path, message: message)
    }
}

private extension RuleMatch {
    var isEmpty: Bool {
        app == nil &&
            appRegex == nil &&
            title == nil &&
            titleRegex == nil &&
            role == nil &&
            subrole == nil &&
            display == nil &&
            desktop == nil &&
            stage == nil &&
            isFloating == nil
    }
}

private extension RuleAction {
    var hasLayoutEffect: Bool {
        assignDesktop != nil ||
            assignDisplay != nil ||
            assignStage != nil ||
            floating != nil ||
            layout != nil ||
            gapOverride != nil ||
            scratchpad != nil
    }
}
