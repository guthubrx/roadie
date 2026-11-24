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
    /// Historique local sécurisé du presse-papiers (Spec 163).
    public var clipboard: ClipboardConfig
    /// Snippets locaux et expandeur optionnel (Spec 163).
    public var snippets: SnippetsConfig

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
        shortcuts: [CommandShortcut] = [],
        clipboard: ClipboardConfig = ClipboardConfig(),
        snippets: SnippetsConfig = SnippetsConfig()
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
        self.clipboard = clipboard
        self.snippets = snippets
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
        switcher: WindowSwitcherConfig = WindowSwitcherConfig(),
        clipboard: ClipboardConfig = ClipboardConfig(),
        snippets: SnippetsConfig = SnippetsConfig()
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
            switcher: switcher,
            clipboard: clipboard,
            snippets: snippets
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
        case clipboard
        case snippets
    }

    // Alias public ; le modèle interne et les anciens fichiers restent compatibles.
    private enum LauncherKeys: String, CodingKey { case launcher }

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
        self.clipboard = try c.decodeIfPresent(ClipboardConfig.self, forKey: .clipboard) ?? ClipboardConfig()
        self.snippets = try c.decodeIfPresent(SnippetsConfig.self, forKey: .snippets) ?? SnippetsConfig()
        let launcher = try decoder.container(keyedBy: LauncherKeys.self)
        if launcher.contains(.launcher) {
            self.experimental.targetMode = try TargetModeConfig(
                container: launcher.nestedContainer(keyedBy: TargetModeConfig.CodingKeys.self, forKey: .launcher),
                barKeys: TargetModeConfig.decodeBarKeys(launcher.nestedContainer(keyedBy: TargetModeConfig.AnyKey.self, forKey: .launcher)),
                defaults: self.experimental.targetMode
            )
        }
    }
}

/// Polices de la fenêtre de réglages. Les autres surfaces gardent leurs tailles indépendantes.
public struct InterfaceConfig: Equatable, Codable, Sendable {
    public var settingsTextFontSize: Double
    public var settingsHelpFontSize: Double
    public var settingsTitleFontSize: Double
    /// Langue de l'interface (session 127) : `auto` (langue de macOS), `fr` ou `en`. Lue au lancement.
    public var language: String

    public init(settingsTextFontSize: Double = 16, settingsHelpFontSize: Double = 14, settingsTitleFontSize: Double = 22,
                language: String = "auto") {
        self.settingsTextFontSize = min(32, max(8, settingsTextFontSize))
        self.settingsHelpFontSize = min(32, max(8, settingsHelpFontSize))
        self.settingsTitleFontSize = min(48, max(10, settingsTitleFontSize))
        self.language = ["auto", "fr", "en"].contains(language) ? language : "auto"
    }

    enum CodingKeys: String, CodingKey {
        case settingsTextFontSize = "settings_text_font_size"
        case settingsHelpFontSize = "settings_help_font_size"
        case settingsTitleFontSize = "settings_title_font_size"
        case language
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            settingsTextFontSize: try c.decodeFlexibleDouble(forKey: .settingsTextFontSize) ?? 16,
            settingsHelpFontSize: try c.decodeFlexibleDouble(forKey: .settingsHelpFontSize) ?? 14,
            settingsTitleFontSize: try c.decodeFlexibleDouble(forKey: .settingsTitleFontSize) ?? 22,
            language: try c.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        )
    }
}

public enum WindowGestureModifier: String, Codable, CaseIterable, Sendable {
    case disabled = ""
    case control, option, command, shift
    case controlOption = "control+option"
    case controlCommand = "control+command"
    case optionCommand = "option+command"
    case controlShift = "control+shift"
    case optionShift = "option+shift"
    case commandShift = "command+shift"
    case controlOptionCommand = "control+option+command"
    case controlOptionShift = "control+option+shift"
    case controlCommandShift = "control+command+shift"
    case optionCommandShift = "option+command+shift"
    case all = "control+option+command+shift"

    public var mask: UInt64 {
        rawValue.split(separator: "+").reduce(0) { value, token in
            value | ["control": UInt64(1 << 18), "option": 1 << 19,
                     "command": 1 << 20, "shift": 1 << 17][String(token), default: 0]
        }
    }

    public var symbols: String {
        rawValue.split(separator: "+").map { ["control": "⌃", "option": "⌥", "command": "⌘", "shift": "⇧"][String($0)] ?? "" }.joined()
    }
}

