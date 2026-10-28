import Foundation
import TOMLKit

public struct RoadieConfig: Equatable, Codable, Sendable {
    public var interface: InterfaceConfig
    public var tiling: TilingConfig
    public var desktops: DesktopsConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var fx: EffectsConfig
    public var focus: FocusConfig
    public var windowPlacement: WindowPlacementConfig
    public var rules: [WindowRule]
    public var widthAdjustment: WidthAdjustmentConfig
    public var experimental: ExperimentalConfig
    public var overview: OverviewConfig
    public var switcher: WindowSwitcherConfig
    /// Raccourcis de commandes gérés par Roadie (session 108).
    public var shortcuts: [CommandShortcut]

    public init(
        interface: InterfaceConfig = InterfaceConfig(),
        tiling: TilingConfig = TilingConfig(),
        desktops: DesktopsConfig = DesktopsConfig(),
        stageManager: StageManagerConfig = StageManagerConfig(),
        exclusions: ExclusionsConfig = ExclusionsConfig(),
        fx: EffectsConfig = EffectsConfig(),
        focus: FocusConfig = FocusConfig(),
        windowPlacement: WindowPlacementConfig = WindowPlacementConfig(),
        rules: [WindowRule],
        widthAdjustment: WidthAdjustmentConfig = WidthAdjustmentConfig(),
        experimental: ExperimentalConfig = ExperimentalConfig(),
        overview: OverviewConfig = OverviewConfig(),
        switcher: WindowSwitcherConfig = WindowSwitcherConfig(),
        shortcuts: [CommandShortcut] = []
    ) {
        self.interface = interface
        self.tiling = tiling
        self.desktops = desktops
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.fx = fx
        self.focus = focus
        self.windowPlacement = windowPlacement
        self.rules = rules
        self.widthAdjustment = widthAdjustment
        self.experimental = experimental
        self.overview = overview
        self.switcher = switcher
        self.shortcuts = shortcuts
    }

    public init(
        interface: InterfaceConfig = InterfaceConfig(),
        tiling: TilingConfig = TilingConfig(),
        desktops: DesktopsConfig = DesktopsConfig(),
        stageManager: StageManagerConfig = StageManagerConfig(),
        exclusions: ExclusionsConfig = ExclusionsConfig(),
        fx: EffectsConfig = EffectsConfig(),
        focus: FocusConfig = FocusConfig(),
        windowPlacement: WindowPlacementConfig = WindowPlacementConfig(),
        widthAdjustment: WidthAdjustmentConfig = WidthAdjustmentConfig(),
        experimental: ExperimentalConfig = ExperimentalConfig(),
        overview: OverviewConfig = OverviewConfig(),
        switcher: WindowSwitcherConfig = WindowSwitcherConfig()
    ) {
        self.init(
            interface: interface,
            tiling: tiling,
            desktops: desktops,
            stageManager: stageManager,
            exclusions: exclusions,
            fx: fx,
            focus: focus,
            windowPlacement: windowPlacement,
            rules: [],
            widthAdjustment: widthAdjustment,
            experimental: experimental,
            overview: overview,
            switcher: switcher
        )
    }

    enum CodingKeys: String, CodingKey {
        case interface
        case tiling
        case desktops
        case stageManager = "stage_manager"
        case exclusions
        case fx
        case focus
        case windowPlacement = "window_placement"
        case rules
        case widthAdjustment = "width_adjustment"
        case experimental
        case overview
        case switcher
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.interface = try c.decodeIfPresent(InterfaceConfig.self, forKey: .interface) ?? InterfaceConfig()
        self.tiling = try c.decodeIfPresent(TilingConfig.self, forKey: .tiling) ?? TilingConfig()
        self.desktops = try c.decodeIfPresent(DesktopsConfig.self, forKey: .desktops) ?? DesktopsConfig()
        self.stageManager = try c.decodeIfPresent(StageManagerConfig.self, forKey: .stageManager) ?? StageManagerConfig()
        self.exclusions = try c.decodeIfPresent(ExclusionsConfig.self, forKey: .exclusions) ?? ExclusionsConfig()
        self.fx = try c.decodeIfPresent(EffectsConfig.self, forKey: .fx) ?? EffectsConfig()
        self.focus = try c.decodeIfPresent(FocusConfig.self, forKey: .focus) ?? FocusConfig()
        self.windowPlacement = try c.decodeIfPresent(WindowPlacementConfig.self, forKey: .windowPlacement) ?? WindowPlacementConfig()
        self.rules = try c.decodeIfPresent([WindowRule].self, forKey: .rules) ?? []
        self.widthAdjustment = try c.decodeIfPresent(WidthAdjustmentConfig.self, forKey: .widthAdjustment) ?? WidthAdjustmentConfig()
        self.experimental = try c.decodeIfPresent(ExperimentalConfig.self, forKey: .experimental) ?? ExperimentalConfig()
        self.overview = try c.decodeIfPresent(OverviewConfig.self, forKey: .overview) ?? OverviewConfig()
        self.switcher = try c.decodeIfPresent(WindowSwitcherConfig.self, forKey: .switcher) ?? WindowSwitcherConfig()
        self.shortcuts = try c.decodeIfPresent([CommandShortcut].self, forKey: .shortcuts) ?? []
    }
}

/// Polices de la fenêtre de réglages. Les autres surfaces gardent leurs tailles indépendantes.
public struct InterfaceConfig: Equatable, Codable, Sendable {
    public var settingsTextFontSize: Double
    public var settingsHelpFontSize: Double
    public var settingsTitleFontSize: Double

    public init(settingsTextFontSize: Double = 16, settingsHelpFontSize: Double = 14, settingsTitleFontSize: Double = 22) {
        self.settingsTextFontSize = min(32, max(8, settingsTextFontSize))
        self.settingsHelpFontSize = min(32, max(8, settingsHelpFontSize))
        self.settingsTitleFontSize = min(48, max(10, settingsTitleFontSize))
    }

    enum CodingKeys: String, CodingKey {
        case settingsTextFontSize = "settings_text_font_size"
        case settingsHelpFontSize = "settings_help_font_size"
        case settingsTitleFontSize = "settings_title_font_size"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            settingsTextFontSize: try c.decodeFlexibleDouble(forKey: .settingsTextFontSize) ?? 16,
            settingsHelpFontSize: try c.decodeFlexibleDouble(forKey: .settingsHelpFontSize) ?? 14,
            settingsTitleFontSize: try c.decodeFlexibleDouble(forKey: .settingsTitleFontSize) ?? 22
        )
    }
}

public struct TilingConfig: Equatable, Codable, Sendable {
    public var defaultStrategy: WindowManagementMode
    public var splitPolicy: String
    /// Poignées dans les séparations des stages utilisant l'arbre persistant.
    public var resizeHandles: Bool
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
    /// Sous-roles AX consideres tile-able. Defaut : ["AXStandardWindow"] (yabai-like).
    /// Les fenetres AXDialog / AXSheet / AXFloatingWindow / AXSystemDialog / AXUnknown
    /// sont exclues du tiling sauf override par regle (action.manage = true).
    public var allowedSubroles: [String]
    /// Quand true (defaut), exclut du tiling les "popups" (fenetres AX sans aucun bouton
    /// close/fullscreen/min/zoom et non focused/main). Inspire d'aerospace isWindowHeuristic.
    /// Cible : tooltips, context menus, "Sonoma keyboard layout switch", IntelliJ context menus.
    public var popupFilter: Bool

    public init(
        defaultStrategy: WindowManagementMode = .bsp,
        splitPolicy: String = "largest_dim",
        resizeHandles: Bool = true,
        gapsOuter: Double = 8,
        gapsOuterTop: Double? = nil,
        gapsOuterRight: Double? = nil,
        gapsOuterBottom: Double? = nil,
        gapsOuterLeft: Double? = nil,
        displayOverrides: [DisplayTilingOverride] = [],
        gapsInner: Double = 4,
        masterRatio: Double = 0.6,
        smartGapsSolo: Bool = false,
        smartGapsSoloSides: [GapSide] = GapSide.allCases,
        allowedSubroles: [String] = ["AXStandardWindow"],
        popupFilter: Bool = true
    ) {
        self.defaultStrategy = defaultStrategy
        self.splitPolicy = splitPolicy
        self.resizeHandles = resizeHandles
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
        self.allowedSubroles = allowedSubroles
        self.popupFilter = popupFilter
    }

    enum CodingKeys: String, CodingKey {
        case defaultStrategy = "default_strategy"
        case splitPolicy = "split_policy"
        case resizeHandles = "resize_handles"
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
        case allowedSubroles = "allowed_subroles"
        case popupFilter = "popup_filter"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStrategy = try c.decodeIfPresent(String.self, forKey: .defaultStrategy) ?? "bsp"
        // Clé absente : bsp. Valeur présente mais inconnue : erreur lisible, jamais un repli silencieux (REL-034).
        guard let strategy = WindowManagementMode(tomlValue: rawStrategy) else {
            throw DecodingError.dataCorruptedError(
                forKey: .defaultStrategy,
                in: c,
                debugDescription: "default_strategy inconnu : \"\(rawStrategy)\" (attendu : bsp, mutableBsp, masterStack, float, spatialBsp ou un alias)"
            )
        }
        self.defaultStrategy = strategy
        self.splitPolicy = try c.decodeIfPresent(String.self, forKey: .splitPolicy) ?? "largest_dim"
        self.resizeHandles = try c.decodeIfPresent(Bool.self, forKey: .resizeHandles) ?? true
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
        self.allowedSubroles = try c.decodeIfPresent([String].self, forKey: .allowedSubroles) ?? ["AXStandardWindow"]
        self.popupFilter = try c.decodeIfPresent(Bool.self, forKey: .popupFilter) ?? true
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

    // Toutes les clés sont facultatives : un décodage synthétisé les rendrait obligatoires.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 10,
            backAndForth: try c.decodeIfPresent(Bool.self, forKey: .backAndForth) ?? true,
            mode: try c.decodeIfPresent(String.self, forKey: .mode) ?? "global"
        )
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

    // Toutes les clés sont facultatives : un décodage synthétisé les rendrait obligatoires.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            hideStrategy: try c.decodeIfPresent(String.self, forKey: .hideStrategy) ?? "corner",
            defaultStage: try c.decodeIfPresent(StageID.self, forKey: .defaultStage)?.rawValue ?? "1",
            workspaces: try c.decodeIfPresent([StageDefinition].self, forKey: .workspaces) ?? []
        )
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(StageID.self, forKey: .id).rawValue,
            displayName: try c.decode(String.self, forKey: .displayName)
        )
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.floatingBundles = try c.decodeIfPresent([String].self, forKey: .floatingBundles) ?? []
    }
}

