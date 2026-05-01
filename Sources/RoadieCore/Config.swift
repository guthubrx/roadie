import Foundation
import TOMLKit

public struct Config: Codable, Sendable {
    public var daemon: DaemonConfig
    public var tiling: TilingConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var multiDesktop: MultiDesktopConfig
    public var desktops: [DesktopRule]

    public init(daemon: DaemonConfig = .init(),
                tiling: TilingConfig = .init(),
                stageManager: StageManagerConfig = .init(),
                exclusions: ExclusionsConfig = .init(),
                multiDesktop: MultiDesktopConfig = .init(),
                desktops: [DesktopRule] = []) {
        self.daemon = daemon
        self.tiling = tiling
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.multiDesktop = multiDesktop
        self.desktops = desktops
    }

    enum CodingKeys: String, CodingKey {
        case daemon
        case tiling
        case stageManager = "stage_manager"
        case exclusions
        case multiDesktop = "multi_desktop"
        case desktops
    }

    /// Decode tolérant : toute section absente du TOML utilisateur retombe sur les
    /// valeurs par défaut (= comportement V1 strict si l'utilisateur n'a pas migré
    /// sa config). Codable synthesised throw "keyNotFound" sans cet override, ce
    /// qui casserait toute config V1 existante au boot V2.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.daemon = try c.decodeIfPresent(DaemonConfig.self, forKey: .daemon) ?? .init()
        self.tiling = try c.decodeIfPresent(TilingConfig.self, forKey: .tiling) ?? .init()
        self.stageManager = try c.decodeIfPresent(StageManagerConfig.self, forKey: .stageManager) ?? .init()
        self.exclusions = try c.decodeIfPresent(ExclusionsConfig.self, forKey: .exclusions) ?? .init()
        self.multiDesktop = try c.decodeIfPresent(MultiDesktopConfig.self, forKey: .multiDesktop) ?? .init()
        self.desktops = try c.decodeIfPresent([DesktopRule].self, forKey: .desktops) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(daemon, forKey: .daemon)
        try c.encode(tiling, forKey: .tiling)
        try c.encode(stageManager, forKey: .stageManager)
        try c.encode(exclusions, forKey: .exclusions)
        try c.encode(multiDesktop, forKey: .multiDesktop)
        try c.encode(desktops, forKey: .desktops)
    }

    /// Validation des règles desktop (FR-018) : chaque DesktopRule DOIT avoir
    /// au moins un de match_index/match_label, jamais les deux. Throw si la config est mal formée.
    public func validateDesktopRules() throws {
        for (idx, rule) in desktops.enumerated() {
            try rule.validate(positionForError: idx)
        }
    }
}

/// Section `[multi_desktop]` de `roadies.toml`. Désactivé par défaut (FR-020 compat V1).
public struct MultiDesktopConfig: Codable, Sendable {
    public var enabled: Bool
    public var backAndForth: Bool

    public init(enabled: Bool = false, backAndForth: Bool = true) {
        self.enabled = enabled
        self.backAndForth = backAndForth
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case backAndForth = "back_and_forth"
    }
}

/// Section `[[desktops]]` répétable : règles statiques par desktop (FR-018).
public struct DesktopRule: Codable, Sendable {
    public var matchIndex: Int?
    public var matchLabel: String?
    public var defaultStrategy: TilerStrategy?
    public var gapsOuter: Int?
    public var gapsOuterTop: Int?
    public var gapsOuterBottom: Int?
    public var gapsOuterLeft: Int?
    public var gapsOuterRight: Int?
    public var gapsInner: Int?
    public var defaultStage: String?

    public init(matchIndex: Int? = nil, matchLabel: String? = nil,
                defaultStrategy: TilerStrategy? = nil,
                gapsOuter: Int? = nil,
                gapsOuterTop: Int? = nil, gapsOuterBottom: Int? = nil,
                gapsOuterLeft: Int? = nil, gapsOuterRight: Int? = nil,
                gapsInner: Int? = nil,
                defaultStage: String? = nil) {
        self.matchIndex = matchIndex
        self.matchLabel = matchLabel
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
        self.gapsOuterRight = gapsOuterRight
        self.gapsInner = gapsInner
        self.defaultStage = defaultStage
    }

    enum CodingKeys: String, CodingKey {
        case matchIndex = "match_index"
        case matchLabel = "match_label"
        case defaultStrategy = "default_strategy"
        case gapsOuter = "gaps_outer"
        case gapsOuterTop = "gaps_outer_top"
        case gapsOuterBottom = "gaps_outer_bottom"
        case gapsOuterLeft = "gaps_outer_left"
        case gapsOuterRight = "gaps_outer_right"
        case gapsInner = "gaps_inner"
        case defaultStage = "default_stage"
    }

    public func validate(positionForError idx: Int) throws {
        let hasIdx = matchIndex != nil
        let hasLbl = matchLabel != nil
        if !hasIdx && !hasLbl {
            throw DesktopRuleError.missingMatcher(rulePosition: idx)
        }
        if hasIdx && hasLbl {
            throw DesktopRuleError.bothMatchers(rulePosition: idx)
        }
    }

    /// Construit un GapsOverride à partir des champs gaps_* de la règle.
    /// Tous les champs nil → retourne nil (pas d'override actif).
    public func gapsOverride() -> GapsOverride? {
        let top = gapsOuterTop ?? gapsOuter
        let bottom = gapsOuterBottom ?? gapsOuter
        let left = gapsOuterLeft ?? gapsOuter
        let right = gapsOuterRight ?? gapsOuter
        if top == nil && bottom == nil && left == nil && right == nil {
            return nil
        }
        return GapsOverride(top: top, bottom: bottom, left: left, right: right)
    }
}

