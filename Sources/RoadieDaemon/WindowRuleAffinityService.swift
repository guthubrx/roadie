import Foundation
import RoadieAX
import RoadieCore

public enum WindowRuleAffinityKind: String, Equatable, Codable, Sendable {
    case app
    case appTitle = "app_title"
    case appRole = "app_role"
}

public struct WindowRuleAffinityResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool
    public var path: String

    public init(message: String, changed: Bool, path: String) {
        self.message = message
        self.changed = changed
        self.path = path
    }
}

public final class WindowRuleAffinityService: @unchecked Sendable {
    private let path: String
    private let eventLog: EventLog

    public init(
        path: String = RoadieConfigLoader.generatedRulesPath(),
        eventLog: EventLog = EventLog()
    ) {
        self.path = path
        self.eventLog = eventLog
    }

    public func saveAffinity(
        kind: WindowRuleAffinityKind,
        window: WindowSnapshot,
        scope: StageScope,
        display: DisplaySnapshot
    ) -> WindowRuleAffinityResult {
        do {
            var rules = try loadRules()
            let rule = affinityRule(kind: kind, window: window, scope: scope, display: display)
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
            try saveRules(rules)
            eventLog.append(RoadieEvent(
                type: "rule.affinity_saved",
                scope: scope,
                details: [
                    "ruleID": rule.id,
                    "kind": kind.rawValue,
                    "windowID": String(window.id.rawValue),
                    "app": window.appName,
                    "displayID": scope.displayID.rawValue,
                    "desktopID": String(scope.desktopID.rawValue),
                    "stageID": scope.stageID.rawValue,
                    "path": path
                ]
            ))
            return WindowRuleAffinityResult(message: "affinite creee: \(rule.id)", changed: true, path: path)
        } catch {
            return WindowRuleAffinityResult(message: "affinite non creee: \(error)", changed: false, path: path)
        }
    }

    public func removeAppAffinity(window: WindowSnapshot, scope: StageScope?) -> WindowRuleAffinityResult {
        do {
            let rules = try loadRules()
            let filtered = rules.filter { rule in
                !(rule.id.hasPrefix("affinity-") && rule.match.app == window.appName)
            }
            guard filtered.count != rules.count else {
                return WindowRuleAffinityResult(message: "aucune affinite pour \(window.appName)", changed: false, path: path)
            }
            try saveRules(filtered)
            eventLog.append(RoadieEvent(
                type: "rule.affinity_removed",
                scope: scope,
                details: [
                    "app": window.appName,
                    "removed": String(rules.count - filtered.count),
                    "path": path
                ]
            ))
            return WindowRuleAffinityResult(message: "affinite retiree: \(window.appName)", changed: true, path: path)
        } catch {
            return WindowRuleAffinityResult(message: "affinite non retiree: \(error)", changed: false, path: path)
        }
    }

    private func affinityRule(
        kind: WindowRuleAffinityKind,
        window: WindowSnapshot,
        scope: StageScope,
        display: DisplaySnapshot
    ) -> WindowRule {
        var match = RuleMatch(app: window.appName)
        switch kind {
        case .app:
            break
        case .appTitle:
            match.title = window.title
        case .appRole:
            match.role = window.role
            match.subrole = window.subrole
        }
        return WindowRule(
            id: ruleID(kind: kind, window: window),
            enabled: true,
            priority: 9_000,
            stopProcessing: true,
            match: match,
            action: RuleAction(
                assignDesktop: String(scope.desktopID.rawValue),
                assignDisplay: display.name.isEmpty ? display.id.rawValue : display.name,
                assignStage: scope.stageID.rawValue,
                follow: false
            )
        )
    }

    private func ruleID(kind: WindowRuleAffinityKind, window: WindowSnapshot) -> String {
        var parts = ["affinity", kind.rawValue, slug(window.bundleID.isEmpty ? window.appName : window.bundleID)]
        switch kind {
        case .app:
            break
        case .appTitle:
            parts.append(stableHash(window.title))
        case .appRole:
            parts.append(slug([window.role, window.subrole].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")))
        }
        return parts.joined(separator: "-")
    }

    private func loadRules() throws -> [WindowRule] {
        try RoadieConfigLoader.loadRulesFile(from: path)
    }

    private func saveRules(_ rules: [WindowRule]) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try render(rules).write(to: url, atomically: true, encoding: .utf8)
    }

    private func render(_ rules: [WindowRule]) -> String {
        var lines: [String] = [
            "# Roadie generated rules.",
            "# Edit by hand only if you accept that the titlebar menu may overwrite matching affinity-* rules.",
            ""
        ]
        for rule in rules.sorted(by: { $0.id < $1.id }) {
            lines.append("[[rules]]")
            lines.append("id = \"\(toml(rule.id))\"")
            lines.append("enabled = \(rule.enabled ? "true" : "false")")
            lines.append("priority = \(rule.priority)")
            lines.append("stop_processing = \(rule.stopProcessing ? "true" : "false")")
            lines.append("")
            lines.append("[rules.match]")
            append("app", rule.match.app, to: &lines)
            append("app_regex", rule.match.appRegex, to: &lines)
            append("title", rule.match.title, to: &lines)
            append("title_regex", rule.match.titleRegex, to: &lines)
            append("role", rule.match.role, to: &lines)
            append("subrole", rule.match.subrole, to: &lines)
            append("display", rule.match.display, to: &lines)
            append("desktop", rule.match.desktop, to: &lines)
            append("stage", rule.match.stage, to: &lines)
            if let isFloating = rule.match.isFloating {
                lines.append("is_floating = \(isFloating ? "true" : "false")")
            }
            lines.append("")
            lines.append("[rules.action]")
            append("assign_desktop", rule.action.assignDesktop, to: &lines)
            append("assign_display", rule.action.assignDisplay, to: &lines)
            append("assign_stage", rule.action.assignStage, to: &lines)
            if let follow = rule.action.follow {
                lines.append("follow = \(follow ? "true" : "false")")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func append(_ key: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(key) = \"\(toml(value))\"")
    }

    private func toml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        let joined = lower.unicodeScalars
            .map { scalar in CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-" }
            .joined()
        let compact = joined
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "window" : compact
    }

    private func stableHash(_ value: String) -> String {
        let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
