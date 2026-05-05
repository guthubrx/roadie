import Foundation
import TOMLKit

public struct Config: Codable, Sendable {
    public var daemon: DaemonConfig
    public var tiling: TilingConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var desktops: DesktopsConfig
    public var displays: [DisplayRule]
    public var mouse: MouseConfig
    public var focus: FocusConfig
    /// SPEC-026 US6 — configuration signal hooks (kill-switch + liste de hooks).
    public var signals: SignalsConfig
    /// SPEC-026 US3 — scratchpads déclarés (clé TOML `[[scratchpads]]`).
    public var scratchpads: [ScratchpadDef]
    /// SPEC-026 US4 — règles sticky par-fenêtre (clé TOML `[[sticky]]`).
    public var stickyRules: [StickyRuleDef]
    /// SPEC-026 fix Firefox slide — lecture minimale de `[fx.opacity.stage_hide].enabled`
    /// pour décider si on installe `OpacityStageHider` au boot. Indépendant du
    /// module dynamique RoadieOpacity (qui décode sa propre section au runtime).
    public var fxOpacityStageHideEnabled: Bool
    /// SPEC-026 — `[fx.rail].stage_numbers_enabled`. Affiche en permanence le
    /// chiffre de la stage en arrière-plan de chaque cellule du navrail.
    /// Désactivable + flash temporaire via `roadie rail stage-numbers flash <s>`.
    public var fxRailStageNumbersEnabled: Bool
    /// SPEC-026 — paramétrage visuel du badge (lus dans `[fx.rail]`).
    public var fxRailStageNumbersOffsetX: Double
    public var fxRailStageNumbersOffsetY: Double
    public var fxRailStageNumbersSize: Double
    public var fxRailStageNumbersOpacity: Double

    public init(daemon: DaemonConfig = .init(),
                tiling: TilingConfig = .init(),
                stageManager: StageManagerConfig = .init(),
                exclusions: ExclusionsConfig = .init(),
                desktops: DesktopsConfig = .init(),
                displays: [DisplayRule] = [],
                mouse: MouseConfig = .init(),
                focus: FocusConfig = .init(),
                signals: SignalsConfig = .init(),
                scratchpads: [ScratchpadDef] = [],
                stickyRules: [StickyRuleDef] = [],
                fxOpacityStageHideEnabled: Bool = false,
                fxRailStageNumbersEnabled: Bool = false,
                fxRailStageNumbersOffsetX: Double = 4,
                fxRailStageNumbersOffsetY: Double = -30,
                fxRailStageNumbersSize: Double = 64,
                fxRailStageNumbersOpacity: Double = 0.22) {
        self.daemon = daemon
        self.tiling = tiling
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.desktops = desktops
        self.displays = displays
        self.mouse = mouse
        self.focus = focus
        self.signals = signals
        self.scratchpads = scratchpads
        self.stickyRules = stickyRules
        self.fxOpacityStageHideEnabled = fxOpacityStageHideEnabled
        self.fxRailStageNumbersEnabled = fxRailStageNumbersEnabled
        self.fxRailStageNumbersOffsetX = fxRailStageNumbersOffsetX
        self.fxRailStageNumbersOffsetY = fxRailStageNumbersOffsetY
        self.fxRailStageNumbersSize = fxRailStageNumbersSize
        self.fxRailStageNumbersOpacity = fxRailStageNumbersOpacity
    }

    enum CodingKeys: String, CodingKey {
        case daemon
        case tiling
        case stageManager = "stage_manager"
        case exclusions
        case desktops
        case displays
        case mouse
        case focus
        case signals
        case scratchpads
        case stickyRules = "sticky"
        case fx
    }

