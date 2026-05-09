import Foundation
import TOMLKit

public struct RoadieConfig: Equatable, Codable, Sendable {
    public var tiling: TilingConfig
    public var desktops: DesktopsConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var fx: EffectsConfig
    public var focus: FocusConfig
    public var signals: SignalsConfig
    public var rules: [WindowRule]
    public var controlCenter: ControlCenterConfig
    public var configReload: ConfigReloadConfig
    public var restoreSafety: RestoreSafetyConfig
    public var transientWindows: TransientWindowsConfig
    public var layoutPersistence: LayoutPersistenceConfig
    public var widthAdjustment: WidthAdjustmentConfig
    public var performance: PerformanceConfig

    public init(
        tiling: TilingConfig = TilingConfig(),
        desktops: DesktopsConfig = DesktopsConfig(),
        stageManager: StageManagerConfig = StageManagerConfig(),
        exclusions: ExclusionsConfig = ExclusionsConfig(),
        fx: EffectsConfig = EffectsConfig(),
        focus: FocusConfig = FocusConfig(),
        signals: SignalsConfig = SignalsConfig(),
        rules: [WindowRule] = [],
        controlCenter: ControlCenterConfig = ControlCenterConfig(),
        configReload: ConfigReloadConfig = ConfigReloadConfig(),
        restoreSafety: RestoreSafetyConfig = RestoreSafetyConfig(),
        transientWindows: TransientWindowsConfig = TransientWindowsConfig(),
        layoutPersistence: LayoutPersistenceConfig = LayoutPersistenceConfig(),
        widthAdjustment: WidthAdjustmentConfig = WidthAdjustmentConfig(),
        performance: PerformanceConfig = PerformanceConfig()
    ) {
        self.tiling = tiling
        self.desktops = desktops
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.fx = fx
        self.focus = focus
        self.signals = signals
        self.rules = rules
        self.controlCenter = controlCenter
        self.configReload = configReload
        self.restoreSafety = restoreSafety
        self.transientWindows = transientWindows
        self.layoutPersistence = layoutPersistence
        self.widthAdjustment = widthAdjustment
        self.performance = performance
    }

    public init(
        tiling: TilingConfig = TilingConfig(),
        desktops: DesktopsConfig = DesktopsConfig(),
        stageManager: StageManagerConfig = StageManagerConfig(),
        exclusions: ExclusionsConfig = ExclusionsConfig(),
        fx: EffectsConfig = EffectsConfig(),
        focus: FocusConfig = FocusConfig(),
        signals: SignalsConfig = SignalsConfig(),
        controlCenter: ControlCenterConfig = ControlCenterConfig(),
        configReload: ConfigReloadConfig = ConfigReloadConfig(),
        restoreSafety: RestoreSafetyConfig = RestoreSafetyConfig(),
        transientWindows: TransientWindowsConfig = TransientWindowsConfig(),
        layoutPersistence: LayoutPersistenceConfig = LayoutPersistenceConfig(),
        widthAdjustment: WidthAdjustmentConfig = WidthAdjustmentConfig(),
        performance: PerformanceConfig = PerformanceConfig()
    ) {
        self.init(
            tiling: tiling,
            desktops: desktops,
            stageManager: stageManager,
            exclusions: exclusions,
            fx: fx,
            focus: focus,
            signals: signals,
            rules: [],
            controlCenter: controlCenter,
            configReload: configReload,
            restoreSafety: restoreSafety,
            transientWindows: transientWindows,
            layoutPersistence: layoutPersistence,
            widthAdjustment: widthAdjustment,
            performance: performance
        )
    }

