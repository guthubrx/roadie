import Foundation
import TOMLKit

public struct RoadieConfig: Equatable, Codable, Sendable {
    public var tiling: TilingConfig
    public var desktops: DesktopsConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var fx: EffectsConfig

    public init(
        tiling: TilingConfig = TilingConfig(),
        desktops: DesktopsConfig = DesktopsConfig(),
        stageManager: StageManagerConfig = StageManagerConfig(),
        exclusions: ExclusionsConfig = ExclusionsConfig(),
        fx: EffectsConfig = EffectsConfig()
    ) {
        self.tiling = tiling
        self.desktops = desktops
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.fx = fx
    }

    enum CodingKeys: String, CodingKey {
        case tiling
        case desktops
        case stageManager = "stage_manager"
        case exclusions
        case fx
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tiling = try c.decodeIfPresent(TilingConfig.self, forKey: .tiling) ?? TilingConfig()
        self.desktops = try c.decodeIfPresent(DesktopsConfig.self, forKey: .desktops) ?? DesktopsConfig()
        self.stageManager = try c.decodeIfPresent(StageManagerConfig.self, forKey: .stageManager) ?? StageManagerConfig()
        self.exclusions = try c.decodeIfPresent(ExclusionsConfig.self, forKey: .exclusions) ?? ExclusionsConfig()
        self.fx = try c.decodeIfPresent(EffectsConfig.self, forKey: .fx) ?? EffectsConfig()
    }
}

public struct TilingConfig: Equatable, Codable, Sendable {
    public var defaultStrategy: WindowManagementMode
    public var splitPolicy: String
    public var gapsOuter: Double
    public var gapsOuterTop: Double?
    public var gapsOuterRight: Double?
    public var gapsOuterBottom: Double?
    public var gapsOuterLeft: Double?
    public var gapsInner: Double
    public var masterRatio: Double
    public var smartGapsSolo: Bool
    public var smartGapsSoloSides: [GapSide]

    public init(
        defaultStrategy: WindowManagementMode = .bsp,
        splitPolicy: String = "largest_dim",
        gapsOuter: Double = 8,
        gapsOuterTop: Double? = nil,
        gapsOuterRight: Double? = nil,
        gapsOuterBottom: Double? = nil,
        gapsOuterLeft: Double? = nil,
        gapsInner: Double = 4,
        masterRatio: Double = 0.6,
        smartGapsSolo: Bool = false,
        smartGapsSoloSides: [GapSide] = GapSide.allCases
    ) {
        self.defaultStrategy = defaultStrategy
        self.splitPolicy = splitPolicy
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterRight = gapsOuterRight
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
        self.gapsInner = gapsInner
        self.masterRatio = masterRatio
        self.smartGapsSolo = smartGapsSolo
        self.smartGapsSoloSides = smartGapsSoloSides
    }

    enum CodingKeys: String, CodingKey {
        case defaultStrategy = "default_strategy"
        case splitPolicy = "split_policy"
        case gapsOuter = "gaps_outer"
        case gapsOuterTop = "gaps_outer_top"
        case gapsOuterRight = "gaps_outer_right"
        case gapsOuterBottom = "gaps_outer_bottom"
        case gapsOuterLeft = "gaps_outer_left"
        case gapsInner = "gaps_inner"
        case masterRatio = "master_ratio"
        case smartGapsSolo = "smart_gaps_solo"
        case smartGapsSoloSides = "smart_gaps_solo_sides"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStrategy = try c.decodeIfPresent(String.self, forKey: .defaultStrategy) ?? "bsp"
        self.defaultStrategy = WindowManagementMode(tomlValue: rawStrategy) ?? .bsp
        self.splitPolicy = try c.decodeIfPresent(String.self, forKey: .splitPolicy) ?? "largest_dim"
        self.gapsOuter = try c.decodeFlexibleDouble(forKey: .gapsOuter) ?? 8
        self.gapsOuterTop = try c.decodeFlexibleDouble(forKey: .gapsOuterTop)
        self.gapsOuterRight = try c.decodeFlexibleDouble(forKey: .gapsOuterRight)
        self.gapsOuterBottom = try c.decodeFlexibleDouble(forKey: .gapsOuterBottom)
        self.gapsOuterLeft = try c.decodeFlexibleDouble(forKey: .gapsOuterLeft)
        self.gapsInner = try c.decodeFlexibleDouble(forKey: .gapsInner) ?? 4
        self.masterRatio = try c.decodeFlexibleDouble(forKey: .masterRatio) ?? 0.6
        self.smartGapsSolo = try c.decodeIfPresent(Bool.self, forKey: .smartGapsSolo) ?? false
        let sides = try c.decodeIfPresent([String].self, forKey: .smartGapsSoloSides) ?? GapSide.allCases.map(\.rawValue)
        self.smartGapsSoloSides = sides.compactMap(GapSide.init(rawValue:))
    }
}