public enum DesktopRuleError: Error, CustomStringConvertible {
    case missingMatcher(rulePosition: Int)
    case bothMatchers(rulePosition: Int)

    public var description: String {
        switch self {
        case .missingMatcher(let i):
            return "[[desktops]] rule #\(i): need at least match_index or match_label"
        case .bothMatchers(let i):
            return "[[desktops]] rule #\(i): cannot have both match_index and match_label"
        }
    }
}

public struct DaemonConfig: Codable, Sendable {
    public var logLevel: String
    public var socketPath: String

    public init(logLevel: String = "info",
                socketPath: String = "~/.roadies/daemon.sock") {
        self.logLevel = logLevel
        self.socketPath = socketPath
    }

    enum CodingKeys: String, CodingKey {
        case logLevel = "log_level"
        case socketPath = "socket_path"
    }
}

public struct TilingConfig: Codable, Sendable {
    public var defaultStrategy: TilerStrategy
    /// Marge externe uniforme appliquée aux 4 côtés. Sert de défaut quand
    /// `gaps_outer_top/bottom/left/right` n'est pas spécifié pour ce côté.
    public var gapsOuter: Int
    /// Override par côté : si non-nil, prend le pas sur `gapsOuter` pour ce côté.
    /// Permet par exemple `gaps_outer = 8` + `gaps_outer_bottom = 30` pour un dock.
    public var gapsOuterTop: Int?
    public var gapsOuterBottom: Int?
    public var gapsOuterLeft: Int?
    public var gapsOuterRight: Int?
    public var gapsInner: Int
    public var masterRatio: Double

    /// Marges externes effectives (avec fallback sur gapsOuter pour les côtés non spécifiés).
    public var effectiveOuterGaps: OuterGaps {
        OuterGaps(top: gapsOuterTop ?? gapsOuter,
                  bottom: gapsOuterBottom ?? gapsOuter,
                  left: gapsOuterLeft ?? gapsOuter,
                  right: gapsOuterRight ?? gapsOuter)
    }

    public init(defaultStrategy: TilerStrategy = .bsp,
                gapsOuter: Int = 8,
                gapsOuterTop: Int? = nil,
                gapsOuterBottom: Int? = nil,
                gapsOuterLeft: Int? = nil,
                gapsOuterRight: Int? = nil,
                gapsInner: Int = 4,
                masterRatio: Double = 0.6) {
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
        self.gapsOuterRight = gapsOuterRight
        self.gapsInner = gapsInner
        self.masterRatio = masterRatio
    }

    enum CodingKeys: String, CodingKey {
        case defaultStrategy = "default_strategy"
        case gapsOuter = "gaps_outer"
        case gapsOuterTop = "gaps_outer_top"
        case gapsOuterBottom = "gaps_outer_bottom"
        case gapsOuterLeft = "gaps_outer_left"
        case gapsOuterRight = "gaps_outer_right"
        case gapsInner = "gaps_inner"
        case masterRatio = "master_ratio"
    }
}

/// Marges externes asymétriques appliquées au workArea avant le calcul du tile.
public struct OuterGaps: Sendable, Equatable {
    public let top: Int
    public let bottom: Int
    public let left: Int
    public let right: Int

    public init(top: Int, bottom: Int, left: Int, right: Int) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static let zero = OuterGaps(top: 0, bottom: 0, left: 0, right: 0)
    public static func uniform(_ value: Int) -> OuterGaps {
        OuterGaps(top: value, bottom: value, left: value, right: value)
    }
}

public struct StageManagerConfig: Codable, Sendable {
    public var enabled: Bool
    public var hideStrategy: HideStrategy
    public var defaultStage: String
    public var workspaces: [StageDef]

    public init(enabled: Bool = false,
                hideStrategy: HideStrategy = .corner,
                defaultStage: String = "main",
                workspaces: [StageDef] = []) {
        self.enabled = enabled
        self.hideStrategy = hideStrategy
        self.defaultStage = defaultStage
        self.workspaces = workspaces
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case hideStrategy = "hide_strategy"
        case defaultStage = "default_stage"
        case workspaces
    }
}

public struct StageDef: Codable, Sendable {
    public var id: String
    public var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct ExclusionsConfig: Codable, Sendable {
    public var floatingBundles: [String]

    public init(floatingBundles: [String] = []) {
        self.floatingBundles = floatingBundles
    }

    enum CodingKeys: String, CodingKey {
        case floatingBundles = "floating_bundles"
    }
}

public enum ConfigLoader {
    public static func defaultConfigPath() -> String {
        (NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath as String)
    }

    /// Charge la config depuis le path donné. Si absent, retourne les défauts.
    /// Throw seulement si le TOML est invalide (format error).
    public static func load(from path: String? = nil) throws -> Config {
        let resolved = path ?? defaultConfigPath()
        guard FileManager.default.fileExists(atPath: resolved) else {
            return Config()
        }
        let data = try String(contentsOfFile: resolved, encoding: .utf8)
        return try TOMLDecoder().decode(Config.self, from: data)
    }

    public static func save(_ config: Config, to path: String? = nil) throws {
        let resolved = path ?? defaultConfigPath()
        let dir = (resolved as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let toml = try TOMLEncoder().encode(config)
        try toml.write(toFile: resolved, atomically: true, encoding: .utf8)
    }
}