public struct FocusConfig: Equatable, Codable, Sendable {
    public var stageFollowsFocus: Bool
    public var assignFollowsFocus: Bool
    public var stageMoveFollowsFocus: Bool
    public var focusFollowsMouse: Bool
    public var mouseFollowsFocus: Bool

    public init(
        stageFollowsFocus: Bool = true,
        assignFollowsFocus: Bool = false,
        stageMoveFollowsFocus: Bool = true,
        focusFollowsMouse: Bool = false,
        mouseFollowsFocus: Bool = false
    ) {
        self.stageFollowsFocus = stageFollowsFocus
        self.assignFollowsFocus = assignFollowsFocus
        self.stageMoveFollowsFocus = stageMoveFollowsFocus
        self.focusFollowsMouse = focusFollowsMouse
        self.mouseFollowsFocus = mouseFollowsFocus
    }

    enum CodingKeys: String, CodingKey {
        case stageFollowsFocus = "stage_follows_focus"
        case assignFollowsFocus = "assign_follows_focus"
        case stageMoveFollowsFocus = "stage_move_follows_focus"
        case focusFollowsMouse = "focus_follows_mouse"
        case mouseFollowsFocus = "mouse_follows_focus"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stageFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .stageFollowsFocus) ?? true
        self.assignFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .assignFollowsFocus) ?? false
        self.stageMoveFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .stageMoveFollowsFocus) ?? true
        self.focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? false
        self.mouseFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? false
    }
}

public struct WindowPlacementConfig: Equatable, Codable, Sendable {
    public var newAppsTarget: String
    /// Côté d'insertion d'une nouvelle fenêtre en mode BSP à arbre persistant (`spatial_bsp`).
    /// "right" = nouvelle fenêtre à droite/en bas du pane focalisé ; "left" = gauche/haut.
    public var newWindowSide: String

    public init(newAppsTarget: String = "focused_display", newWindowSide: String = "right") {
        self.newAppsTarget = newAppsTarget
        self.newWindowSide = newWindowSide
    }

    enum CodingKeys: String, CodingKey {
        case newAppsTarget = "new_apps_target"
        case newWindowSide = "new_window_side"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decodeIfPresent(String.self, forKey: .newAppsTarget) ?? "focused_display"
        self.newAppsTarget = ["mouse", "focused_display", "macos"].contains(value) ? value : "focused_display"
        let side = try c.decodeIfPresent(String.self, forKey: .newWindowSide) ?? "right"
        self.newWindowSide = ["right", "left"].contains(side) ? side : "right"
    }
}

public struct EffectsConfig: Equatable, Codable, Sendable {
    public var borders: BorderConfig

    public init(borders: BorderConfig = BorderConfig()) {
        self.borders = borders
    }

    // `borders` est facultatif : `[fx.rail]` seul est une configuration valide.
    enum CodingKeys: String, CodingKey {
        case borders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.borders = try c.decodeIfPresent(BorderConfig.self, forKey: .borders) ?? BorderConfig()
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

public struct ExperimentalConfig: Equatable, Codable, Sendable {
    public var titlebarContextMenu: TitlebarContextMenuConfig
    public var targetMode: TargetModeConfig
    public var appTargets: AppTargetsConfig
    public var targetGrid: TargetGridConfig
    public var targetRecord: TargetRecordConfig

    public init(
        titlebarContextMenu: TitlebarContextMenuConfig = TitlebarContextMenuConfig(),
        targetMode: TargetModeConfig = TargetModeConfig(),
        appTargets: AppTargetsConfig = AppTargetsConfig(),
        targetGrid: TargetGridConfig = TargetGridConfig(),
        targetRecord: TargetRecordConfig = TargetRecordConfig()
    ) {
        self.titlebarContextMenu = titlebarContextMenu
        self.targetMode = targetMode
        self.appTargets = appTargets
        self.targetGrid = targetGrid
        self.targetRecord = targetRecord
    }

    enum CodingKeys: String, CodingKey {
        case titlebarContextMenu = "titlebar_context_menu"
        case targetMode = "target_mode"
        case appTargets = "app_targets"
        case targetGrid = "target_grid"
        case targetRecord = "target_record"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.titlebarContextMenu = try c.decodeIfPresent(TitlebarContextMenuConfig.self, forKey: .titlebarContextMenu) ?? TitlebarContextMenuConfig()
        self.targetMode = try c.decodeIfPresent(TargetModeConfig.self, forKey: .targetMode) ?? TargetModeConfig()
        self.appTargets = try c.decodeIfPresent(AppTargetsConfig.self, forKey: .appTargets) ?? AppTargetsConfig()
        self.targetGrid = try c.decodeIfPresent(TargetGridConfig.self, forKey: .targetGrid) ?? TargetGridConfig()
        self.targetRecord = try c.decodeIfPresent(TargetRecordConfig.self, forKey: .targetRecord) ?? TargetRecordConfig()
    }
}

/// Recherche par mot-clé de la barre (SPEC-090) : `yt chat` cherche « chat » sur YouTube.
public struct WebSearch: Equatable, Codable, Sendable {
    public var keyword: String
    public var title: String
    /// Adresse avec `{query}`.
    public var url: String

    public init(keyword: String, title: String, url: String) {
        self.keyword = keyword
        self.title = title
        self.url = url
    }

    /// Recherches proposées quand `web_searches` est absent.
    public static let defaults = [
        WebSearch(keyword: "g", title: "Google", url: "https://www.google.com/search?q={query}"),
        WebSearch(keyword: "yt", title: "YouTube", url: "https://www.youtube.com/results?search_query={query}"),
        WebSearch(keyword: "wp", title: "Wikipédia", url: "https://fr.wikipedia.org/w/index.php?search={query}"),
        WebSearch(keyword: "ddg", title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}"),
        WebSearch(keyword: "maps", title: "Plans", url: "maps://?q={query}"),
    ]
}

/// Actions de la barre qui ont une touche réglable (session 108). L'ordre est celui des paramètres.
public enum LauncherBarKeys {
    public struct Action: Sendable, Equatable {
        public let id: String
        public let label: String
        public let help: String
        public let defaultKey: String
        public var configKey: String { id + "_key" }
    }

    public static let actions: [Action] = [
        Action(id: "large_type", label: "Grand texte", help: "Montre la ligne choisie en très grands caractères, comme ⌘L dans Alfred.", defaultKey: "command+l"),
        Action(id: "copy", label: "Copier la ligne", help: "Copie le chemin, l'adresse ou le titre de la ligne choisie, quand aucun texte n'est sélectionné dans la saisie.", defaultKey: "command+c"),
        Action(id: "preview", label: "Aperçu", help: "Ouvre l'aperçu (Quick Look) du fichier choisi.", defaultKey: "command+y"),
        Action(id: "save_action", label: "Garder l'action", help: "Enregistre l'action choisie sous une abréviation.", defaultKey: "command+s"),
        Action(id: "show_rules", label: "Règle proposée", help: "Montre la règle proposée pour la fenêtre choisie.", defaultKey: "command+r"),
        Action(id: "close", label: "Fermer la barre", help: "Ferme la barre.", defaultKey: "command+w"),
        Action(id: "close_all", label: "Tout fermer", help: "Ferme la barre d'un coup, même dans un dossier ou un verbe.", defaultKey: "command+escape"),
        Action(id: "select_toggle", label: "Ajouter ou retirer de la sélection", help: "Sélection multiple : ajoute la ligne choisie, ou la retire.", defaultKey: "alt+up"),
        Action(id: "select_add_next", label: "Ajouter et passer à la suivante", help: "Sélection multiple : ajoute la ligne choisie, puis descend d'une ligne.", defaultKey: "alt+down"),
        Action(id: "select_remove_last", label: "Retirer la dernière", help: "Sélection multiple : retire le dernier élément ajouté.", defaultKey: "alt+left"),
        Action(id: "selection_verbs", label: "Actions de la sélection", help: "Sélection multiple : montre les actions qui s'appliquent à toute la sélection.", defaultKey: "alt+right"),
        Action(id: "select_clear", label: "Vider la sélection", help: "Sélection multiple : retire tous les éléments.", defaultKey: "alt+backspace"),
    ]

    /// Défauts, puis valeurs données, normalisées ; une action inconnue est ignorée. O(a).
    public static func resolved(_ given: [String: String]) -> [String: String] {
        var keys: [String: String] = [:]
        for action in actions {
            keys[action.id] = TargetGridConfig.normalizedKey(given[action.id] ?? action.defaultKey, fallback: "")
        }
        return keys
    }
}

/// Raccourci global géré par Roadie pour une commande `roadie …` (session 108), table `[[shortcuts]]`.
/// `bttUUID` : raccourci BTT d'origine, désactivé tant que Roadie prend la main.
public struct CommandShortcut: Equatable, Codable, Sendable {
    public var keys: String
    public var command: String
    public var enabled: Bool
    public var bttUUID: String

    public init(keys: String, command: String, enabled: Bool = true, bttUUID: String = "") {
        self.keys = TargetGridConfig.normalizedKey(keys, fallback: "")
        self.command = command.trimmingCharacters(in: .whitespaces)
        self.enabled = enabled
        self.bttUUID = bttUUID
    }