    /// SPEC-026 — décodeur minimal pour les sous-sections `[fx.*]` lues par le
    /// daemon (independant des décodages des modules dynamiques).
    private struct FXSection: Codable {
        let opacity: OpacitySection?
        let rail: RailSection?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            opacity = try c.decodeIfPresent(OpacitySection.self, forKey: .opacity)
            rail = try c.decodeIfPresent(RailSection.self, forKey: .rail)
        }
        enum CodingKeys: String, CodingKey { case opacity, rail }
        struct OpacitySection: Codable {
            let stage_hide: StageHideSection?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                stage_hide = try c.decodeIfPresent(StageHideSection.self, forKey: .stage_hide)
            }
            enum CodingKeys: String, CodingKey { case stage_hide }
            struct StageHideSection: Codable {
                let enabled: Bool?
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
                }
                enum CodingKeys: String, CodingKey { case enabled }
            }
        }
        struct RailSection: Codable {
            let stage_numbers_enabled: Bool?
            let stage_numbers_offset_x: Double?
            let stage_numbers_offset_y: Double?
            let stage_numbers_size: Double?
            let stage_numbers_opacity: Double?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                stage_numbers_enabled = try c.decodeIfPresent(Bool.self, forKey: .stage_numbers_enabled)
                stage_numbers_offset_x = try c.decodeIfPresent(Double.self, forKey: .stage_numbers_offset_x)
                stage_numbers_offset_y = try c.decodeIfPresent(Double.self, forKey: .stage_numbers_offset_y)
                stage_numbers_size = try c.decodeIfPresent(Double.self, forKey: .stage_numbers_size)
                stage_numbers_opacity = try c.decodeIfPresent(Double.self, forKey: .stage_numbers_opacity)
            }
            enum CodingKeys: String, CodingKey {
                case stage_numbers_enabled, stage_numbers_offset_x, stage_numbers_offset_y
                case stage_numbers_size, stage_numbers_opacity
            }
        }
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
        self.displays = try c.decodeIfPresent([DisplayRule].self, forKey: .displays) ?? []
        self.mouse = try c.decodeIfPresent(MouseConfig.self, forKey: .mouse) ?? .init()
        self.focus = try c.decodeIfPresent(FocusConfig.self, forKey: .focus) ?? .init()
        self.signals = try c.decodeIfPresent(SignalsConfig.self, forKey: .signals) ?? .init()
        self.scratchpads = try c.decodeIfPresent([ScratchpadDef].self, forKey: .scratchpads) ?? []
        self.stickyRules = try c.decodeIfPresent([StickyRuleDef].self, forKey: .stickyRules) ?? []
        // SPEC-026 — extraits depuis [fx.*] : opacity.stage_hide.enabled,
        // rail.stage_numbers_enabled.
        let fx = try c.decodeIfPresent(FXSection.self, forKey: .fx)
        self.fxOpacityStageHideEnabled = fx?.opacity?.stage_hide?.enabled ?? false
        self.fxRailStageNumbersEnabled = fx?.rail?.stage_numbers_enabled ?? false
        self.fxRailStageNumbersOffsetX = fx?.rail?.stage_numbers_offset_x ?? 4
        self.fxRailStageNumbersOffsetY = fx?.rail?.stage_numbers_offset_y ?? -30
        self.fxRailStageNumbersSize = fx?.rail?.stage_numbers_size ?? 64
        self.fxRailStageNumbersOpacity = fx?.rail?.stage_numbers_opacity ?? 0.22
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(daemon, forKey: .daemon)
        try c.encode(tiling, forKey: .tiling)
        try c.encode(stageManager, forKey: .stageManager)
        try c.encode(exclusions, forKey: .exclusions)
        try c.encode(desktops, forKey: .desktops)
        if !displays.isEmpty {
            try c.encode(displays, forKey: .displays)
        }
        try c.encode(mouse, forKey: .mouse)
        try c.encode(focus, forKey: .focus)
    }
}

// MARK: - MouseConfig (SPEC-015)

/// Modifier clavier pour activer drag/resize souris.
public enum ModifierKey: String, Codable, Sendable, Equatable {
    case ctrl
    case alt
    case cmd
    case shift
    case hyper   // ctrl+alt+cmd+shift
    case none
}

/// Action déclenchée par un bouton souris + modifier.
public enum MouseAction: String, Codable, Sendable, Equatable {
    case move
    case resize
    case none
}

/// Configuration souris (section `[mouse]` du TOML).
public struct MouseConfig: Codable, Sendable, Equatable {
    public var modifier: ModifierKey
    public var slowModifier: ModifierKey
    public var slowFactor: Double
    public var actionLeft: MouseAction
    public var actionRight: MouseAction
    public var actionMiddle: MouseAction
    public var edgeThreshold: Int

