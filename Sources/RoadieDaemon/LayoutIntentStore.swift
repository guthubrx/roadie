import Foundation
import RoadieCore

public struct LayoutIntent: Equatable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case auto
        case command
    }

    public var scope: StageScope
    public var windowIDs: [WindowID]
    public var placements: [WindowID: Rect]
    public var createdAt: Date
    public var source: Source
    /// Fenêtre zoomée par une commande plein écran Roadie (SPEC-016 FR-001, FR-012).
    /// Posé par `toggleFullscreen`, lu par le moteur de disposition. nil = pas de zoom.
    /// L'encodage synthétisé utilise `encodeIfPresent` : la clé n'est écrite que si elle est posée.
    public var zoomedWindowID: WindowID?
    /// Début d'absence du display de l'intent ; l'intent est purgé après 10 min (SPEC-016 T015).
    public var displayMissingSince: Date?

    public init(
        scope: StageScope,
        windowIDs: [WindowID],
        placements: [WindowID: Rect],
        createdAt: Date = Date(),
        source: Source = .auto,
        zoomedWindowID: WindowID? = nil
    ) {
        self.scope = scope
        self.windowIDs = windowIDs
        self.placements = placements
        self.createdAt = createdAt
        self.source = source
        self.zoomedWindowID = zoomedWindowID
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case windowIDs
        case placements
        case createdAt
        case source
        case zoomedWindowID
        case displayMissingSince
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scope = try container.decode(StageScope.self, forKey: .scope)
        self.windowIDs = try container.decode([WindowID].self, forKey: .windowIDs)
        self.placements = try container.decode([WindowID: Rect].self, forKey: .placements)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.source = (try container.decodeIfPresent(LayoutIntent.Source.self, forKey: .source)) ?? .auto
        self.zoomedWindowID = try container.decodeIfPresent(WindowID.self, forKey: .zoomedWindowID)
        self.displayMissingSince = try container.decodeIfPresent(Date.self, forKey: .displayMissingSince)
    }
}

public struct LayoutIntentStore: Sendable {
    private let url: URL

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func defaultPath() -> String {
        if TestEnvironment.isRunningTests {
            return "\(NSTemporaryDirectory())roadie-test-layout-intents-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).json"
        }
        return "~/.roadies/layout-intents.json"
    }

    public func intent(for scope: StageScope) -> LayoutIntent? {
        load()[scope.description]
    }

    public func save(_ intent: LayoutIntent) {
        mutate { $0[intent.scope.description] = intent }
    }

    public func remove(scope: StageScope) {
        mutate { $0.removeValue(forKey: scope.description) }
    }

    /// Purge les intents dont le display est absent depuis plus de `missingGrace` (10 min par
    /// défaut, un débranchement bref ne perd pas la disposition). Pré-contrôle sans verrou :
    /// au repos, ni verrou ni écriture. O(n), n = nombre d'intents.
    public func prune(
        keepingDisplayIDs displayIDs: Set<DisplayID>,
        missingGrace: TimeInterval = 600,
        now: Date = Date()
    ) {
        let current = load()
        guard Self.pruned(current, keepingDisplayIDs: displayIDs, missingGrace: missingGrace, now: now) != current else {
            return
        }
        mutate { intents in
            intents = Self.pruned(intents, keepingDisplayIDs: displayIDs, missingGrace: missingGrace, now: now)
        }
    }

    /// Modifie les intents en une transaction lecture-modification-écriture exclusive (SPEC-016 FR-013).
    /// `body` ne doit pas rappeler ce store (verrou non réentrant).
    @discardableResult
    public func mutate<R>(_ body: (inout [String: LayoutIntent]) throws -> R) rethrows -> R {
        try JSONPersistence.mutate([String: LayoutIntent].self, at: url, default: [:], label: "layout intent", body)
    }

    private func load() -> [String: LayoutIntent] {
        JSONPersistence.load([String: LayoutIntent].self, from: url, default: [:])
    }

    private static func pruned(
        _ intents: [String: LayoutIntent],
        keepingDisplayIDs displayIDs: Set<DisplayID>,
        missingGrace: TimeInterval,
        now: Date
    ) -> [String: LayoutIntent] {
        var result: [String: LayoutIntent] = [:]
        for (key, var intent) in intents {
            if displayIDs.contains(intent.scope.displayID) {
                intent.displayMissingSince = nil
            } else if let missingSince = intent.displayMissingSince {
                if now.timeIntervalSince(missingSince) >= missingGrace { continue }
            } else {
                intent.displayMissingSince = now
            }
            result[key] = intent
        }
        return result
    }
}