    enum CodingKeys: String, CodingKey {
        case tiling
        case desktops
        case stageManager = "stage_manager"
        case exclusions
        case fx
        case focus
        case signals
        case rules
        case controlCenter = "control_center"
        case configReload = "config_reload"
        case restoreSafety = "restore_safety"
        case transientWindows = "transient_windows"
        case layoutPersistence = "layout_persistence"
        case widthAdjustment = "width_adjustment"
        case performance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tiling = try c.decodeIfPresent(TilingConfig.self, forKey: .tiling) ?? TilingConfig()
        self.desktops = try c.decodeIfPresent(DesktopsConfig.self, forKey: .desktops) ?? DesktopsConfig()
        self.stageManager = try c.decodeIfPresent(StageManagerConfig.self, forKey: .stageManager) ?? StageManagerConfig()
        self.exclusions = try c.decodeIfPresent(ExclusionsConfig.self, forKey: .exclusions) ?? ExclusionsConfig()
        self.fx = try c.decodeIfPresent(EffectsConfig.self, forKey: .fx) ?? EffectsConfig()
        self.focus = try c.decodeIfPresent(FocusConfig.self, forKey: .focus) ?? FocusConfig()
        self.signals = try c.decodeIfPresent(SignalsConfig.self, forKey: .signals) ?? SignalsConfig()
        self.rules = try c.decodeIfPresent([WindowRule].self, forKey: .rules) ?? []
        self.controlCenter = try c.decodeIfPresent(ControlCenterConfig.self, forKey: .controlCenter) ?? ControlCenterConfig()
        self.configReload = try c.decodeIfPresent(ConfigReloadConfig.self, forKey: .configReload) ?? ConfigReloadConfig()
        self.restoreSafety = try c.decodeIfPresent(RestoreSafetyConfig.self, forKey: .restoreSafety) ?? RestoreSafetyConfig()
        self.transientWindows = try c.decodeIfPresent(TransientWindowsConfig.self, forKey: .transientWindows) ?? TransientWindowsConfig()
        self.layoutPersistence = try c.decodeIfPresent(LayoutPersistenceConfig.self, forKey: .layoutPersistence) ?? LayoutPersistenceConfig()
        self.widthAdjustment = try c.decodeIfPresent(WidthAdjustmentConfig.self, forKey: .widthAdjustment) ?? WidthAdjustmentConfig()
        self.performance = try c.decodeIfPresent(PerformanceConfig.self, forKey: .performance) ?? PerformanceConfig()
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
    public var displayOverrides: [DisplayTilingOverride]
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
        displayOverrides: [DisplayTilingOverride] = [],
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
        self.displayOverrides = displayOverrides
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
        case displayOverrides = "display_overrides"
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
        self.displayOverrides = try c.decodeIfPresent([DisplayTilingOverride].self, forKey: .displayOverrides) ?? []
        self.gapsInner = try c.decodeFlexibleDouble(forKey: .gapsInner) ?? 4
        self.masterRatio = try c.decodeFlexibleDouble(forKey: .masterRatio) ?? 0.6
        self.smartGapsSolo = try c.decodeIfPresent(Bool.self, forKey: .smartGapsSolo) ?? false
        let sides = try c.decodeIfPresent([String].self, forKey: .smartGapsSoloSides) ?? GapSide.allCases.map(\.rawValue)
        self.smartGapsSoloSides = sides.compactMap(GapSide.init(rawValue:))
    }
}

public struct DisplayTilingOverride: Equatable, Codable, Sendable {
    public var displayID: String?
    public var displayName: String?
    public var gapsOuter: Double?
    public var gapsOuterTop: Double?
    public var gapsOuterRight: Double?
    public var gapsOuterBottom: Double?
    public var gapsOuterLeft: Double?

    public init(
        displayID: String? = nil,
        displayName: String? = nil,
        gapsOuter: Double? = nil,
        gapsOuterTop: Double? = nil,
        gapsOuterRight: Double? = nil,
        gapsOuterBottom: Double? = nil,
        gapsOuterLeft: Double? = nil
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterRight = gapsOuterRight
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
    }