    public init(modifier: ModifierKey = .ctrl,
                slowModifier: ModifierKey = .none,
                slowFactor: Double = 0.3,
                actionLeft: MouseAction = .move,
                actionRight: MouseAction = .resize,
                actionMiddle: MouseAction = .none,
                edgeThreshold: Int = 30) {
        self.modifier = modifier
        self.slowModifier = slowModifier
        self.slowFactor = max(0.05, min(1.0, slowFactor))
        self.actionLeft = actionLeft
        self.actionRight = actionRight
        self.actionMiddle = actionMiddle
        self.edgeThreshold = max(5, min(200, edgeThreshold))
    }

    enum CodingKeys: String, CodingKey {
        case modifier
        case slowModifier = "slow_modifier"
        case slowFactor = "slow_factor"
        case actionLeft = "action_left"
        case actionRight = "action_right"
        case actionMiddle = "action_middle"
        case edgeThreshold = "edge_threshold"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // FR-002 : valeur invalide → fallback ctrl + warn (caller log).
        if let raw = try c.decodeIfPresent(String.self, forKey: .modifier) {
            self.modifier = ModifierKey(rawValue: raw) ?? .ctrl
        } else {
            self.modifier = .ctrl
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .slowModifier) {
            self.slowModifier = ModifierKey(rawValue: raw) ?? .none
        } else {
            self.slowModifier = .none
        }
        let rawSlow = try c.decodeIfPresent(Double.self, forKey: .slowFactor) ?? 0.3
        self.slowFactor = max(0.05, min(1.0, rawSlow))
        // FR-003 : valeur invalide → fallback default (move pour left, resize pour right, none pour middle).
        if let raw = try c.decodeIfPresent(String.self, forKey: .actionLeft) {
            self.actionLeft = MouseAction(rawValue: raw) ?? .move
        } else {
            self.actionLeft = .move
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .actionRight) {
            self.actionRight = MouseAction(rawValue: raw) ?? .resize
        } else {
            self.actionRight = .resize
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .actionMiddle) {
            self.actionMiddle = MouseAction(rawValue: raw) ?? .none
        } else {
            self.actionMiddle = .none
        }
        let rawEdge = try c.decodeIfPresent(Int.self, forKey: .edgeThreshold) ?? 30
        self.edgeThreshold = max(5, min(200, rawEdge))
    }
}

// MARK: - DisplayRule (SPEC-012 T037, R-008, FR-018)

/// Override de configuration per-écran. Défini en TOML via la section `[[displays]]`.
/// Le premier match (matchIndex | matchUUID | matchName) remporte.
public struct DisplayRule: Codable, Sendable, Equatable {
    /// Match par index 1-based dans `NSScreen.screens`.
    public var matchIndex: Int?
    /// Match par UUID stable cross-reboot (`CGDisplayCreateUUIDFromDisplayID`).
    public var matchUUID: String?
    /// Match par nom localisé (`NSScreen.localizedName`).
    public var matchName: String?
    /// Stratégie de tiling pour cet écran ("bsp" / "master_stack").
    public var defaultStrategy: String?
    /// Marge extérieure px — override de la valeur globale.
    public var gapsOuter: Int?
    /// Espacement interne px — override de la valeur globale.
    public var gapsInner: Int?

    public init(matchIndex: Int? = nil,
                matchUUID: String? = nil,
                matchName: String? = nil,
                defaultStrategy: String? = nil,
                gapsOuter: Int? = nil,
                gapsInner: Int? = nil) {
        self.matchIndex = matchIndex
        self.matchUUID = matchUUID
        self.matchName = matchName
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsInner = gapsInner
    }

    enum CodingKeys: String, CodingKey {
        case matchIndex = "match_index"
        case matchUUID = "match_uuid"
        case matchName = "match_name"
        case defaultStrategy = "default_strategy"
        case gapsOuter = "gaps_outer"
        case gapsInner = "gaps_inner"
    }
}

// MARK: - DesktopsConfig (SPEC-011 + SPEC-013)

/// Mode de gestion des desktops sur configuration multi-écran (SPEC-013 FR-001).
/// - `global` : un seul current desktop pour tous les écrans (V2, défaut).
/// - `perDisplay` : chaque écran maintient son current desktop indépendamment.
public enum DesktopMode: String, Codable, Sendable, Equatable {
    case global
    case perDisplay = "per_display"
}

