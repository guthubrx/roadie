import Foundation
import TOMLKit

public struct Config: Codable, Sendable {
    public var daemon: DaemonConfig
    public var tiling: TilingConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var desktops: DesktopsConfig

    public init(daemon: DaemonConfig = .init(),
                tiling: TilingConfig = .init(),
                stageManager: StageManagerConfig = .init(),
                exclusions: ExclusionsConfig = .init(),
                desktops: DesktopsConfig = .init()) {
        self.daemon = daemon
        self.tiling = tiling
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.desktops = desktops
    }

    enum CodingKeys: String, CodingKey {
        case daemon
        case tiling
        case stageManager = "stage_manager"
        case exclusions
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
        self.desktops = try c.decodeIfPresent(DesktopsConfig.self, forKey: .desktops) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(daemon, forKey: .daemon)
        try c.encode(tiling, forKey: .tiling)
        try c.encode(stageManager, forKey: .stageManager)
        try c.encode(exclusions, forKey: .exclusions)
        try c.encode(desktops, forKey: .desktops)
    }
}

// MARK: - DesktopsConfig (SPEC-011)

/// Configuration de la feature multi-desktop virtuel (pivot AeroSpace).
/// Validation : count ∈ 1..16 (FR-001, FR-018).
public struct DesktopsConfig: Codable, Sendable {
    public var enabled: Bool
    public var count: Int
    public var defaultFocus: Int
    public var backAndForth: Bool
    public var offscreenX: Int
    public var offscreenY: Int

    public init(enabled: Bool = true,
                count: Int = 10,
                defaultFocus: Int = 1,
                backAndForth: Bool = true,
                offscreenX: Int = -30000,
                offscreenY: Int = -30000) {
        self.enabled = enabled
        self.count = count
        self.defaultFocus = defaultFocus
        self.backAndForth = backAndForth
        self.offscreenX = offscreenX
        self.offscreenY = offscreenY
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case count
        case defaultFocus = "default_focus"
        case backAndForth = "back_and_forth"
        case offscreenX = "offscreen_x"
        case offscreenY = "offscreen_y"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let rawCount = try c.decodeIfPresent(Int.self, forKey: .count) ?? 10
        guard (1...16).contains(rawCount) else {
            throw DecodingError.dataCorruptedError(
                forKey: .count, in: c,
                debugDescription: "desktops.count must be in 1..16, got \(rawCount)")
        }
        self.count = rawCount
        self.defaultFocus = try c.decodeIfPresent(Int.self, forKey: .defaultFocus) ?? 1
        self.backAndForth = try c.decodeIfPresent(Bool.self, forKey: .backAndForth) ?? true
        self.offscreenX = try c.decodeIfPresent(Int.self, forKey: .offscreenX) ?? -30000
        self.offscreenY = try c.decodeIfPresent(Int.self, forKey: .offscreenY) ?? -30000
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