    enum CodingKeys: String, CodingKey {
        case displayID = "display_id"
        case displayName = "display_name"
        case gapsOuter = "gaps_outer"
        case gapsOuterTop = "gaps_outer_top"
        case gapsOuterRight = "gaps_outer_right"
        case gapsOuterBottom = "gaps_outer_bottom"
        case gapsOuterLeft = "gaps_outer_left"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.displayID = try c.decodeIfPresent(String.self, forKey: .displayID)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.gapsOuter = try c.decodeFlexibleDouble(forKey: .gapsOuter)
        self.gapsOuterTop = try c.decodeFlexibleDouble(forKey: .gapsOuterTop)
        self.gapsOuterRight = try c.decodeFlexibleDouble(forKey: .gapsOuterRight)
        self.gapsOuterBottom = try c.decodeFlexibleDouble(forKey: .gapsOuterBottom)
        self.gapsOuterLeft = try c.decodeFlexibleDouble(forKey: .gapsOuterLeft)
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

public struct FocusConfig: Equatable, Codable, Sendable {
    public var stageFollowsFocus: Bool
    public var assignFollowsFocus: Bool
    public var focusFollowsMouse: Bool
    public var mouseFollowsFocus: Bool

    public init(
        stageFollowsFocus: Bool = true,
        assignFollowsFocus: Bool = false,
        focusFollowsMouse: Bool = false,
        mouseFollowsFocus: Bool = false
    ) {
        self.stageFollowsFocus = stageFollowsFocus
        self.assignFollowsFocus = assignFollowsFocus
        self.focusFollowsMouse = focusFollowsMouse
        self.mouseFollowsFocus = mouseFollowsFocus
    }

    enum CodingKeys: String, CodingKey {
        case stageFollowsFocus = "stage_follows_focus"
        case assignFollowsFocus = "assign_follows_focus"
        case focusFollowsMouse = "focus_follows_mouse"
        case mouseFollowsFocus = "mouse_follows_focus"
    }
}

public struct EffectsConfig: Equatable, Codable, Sendable {
    public var borders: BorderConfig

    public init(borders: BorderConfig = BorderConfig()) {
        self.borders = borders
    }

    enum CodingKeys: String, CodingKey {
        case borders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.borders = try c.decodeIfPresent(BorderConfig.self, forKey: .borders) ?? BorderConfig()
    }
}

public struct SignalsConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var hooks: [SignalHookConfig]

    public init(enabled: Bool = false, hooks: [SignalHookConfig] = []) {
        self.enabled = enabled
        self.hooks = hooks
    }
}

public struct SignalHookConfig: Equatable, Codable, Sendable {
    public var event: String
    public var cmd: String

    public init(event: String, cmd: String) {
        self.event = event
        self.cmd = cmd
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

public struct ControlCenterConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var showMenuBar: Bool
    public var showRecentErrors: Bool

    public init(enabled: Bool = true, showMenuBar: Bool = true, showRecentErrors: Bool = true) {
        self.enabled = enabled
        self.showMenuBar = showMenuBar
        self.showRecentErrors = showRecentErrors
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case showMenuBar = "show_menu_bar"
        case showRecentErrors = "show_recent_errors"
    }
}

public struct ConfigReloadConfig: Equatable, Codable, Sendable {
    public var watch: Bool
    public var debounceMS: Int
    public var keepPreviousOnError: Bool

    public init(watch: Bool = true, debounceMS: Int = 250, keepPreviousOnError: Bool = true) {
        self.watch = watch
        self.debounceMS = debounceMS
        self.keepPreviousOnError = keepPreviousOnError
    }

    enum CodingKeys: String, CodingKey {
        case watch
        case debounceMS = "debounce_ms"
        case keepPreviousOnError = "keep_previous_on_error"
    }
}

public struct RestoreSafetyConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var restoreOnExit: Bool
    public var crashWatcher: Bool
    public var snapshotPath: String

