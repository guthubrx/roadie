import Foundation
import RoadieCore

public struct Stage: Codable, Sendable {
    public let id: StageID
    public var displayName: String
    public var memberWindows: [StageMember]
    public var tilerStrategy: TilerStrategy
    public var lastActiveAt: Date
    /// SPEC-027 US3 — rang dans le navrail. Plus petit = affiché en premier.
    /// Default 0 pour rétrocompat ; le premier reorder pose un ordre custom
    /// (réécrit les order de toutes les stages du scope avec un pas de 10).
    public var order: Int

    public init(id: StageID, displayName: String,
                tilerStrategy: TilerStrategy = .bsp,
                memberWindows: [StageMember] = [],
                order: Int = 0) {
        self.id = id
        self.displayName = displayName
        self.tilerStrategy = tilerStrategy
        self.memberWindows = memberWindows
        self.lastActiveAt = Date()
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case memberWindows = "members"
        case tilerStrategy = "tiler_strategy"
        case lastActiveAt = "last_active_at"
        case order
    }

    /// Decode tolérant : `order` est optionnel pour rétrocompat avec les
    /// fichiers persistés pré-SPEC-027.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(StageID.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.memberWindows = try c.decodeIfPresent([StageMember].self, forKey: .memberWindows) ?? []
        self.tilerStrategy = try c.decodeIfPresent(TilerStrategy.self, forKey: .tilerStrategy) ?? .bsp
        self.lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? Date()
        self.order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

public struct StageMember: Codable, Sendable {
    public var cgWindowID: WindowID
    public let bundleID: String
    public var titleHint: String
    public var savedFrame: SavedRect?

    public init(cgWindowID: WindowID, bundleID: String,
                titleHint: String, savedFrame: SavedRect? = nil) {
        self.cgWindowID = cgWindowID
        self.bundleID = bundleID
        self.titleHint = titleHint
        self.savedFrame = savedFrame
    }

    enum CodingKeys: String, CodingKey {
        case cgWindowID = "cg_window_id"
        case bundleID = "bundle_id"
        case titleHint = "title_hint"
        case savedFrame = "saved_frame"
    }
}

/// Représentation Codable d'un CGRect (TOML ne sérialise pas CGRect nativement).
public struct SavedRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(_ rect: CGRect) {
        x = Double(rect.origin.x); y = Double(rect.origin.y)
        w = Double(rect.size.width); h = Double(rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - SPEC-025 T020 — Validation au load

extension Stage {
    /// Reset les `savedFrame` des members dont le centre n'est dans aucun
    /// display connu. Retourne le nombre de members invalidés. Appelé par
    /// `StageManager.loadFromDisk` (FR-001) pour empêcher la restauration
    /// aveugle de positions offscreen persistées (cause racine BUG-001).
    ///
    /// La frame `nil` après reset signifie "pas de frame mémorisée" — le
    /// tree calculera un slot fresh au prochain `applyLayout`.
    public mutating func validateMembers(againstDisplayFrames frames: [CGRect]) -> Int {
        var invalidated = 0
        for i in memberWindows.indices {
            guard let saved = memberWindows[i].savedFrame else { continue }
            let rect = saved.cgRect
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let isOnKnownDisplay = frames.contains { $0.contains(center) }
            if !isOnKnownDisplay {
                memberWindows[i].savedFrame = nil
                invalidated += 1
            }
        }
        return invalidated
    }
}
