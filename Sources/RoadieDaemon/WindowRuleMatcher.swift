import Foundation
import RoadieAX
import RoadieCore

public struct WindowRuleMatchContext: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var display: String?
    public var desktop: String?
    public var stage: String?
    public var isFloating: Bool?

    public init(
        role: String? = nil,
        subrole: String? = nil,
        display: String? = nil,
        desktop: String? = nil,
        stage: String? = nil,
        isFloating: Bool? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.display = display
        self.desktop = desktop
        self.stage = stage
        self.isFloating = isFloating
    }
}

public enum WindowRuleMatcher {
    public static func matches(
        rule: WindowRule,
        window: WindowSnapshot,
        context: WindowRuleMatchContext = WindowRuleMatchContext()
    ) -> Bool {
        guard rule.enabled else { return false }

        return exact(rule.match.app, window.appName) &&
            regex(rule.match.appRegex, candidates: [window.appName, window.bundleID]) &&
            exact(rule.match.title, window.title) &&
            regex(rule.match.titleRegex, candidates: [window.title]) &&
            exact(rule.match.role, context.role) &&
            exact(rule.match.subrole, context.subrole) &&
            exact(rule.match.display, context.display) &&
            exact(rule.match.desktop, context.desktop) &&
            exact(rule.match.stage, context.stage) &&
            optionalEquals(rule.match.isFloating, context.isFloating)
    }

    public static func firstMatch(
        rules: [WindowRule],
        window: WindowSnapshot,
        context: WindowRuleMatchContext = WindowRuleMatchContext()
    ) -> WindowRule? {
        let sorted = rules
            .filter(\.enabled)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.id < rhs.id
                }
                return lhs.priority > rhs.priority
            }
        return firstMatch(sortedRules: sorted, window: window, context: context)
    }

    /// Variante hot-path : prend des regles deja filtrees+triees une seule fois en amont
    /// pour eviter O(n_windows * n_rules log n_rules) quand on classe une vague de fenetres.
    /// L'appelant garantit que `sortedRules` ne contient que les regles enabled, triees par
    /// (priority desc, id asc).
    public static func firstMatch(
        sortedRules: [WindowRule],
        window: WindowSnapshot,
        context: WindowRuleMatchContext = WindowRuleMatchContext()
    ) -> WindowRule? {
        sortedRules.first { matches(rule: $0, window: window, context: context) }
    }

    private static func exact(_ expected: String?, _ actual: String?) -> Bool {
        guard let expected else { return true }
        return actual == expected
    }

    /// Cache des NSRegularExpression compilees, partage entre tous les matchers.
    /// La compilation est lente (microsecs) et la regex peut etre evaluee 10x par tick
    /// par fenetre par regle. Un verrou explicite evite les deadlocks observes avec
    /// DispatchQueue.sync + barrier async sous Swift Testing parallele.
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    private static func compiledRegex(_ pattern: String) -> NSRegularExpression? {
        regexCacheLock.lock()
        if let cached = regexCache[pattern] {
            regexCacheLock.unlock()
            return cached
        }
        regexCacheLock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }

        regexCacheLock.lock()
        let result = regexCache[pattern] ?? compiled
        regexCache[pattern] = result
        regexCacheLock.unlock()
        return result
    }

    private static func regex(_ pattern: String?, candidates: [String]) -> Bool {
        guard let pattern else { return true }
        guard let expression = compiledRegex(pattern) else { return false }
        return candidates.contains { candidate in
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            return expression.firstMatch(in: candidate, range: range) != nil
        }
    }

    private static func optionalEquals<T: Equatable>(_ expected: T?, _ actual: T?) -> Bool {
        guard let expected else { return true }
        return actual == expected
    }
}