    public init(
        enabled: Bool = true,
        restoreOnExit: Bool = true,
        crashWatcher: Bool = true,
        snapshotPath: String = "~/.local/state/roadies/restore.json"
    ) {
        self.enabled = enabled
        self.restoreOnExit = restoreOnExit
        self.crashWatcher = crashWatcher
        self.snapshotPath = snapshotPath
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case restoreOnExit = "restore_on_exit"
        case crashWatcher = "crash_watcher"
        case snapshotPath = "snapshot_path"
    }
}

public struct TransientWindowsConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var pauseTiling: Bool
    public var recoverOffscreen: Bool

    public init(enabled: Bool = true, pauseTiling: Bool = true, recoverOffscreen: Bool = true) {
        self.enabled = enabled
        self.pauseTiling = pauseTiling
        self.recoverOffscreen = recoverOffscreen
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case pauseTiling = "pause_tiling"
        case recoverOffscreen = "recover_offscreen"
    }
}

public struct LayoutPersistenceConfig: Equatable, Codable, Sendable {
    public var version: Int
    public var stableIdentity: Bool
    public var minimumMatchScore: Double

    public init(version: Int = 2, stableIdentity: Bool = true, minimumMatchScore: Double = 0.75) {
        self.version = version
        self.stableIdentity = stableIdentity
        self.minimumMatchScore = minimumMatchScore
    }

    enum CodingKeys: String, CodingKey {
        case version
        case stableIdentity = "stable_identity"
        case minimumMatchScore = "minimum_match_score"
    }
}

public struct WidthAdjustmentConfig: Equatable, Codable, Sendable {
    public var presets: [Double]
    public var nudgeStep: Double
    public var minimumRatio: Double
    public var maximumRatio: Double

    public init(
        presets: [Double] = [0.5, 0.67, 0.8, 1.0],
        nudgeStep: Double = 0.05,
        minimumRatio: Double = 0.25,
        maximumRatio: Double = 1.5
    ) {
        self.presets = Array(Set(presets)).sorted()
        self.nudgeStep = nudgeStep
        self.minimumRatio = minimumRatio
        self.maximumRatio = maximumRatio
    }

    enum CodingKeys: String, CodingKey {
        case presets
        case nudgeStep = "nudge_step"
        case minimumRatio = "minimum_ratio"
        case maximumRatio = "maximum_ratio"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            presets: try c.decodeIfPresent([Double].self, forKey: .presets) ?? [0.5, 0.67, 0.8, 1.0],
            nudgeStep: try c.decodeFlexibleDouble(forKey: .nudgeStep) ?? 0.05,
            minimumRatio: try c.decodeFlexibleDouble(forKey: .minimumRatio) ?? 0.25,
            maximumRatio: try c.decodeFlexibleDouble(forKey: .maximumRatio) ?? 1.5
        )
    }
}