    /// Arguments de la commande, sans le mot `roadie` du début ; guillemets simples et doubles respectés. O(n).
    public var arguments: [String] {
        var result: [String] = [], current = "", quote: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == " " {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { result.append(current) }
        if result.first == "roadie" || result.first?.hasSuffix("/roadie") == true { result.removeFirst() }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case keys, command, enabled
        case bttUUID = "btt_uuid"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(keys: try c.decodeIfPresent(String.self, forKey: .keys) ?? "",
                  command: try c.decodeIfPresent(String.self, forKey: .command) ?? "",
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  bttUUID: try c.decodeIfPresent(String.self, forKey: .bttUUID) ?? "")
    }
}

public struct TargetModeConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var pickerEnabled: Bool
    public var overlayEnabled: Bool
    public var overlayLabelsOnly: Bool
    public var overlayDurationSeconds: Double
    public var appMouseActionsEnabled: Bool
    public var scrollModeEnabled: Bool
    /// Raccourci global du mode recherche (SPEC-021), forme normalisée `command+control+alt+f` ;
    /// vide = désactivé. Défaut : la hyper key (Cmd+Option+Ctrl) + F, comme le conseille Homerow.
    public var searchHotkey: String
    /// Raccourci qui ouvre la barre aux verbes de la fenêtre active (SPEC-075) ; vide = désactivé.
    /// Défaut : hyper key + Maj + F (Capslock + Maj + F).
    public var actionsHotkey: String
    /// Recherche web de ⌃ Retour (SPEC-075) ; `{query}` reçoit le texte tapé, encodé.
    public var webSearchURL: String
    /// Modificateur des raccourcis 1 à 9 du lanceur (SPEC-085) : `command`, `shift`, `alt` ou `control`.
    /// Une autre valeur revient à `command`.
    public var pickModifier: String
    /// Workflows dans la barre (SPEC-088) ; `alfredWorkflows` : lire aussi ceux installés dans Alfred.
    public var workflowsEnabled: Bool
    public var alfredWorkflows: Bool
    /// Recherches par mot-clé de la barre (SPEC-090) ; nil = défauts (`WebSearch.defaults`), vide = aucune.
    public var webSearches: [WebSearch]?
    /// Mots-clés de `webSearches` proposés en repli, après la recherche de `web_search_url`.
    public var fallbackSearches: [String]
    /// Barre vide (session 096) : « Souvent ici » et « Recherches récentes », activation et nombre de lignes.
    /// Le décodage ramène le nombre dans 1…10 et 1…20 (l'historique garde 20 saisies).
    public var idleFrequentEnabled: Bool
    public var idleFrequentCount: Int
    public var idleRecentSearchesEnabled: Bool
    public var idleRecentSearchesCount: Int
    /// Touche qui fait passer les résultats de la liste à la grille puis aux grandes tuiles (session 099) ;
    /// vide : désactivée.
    public var viewCycleHotkey: String
    /// Taille de police des étiquettes en points (SPEC-023). Le décodage ramène toute valeur dans 8…48 (clamp dans l'init) : aucune validation hors plage n'est nécessaire.
    public var labelFontSize: Double
    public var searchLabelFontSize: Double
    public var searchTextFontSize: Double
    public var commandTextFontSize: Double
    public var searchFontFamily: String
    public var commandFontFamily: String
    /// Thème de la barre (session 101) : identifiant d'un thème fourni (`roadie`, `alfred`, `alfred-dark`…)
    /// ou nom d'un fichier `.alfredappearance` importé. `themeDark` : thème quand macOS est en mode sombre ;
    /// vide = `theme`.
    public var theme: String
    public var themeDark: String
    /// Nombre de résultats montrés (session 101) ; 0 = autant que la place, sinon 3…20.
    public var visibleResults: Int
    /// Écran de la barre (session 102) : `mouse` (écran du pointeur), `active` (écran de la fenêtre
    /// active) ou `main` (écran principal). Une autre valeur revient à `mouse`.
    public var barScreen: String
    /// Place par défaut de la barre (session 102) : `bottom`, `center` ou `top`.
    public var barPosition: String
    /// La barre déplacée à la souris garde sa place d'une ouverture à l'autre (session 102).
    public var barSavePosition: Bool
    /// Terminal qui lance une commande tapée après `>` (session 103) : `terminal`, `iterm`, `ghostty`,
    /// `warp`, `kitty`, `wezterm` ou `alacritty`.
    public var terminalApp: String
    /// Signets des navigateurs dans la barre (session 104) et navigateurs lus (`firefox`, `safari`, `chrome`,
    /// `brave`, `edge`, `arc`).
    public var bookmarksEnabled: Bool
    public var bookmarkBrowsers: [String]
    /// Dossiers d'applications ajoutés à la portée par défaut (session 105), `~` accepté.
    public var appSearchPaths: [String]
    /// Classement appris des résultats (session 105) ; faux : ordre sans apprentissage, rien n'est enregistré.
    public var learningEnabled: Bool
    /// Ordre des éléments d'un chemin tapé (session 105) : `name`, `modified` ou `created` ; dossiers en tête.
    public var pathSort: String
    /// « Tout quitter » demande une confirmation (session 105).
    public var confirmQuitAll: Bool
    /// Retour sur un calcul ouvre aussi Calculette, en plus de copier le résultat (session 110).
    public var calcOpensCalculator: Bool
    /// Les verbes les plus choisis pour un type d'objet passent en tête (session 111).
    public var learnVerbOrder: Bool
    /// Mots-clés de la recherche dans le contenu et par étiquette Finder (session 113) ; vide : désactivé.
    public var contentSearchKeyword: String
    public var tagSearchKeyword: String
    /// Touches de la barre (session 108), par action de `LauncherBarKeys.actions` ; forme normalisée,
    /// vide : touche désactivée. Clés TOML `<action>_key`.
    public var barKeys: [String: String]
    /// Touches de la barre qui passent avant BetterTouchTool (session 108) : tant que la barre est ouverte,
    /// Roadie met en pause les raccourcis BTT de ces combinaisons, puis les réactive.
    public var bttPauseKeys: [String]

    public static let defaultSearchHotkey = "command+control+alt+f"
    public static let defaultActionsHotkey = "command+control+alt+shift+f"
    public static let defaultWebSearchURL = "https://www.google.com/search?q={query}"
    public static let pickModifiers = ["command", "shift", "alt", "control"]
    public static let barScreens = ["mouse", "active", "main"]
    public static let barPositions = ["bottom", "center", "top"]
    public static let terminalApps = ["terminal", "iterm", "ghostty", "warp", "kitty", "wezterm", "alacritty"]
    public static let bookmarkBrowserIDs = ["firefox", "safari", "chrome", "brave", "edge", "arc"]
    public static let pathSorts = ["name", "modified", "created"]

    public init(
        enabled: Bool = true,
        pickerEnabled: Bool = true,
        overlayEnabled: Bool = false,
        overlayLabelsOnly: Bool = true,
        overlayDurationSeconds: Double = 3,
        appMouseActionsEnabled: Bool = false,
        scrollModeEnabled: Bool = false,
        searchHotkey: String = TargetModeConfig.defaultSearchHotkey,
        actionsHotkey: String = TargetModeConfig.defaultActionsHotkey,
        webSearchURL: String = TargetModeConfig.defaultWebSearchURL,
        pickModifier: String = "command",
        workflowsEnabled: Bool = true,
        alfredWorkflows: Bool = true,
        webSearches: [WebSearch]? = nil,
        fallbackSearches: [String] = [],
        idleFrequentEnabled: Bool = true,
        idleFrequentCount: Int = 3,
        idleRecentSearchesEnabled: Bool = true,
        idleRecentSearchesCount: Int = 3,
        viewCycleHotkey: String = "command+g",
        labelFontSize: Double = 13,
        searchLabelFontSize: Double = 13,
        searchTextFontSize: Double = 15,
        commandTextFontSize: Double = 13,
        searchFontFamily: String = "system",
        commandFontFamily: String = "system",
        theme: String = "roadie",
        themeDark: String = "",
        visibleResults: Int = 0,
        barScreen: String = "mouse",
        barPosition: String = "bottom",
        barSavePosition: Bool = true,
        terminalApp: String = "terminal",
        bookmarksEnabled: Bool = true,
        bookmarkBrowsers: [String] = ["firefox", "safari", "chrome"],
        appSearchPaths: [String] = [],
        learningEnabled: Bool = true,
        pathSort: String = "name",
        confirmQuitAll: Bool = true,
        calcOpensCalculator: Bool = false,
        learnVerbOrder: Bool = true,
        contentSearchKeyword: String = "in",
        tagSearchKeyword: String = "tags",
        barKeys: [String: String] = [:],
        bttPauseKeys: [String] = []
    ) {
        self.enabled = enabled
        self.pickerEnabled = pickerEnabled
        self.overlayEnabled = overlayEnabled
        self.overlayLabelsOnly = overlayLabelsOnly
        self.overlayDurationSeconds = overlayDurationSeconds
        self.appMouseActionsEnabled = appMouseActionsEnabled
        self.scrollModeEnabled = scrollModeEnabled
        self.searchHotkey = TargetGridConfig.normalizedKey(searchHotkey, fallback: "")
        self.actionsHotkey = TargetGridConfig.normalizedKey(actionsHotkey, fallback: "")
        self.webSearchURL = webSearchURL
        self.pickModifier = TargetModeConfig.pickModifiers.contains(pickModifier) ? pickModifier : "command"
        self.workflowsEnabled = workflowsEnabled
        self.alfredWorkflows = alfredWorkflows
        self.webSearches = webSearches
        self.fallbackSearches = fallbackSearches
        self.idleFrequentEnabled = idleFrequentEnabled
        self.idleFrequentCount = min(10, max(1, idleFrequentCount))
        self.idleRecentSearchesEnabled = idleRecentSearchesEnabled
        self.idleRecentSearchesCount = min(20, max(1, idleRecentSearchesCount))
        self.viewCycleHotkey = TargetGridConfig.normalizedKey(viewCycleHotkey, fallback: "")
        self.labelFontSize = min(48, max(8, labelFontSize))
        self.searchLabelFontSize = min(48, max(8, searchLabelFontSize))
        self.searchTextFontSize = min(48, max(8, searchTextFontSize))
        self.commandTextFontSize = min(48, max(8, commandTextFontSize))
        self.searchFontFamily = searchFontFamily
        self.commandFontFamily = commandFontFamily
        self.theme = theme.isEmpty ? "roadie" : theme
        self.themeDark = themeDark
        self.visibleResults = visibleResults <= 0 ? 0 : min(20, max(3, visibleResults))
        self.barScreen = TargetModeConfig.barScreens.contains(barScreen) ? barScreen : "mouse"
        self.barPosition = TargetModeConfig.barPositions.contains(barPosition) ? barPosition : "bottom"
        self.barSavePosition = barSavePosition
        self.terminalApp = TargetModeConfig.terminalApps.contains(terminalApp) ? terminalApp : "terminal"
        self.bookmarksEnabled = bookmarksEnabled
        self.bookmarkBrowsers = bookmarkBrowsers.filter { TargetModeConfig.bookmarkBrowserIDs.contains($0) }
        self.appSearchPaths = appSearchPaths
        self.learningEnabled = learningEnabled
        self.pathSort = TargetModeConfig.pathSorts.contains(pathSort) ? pathSort : "name"
        self.confirmQuitAll = confirmQuitAll
        self.calcOpensCalculator = calcOpensCalculator
        self.learnVerbOrder = learnVerbOrder
        self.contentSearchKeyword = contentSearchKeyword.trimmingCharacters(in: .whitespaces)
        self.tagSearchKeyword = tagSearchKeyword.trimmingCharacters(in: .whitespaces)
        self.barKeys = LauncherBarKeys.resolved(barKeys)
        self.bttPauseKeys = bttPauseKeys.map { TargetGridConfig.normalizedKey($0, fallback: "") }.filter { !$0.isEmpty }
    }