public enum GapSide: String, Codable, Sendable, CaseIterable {
    case top
    case right
    case bottom
    case left
}

public struct DesktopsConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var count: Int
    public var backAndForth: Bool
    public var mode: String

    public init(enabled: Bool = true, count: Int = 10, backAndForth: Bool = true, mode: String = "global") {
        self.enabled = enabled
        self.count = min(16, max(1, count))
        self.backAndForth = backAndForth
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case count
        case backAndForth = "back_and_forth"
        case mode
    }
}

public struct StageManagerConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var hideStrategy: String
    public var defaultStage: String
    public var workspaces: [StageDefinition]

    public init(enabled: Bool = true, hideStrategy: String = "corner", defaultStage: String = "1", workspaces: [StageDefinition] = []) {
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

public struct StageDefinition: Equatable, Codable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct ExclusionsConfig: Equatable, Codable, Sendable {
    public var floatingBundles: [String]

    public init(floatingBundles: [String] = []) {
        self.floatingBundles = floatingBundles
    }

    enum CodingKeys: String, CodingKey {
        case floatingBundles = "floating_bundles"
    }
}

public struct EffectsConfig: Equatable, Codable, Sendable {
    public var borders: BorderConfig

    public init(borders: BorderConfig = BorderConfig()) {
        self.borders = borders
    }
}

public struct BorderConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var thickness: Double
    public var cornerRadius: Double
    public var activeColor: String
    public var inactiveColor: String
    public var pulseOnFocus: Bool
    public var stageOverrides: [BorderStageOverride]

    public init(
        enabled: Bool = false,
        thickness: Double = 2,
        cornerRadius: Double = 10,
        activeColor: String = "#7AA2F7",
        inactiveColor: String = "#414868",
        pulseOnFocus: Bool = false,
        stageOverrides: [BorderStageOverride] = []
    ) {
        self.enabled = enabled
        self.thickness = thickness
        self.cornerRadius = cornerRadius
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.pulseOnFocus = pulseOnFocus
        self.stageOverrides = stageOverrides
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case thickness
        case cornerRadius = "corner_radius"
        case activeColor = "active_color"
        case inactiveColor = "inactive_color"
        case pulseOnFocus = "pulse_on_focus"
        case stageOverrides = "stage_overrides"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.thickness = try c.decodeFlexibleDouble(forKey: .thickness) ?? 2
        self.cornerRadius = try c.decodeFlexibleDouble(forKey: .cornerRadius) ?? 10
        self.activeColor = try c.decodeIfPresent(String.self, forKey: .activeColor) ?? "#7AA2F7"
        self.inactiveColor = try c.decodeIfPresent(String.self, forKey: .inactiveColor) ?? "#414868"
        self.pulseOnFocus = try c.decodeIfPresent(Bool.self, forKey: .pulseOnFocus) ?? false
        self.stageOverrides = try c.decodeIfPresent([BorderStageOverride].self, forKey: .stageOverrides) ?? []
    }
}

public struct BorderStageOverride: Equatable, Codable, Sendable {
    public var stageID: String
    public var activeColor: String?

    public init(stageID: String, activeColor: String? = nil) {
        self.stageID = stageID
        self.activeColor = activeColor
    }

    enum CodingKeys: String, CodingKey {
        case stageID = "stage_id"
        case activeColor = "active_color"
    }
}

public enum RoadieConfigLoader {
    public static func defaultConfigPath() -> String {
        (NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath as String)
    }

    public static func load(from path: String? = nil) throws -> RoadieConfig {
        let resolved = path ?? defaultConfigPath()
        guard FileManager.default.fileExists(atPath: resolved) else {
            return RoadieConfig()
        }
        let raw = try String(contentsOfFile: resolved, encoding: .utf8)
        return try TOMLDecoder().decode(RoadieConfig.self, from: raw)
    }
}

private extension WindowManagementMode {
    init?(tomlValue: String) {
        guard let mode = WindowManagementMode(roadieValue: tomlValue) else {
            return nil
        }
        self = mode
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