public struct PerformanceConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var maxInteractions: Int
    public var frameTolerancePoints: Double
    public var stageSwitchMs: Double
    public var desktopSwitchMs: Double
    public var altTabActivationMs: Double
    public var borderRefreshMs: Double
    public var displayFocusMs: Double
    public var directionalFocusMs: Double
    public var railActionMs: Double

    public init(
        enabled: Bool = true,
        maxInteractions: Int = 100,
        frameTolerancePoints: Double = 2,
        stageSwitchMs: Double = 150,
        desktopSwitchMs: Double = 200,
        altTabActivationMs: Double = 250,
        borderRefreshMs: Double = 80,
        displayFocusMs: Double = 150,
        directionalFocusMs: Double = 120,
        railActionMs: Double = 200
    ) {
        self.enabled = enabled
        self.maxInteractions = max(1, maxInteractions)
        self.frameTolerancePoints = max(0, frameTolerancePoints)
        self.stageSwitchMs = max(1, stageSwitchMs)
        self.desktopSwitchMs = max(1, desktopSwitchMs)
        self.altTabActivationMs = max(1, altTabActivationMs)
        self.borderRefreshMs = max(1, borderRefreshMs)
        self.displayFocusMs = max(1, displayFocusMs)
        self.directionalFocusMs = max(1, directionalFocusMs)
        self.railActionMs = max(1, railActionMs)
    }

    public var thresholds: [PerformanceThreshold] {
        [
            PerformanceThreshold(interactionType: .stageSwitch, limitMs: stageSwitchMs, percentileTarget: 95),
            PerformanceThreshold(interactionType: .desktopSwitch, limitMs: desktopSwitchMs, percentileTarget: 95),
            PerformanceThreshold(interactionType: .altTabActivation, limitMs: altTabActivationMs, percentileTarget: 90),
            PerformanceThreshold(interactionType: .borderRefresh, limitMs: borderRefreshMs, percentileTarget: 95),
            PerformanceThreshold(interactionType: .displayFocus, limitMs: displayFocusMs, percentileTarget: 95),
            PerformanceThreshold(interactionType: .directionalFocus, limitMs: directionalFocusMs, percentileTarget: 95),
            PerformanceThreshold(interactionType: .railAction, limitMs: railActionMs, percentileTarget: 95),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxInteractions = "max_interactions"
        case frameTolerancePoints = "frame_tolerance_points"
        case stageSwitchMs = "stage_switch_ms"
        case desktopSwitchMs = "desktop_switch_ms"
        case altTabActivationMs = "alt_tab_activation_ms"
        case borderRefreshMs = "border_refresh_ms"
        case displayFocusMs = "display_focus_ms"
        case directionalFocusMs = "directional_focus_ms"
        case railActionMs = "rail_action_ms"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            maxInteractions: try c.decodeIfPresent(Int.self, forKey: .maxInteractions) ?? 100,
            frameTolerancePoints: try c.decodeFlexibleDouble(forKey: .frameTolerancePoints) ?? 2,
            stageSwitchMs: try c.decodeFlexibleDouble(forKey: .stageSwitchMs) ?? 150,
            desktopSwitchMs: try c.decodeFlexibleDouble(forKey: .desktopSwitchMs) ?? 200,
            altTabActivationMs: try c.decodeFlexibleDouble(forKey: .altTabActivationMs) ?? 250,
            borderRefreshMs: try c.decodeFlexibleDouble(forKey: .borderRefreshMs) ?? 80,
            displayFocusMs: try c.decodeFlexibleDouble(forKey: .displayFocusMs) ?? 150,
            directionalFocusMs: try c.decodeFlexibleDouble(forKey: .directionalFocusMs) ?? 120,
            railActionMs: try c.decodeFlexibleDouble(forKey: .railActionMs) ?? 200
        )
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

    public static func validate(path: String? = nil) -> ConfigValidationReport {
        let resolved = path ?? defaultConfigPath()
        guard FileManager.default.fileExists(atPath: resolved) else {
            return ConfigValidationReport(items: [
                ConfigValidationItem(level: .warning, path: resolved, message: "config file not found; defaults will be used")
            ])
        }

        do {
            let config = try load(from: resolved)
            let raw = try String(contentsOfFile: resolved, encoding: .utf8)
            var items = ConfigValidationRules.validate(rawToml: raw)
            items.append(contentsOf: ConfigValidationRules.semanticChecks(config: config))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: "config is valid"))
            }
            return ConfigValidationReport(items: items)
        } catch {
            return ConfigValidationReport(items: [
                ConfigValidationItem(level: .error, path: resolved, message: "config decode failed: \(error)")
            ])
        }
    }
}

public enum ConfigValidationLevel: String, Codable, Sendable {
    case ok
    case warning
    case error
}

public struct ConfigValidationItem: Equatable, Codable, Sendable {
    public var level: ConfigValidationLevel
    public var path: String
    public var message: String

    public init(level: ConfigValidationLevel, path: String, message: String) {
        self.level = level
        self.path = path
        self.message = message
    }
}

public struct ConfigValidationReport: Equatable, Codable, Sendable {
    public var items: [ConfigValidationItem]

    public init(items: [ConfigValidationItem]) {
        self.items = items
    }