    /// Modificateurs (`command`, `control`, `alt`, `shift`) et touche d'un raccourci normalisé ;
    /// nil si la chaîne n'a pas exactement une touche et au moins un modificateur.
    public static func hotkeyParts(_ normalized: String) -> (modifiers: Set<String>, key: String)? {
        let modifierNames: Set<String> = ["command", "control", "alt", "shift"]
        let parts = normalized.split(separator: "+").map(String.init)
        let modifiers = Set(parts.filter { modifierNames.contains($0) })
        let keys = parts.filter { !modifierNames.contains($0) }
        guard !modifiers.isEmpty, keys.count == 1, let key = keys.first, !key.isEmpty else { return nil }
        return (modifiers, key)
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case pickerEnabled = "picker_enabled"
        case overlayEnabled = "overlay_enabled"
        case overlayLabelsOnly = "overlay_labels_only"
        case overlayDurationSeconds = "overlay_duration_seconds"
        case appMouseActionsEnabled = "app_mouse_actions_enabled"
        case scrollModeEnabled = "scroll_mode_enabled"
        case searchHotkey = "search_hotkey"
        case actionsHotkey = "actions_hotkey"
        case webSearchURL = "web_search_url"
        case pickModifier = "pick_modifier"
        case workflowsEnabled = "workflows_enabled"
        case alfredWorkflows = "alfred_workflows"
        case webSearches = "web_searches"
        case fallbackSearches = "fallback_searches"
        case idleFrequentEnabled = "idle_frequent_enabled"
        case idleFrequentCount = "idle_frequent_count"
        case idleRecentSearchesEnabled = "idle_recent_searches_enabled"
        case idleRecentSearchesCount = "idle_recent_searches_count"
        case viewCycleHotkey = "view_cycle_hotkey"
        case labelFontSize = "label_font_size"
        case searchLabelFontSize = "search_label_font_size"
        case searchTextFontSize = "search_text_font_size"
        case commandTextFontSize = "command_text_font_size"
        case searchFontFamily = "search_font_family"
        case commandFontFamily = "command_font_family"
        case theme
        case themeDark = "theme_dark"
        case visibleResults = "visible_results"
        case barScreen = "bar_screen"
        case barPosition = "bar_position"
        case barSavePosition = "bar_save_position"
        case terminalApp = "terminal_app"
        case bookmarksEnabled = "bookmarks_enabled"
        case bookmarkBrowsers = "bookmark_browsers"
        case appSearchPaths = "app_search_paths"
        case learningEnabled = "learning_enabled"
        case pathSort = "path_sort"
        case confirmQuitAll = "confirm_quit_all"
        case calcOpensCalculator = "calc_opens_calculator"
        case learnVerbOrder = "learn_verb_order"
        case contentSearchKeyword = "content_search_keyword"
        case tagSearchKeyword = "tag_search_keyword"
        case bttPauseKeys = "btt_pause_keys"
    }

    /// Clé TOML quelconque : les touches de la barre se lisent par leur nom (`large_type_key`…).
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            pickerEnabled: try c.decodeIfPresent(Bool.self, forKey: .pickerEnabled) ?? true,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? false,
            overlayLabelsOnly: try c.decodeIfPresent(Bool.self, forKey: .overlayLabelsOnly) ?? true,
            overlayDurationSeconds: try c.decodeFlexibleDouble(forKey: .overlayDurationSeconds) ?? 3,
            appMouseActionsEnabled: try c.decodeIfPresent(Bool.self, forKey: .appMouseActionsEnabled) ?? false,
            scrollModeEnabled: try c.decodeIfPresent(Bool.self, forKey: .scrollModeEnabled) ?? false,
            searchHotkey: try c.decodeIfPresent(String.self, forKey: .searchHotkey) ?? TargetModeConfig.defaultSearchHotkey,
            actionsHotkey: try c.decodeIfPresent(String.self, forKey: .actionsHotkey) ?? TargetModeConfig.defaultActionsHotkey,
            webSearchURL: try c.decodeIfPresent(String.self, forKey: .webSearchURL) ?? TargetModeConfig.defaultWebSearchURL,
            pickModifier: try c.decodeIfPresent(String.self, forKey: .pickModifier) ?? "command",
            workflowsEnabled: try c.decodeIfPresent(Bool.self, forKey: .workflowsEnabled) ?? true,
            alfredWorkflows: try c.decodeIfPresent(Bool.self, forKey: .alfredWorkflows) ?? true,
            webSearches: try c.decodeIfPresent([WebSearch].self, forKey: .webSearches),
            fallbackSearches: try c.decodeIfPresent([String].self, forKey: .fallbackSearches) ?? [],
            idleFrequentEnabled: try c.decodeIfPresent(Bool.self, forKey: .idleFrequentEnabled) ?? true,
            idleFrequentCount: try c.decodeIfPresent(Int.self, forKey: .idleFrequentCount) ?? 3,
            idleRecentSearchesEnabled: try c.decodeIfPresent(Bool.self, forKey: .idleRecentSearchesEnabled) ?? true,
            idleRecentSearchesCount: try c.decodeIfPresent(Int.self, forKey: .idleRecentSearchesCount) ?? 3,
            viewCycleHotkey: try c.decodeIfPresent(String.self, forKey: .viewCycleHotkey) ?? "command+g",
            labelFontSize: try c.decodeFlexibleDouble(forKey: .labelFontSize) ?? 13,
            searchLabelFontSize: try c.decodeFlexibleDouble(forKey: .searchLabelFontSize) ?? 13,
            searchTextFontSize: try c.decodeFlexibleDouble(forKey: .searchTextFontSize) ?? 15,
            commandTextFontSize: try c.decodeFlexibleDouble(forKey: .commandTextFontSize) ?? 13,
            searchFontFamily: try c.decodeIfPresent(String.self, forKey: .searchFontFamily) ?? "system",
            commandFontFamily: try c.decodeIfPresent(String.self, forKey: .commandFontFamily) ?? "system",
            theme: try c.decodeIfPresent(String.self, forKey: .theme) ?? "roadie",
            themeDark: try c.decodeIfPresent(String.self, forKey: .themeDark) ?? "",
            visibleResults: try c.decodeIfPresent(Int.self, forKey: .visibleResults) ?? 0,
            barScreen: try c.decodeIfPresent(String.self, forKey: .barScreen) ?? "mouse",
            barPosition: try c.decodeIfPresent(String.self, forKey: .barPosition) ?? "bottom",
            barSavePosition: try c.decodeIfPresent(Bool.self, forKey: .barSavePosition) ?? true,
            terminalApp: try c.decodeIfPresent(String.self, forKey: .terminalApp) ?? "terminal",
            bookmarksEnabled: try c.decodeIfPresent(Bool.self, forKey: .bookmarksEnabled) ?? true,
            bookmarkBrowsers: try c.decodeIfPresent([String].self, forKey: .bookmarkBrowsers) ?? ["firefox", "safari", "chrome"],
            appSearchPaths: try c.decodeIfPresent([String].self, forKey: .appSearchPaths) ?? [],
            learningEnabled: try c.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? true,
            pathSort: try c.decodeIfPresent(String.self, forKey: .pathSort) ?? "name",
            confirmQuitAll: try c.decodeIfPresent(Bool.self, forKey: .confirmQuitAll) ?? true,
            calcOpensCalculator: try c.decodeIfPresent(Bool.self, forKey: .calcOpensCalculator) ?? false,
            learnVerbOrder: try c.decodeIfPresent(Bool.self, forKey: .learnVerbOrder) ?? true,
            contentSearchKeyword: try c.decodeIfPresent(String.self, forKey: .contentSearchKeyword) ?? "in",
            tagSearchKeyword: try c.decodeIfPresent(String.self, forKey: .tagSearchKeyword) ?? "tags",
            barKeys: try Self.decodeBarKeys(decoder),
            bttPauseKeys: try c.decodeIfPresent([String].self, forKey: .bttPauseKeys) ?? []
        )
    }

    /// O(a), a = nombre d'actions de la barre.
    private static func decodeBarKeys(_ decoder: Decoder) throws -> [String: String] {
        let any = try decoder.container(keyedBy: AnyKey.self)
        var keys: [String: String] = [:]
        for action in LauncherBarKeys.actions {
            if let value = try any.decodeIfPresent(String.self, forKey: AnyKey(stringValue: action.configKey)) {
                keys[action.id] = value
            }
        }
        return keys
    }
}

public struct AppTargetsConfig: Equatable, Codable, Sendable {
    /// `frontmost_window` : fenêtre active ; `visible_windows` : toutes les fenêtres à l'écran (SPEC-021).
    public static let scopes: Set<String> = ["frontmost_window", "visible_windows"]

    public var enabled: Bool
    public var scope: String
    public var maxTargets: Int
    public var timeoutMs: Int
    public var hintCharacters: String
    public var includeRoles: [String]
    public var axBoostEnabled: Bool
    public var maxDepth: Int
    public var additionalBoostBundleIDs: [String]