/// Configuration de la feature multi-desktop virtuel (pivot AeroSpace).
/// Validation : count ∈ 1..16 (FR-001, FR-018).
public struct DesktopsConfig: Codable, Sendable {
    public var enabled: Bool
    public var count: Int
    public var defaultFocus: Int
    public var backAndForth: Bool
    /// SPEC-013 FR-001 : `global` (V2 compat, défaut) ou `per_display`.
    public var mode: DesktopMode
    /// SPEC-021 T047 : intervalle de poll du reconciler desktop (ms). 0 = désactivé.
    /// Clé TOML : [desktops].window_desktop_poll_ms
    public var windowDesktopPollMs: Int

    public init(enabled: Bool = true,
                count: Int = 10,
                defaultFocus: Int = 1,
                backAndForth: Bool = true,
                mode: DesktopMode = .global,
                windowDesktopPollMs: Int = 2000) {
        self.enabled = enabled
        self.count = count
        self.defaultFocus = defaultFocus
        self.backAndForth = backAndForth
        self.mode = mode
        self.windowDesktopPollMs = windowDesktopPollMs
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case count
        case defaultFocus = "default_focus"
        case backAndForth = "back_and_forth"
        case mode
        case windowDesktopPollMs = "window_desktop_poll_ms"
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
        // FR-002 : valeur invalide pour `mode` → fallback global + warn (caller-side).
        // Codable lèverait une erreur typée pour valeur inconnue ; on attrape ici en
        // décodant en String d'abord, puis en mappant manuellement.
        if let raw = try c.decodeIfPresent(String.self, forKey: .mode) {
            self.mode = DesktopMode(rawValue: raw) ?? .global
        } else {
            self.mode = .global
        }
        self.windowDesktopPollMs = try c.decodeIfPresent(Int.self,
                                        forKey: .windowDesktopPollMs) ?? 2000
    }
}

/// Configuration des comportements liés au focus (section `[focus]`).
public struct FocusConfig: Codable, Sendable, Equatable {
    public var stageFollowsFocus: Bool
    public var assignFollowsFocus: Bool
    /// SPEC-026 US5 — focus suit la souris (hover focus). Default false (opt-in obligatoire).
    public var focusFollowsMouse: Bool
    /// SPEC-026 US5 — curseur saute sur la fenêtre focalisée par raccourci. Default false.
    public var mouseFollowsFocus: Bool

    public init(stageFollowsFocus: Bool = false,
                assignFollowsFocus: Bool = true,
                focusFollowsMouse: Bool = false,
                mouseFollowsFocus: Bool = false) {
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stageFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .stageFollowsFocus) ?? false
        self.assignFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .assignFollowsFocus) ?? true
        self.focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? false
        self.mouseFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? false
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

    /// Decode tolérant : un `[daemon]` partiel (ex: seulement `log_level`) ne
    /// doit pas lever `keyNotFound`. Cohérent avec le pattern des autres configs
    /// (MouseConfig, DesktopsConfig, Config root). Préserve la rétrocompat sur
    /// les TOML utilisateurs antérieurs à l'ajout de `socket_path`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.logLevel = try c.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
        self.socketPath = try c.decodeIfPresent(String.self, forKey: .socketPath)
            ?? "~/.roadies/daemon.sock"
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
    /// SPEC-025 amend — politique de split BSP.
    public var splitPolicy: String
    /// SPEC-026 US2 — si true et qu'un display contient 1 seule fenêtre tilée,
    /// les gaps (outer + inner) sont forcés à 0 sur ce display. Default false.
    public var smartGapsSolo: Bool
    /// SPEC-027 US2 — sélection des côtés à neutraliser quand `smartGapsSolo`
    /// est actif. Liste de strings parmi `top|bottom|left|right`. Default
    /// `["top","bottom","left","right"]` (tous → comportement SPEC-026).
    /// Si vide → équivalent à `smartGapsSolo = false`. Permet par exemple
    /// de garder `gaps_outer_left = 150` (réserve navrail) tout en mettant
    /// les autres côtés à 0 quand une seule fenêtre est présente.
    public var smartGapsSoloSides: [String]

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
                masterRatio: Double = 0.6,
                splitPolicy: String = "largest_dim",
                smartGapsSolo: Bool = false,
                smartGapsSoloSides: [String] = ["top", "bottom", "left", "right"]) {
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
        self.gapsOuterRight = gapsOuterRight
        self.gapsInner = gapsInner
        self.masterRatio = masterRatio
        self.splitPolicy = splitPolicy
        self.smartGapsSolo = smartGapsSolo
        self.smartGapsSoloSides = smartGapsSoloSides
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
        case splitPolicy = "split_policy"
        case smartGapsSolo = "smart_gaps_solo"
        case smartGapsSoloSides = "smart_gaps_solo_sides"
    }

    /// Decode tolérant : tous les champs sont optionnels et ont un default.
    /// Permet d'ajouter de nouvelles clés (ex: split_policy) sans casser les
    /// configs TOML existantes des utilisateurs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultStrategy = try c.decodeIfPresent(TilerStrategy.self, forKey: .defaultStrategy) ?? .bsp
        self.gapsOuter = try c.decodeIfPresent(Int.self, forKey: .gapsOuter) ?? 8
        self.gapsOuterTop = try c.decodeIfPresent(Int.self, forKey: .gapsOuterTop)
        self.gapsOuterBottom = try c.decodeIfPresent(Int.self, forKey: .gapsOuterBottom)
        self.gapsOuterLeft = try c.decodeIfPresent(Int.self, forKey: .gapsOuterLeft)
        self.gapsOuterRight = try c.decodeIfPresent(Int.self, forKey: .gapsOuterRight)
        self.gapsInner = try c.decodeIfPresent(Int.self, forKey: .gapsInner) ?? 4
        self.masterRatio = try c.decodeIfPresent(Double.self, forKey: .masterRatio) ?? 0.6
        self.splitPolicy = try c.decodeIfPresent(String.self, forKey: .splitPolicy) ?? "largest_dim"
        self.smartGapsSolo = try c.decodeIfPresent(Bool.self, forKey: .smartGapsSolo) ?? false
        self.smartGapsSoloSides = try c.decodeIfPresent([String].self, forKey: .smartGapsSoloSides)
            ?? ["top", "bottom", "left", "right"]
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