    public var hasErrors: Bool {
        items.contains { $0.level == .error }
    }
}

private enum ConfigValidationRules {
    private static let supportedTables: Set<String> = [
        "tiling",
        "desktops",
        "stage_manager",
        "stage_manager.workspaces",
        "tiling.display_overrides",
        "exclusions",
        "fx",
        "fx.borders",
        "fx.borders.stage_overrides",
        "fx.rail",
        "fx.rail.header",
        "fx.rail.header.display",
        "fx.rail.header.desktop",
        "fx.rail.layout",
        "fx.rail.parallax",
        "fx.rail.preview",
        "fx.rail.preview.stage_overrides",
        "fx.rail.stacked",
        "fx.rail.stages",
        "focus",
        "signals",
        "signals.hooks",
        "control_center",
        "config_reload",
        "restore_safety",
        "transient_windows",
        "layout_persistence",
        "width_adjustment",
        "rules",
        "rules.match",
        "rules.action"
    ]

    private static let knownUnsupportedTables: Set<String> = [
        "daemon",
        "mouse",
        "scratchpads",
        "sticky",
        "fx.animations",
        "fx.opacity",
        "fx.opacity.stage_hide"
    ]

    static func validate(rawToml: String) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        let tables = tableNames(in: rawToml)
        for table in tables.sorted() {
            if supportedTables.contains(table) {
                continue
            }
            if knownUnsupportedTables.contains(table) {
                items.append(ConfigValidationItem(
                    level: .warning,
                    path: table,
                    message: "known but not fully supported yet"
                ))
            } else {
                items.append(ConfigValidationItem(
                    level: .warning,
                    path: table,
                    message: "unknown table ignored"
                ))
            }
        }
        items.append(contentsOf: scalarTypeChecks(rawToml: rawToml))
        return items
    }

    private static func tableNames(in rawToml: String) -> Set<String> {
        var result: Set<String> = []
        for line in rawToml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            let withoutComment = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
            let table = withoutComment
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespaces))
            guard !table.isEmpty else { continue }
            result.insert(table)
        }
        return result
    }

    private static func scalarTypeChecks(rawToml: String) -> [ConfigValidationItem] {
        let numericKeys: Set<String> = [
            "gaps_outer",
            "gaps_outer_top",
            "gaps_outer_right",
            "gaps_outer_bottom",
            "gaps_outer_left",
            "gaps_inner",
            "master_ratio",
            "count",
            "thickness",
            "corner_radius"
        ]
        var items: [ConfigValidationItem] = []
        var currentTable = ""
        for line in rawToml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if trimmed.hasPrefix("[") {
                currentTable = trimmed
                    .split(separator: "#", maxSplits: 1)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespaces)) ?? ""
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1]
                .split(separator: "#", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard numericKeys.contains(key), value.hasPrefix("\"") else { continue }
            items.append(ConfigValidationItem(
                level: .error,
                path: [currentTable, key].filter { !$0.isEmpty }.joined(separator: "."),
                message: "expected numeric value, got string"
            ))
        }
        return items
    }

    static func semanticChecks(config: RoadieConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if !(50...5000).contains(config.configReload.debounceMS) {
            items.append(ConfigValidationItem(level: .error, path: "config_reload.debounce_ms", message: "must be between 50 and 5000"))
        }
        if !(0...1).contains(config.layoutPersistence.minimumMatchScore) {
            items.append(ConfigValidationItem(level: .error, path: "layout_persistence.minimum_match_score", message: "must be between 0 and 1"))
        }
        if config.widthAdjustment.presets.isEmpty {
            items.append(ConfigValidationItem(level: .error, path: "width_adjustment.presets", message: "must contain at least one ratio"))
        }
        if config.widthAdjustment.minimumRatio > config.widthAdjustment.maximumRatio {
            items.append(ConfigValidationItem(level: .error, path: "width_adjustment.minimum_ratio", message: "must be lower than or equal to maximum_ratio"))
        }
        return items
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