    public init(
        enabled: Bool = false,
        scope: String = "frontmost_window",
        maxTargets: Int = 150,
        timeoutMs: Int = 120,
        hintCharacters: String = "asdfghjkl",
        includeRoles: [String] = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow", "AXCheckBox", "AXRadioButton", "AXPopUpButton"],
        axBoostEnabled: Bool = false,
        maxDepth: Int = 12,
        additionalBoostBundleIDs: [String] = []
    ) {
        self.enabled = enabled
        self.scope = scope
        self.maxTargets = min(500, max(1, maxTargets))
        self.timeoutMs = min(2_000, max(10, timeoutMs))
        self.hintCharacters = hintCharacters.isEmpty ? "asdfghjkl" : hintCharacters
        self.includeRoles = includeRoles
        self.axBoostEnabled = axBoostEnabled
        self.maxDepth = min(40, max(1, maxDepth))
        self.additionalBoostBundleIDs = additionalBoostBundleIDs
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case scope
        case maxTargets = "max_targets"
        case timeoutMs = "timeout_ms"
        case hintCharacters = "hint_characters"
        case includeRoles = "include_roles"
        case axBoostEnabled = "ax_boost_enabled"
        case maxDepth = "max_depth"
        case additionalBoostBundleIDs = "additional_boost_bundle_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            scope: try c.decodeIfPresent(String.self, forKey: .scope) ?? "frontmost_window",
            maxTargets: try c.decodeIfPresent(Int.self, forKey: .maxTargets) ?? 150,
            timeoutMs: try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 120,
            hintCharacters: try c.decodeIfPresent(String.self, forKey: .hintCharacters) ?? "asdfghjkl",
            includeRoles: try c.decodeIfPresent([String].self, forKey: .includeRoles) ?? ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow", "AXCheckBox", "AXRadioButton", "AXPopUpButton"],
            axBoostEnabled: try c.decodeIfPresent(Bool.self, forKey: .axBoostEnabled) ?? false,
            maxDepth: try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 12,
            additionalBoostBundleIDs: try c.decodeIfPresent([String].self, forKey: .additionalBoostBundleIDs) ?? []
        )
    }
}

public enum TargetGridInteractionMode: String, Codable, Equatable, Sendable {
    case autoClick = "auto_click"
    case recursive
}

public enum TargetGridArrowEdgeBehavior: String, Codable, Equatable, Sendable {
    case clamp
    case wrap
}

public enum TargetGridLabelPlacement: String, Codable, Equatable, Sendable {
    case callout
    case center
}

public enum TargetGridScope: String, Codable, Equatable, Sendable {
    case display
    case focusedWindow = "focused_window"
}

public struct TargetGridConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var mode: TargetGridInteractionMode
    public var overlayEnabled: Bool
    public var overlayDrawGrid: Bool
    public var overlayFillColor: String
    public var overlayFillOpacity: Double
    public var overlayBorderColor: String
    public var overlayBorderOpacity: Double
    public var overlayLabelColor: String
    public var overlayLabelBackgroundOpacity: Double
    public var rows: Int
    public var columns: Int
    public var maxDepth: Int
    public var hintCharacters: String
    public var confirmActionKey: String
    public var resetKey: String
    public var backKey: String
    public var exitKey: String
    public var arrowNavigationEnabled: Bool
    public var arrowEdgeBehavior: TargetGridArrowEdgeBehavior
    public var actionDelayMs: Int
    public var wakeMousePixels: Int
    public var mouseFollowGrid: Bool
    public var focusFollowGrid: Bool
    public var labelPlacement: TargetGridLabelPlacement
    public var defaultScope: TargetGridScope
    /// Taille de police des étiquettes en points (SPEC-023). Le décodage ramène toute valeur dans 8…48 (clamp dans l'init) : aucune validation hors plage n'est nécessaire.
    public var labelFontSize: Double

    public init(
        enabled: Bool = false,
        mode: TargetGridInteractionMode = .recursive,
        overlayEnabled: Bool = true,
        overlayDrawGrid: Bool = true,
        overlayFillColor: String = "#4DABF7",
        overlayFillOpacity: Double = 0.10,
        overlayBorderColor: String = "#4DABF7",
        overlayBorderOpacity: Double = 0.55,
        overlayLabelColor: String = "#FFFFFF",
        overlayLabelBackgroundOpacity: Double = 0.84,
        rows: Int = 3,
        columns: Int = 3,
        maxDepth: Int = 3,
        hintCharacters: String = "azeqsdwxc",
        confirmActionKey: String = "space",
        resetKey: String = "r",
        backKey: String = "backspace",
        exitKey: String = "escape",
        arrowNavigationEnabled: Bool = true,
        arrowEdgeBehavior: TargetGridArrowEdgeBehavior = .clamp,
        actionDelayMs: Int = 30,
        wakeMousePixels: Int = 1,
        mouseFollowGrid: Bool = false,
        focusFollowGrid: Bool = false,
        labelPlacement: TargetGridLabelPlacement = .callout,
        defaultScope: TargetGridScope = .display,
        labelFontSize: Double = 13
    ) {
        self.enabled = enabled
        self.mode = mode
        self.overlayEnabled = overlayEnabled
        self.overlayDrawGrid = overlayDrawGrid
        self.overlayFillColor = overlayFillColor.isEmpty ? "#4DABF7" : overlayFillColor
        self.overlayFillOpacity = min(1, max(0, overlayFillOpacity))
        self.overlayBorderColor = overlayBorderColor.isEmpty ? "#4DABF7" : overlayBorderColor
        self.overlayBorderOpacity = min(1, max(0, overlayBorderOpacity))
        self.overlayLabelColor = overlayLabelColor.isEmpty ? "#FFFFFF" : overlayLabelColor
        self.overlayLabelBackgroundOpacity = min(1, max(0, overlayLabelBackgroundOpacity))
        self.rows = min(12, max(2, rows))
        self.columns = min(12, max(2, columns))
        self.maxDepth = min(20, max(1, maxDepth))
        self.hintCharacters = hintCharacters.isEmpty ? "azeqsdwxc" : hintCharacters
        self.confirmActionKey = Self.normalizedKey(confirmActionKey, fallback: "space")
        self.resetKey = Self.normalizedKey(resetKey, fallback: "r")
        self.backKey = Self.normalizedKey(backKey, fallback: "backspace")
        self.exitKey = Self.normalizedKey(exitKey, fallback: "escape")
        self.arrowNavigationEnabled = arrowNavigationEnabled
        self.arrowEdgeBehavior = arrowEdgeBehavior
        self.actionDelayMs = min(1_000, max(0, actionDelayMs))
        self.wakeMousePixels = min(20, max(0, wakeMousePixels))
        self.mouseFollowGrid = mouseFollowGrid
        self.focusFollowGrid = focusFollowGrid
        self.labelPlacement = labelPlacement
        self.defaultScope = defaultScope
        self.labelFontSize = min(48, max(8, labelFontSize))
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case overlayEnabled = "overlay_enabled"
        case overlayDrawGrid = "overlay_draw_grid"
        case overlayFillColor = "overlay_fill_color"
        case overlayFillOpacity = "overlay_fill_opacity"
        case overlayBorderColor = "overlay_border_color"
        case overlayBorderOpacity = "overlay_border_opacity"
        case overlayLabelColor = "overlay_label_color"
        case overlayLabelBackgroundOpacity = "overlay_label_background_opacity"
        case rows
        case columns
        case maxDepth = "max_depth"
        case hintCharacters = "hint_characters"
        case mode
        case confirmActionKey = "confirm_action_key"
        case resetKey = "reset_key"
        case backKey = "back_key"
        case exitKey = "exit_key"
        case arrowNavigationEnabled = "arrow_navigation_enabled"
        case arrowEdgeBehavior = "arrow_edge_behavior"
        case actionDelayMs = "action_delay_ms"
        case wakeMousePixels = "wake_mouse_pixels"
        case mouseFollowGrid = "mouse_follow_grid"
        case focusFollowGrid = "focus_follow_grid"
        case labelPlacement = "label_placement"
        case defaultScope = "default_scope"
        case labelFontSize = "label_font_size"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            mode: try c.decodeIfPresent(TargetGridInteractionMode.self, forKey: .mode) ?? .recursive,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? true,
            overlayDrawGrid: try c.decodeIfPresent(Bool.self, forKey: .overlayDrawGrid) ?? true,
            overlayFillColor: try c.decodeIfPresent(String.self, forKey: .overlayFillColor) ?? "#4DABF7",
            overlayFillOpacity: try c.decodeFlexibleDouble(forKey: .overlayFillOpacity) ?? 0.10,
            overlayBorderColor: try c.decodeIfPresent(String.self, forKey: .overlayBorderColor) ?? "#4DABF7",
            overlayBorderOpacity: try c.decodeFlexibleDouble(forKey: .overlayBorderOpacity) ?? 0.55,
            overlayLabelColor: try c.decodeIfPresent(String.self, forKey: .overlayLabelColor) ?? "#FFFFFF",
            overlayLabelBackgroundOpacity: try c.decodeFlexibleDouble(forKey: .overlayLabelBackgroundOpacity) ?? 0.84,
            rows: try c.decodeIfPresent(Int.self, forKey: .rows) ?? 3,
            columns: try c.decodeIfPresent(Int.self, forKey: .columns) ?? 3,
            maxDepth: try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 3,
            hintCharacters: try c.decodeIfPresent(String.self, forKey: .hintCharacters) ?? "azeqsdwxc",
            confirmActionKey: try c.decodeIfPresent(String.self, forKey: .confirmActionKey) ?? "space",
            resetKey: try c.decodeIfPresent(String.self, forKey: .resetKey) ?? "r",
            backKey: try c.decodeIfPresent(String.self, forKey: .backKey) ?? "backspace",
            exitKey: try c.decodeIfPresent(String.self, forKey: .exitKey) ?? "escape",
            arrowNavigationEnabled: try c.decodeIfPresent(Bool.self, forKey: .arrowNavigationEnabled) ?? true,
            arrowEdgeBehavior: try c.decodeIfPresent(TargetGridArrowEdgeBehavior.self, forKey: .arrowEdgeBehavior) ?? .clamp,
            actionDelayMs: try c.decodeIfPresent(Int.self, forKey: .actionDelayMs) ?? 30,
            wakeMousePixels: try c.decodeIfPresent(Int.self, forKey: .wakeMousePixels) ?? 1,
            mouseFollowGrid: try c.decodeIfPresent(Bool.self, forKey: .mouseFollowGrid) ?? false,
            focusFollowGrid: try c.decodeIfPresent(Bool.self, forKey: .focusFollowGrid) ?? false,
            labelPlacement: try c.decodeIfPresent(TargetGridLabelPlacement.self, forKey: .labelPlacement) ?? .callout,
            defaultScope: try c.decodeIfPresent(TargetGridScope.self, forKey: .defaultScope) ?? .display,
            labelFontSize: try c.decodeFlexibleDouble(forKey: .labelFontSize) ?? 13
        )
    }

    /// Partagé avec `TargetModeConfig.searchHotkey` (SPEC-021).
    static func normalizedKey(_ value: String, fallback: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return fallback }
        let parts = cleaned.split(separator: "+").map(String.init).map { part in
            switch part {
            case "option":
                return "alt"
            case "cmd":
                return "command"
            case "ctrl":
                return "control"
            case "hyper":
                return "command+control+alt"
            case "esc":
                return "escape"
            case "delete":
                return "backspace"
            case "enter":
                return "return"
            default:
                return part
            }
        }
        return parts.joined(separator: "+")
    }
}