// MARK: - SPEC-026 — nouvelles entités

/// SPEC-026 US6 — config signaux. `[signals]` global + `[[signals.hooks]]` liste.
public struct SignalsConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var hooks: [SignalDef]

    public init(enabled: Bool = true, hooks: [SignalDef] = []) {
        self.enabled = enabled
        self.hooks = hooks
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case hooks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.hooks = try c.decodeIfPresent([SignalDef].self, forKey: .hooks) ?? []
    }
}

/// SPEC-026 US6 — un hook : event → cmd shell.
public struct SignalDef: Codable, Sendable, Equatable {
    public var event: String
    public var cmd: String

    public init(event: String, cmd: String) {
        self.event = event
        self.cmd = cmd
    }
}

/// SPEC-026 US3 — déclaration d'un scratchpad.
public struct ScratchpadDef: Codable, Sendable, Equatable {
    public var name: String
    public var cmd: String
    /// Optionnel : force le bundleID matché plutôt que l'heuristic basée sur cmd.
    public var matchBundleID: String?

    public init(name: String, cmd: String, matchBundleID: String? = nil) {
        self.name = name
        self.cmd = cmd
        self.matchBundleID = matchBundleID
    }

    enum CodingKeys: String, CodingKey {
        case name
        case cmd
        case matchBundleID = "match_bundle_id"
    }
}

/// SPEC-026 US4 — règle sticky par-fenêtre.
/// Match minimal sur bundle_id (pour rester autonome de SPEC-016 RuleDef qui n'existe pas).
public struct StickyRuleDef: Codable, Sendable, Equatable {
    public var matchBundleID: String
    public var scope: StickyScope

    public init(matchBundleID: String, scope: StickyScope = .stage) {
        self.matchBundleID = matchBundleID
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case matchBundleID = "bundle_id"
        case scope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.matchBundleID = try c.decode(String.self, forKey: .matchBundleID)
        if let raw = try c.decodeIfPresent(String.self, forKey: .scope) {
            self.scope = StickyScope(rawValue: raw) ?? .stage
        } else {
            self.scope = .stage
        }
    }
}

/// SPEC-026 US4 — portée du sticky.
public enum StickyScope: String, Codable, Sendable, Equatable {
    case stage    // visible sur toutes stages d'un (display, desktop)
    case desktop  // visible sur tous desktops d'un display
    case all      // suit le display actif (cross-display)
}
