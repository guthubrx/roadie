import Foundation
import CoreGraphics

// MARK: - Identifiants typés

public typealias WindowID = CGWindowID

public struct WorkspaceID: Hashable, Codable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public static let main = WorkspaceID("main")
}

public struct StageID: Hashable, Codable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

// MARK: - Énumérations

public enum Direction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down

    public var orientation: Orientation {
        self == .left || self == .right ? .horizontal : .vertical
    }

    public var sign: Int {
        self == .right || self == .down ? 1 : -1
    }
}

public enum Orientation: String, Codable, Sendable {
    case horizontal, vertical

    public var opposite: Orientation { self == .horizontal ? .vertical : .horizontal }
}

/// Identifiant de stratégie de tiling. Struct String-based pour permettre
/// l'enregistrement dynamique de nouvelles stratégies sans modifier ce type.
/// Les valeurs disponibles sont déclarées par `TilerRegistry` au runtime.
public struct TilerStrategy: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    // Constantes prédéfinies (pour autocomplete et type-safety dans le code daemon).
    // L'ajout de "papillon" se fait via TilerRegistry.register() dans bootstrap,
    // sans modifier ce fichier.
    public static let bsp: TilerStrategy = "bsp"
    public static let masterStack: TilerStrategy = "masterStack"
}

public enum AXSubrole: String, Codable, Sendable {
    case standard
    case dialog
    case sheet
    case systemDialog
    case unknown

    public init(rawAXValue: String?) {
        switch rawAXValue {
        case "AXStandardWindow": self = .standard
        case "AXDialog": self = .dialog
        case "AXSheet": self = .sheet
        case "AXSystemDialog": self = .systemDialog
        default: self = .unknown
        }
    }

    public var isFloatingByDefault: Bool { self != .standard }
}

public enum HideStrategy: String, Codable, Sendable {
    case corner
    case minimize
    case hybrid
}

// MARK: - Codes d'erreur (protocole socket)

public enum ErrorCode: String, Codable, Sendable {
    case daemonNotRunning = "daemon_not_running"
    case invalidArgument = "invalid_argument"
    case unknownStage = "unknown_stage"
    case stageManagerDisabled = "stage_manager_disabled"
    case windowNotFound = "window_not_found"
    case accessibilityDenied = "accessibility_denied"
    case internalError = "internal_error"
    /// V2 : `multi_desktop.enabled = false` mais commande desktop demandée (exit 4 CLI).
    case multiDesktopDisabled = "multi_desktop_disabled"
    /// V2 : selector desktop introuvable (exit 5 CLI).
    case unknownDesktop = "unknown_desktop"
    /// SPEC-018 US4 : selector display invalide (index hors range ou UUID inconnu).
    case unknownDisplay = "unknown_display"
    /// SPEC-018 US4 : id desktop hors range 1..N.
    case desktopOutOfRange = "desktop_out_of_range"
}

// MARK: - WindowState

public struct WindowState: Sendable {
    public let cgWindowID: WindowID
    public let pid: pid_t
    public let bundleID: String
    public var title: String
    public var frame: CGRect
    public let subrole: AXSubrole
    public var isFloating: Bool
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var workspaceID: WorkspaceID
    /// SPEC-021 : computed read-only. Source unique de vérité = StageManager.widToScope.
    /// Toute écriture `state.stageID = X` est un compile error (intention : supprimer le drift).
    /// Pour attribuer une wid à un stage : `stageManager.assign(wid:to:)`.
    public var stageID: StageID? {
        StageManagerLocator.shared?.stageIDOf(wid: cgWindowID)
    }
    /// UUID du desktop macOS (Mission Control) — legacy SPEC-003, conservé pour compat.
    public var desktopUUID: String?
    /// SPEC-011 : identifiant du desktop virtuel roadie (1..count). Défaut 1.
    public var desktopID: Int
    /// SPEC-011 : position/taille attendues quand la fenêtre est on-screen sur son desktop.
    /// Mise à jour uniquement quand desktopID == currentDesktopID (R-002).
    public var expectedFrame: CGRect
    /// Toggle fullscreen non-natif (zoom-fullscreen yabai-style) : la fenêtre prend
    /// tout le visibleFrame du display courant en restant dans la même Space.
    /// `preZoomFrame` mémorise sa position pré-zoom pour la restoration.
    public var isZoomed: Bool
    public var preZoomFrame: CGRect?

    public init(cgWindowID: WindowID, pid: pid_t, bundleID: String,
                title: String, frame: CGRect, subrole: AXSubrole,
                isFloating: Bool, isMinimized: Bool = false, isFullscreen: Bool = false,
                workspaceID: WorkspaceID = .main,
                desktopUUID: String? = nil, desktopID: Int = 1,
                expectedFrame: CGRect = .zero,
                isZoomed: Bool = false, preZoomFrame: CGRect? = nil) {
        self.cgWindowID = cgWindowID
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.subrole = subrole
        self.isFloating = isFloating
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.workspaceID = workspaceID
        self.desktopUUID = desktopUUID
        self.desktopID = desktopID
        self.expectedFrame = expectedFrame == .zero ? frame : expectedFrame
        self.isZoomed = isZoomed
        self.preZoomFrame = preZoomFrame
    }

    /// Seuil de taille mini pour qu'une fenêtre soit considérée comme une fenêtre
    /// applicative réelle (vs utility/tooltip/popup helper). Les apps modernes
    /// (Firefox WebExtension frames, Grayjay/Electron helpers, iTerm popovers)
    /// enregistrent des `NSWindow` 66×20 px comme `AXStandardWindow`. Sans ce
    /// filtre elles polluent le tiling et l'attribution stage.
    public static let minimumUsefulDimension: CGFloat = 100

    public var isTileable: Bool {
        !isFloating && !isMinimized && !isFullscreen && !isZoomed && subrole == .standard
            && !isHelperWindow
    }

    /// `true` si la fenêtre est un utility/popup/tooltip non destiné à l'utilisateur final
    /// (Firefox WebExtension frames 66×20, Grayjay/Electron tooltips, iTerm popovers).
    /// Critère : au moins une dimension < `minimumUsefulDimension`. Utilisé partout pour
    /// refuser l'assignation à un stage et la persistance dans `memberWindows`.
    public var isHelperWindow: Bool {
        frame.size.width  < Self.minimumUsefulDimension ||
        frame.size.height < Self.minimumUsefulDimension
    }
}