public struct TilingConfig: Equatable, Codable, Sendable {
    public var defaultStrategy: WindowManagementMode
    public var splitPolicy: String
    /// Poignées dans les séparations des stages utilisant l'arbre persistant.
    public var resizeHandles: Bool
    /// Déplace les voisines vers les places du dépôt pendant le glisser.
    public var liveDragPreview: Bool
    public var dragMoveModifier: WindowGestureModifier
    public var dragResizeModifier: WindowGestureModifier
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
    /// Quand true (defaut), laisse flotter automatiquement les fenetres Picture-in-Picture (Spec 157).
    public var floatPictureInPicture: Bool
    /// Quand true (defaut), active le scratchpad flottant nommé (`roadie scratchpad`, Spec 162).
    public var scratchpadEnabled: Bool
    /// Hauteur réservée en haut de la stage pour la barre d'onglets en mode `.tabbed` (`20...44`, Spec 164).
    public var tabbedBarHeight: Double
    /// Largeur d'une colonne en mode `.scrolling`, en proportion de la largeur utile (`0.25...1.0`, Spec 164).
    public var scrollingColumnWidth: Double

    public init(
        defaultStrategy: WindowManagementMode = .bsp,
        splitPolicy: String = "largest_dim",
        resizeHandles: Bool = true,
        liveDragPreview: Bool = true,
        dragMoveModifier: WindowGestureModifier = .control,
        dragResizeModifier: WindowGestureModifier = .controlOption,
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
        popupFilter: Bool = true,
        floatPictureInPicture: Bool = true,
        scratchpadEnabled: Bool = true,
        tabbedBarHeight: Double = 28,
        scrollingColumnWidth: Double = 0.65
    ) {
        self.defaultStrategy = defaultStrategy
        self.splitPolicy = splitPolicy
        self.resizeHandles = resizeHandles
        self.liveDragPreview = liveDragPreview
        self.dragMoveModifier = dragMoveModifier
        self.dragResizeModifier = dragResizeModifier
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
        self.floatPictureInPicture = floatPictureInPicture
        self.scratchpadEnabled = scratchpadEnabled
        self.tabbedBarHeight = tabbedBarHeight.isFinite ? min(44, max(20, tabbedBarHeight)) : 28
        self.scrollingColumnWidth = scrollingColumnWidth.isFinite ? min(1.0, max(0.25, scrollingColumnWidth)) : 0.65
    }

    enum CodingKeys: String, CodingKey {
        case defaultStrategy = "default_strategy"
        case splitPolicy = "split_policy"
        case resizeHandles = "resize_handles"
        case liveDragPreview = "live_drag_preview"
        case dragMoveModifier = "drag_move_modifier"
        case dragResizeModifier = "drag_resize_modifier"
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
        case floatPictureInPicture = "float_picture_in_picture"
        case scratchpadEnabled = "scratchpad_enabled"
        case tabbedBarHeight = "tabbed_bar_height"
        case scrollingColumnWidth = "scrolling_column_width"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStrategy = try c.decodeIfPresent(String.self, forKey: .defaultStrategy) ?? "bsp"
        // Clé absente : bsp. Valeur présente mais inconnue : erreur lisible, jamais un repli silencieux (REL-034).
        guard let strategy = WindowManagementMode(tomlValue: rawStrategy) else {
            throw DecodingError.dataCorruptedError(
                forKey: .defaultStrategy,
                in: c,
                debugDescription: tr("default_strategy inconnu : \"\(rawStrategy)\" (attendu : bsp, mutableBsp, masterStack, tabbed, scrolling, float, spatialBsp ou un alias)", "unknown default_strategy: \"\(rawStrategy)\" (expected: bsp, mutableBsp, masterStack, tabbed, scrolling, float, spatialBsp or an alias)")
            )
        }
        self.defaultStrategy = strategy
        self.splitPolicy = try c.decodeIfPresent(String.self, forKey: .splitPolicy) ?? "largest_dim"
        self.resizeHandles = try c.decodeIfPresent(Bool.self, forKey: .resizeHandles) ?? true
        self.liveDragPreview = try c.decodeIfPresent(Bool.self, forKey: .liveDragPreview) ?? true
        self.dragMoveModifier = try c.decodeIfPresent(WindowGestureModifier.self, forKey: .dragMoveModifier) ?? .control
        self.dragResizeModifier = try c.decodeIfPresent(WindowGestureModifier.self, forKey: .dragResizeModifier) ?? .controlOption
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
        self.floatPictureInPicture = try c.decodeIfPresent(Bool.self, forKey: .floatPictureInPicture) ?? true
        self.scratchpadEnabled = try c.decodeIfPresent(Bool.self, forKey: .scratchpadEnabled) ?? true
        let rawTabHeight = try c.decodeFlexibleDouble(forKey: .tabbedBarHeight) ?? 28
        self.tabbedBarHeight = min(44, max(20, rawTabHeight))
        let rawColWidth = try c.decodeFlexibleDouble(forKey: .scrollingColumnWidth) ?? 0.65
        self.scrollingColumnWidth = min(1.0, max(0.25, rawColWidth))
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
    /// Fenêtres toujours flottantes, par application et titre (session 125).
    public var floatingWindows: [FloatingWindowConfig]
    /// Session 132 : une fenêtre flottante qui apparaît sur le rail est décalée à sa droite.
    public var floatingAvoidRail: Bool