public struct TargetRecordConfig: Equatable, Codable, Sendable {
    public enum IndicatorMode: String, Codable, Equatable, Sendable {
        case notification
        case navrail
        case both
        case none

        public var showsNotification: Bool {
            self == .notification || self == .both
        }

        public var showsNavrail: Bool {
            self == .navrail || self == .both
        }
    }

    public var enabled: Bool
    public var replayEnabled: Bool
    public var directory: String
    public var defaultDurationSeconds: Double
    public var maxDurationSeconds: Double
    public var maxEvents: Int
    public var includeMouseMoves: Bool
    public var includeKeyEvents: Bool
    public var includeAXContext: Bool
    public var recordTextInput: Bool
    public var indicator: IndicatorMode
    public var navrailBottomOffset: Double

    public init(
        enabled: Bool = false,
        replayEnabled: Bool = false,
        directory: String = "~/.local/state/roadies/records",
        defaultDurationSeconds: Double = 10,
        maxDurationSeconds: Double = 120,
        maxEvents: Int = 2_000,
        includeMouseMoves: Bool = false,
        includeKeyEvents: Bool = true,
        includeAXContext: Bool = true,
        recordTextInput: Bool = false,
        indicator: IndicatorMode = .notification,
        navrailBottomOffset: Double = 50
    ) {
        self.enabled = enabled
        self.replayEnabled = replayEnabled
        self.directory = directory
        self.defaultDurationSeconds = min(maxDurationSeconds, max(0.5, defaultDurationSeconds))
        self.maxDurationSeconds = min(3_600, max(1, maxDurationSeconds))
        self.maxEvents = min(20_000, max(1, maxEvents))
        self.includeMouseMoves = includeMouseMoves
        self.includeKeyEvents = includeKeyEvents
        self.includeAXContext = includeAXContext
        self.recordTextInput = recordTextInput
        self.indicator = indicator
        self.navrailBottomOffset = min(400, max(0, navrailBottomOffset))
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case replayEnabled = "replay_enabled"
        case directory
        case defaultDurationSeconds = "default_duration_seconds"
        case maxDurationSeconds = "max_duration_seconds"
        case maxEvents = "max_events"
        case includeMouseMoves = "include_mouse_moves"
        case includeKeyEvents = "include_key_events"
        case includeAXContext = "include_ax_context"
        case recordTextInput = "record_text_input"
        case indicator
        case navrailBottomOffset = "navrail_bottom_offset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            replayEnabled: try c.decodeIfPresent(Bool.self, forKey: .replayEnabled) ?? false,
            directory: try c.decodeIfPresent(String.self, forKey: .directory) ?? "~/.local/state/roadies/records",
            defaultDurationSeconds: try c.decodeFlexibleDouble(forKey: .defaultDurationSeconds) ?? 10,
            maxDurationSeconds: try c.decodeFlexibleDouble(forKey: .maxDurationSeconds) ?? 120,
            maxEvents: try c.decodeIfPresent(Int.self, forKey: .maxEvents) ?? 2_000,
            includeMouseMoves: try c.decodeIfPresent(Bool.self, forKey: .includeMouseMoves) ?? false,
            includeKeyEvents: try c.decodeIfPresent(Bool.self, forKey: .includeKeyEvents) ?? true,
            includeAXContext: try c.decodeIfPresent(Bool.self, forKey: .includeAXContext) ?? true,
            recordTextInput: try c.decodeIfPresent(Bool.self, forKey: .recordTextInput) ?? false,
            indicator: try c.decodeIfPresent(IndicatorMode.self, forKey: .indicator) ?? .notification,
            navrailBottomOffset: try c.decodeFlexibleDouble(forKey: .navrailBottomOffset) ?? 50
        )
    }
}

public struct TitlebarContextMenuConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var height: Double
    public var leadingExclusion: Double
    public var trailingExclusion: Double
    public var managedWindowsOnly: Bool
    public var tileCandidatesOnly: Bool
    public var includeStageDestinations: Bool
    public var includeDesktopDestinations: Bool
    public var includeDisplayDestinations: Bool
    /// Double-clic sur la barre de titre : maximisation Roadie (SPEC-050). Actif seulement si
    /// l'action macOS de ce double-clic vaut « Ne rien faire ». Indépendant du menu par clic droit.
    public var doubleClickMaximize: Bool

    public init(
        enabled: Bool = false,
        height: Double = 36,
        leadingExclusion: Double = 84,
        trailingExclusion: Double = 16,
        managedWindowsOnly: Bool = true,
        tileCandidatesOnly: Bool = true,
        includeStageDestinations: Bool = true,
        includeDesktopDestinations: Bool = true,
        includeDisplayDestinations: Bool = true,
        doubleClickMaximize: Bool = false
    ) {
        self.doubleClickMaximize = doubleClickMaximize
        self.enabled = enabled
        self.height = height
        self.leadingExclusion = leadingExclusion
        self.trailingExclusion = trailingExclusion
        self.managedWindowsOnly = managedWindowsOnly
        self.tileCandidatesOnly = tileCandidatesOnly
        self.includeStageDestinations = includeStageDestinations
        self.includeDesktopDestinations = includeDesktopDestinations
        self.includeDisplayDestinations = includeDisplayDestinations
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case height
        case leadingExclusion = "leading_exclusion"
        case trailingExclusion = "trailing_exclusion"
        case managedWindowsOnly = "managed_windows_only"
        case tileCandidatesOnly = "tile_candidates_only"
        case includeStageDestinations = "include_stage_destinations"
        case includeDesktopDestinations = "include_desktop_destinations"
        case includeDisplayDestinations = "include_display_destinations"
        case doubleClickMaximize = "double_click_maximize"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            height: try c.decodeFlexibleDouble(forKey: .height) ?? 36,
            leadingExclusion: try c.decodeFlexibleDouble(forKey: .leadingExclusion) ?? 84,
            trailingExclusion: try c.decodeFlexibleDouble(forKey: .trailingExclusion) ?? 16,
            managedWindowsOnly: try c.decodeIfPresent(Bool.self, forKey: .managedWindowsOnly) ?? true,
            tileCandidatesOnly: try c.decodeIfPresent(Bool.self, forKey: .tileCandidatesOnly) ?? true,
            includeStageDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeStageDestinations) ?? true,
            includeDesktopDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeDesktopDestinations) ?? true,
            includeDisplayDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeDisplayDestinations) ?? true,
            doubleClickMaximize: try c.decodeIfPresent(Bool.self, forKey: .doubleClickMaximize) ?? false
        )
    }
}

public enum RoadieConfigLoader {
    /// Clés qui sont des listes ou des tableaux de tables : hors du catalogue de réglages scalaires (SPEC-023).
    private static let nonScalarKeys: [String: Set<String>] = [
        "tiling": ["display_overrides", "smart_gaps_solo_sides", "allowed_subroles"],
        "stage_manager": ["workspaces"],
        "exclusions": ["floating_bundles"],
        "fx.borders": ["stage_overrides"],
        "width_adjustment": ["presets"],
        "experimental.app_targets": ["include_roles", "additional_boost_bundle_ids"],
        "experimental.target_mode": ["web_searches", "fallback_searches", "bookmark_browsers", "app_search_paths", "btt_pause_keys"],
        "switcher": ["excluded_bundles", "shortcuts"]
    ]

    /// Tables qui sont elles-mêmes des tableaux de tables ou leurs sous-tables.
    private static let nonScalarTables: Set<String> = [
        "tiling.display_overrides", "stage_manager.workspaces", "fx.borders.stage_overrides",
        "fx.rail.preview.stage_overrides", "switcher.shortcuts", "experimental.target_mode.web_searches", "rules", "rules.match", "rules.action",
        "shortcuts"
    ]

