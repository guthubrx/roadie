import Foundation
import os
import RoadieAX
import RoadieCore

/// Règle ponctuelle éphémère en mémoire (consommation unique + TTL) pour placer silencieusement
/// une fenêtre dès sa création (ex. lancement Chrome/Playwright dans une stage inactive sans flash
/// ni vol de focus). Zéro écriture sur `roadies.toml`, zéro timer.
public struct OneShotWindowRule: Codable, Equatable, Sendable {
    public let id: String
    public let app: String?
    public let bundleID: String?
    public let titlePrefix: String?
    public let pid: Int32?
    public let display: String?
    public let desktop: String?
    public let stage: String?
    public let stagePosition: Int?
    public let follow: Bool
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        id: String = "once-\(UUID().uuidString.prefix(8).lowercased())",
        app: String? = nil,
        bundleID: String? = nil,
        titlePrefix: String? = nil,
        pid: Int32? = nil,
        display: String? = nil,
        desktop: String? = nil,
        stage: String? = nil,
        stagePosition: Int? = nil,
        follow: Bool = false,
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval = 30
    ) {
        self.id = id
        self.app = Self.cleaned(app)
        self.bundleID = Self.cleaned(bundleID)
        self.titlePrefix = Self.cleaned(titlePrefix)
        self.pid = pid.flatMap { $0 > 0 ? $0 : nil }
        self.display = Self.cleaned(display)
        self.desktop = Self.cleaned(desktop)
        self.stage = Self.cleaned(stage)
        self.stagePosition = stagePosition.flatMap { $0 > 0 ? $0 : nil }
        self.follow = follow
        self.createdAt = createdAt
        let clampedTTL = min(600, max(1, ttlSeconds))
        self.expiresAt = createdAt.addingTimeInterval(clampedTTL)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Au moins un critère de correspondance et une destination doivent être présents.
    public var isValid: Bool {
        let hasMatcher = app != nil || bundleID != nil || titlePrefix != nil || pid != nil
        let hasDestination = display != nil || desktop != nil || stage != nil || stagePosition != nil
        return hasMatcher && hasDestination
    }

    public func isExpired(at now: Date) -> Bool {
        expiresAt <= now
    }

    /// Vérifie si `window` correspond à tous les filtres actifs de la règle. O(1).
    public func matches(_ window: WindowSnapshot) -> Bool {
        guard isValid else { return false }
        if let pid, window.pid != pid {
            return false
        }
        if let app {
            let appMatches = window.appName.caseInsensitiveCompare(app) == .orderedSame
                || window.bundleID.caseInsensitiveCompare(app) == .orderedSame
            if !appMatches { return false }
        }
        if let bundleID, window.bundleID.caseInsensitiveCompare(bundleID) != .orderedSame {
            return false
        }
        if let titlePrefix {
            let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedPrefix = titlePrefix.lowercased()
            if !normalizedTitle.hasPrefix(normalizedPrefix) {
                return false
            }
        }
        return true
    }
}

/// Registre thread-safe des règles ponctuelles (`roadie rules add-once`) vivant dans le daemon.
/// Purgé paresseusement à chaque lecture/ajout/correspondance (0 timer en arrière-plan).
public final class OneShotWindowRulesStore: @unchecked Sendable {
    public static let shared = OneShotWindowRulesStore()

    private let state = OSAllocatedUnfairLock<[OneShotWindowRule]>(initialState: [])

    public init() {}

    @discardableResult
    public func add(_ rule: OneShotWindowRule, now: Date = Date()) -> Bool {
        guard rule.isValid, !rule.isExpired(at: now) else { return false }
        state.withLock { rules in
            rules.removeAll { $0.isExpired(at: now) || $0.id == rule.id }
            rules.append(rule)
        }
        return true
    }

    public func list(now: Date = Date()) -> [OneShotWindowRule] {
        state.withLock { rules in
            rules.removeAll { $0.isExpired(at: now) }
            return rules
        }
    }

    public var hasActiveRules: Bool {
        !list().isEmpty
    }

    @discardableResult
    public func clear(id: String? = nil) -> Int {
        state.withLock { rules in
            let before = rules.count
            if let id {
                rules.removeAll { $0.id == id }
            } else {
                rules.removeAll()
            }
            return before - rules.count
        }
    }

    /// Cherche la première règle ponctuelle active qui matche `window` sans encore la consommer
    /// (permet de différer si l'écran cible est momentanément indisponible).
    public func peekMatch(for window: WindowSnapshot, now: Date = Date()) -> OneShotWindowRule? {
        state.withLock { rules in
            rules.removeAll { $0.isExpired(at: now) }
            return rules.first { $0.matches(window) }
        }
    }

    /// Consomme atomiquement la règle `id` après application réussie.
    @discardableResult
    public func consume(id: String, now: Date = Date()) -> OneShotWindowRule? {
        state.withLock { rules in
            rules.removeAll { $0.isExpired(at: now) }
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return nil }
            return rules.remove(at: index)
        }
    }
}