    public init(floatingBundles: [String] = [], floatingWindows: [FloatingWindowConfig] = [], floatingAvoidRail: Bool = true) {
        self.floatingBundles = floatingBundles
        self.floatingWindows = floatingWindows
        self.floatingAvoidRail = floatingAvoidRail
    }

    enum CodingKeys: String, CodingKey {
        case floatingBundles = "floating_bundles"
        case floatingWindows = "floating_windows"
        case floatingAvoidRail = "floating_avoid_rail"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.floatingBundles = try c.decodeIfPresent([String].self, forKey: .floatingBundles) ?? []
        self.floatingWindows = try c.decodeIfPresent([FloatingWindowConfig].self, forKey: .floatingWindows) ?? []
        self.floatingAvoidRail = try c.decodeIfPresent(Bool.self, forKey: .floatingAvoidRail) ?? true
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

/// Assombrissement des fenêtres inactives (`[fx.dim_inactive]`, Spec 162).
public struct DimInactiveConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    /// Opacité du voile sombre sur les fenêtres inactives, bornée dans `0.05...0.75`.
    public var opacity: Double

    public init(enabled: Bool = false, opacity: Double = 0.22) {
        self.enabled = enabled
        self.opacity = opacity.isFinite ? min(0.75, max(0.05, opacity)) : 0.22
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case opacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let opacity = try c.decodeFlexibleDouble(forKey: .opacity) ?? 0.22
        guard opacity.isFinite, (0.05...0.75).contains(opacity) else {
            throw DecodingError.dataCorruptedError(forKey: .opacity, in: c, debugDescription: "fx.dim_inactive.opacity must be between 0.05 and 0.75")
        }
        self.init(enabled: enabled, opacity: opacity)
    }
}

public struct EffectsConfig: Equatable, Codable, Sendable {
    public var borders: BorderConfig
    public var animations: AnimationsConfig
    public var dimInactive: DimInactiveConfig
    public var dropPreview: String
    public var dragPreview: String = "content"
    public var dragPreviewOpacityPercent: Double = 85
    public var dragPreviewScalePercent: Double = 50

    public init(borders: BorderConfig = BorderConfig(), dimInactive: DimInactiveConfig = DimInactiveConfig()) {
        self.borders = borders
        self.animations = AnimationsConfig()
        self.dimInactive = dimInactive
        self.dropPreview = "contour"
    }

    public init(borders: BorderConfig = BorderConfig(), animations: AnimationsConfig, dropPreview: String = "contour", dimInactive: DimInactiveConfig = DimInactiveConfig()) {
        self.borders = borders
        self.animations = animations
        self.dimInactive = dimInactive
        self.dropPreview = dropPreview
    }

    // `borders` est facultatif : `[fx.rail]` seul est une configuration valide.
    enum CodingKeys: String, CodingKey {
        case borders, animations
        case dimInactive = "dim_inactive"
        case dropPreview = "drop_preview"
        case dragPreview = "drag_preview"
        case dragPreviewOpacityPercent = "drag_preview_opacity_percent"
        case dragPreviewScalePercent = "drag_preview_scale_percent"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.borders = try c.decodeIfPresent(BorderConfig.self, forKey: .borders) ?? BorderConfig()
        self.animations = try c.decodeIfPresent(AnimationsConfig.self, forKey: .animations) ?? AnimationsConfig()
        self.dimInactive = try c.decodeIfPresent(DimInactiveConfig.self, forKey: .dimInactive) ?? DimInactiveConfig()
        self.dropPreview = try c.decodeIfPresent(String.self, forKey: .dropPreview) ?? "contour"
        dragPreview = try c.decodeIfPresent(String.self, forKey: .dragPreview) ?? "content"
        dragPreviewOpacityPercent = try c.decodeIfPresent(Double.self, forKey: .dragPreviewOpacityPercent) ?? 85
        dragPreviewScalePercent = try c.decodeIfPresent(Double.self, forKey: .dragPreviewScalePercent) ?? 50
        guard ["content", "outline", "none"].contains(dragPreview),
              dragPreviewOpacityPercent.isFinite, (10...100).contains(dragPreviewOpacityPercent),
              dragPreviewScalePercent.isFinite, (25...100).contains(dragPreviewScalePercent) else {
            throw DecodingError.dataCorruptedError(forKey: .dragPreview, in: c, debugDescription: "invalid pointer preview")
        }
        guard ["contour", "real"].contains(dropPreview) else {
            throw DecodingError.dataCorruptedError(forKey: .dropPreview, in: c, debugDescription: "unknown drop preview")
        }
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