    /// Clés scalaires reconnues par le validateur, par chemin de table TOML complet.
    /// Les tables sans clé scalaire sont omises. Complexité : O(k) — k nombre de clés connues.
    public static func knownScalarKeys() -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for (table, keys) in ConfigValidationRules.knownKeys where !nonScalarTables.contains(table) {
            let scalars = keys.subtracting(nonScalarKeys[table] ?? [])
            if !scalars.isEmpty { result[table] = scalars }
        }
        return result
    }

    /// Clés décodées mais lues nulle part dans le daemon, par chemin de table.
    public static func ineffectiveKeys() -> [String: Set<String>] {
        ConfigValidationRules.ineffectiveKeys
    }

    /// Distance de Levenshtein, partagée avec le validateur (aucune seconde implémentation).
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        ConfigValidationRules.editDistance(lhs, rhs)
    }

    public static func defaultConfigPath() -> String {
        (NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath as String)
    }

    public static func generatedRulesPath(for path: String? = nil) -> String {
        let resolved = path ?? defaultConfigPath()
        let url = URL(fileURLWithPath: NSString(string: resolved).expandingTildeInPath)
        let filename = url.deletingPathExtension().lastPathComponent + ".generated.toml"
        return url.deletingLastPathComponent().appendingPathComponent(filename).path
    }

    public static func load(from path: String? = nil) throws -> RoadieConfig {
        let resolved = path ?? defaultConfigPath()
        var config = RoadieConfig()
        if FileManager.default.fileExists(atPath: resolved) {
            let raw = try String(contentsOfFile: resolved, encoding: .utf8)
            config = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
        }
        config.rules.append(contentsOf: try generatedRules(from: generatedRulesPath(for: resolved)))
        return config
    }

    public static func validate(path: String? = nil) -> ConfigValidationReport {
        let resolved = path ?? defaultConfigPath()
        let generatedPath = generatedRulesPath(for: resolved)
        var items: [ConfigValidationItem] = []
        guard FileManager.default.fileExists(atPath: resolved) else {
            items.append(
                ConfigValidationItem(level: .warning, path: resolved, message: "config file not found; defaults will be used")
            )
            items.append(contentsOf: validateGeneratedRules(path: generatedPath))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: "config is valid"))
            }
            return ConfigValidationReport(items: items)
        }

        var raw = ""
        do {
            raw = try String(contentsOfFile: resolved, encoding: .utf8)
            _ = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
            items.append(contentsOf: ConfigValidationRules.validate(rawToml: raw))
            items.append(contentsOf: validateGeneratedRules(path: generatedPath))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: "config is valid"))
            }
            return ConfigValidationReport(items: items)
        } catch {
            return ConfigValidationReport(items: [
                ConfigValidationItem(level: .error, path: resolved, message: ConfigValidationRules.describe(decodeError: error, rawToml: raw))
            ])
        }
    }

    public static func loadRulesFile(from path: String) throws -> [WindowRule] {
        try generatedRules(from: path)
    }

    private static func generatedRules(from path: String) throws -> [WindowRule] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        return try TOMLDecoder().decode(RoadieConfig.self, from: raw).rules
    }

    private static func validateGeneratedRules(path: String) -> [ConfigValidationItem] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var raw = ""
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
            _ = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
            return ConfigValidationRules.validateGeneratedRules(rawToml: raw, path: path)
        } catch {
            return [
                ConfigValidationItem(level: .error, path: path, message: ConfigValidationRules.describe(decodeError: error, rawToml: raw))
            ]
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
        "interface",
        "tiling",
        "desktops",
        "stage_manager",
        "stage_manager.workspaces",
        "tiling.display_overrides",
        "exclusions",
        "fx",
        "fx.borders",
        "fx.borders.stage_overrides",
        // Tables lues par RailSettings (Sources/RoadieDaemon/RailSettings.swift).
        "fx.rail",
        "fx.rail.layout",
        "fx.rail.header",
        "fx.rail.header.display",
        "fx.rail.header.desktop",
        "fx.rail.stages",
        "fx.rail.preview",
        "fx.rail.preview.stage_overrides",
        "fx.rail.stacked",
        "fx.rail.stage_labels",
        "fx.rail.parallax",
        "focus",
        "window_placement",
        "width_adjustment",
        "overview",
        "switcher",
        "switcher.shortcuts",
        "experimental",
        "experimental.titlebar_context_menu",
        "experimental.target_mode",
        "experimental.target_mode.web_searches",
        "experimental.app_targets",
        "experimental.target_grid",
        "experimental.target_record",
        "rules",
        "rules.match",
        "rules.action",
        "shortcuts"
    ]

    private static let knownUnsupportedTables: Set<String> = [
        "daemon",
        "mouse",
        "scratchpads",
        "sticky",
        "signals",
        "signals.hooks",
        "fx.animations",
        "fx.opacity",
        "fx.opacity.stage_hide"
    ]

    /// Clés réellement lues, par table. Une table absente de ce dictionnaire n'est pas vérifiée.
    /// Source : les `CodingKeys` de ce fichier, `WindowRule.swift` et `RailSettings.swift`.
    static let knownKeys: [String: Set<String>] = {
        let labelKeys: Set<String> = ["enabled", "template", "color", "font_size", "font_family", "weight", "alignment", "opacity", "offset_x", "offset_y"]
        let gapKeys: Set<String> = ["gaps_outer", "gaps_outer_top", "gaps_outer_right", "gaps_outer_bottom", "gaps_outer_left"]
        return [
            "": [],
            "fx": [],
            "interface": ["settings_text_font_size", "settings_help_font_size", "settings_title_font_size"],
            "tiling": gapKeys.union(["default_strategy", "split_policy", "resize_handles", "display_overrides", "gaps_inner", "master_ratio", "smart_gaps_solo", "smart_gaps_solo_sides", "allowed_subroles", "popup_filter"]),
            "tiling.display_overrides": gapKeys.union(["display_id", "display_name"]),
            "desktops": ["enabled", "count", "back_and_forth", "mode"],
            "stage_manager": ["enabled", "hide_strategy", "default_stage", "workspaces"],
            "stage_manager.workspaces": ["id", "display_name"],
            "exclusions": ["floating_bundles"],
            "fx.borders": ["enabled", "thickness", "corner_radius", "active_color", "inactive_color", "pulse_on_focus", "stage_overrides"],
            "fx.borders.stage_overrides": ["stage_id", "active_color"],
            "fx.rail": ["renderer", "width", "background_color", "background_opacity", "auto_hide", "edge_hit_width", "edge_magnetism_width", "animation_ms", "hide_delay_ms", "layout_mode", "dynamic_left_gap", "empty_click_hide_active", "empty_click_safety_margin", "hide_on_maximized"],
            "fx.rail.layout": ["header_position", "stages_position", "spacing", "top_padding", "bottom_padding"],
            "fx.rail.header": ["enabled", "placement", "alignment", "top_padding", "bottom_padding", "height", "width", "title_color", "subtitle_color", "title_font_size", "subtitle_font_size", "font_family", "title_weight", "subtitle_weight", "title_template", "subtitle_template"],
            "fx.rail.header.display": labelKeys,
            "fx.rail.header.desktop": labelKeys,
            "fx.rail.stage_labels": ["enabled", "color", "font_size", "font_family", "weight", "alignment", "opacity", "offset_x", "offset_y", "placement", "z_order", "visibility_seconds", "fade_seconds", "caption_font_size", "gap", "follows_perspective"],
            "fx.rail.stages": ["position", "alignment", "gap", "slot_height", "reorder_magnetism"],
            "fx.rail.preview": ["width", "height", "leading_padding", "trailing_padding", "vertical_padding"],
            "fx.rail.preview.stage_overrides": ["stage_id", "active_color"],
            "fx.rail.stacked": ["offset_x", "offset_y", "scale_per_layer", "opacity_per_layer"],
            "fx.rail.parallax": ["rotation", "offset_x", "offset_y", "scale_per_layer", "opacity_per_layer", "darken_per_layer", "width", "height", "leading_padding", "trailing_padding", "vertical_padding"],
            "focus": ["stage_follows_focus", "assign_follows_focus", "stage_move_follows_focus", "focus_follows_mouse", "mouse_follows_focus"],
            "window_placement": ["new_apps_target", "new_window_side"],
            "width_adjustment": ["presets", "nudge_step", "minimum_ratio", "maximum_ratio"],
            "overview": ["enabled", "presentation", "loupe", "magnification", "hotkey", "background_blur", "selection_color", "selection_width"],
            "switcher": ["enabled", "presentation", "style", "auto_size", "thumbnail_width", "font_size", "font_family", "preview", "excluded_bundles", "shortcuts"],
            "experimental.target_mode.web_searches": ["keyword", "title", "url"],
            "switcher.shortcuts": ["id", "name", "hotkey", "scope", "release_action", "sort_order", "include_minimized", "include_hidden", "include_fullscreen", "one_per_app", "enabled", "trigger_source", "search_visibility", "actions_visibility", "arrow_navigation", "mouse_hover", "btt_forward_uuid", "btt_reverse_uuid", "presentation", "style", "preview", "auto_size", "thumbnail_width", "font_size", "font_family"],
            "experimental": [],
            "experimental.titlebar_context_menu": ["enabled", "height", "leading_exclusion", "trailing_exclusion", "managed_windows_only", "tile_candidates_only", "include_stage_destinations", "include_desktop_destinations", "include_display_destinations", "double_click_maximize"],
            "experimental.target_mode": Set<String>(["enabled", "picker_enabled", "overlay_enabled", "overlay_labels_only", "overlay_duration_seconds", "app_mouse_actions_enabled", "scroll_mode_enabled", "search_hotkey", "actions_hotkey", "web_search_url", "pick_modifier", "workflows_enabled", "alfred_workflows", "web_searches", "fallback_searches", "idle_frequent_enabled", "idle_frequent_count", "idle_recent_searches_enabled", "idle_recent_searches_count", "view_cycle_hotkey", "label_font_size", "search_label_font_size", "search_text_font_size", "command_text_font_size", "search_font_family", "command_font_family", "theme", "theme_dark", "visible_results", "bar_screen", "bar_position", "bar_save_position", "terminal_app", "bookmarks_enabled", "bookmark_browsers", "app_search_paths", "learning_enabled", "path_sort", "confirm_quit_all", "calc_opens_calculator", "learn_verb_order", "content_search_keyword", "tag_search_keyword", "btt_pause_keys"]).union(LauncherBarKeys.actions.map(\.configKey)),
            "experimental.app_targets": ["enabled", "scope", "max_targets", "timeout_ms", "hint_characters", "include_roles", "ax_boost_enabled", "max_depth", "additional_boost_bundle_ids"],
            "experimental.target_grid": ["enabled", "mode", "overlay_enabled", "overlay_draw_grid", "overlay_fill_color", "overlay_fill_opacity", "overlay_border_color", "overlay_border_opacity", "overlay_label_color", "overlay_label_background_opacity", "rows", "columns", "max_depth", "hint_characters", "confirm_action_key", "reset_key", "back_key", "exit_key", "arrow_navigation_enabled", "arrow_edge_behavior", "action_delay_ms", "wake_mouse_pixels", "mouse_follow_grid", "focus_follow_grid", "label_placement", "default_scope", "label_font_size"],
            "experimental.target_record": ["enabled", "replay_enabled", "directory", "default_duration_seconds", "max_duration_seconds", "max_events", "include_mouse_moves", "include_key_events", "include_ax_context", "record_text_input", "indicator", "navrail_bottom_offset"],
            "rules": ["id", "enabled", "priority", "stop_processing", "match", "action"],
            "shortcuts": ["keys", "command", "enabled", "btt_uuid"],
            "rules.match": ["app", "app_regex", "title", "title_regex", "role", "subrole", "display", "desktop", "stage", "is_floating"],
            "rules.action": ["manage", "exclude", "assign_desktop", "assign_display", "assign_stage", "follow", "floating", "layout", "gap_override", "scratchpad", "emit_event"]
        ]
    }()

    /// Clés décodées mais lues nulle part dans le daemon (vérifié par recherche dans `Sources/`).
    static let ineffectiveKeys: [String: Set<String>] = [
        "desktops": ["enabled", "count", "back_and_forth", "mode"],
        "stage_manager": ["enabled", "hide_strategy"],
        // Anciennes clés d'en-tête du rail : sans effet, la hauteur dépend des tailles de police.
        "fx.rail.header": ["height", "width"]
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
                    message: "table inconnue, ignorée" + suggestionSuffix(for: table, among: supportedTables.union(knownUnsupportedTables))
                ))
            }
        }
        if let root = try? TOMLTable(string: rawToml) {
            items.append(contentsOf: keyChecks(in: root, path: ""))
        }
        if let config = try? TOMLDecoder().decode(RoadieConfig.self, from: rawToml) {
            if config.widthAdjustment.presets.isEmpty {
                items.append(ConfigValidationItem(level: .error, path: "width_adjustment.presets", message: "must contain at least one ratio"))
            }
            if config.widthAdjustment.minimumRatio > config.widthAdjustment.maximumRatio {
                items.append(ConfigValidationItem(level: .error, path: "width_adjustment.minimum_ratio", message: "must be lower than or equal to maximum_ratio"))
            }
            items.append(contentsOf: validateTitlebarContextMenu(config.experimental.titlebarContextMenu))
            items.append(contentsOf: validateTargetMode(config.experimental.targetMode))
            if !config.overview.hotkey.isEmpty, TargetModeConfig.hotkeyParts(config.overview.hotkey) == nil {
                items.append(ConfigValidationItem(level: .error, path: "overview.hotkey", message: "expected modifiers and one key; empty disables"))
            }
            items.append(contentsOf: validateAppTargets(config.experimental.appTargets))
            items.append(contentsOf: validateTargetGrid(config.experimental.targetGrid))
            items.append(contentsOf: validateTargetRecord(config.experimental.targetRecord))
        }
        return items
    }

    static func validateGeneratedRules(rawToml: String, path: String) -> [ConfigValidationItem] {
        tableNames(in: rawToml).sorted().compactMap { table in
            guard ["rules", "rules.match", "rules.action"].contains(table) else {
                return ConfigValidationItem(
                    level: .warning,
                    path: "\(path):\(table)",
                    message: "generated rules file should only contain [[rules]] tables"
                )
            }
            return nil
        }
    }

    /// Signale les clés inconnues (avec suggestion) et les clés sans effet.
    /// Complexité : O(k * c * l²) — k clés du fichier, c candidats de la table (≤ 30), l longueur d'un nom (≤ 40).
    private static func keyChecks(in table: TOMLTable, path: String) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        let known = knownKeys[path]
        for key in table.keys.sorted() {
            guard let value = table[key] else { continue }
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let child = value.table {
                items.append(contentsOf: keyChecks(in: child, path: childPath))
            } else if let array = value.array, array.count > 0, array.allSatisfy({ $0.table != nil }) {
                for element in array {
                    if let child = element.table {
                        items.append(contentsOf: keyChecks(in: child, path: childPath))
                    }
                }
            } else if let known {
                if ineffectiveKeys[path]?.contains(key) == true {
                    items.append(ConfigValidationItem(
                        level: .warning,
                        path: childPath,
                        message: "clé sans effet : roadie ne la lit pas"
                    ))
                } else if !known.contains(key) {
                    items.append(ConfigValidationItem(
                        level: .warning,
                        path: childPath,
                        message: "clé inconnue, ignorée" + suggestionSuffix(for: key, among: known)
                    ))
                }
            }
        }
        return items
    }

    private static func suggestionSuffix(for name: String, among candidates: Set<String>) -> String {
        guard let best = closest(to: name, among: candidates) else { return "" }
        return " ; vouliez-vous dire « \(best) » ?"
    }

    /// Candidat le plus proche par distance d'édition, à 2 modifications au plus (1 pour un nom court).
    private static func closest(to name: String, among candidates: Set<String>) -> String? {
        let limit = name.count <= 4 ? 1 : 2
        return candidates
            .map { (candidate: $0, distance: editDistance(name, $0)) }
            .filter { $0.distance <= limit }
            .min { ($0.distance, $0.candidate) < ($1.distance, $1.candidate) }?
            .candidate
    }

    /// Distance de Levenshtein. Complexité : O(a * b) en temps, O(b) en mémoire.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Traduit une erreur de décodage en message lisible : `table.clé : attendu X, reçu Y`.
    static func describe(decodeError error: Error, rawToml: String) -> String {
        if let parseError = error as? TOMLParseError {
            let begin = parseError.source.begin
            return "syntaxe TOML invalide (ligne \(begin.line), colonne \(begin.column)) : \(parseError.description)"
        }
        guard let decodingError = error as? DecodingError else { return "\(error)" }
        let context: DecodingError.Context
        var expected: String?
        switch decodingError {
        case .typeMismatch(let type, let ctx), .valueNotFound(let type, let ctx):
            context = ctx
            expected = expectedName("\(type)")
        case .keyNotFound(_, let ctx):
            context = ctx
            // TOMLKit : `A "String" does not exist at ...`
            let parts = ctx.debugDescription.split(separator: "\"", omittingEmptySubsequences: false)
            expected = parts.count > 1 ? expectedName(String(parts[1])) : nil
        case .dataCorrupted(let ctx):
            context = ctx
        @unknown default:
            return "\(error)"
        }
        let path = displayPath(context.codingPath)
        let received = (try? TOMLTable(string: rawToml)).flatMap { rawValue(at: context.codingPath, in: $0) }
        var message = path.isEmpty ? "" : "\(path) : "
        switch (expected, received) {
        case (let expected?, let received?):
            message += "attendu \(expected), reçu \(receivedName(received.type))"
        case (let expected?, nil):
            message += "clé obligatoire absente (attendu \(expected))"
        default:
            message += context.debugDescription
        }
        return message
    }

    private static func displayPath(_ codingPath: [CodingKey]) -> String {
        codingPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    private static func rawValue(at codingPath: [CodingKey], in root: TOMLTable) -> TOMLValueConvertible? {
        var current: TOMLValueConvertible = root
        for key in codingPath {
            if let index = key.intValue {
                guard let array = current.array, index >= 0, index < array.count else { return nil }
                current = array[index]
            } else {
                guard let next = current.table?[key.stringValue] else { return nil }
                current = next
            }
        }
        return current
    }

    private static func expectedName(_ swiftType: String) -> String {
        switch swiftType {
        case "String": return "texte"
        case "Bool": return "booléen"
        case "Double": return "nombre"
        case "Int": return "entier"
        default: return swiftType
        }
    }

    private static func receivedName(_ type: TOMLType) -> String {
        switch type {
        case .string: return "texte"
        case .bool: return "booléen"
        case .double: return "nombre"
        case .int: return "entier"
        case .table: return "table"
        case .array: return "tableau"
        case .date, .time, .dateTime: return "date"
        }
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

    private static func validateTitlebarContextMenu(_ config: TitlebarContextMenuConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.height < 12 || config.height > 96 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.height",
                message: "must be between 12 and 96"
            ))
        }
        if config.leadingExclusion < 0 || config.leadingExclusion > 240 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.leading_exclusion",
                message: "must be between 0 and 240"
            ))
        }
        if config.trailingExclusion < 0 || config.trailingExclusion > 240 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.trailing_exclusion",
                message: "must be between 0 and 240"
            ))
        }
        if config.enabled &&
            !config.includeStageDestinations &&
            !config.includeDesktopDestinations &&
            !config.includeDisplayDestinations {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.titlebar_context_menu",
                message: "all destination families are disabled; menu will not be shown"
            ))
        }
        return items
    }

    private static func validateTargetMode(_ config: TargetModeConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.overlayDurationSeconds < 0.2 || config.overlayDurationSeconds > 30 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.overlay_duration_seconds",
                message: "must be between 0.2 and 30"
            ))
        }
        if !config.enabled &&
            (config.pickerEnabled || config.overlayEnabled || config.appMouseActionsEnabled || config.scrollModeEnabled) {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_mode",
                message: "target mode is disabled; sub-features will be ignored"
            ))
        }
        if !config.searchHotkey.isEmpty, TargetModeConfig.hotkeyParts(config.searchHotkey) == nil {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.search_hotkey",
                message: "expected modifiers and one key, e.g. \"cmd+alt+ctrl+f\" or \"hyper+f\"; empty disables"
            ))
        }
        if !config.actionsHotkey.isEmpty, TargetModeConfig.hotkeyParts(config.actionsHotkey) == nil {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.actions_hotkey",
                message: "expected modifiers and one key, e.g. \"hyper+shift+f\"; empty disables"
            ))
        }
        if !config.webSearchURL.contains("{query}") || URL(string: config.webSearchURL.replacingOccurrences(of: "{query}", with: "q")) == nil {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_mode.web_search_url",
                message: "expected an address containing {query}"
            ))
        }
        return items
    }

    private static func validateAppTargets(_ config: AppTargetsConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if !AppTargetsConfig.scopes.contains(config.scope) {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.app_targets.scope",
                message: "supported scopes: frontmost_window, visible_windows"
            ))
        }
        if config.hintCharacters.count < 2 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.app_targets.hint_characters",
                message: "must contain at least two characters"
            ))
        }
        if config.includeRoles.isEmpty {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.app_targets.include_roles",
                message: "must contain at least one AX role"
            ))
        }
        return items
    }

    private static func validateTargetGrid(_ config: TargetGridConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.hintCharacters.count < config.rows * config.columns {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_grid.hint_characters",
                message: "must contain at least rows*columns characters"
            ))
        }
        return items
    }

    private static func validateTargetRecord(_ config: TargetRecordConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.defaultDurationSeconds > config.maxDurationSeconds {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_record.default_duration_seconds",
                message: "must be lower than or equal to max_duration_seconds"
            ))
        }
        if config.replayEnabled && !config.enabled {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_record.replay_enabled",
                message: "replay is enabled but recording capability is disabled"
            ))
        }
        return items
    }
}

private extension WindowManagementMode {
    /// La config n'a pas d'état : `mutableBsp` et `yabai` y désignent directement l'unique
    /// moteur à arbre `spatialBsp` (SPEC-017 R1, A8).
    init?(tomlValue: String) {
        guard let mode = WindowManagementMode(roadieValue: tomlValue) else {
            return nil
        }
        self = mode == .mutableBsp ? .spatialBsp : mode
    }
}

extension KeyedDecodingContainer {
    /// Accepte un nombre décimal ou un entier TOML. Clé absente : `nil` (le défaut s'applique).
    /// Autre type (booléen, texte, tableau) : l'erreur de décodage est propagée, jamais remplacée
    /// par le défaut (REL-011).
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        let value: Double?
        do {
            value = try decodeIfPresent(Double.self, forKey: key)
        } catch {
            guard let integer = try? decodeIfPresent(Int.self, forKey: key) else { throw error }
            value = Double(integer)
        }
        // TOML autorise nan/inf, mais les cadres AX et les exports JSON exigent un nombre fini.
        guard value?.isFinite != false else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a finite number")
        }
        return value
    }
}
