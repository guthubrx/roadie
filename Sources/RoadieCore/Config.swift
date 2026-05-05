import Foundation
import TOMLKit

public struct Config: Codable, Sendable {
    public var daemon: DaemonConfig
    public var tiling: TilingConfig
    public var stageManager: StageManagerConfig
    public var exclusions: ExclusionsConfig
    public var desktops: DesktopsConfig
    // SPEC-012 T037 : règles de config per-écran (section [[displays]] dans roadies.toml)

    public var displays: [DisplayRule]
    /// SPEC-015 : config souris (drag/resize avec modifier).
    public var mouse: MouseConfig
    /// Config des comportements liés au focus (auto-switch stage/desktop sur AltTab).
    public var focus: FocusConfig

    public init(daemon: DaemonConfig = .init(),
                tiling: TilingConfig = .init(),
                stageManager: StageManagerConfig = .init(),
                exclusions: ExclusionsConfig = .init(),
                desktops: DesktopsConfig = .init(),
                displays: [DisplayRule] = [],
                mouse: MouseConfig = .init(),
                focus: FocusConfig = .init()) {
        self.daemon = daemon
        self.tiling = tiling
        self.stageManager = stageManager
        self.exclusions = exclusions
        self.desktops = desktops
        self.displays = displays
        self.mouse = mouse
        self.focus = focus
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
    /// Si true, basculer automatiquement vers le stage/desktop de la fenêtre
    /// nouvellement focused (typiquement déclenché par AltTab/Cmd-Tab).
    /// Sans ça, l'app prend le focus mais sa fenêtre reste invisible
    /// (cachée offscreen sur un autre stage/desktop).
    public var stageFollowsFocus: Bool

    /// Si true, après `stage.assign`, basculer aussi vers le stage cible
    /// (comportement yabai `--focus`). Sans ça, la fenêtre est envoyée mais
    /// l'utilisateur reste sur la stage courante (utile pour dispatcher
    /// plusieurs fenêtres avant de bouger).
    public var assignFollowsFocus: Bool

    public init(stageFollowsFocus: Bool = false,
                assignFollowsFocus: Bool = true) {
        self.stageFollowsFocus = stageFollowsFocus
        self.assignFollowsFocus = assignFollowsFocus
    }

    enum CodingKeys: String, CodingKey {
        case stageFollowsFocus = "stage_follows_focus"
        case assignFollowsFocus = "assign_follows_focus"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Default false : éviter l'animation involontaire des fenêtres déplacées
        // par HideStrategy.corner quand on tabe entre apps. Opt-in via TOML.
        self.stageFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .stageFollowsFocus) ?? false
        self.assignFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .assignFollowsFocus) ?? true
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
    /// "largest_dim" (default) : split sur le côté le plus long de la cible
    ///   → fenêtres ≈ carrées, mais peut produire 3+ colonnes étirées en cas
    ///     d'insertions successives sur une cible large.
    /// "dwindle" : split orthogonal au parent (alterne H/V à chaque profondeur)
    ///   → layouts plus équilibrés, comportement i3/sway classique.
    public var splitPolicy: String

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
                splitPolicy: String = "largest_dim") {
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsOuterTop = gapsOuterTop
        self.gapsOuterBottom = gapsOuterBottom
        self.gapsOuterLeft = gapsOuterLeft
        self.gapsOuterRight = gapsOuterRight
        self.gapsInner = gapsInner
        self.masterRatio = masterRatio
        self.splitPolicy = splitPolicy
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
