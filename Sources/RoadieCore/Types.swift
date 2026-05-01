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
    public var stageID: StageID?
    /// UUID du desktop macOS (Mission Control) sur lequel cette fenêtre est physiquement
    /// présente. nil au boot tant que la transition initiale n'a pas mis à jour le registry
    /// (FR-007 + data-model SPEC-003).
    public var desktopUUID: String?

    public init(cgWindowID: WindowID, pid: pid_t, bundleID: String,
                title: String, frame: CGRect, subrole: AXSubrole,
                isFloating: Bool, isMinimized: Bool = false, isFullscreen: Bool = false,
                workspaceID: WorkspaceID = .main, stageID: StageID? = nil,
                desktopUUID: String? = nil) {
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
        self.stageID = stageID
        self.desktopUUID = desktopUUID
    }

    public var isTileable: Bool {
        !isFloating && !isMinimized && !isFullscreen && subrole == .standard
    }
}
