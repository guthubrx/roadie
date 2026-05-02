import Foundation
import CoreGraphics

// MARK: - Layout

/// Stratégie de tiling d'un desktop virtuel (SPEC-011 data-model).
public enum DesktopLayout: String, Codable, Sendable, CaseIterable {
    case bsp
    case masterStack = "master_stack"
    case floating
}

// MARK: - WindowEntry

/// Fenêtre assignée à un desktop, avec sa position attendue on-screen (R-002).
/// Sérialisé en section [[windows]] du fichier state.toml.
public struct WindowEntry: Codable, Sendable, Equatable {
    public var cgwid: UInt32
    public var bundleID: String
    public var title: String
    public var expectedFrame: CGRect
    public var stageID: Int
    /// UUID de l'écran physique d'origine (SPEC-012 FR-020).
    /// Optionnel pour backward-compatibilité avec les state.toml SPEC-011.
    /// Si nil au boot, fallback sur l'écran principal.
    public var displayUUID: String?

    public init(cgwid: UInt32, bundleID: String, title: String,
                expectedFrame: CGRect, stageID: Int,
                displayUUID: String? = nil) {
        self.cgwid = cgwid
        self.bundleID = bundleID
        self.title = title
        self.expectedFrame = expectedFrame
        self.stageID = stageID
        self.displayUUID = displayUUID
    }
}

// MARK: - Stage

/// Stage (groupe de fenêtres) local à un desktop. Sérialisé en [[stages]].
/// Identifiant 1-based, local au desktop parent.
public struct DesktopStage: Codable, Sendable, Equatable {
    public var id: Int
    public var label: String?
    public var windows: [UInt32]

    public init(id: Int, label: String? = nil, windows: [UInt32] = []) {
        self.id = id
        self.label = label
        self.windows = windows
    }
}

// MARK: - RoadieDesktop

/// Entité principale représentant un desktop virtuel roadie.
/// Stocké dans ~/.config/roadies/desktops/<id>/state.toml (R-004).
public struct RoadieDesktop: Codable, Sendable, Equatable {
    public var id: Int
    public var label: String?
    public var layout: DesktopLayout
    public var gapsOuter: Int
    public var gapsInner: Int
    public var activeStageID: Int
    public var stages: [DesktopStage]
    public var windows: [WindowEntry]

    public init(id: Int,
                label: String? = nil,
                layout: DesktopLayout = .bsp,
                gapsOuter: Int = 8,
                gapsInner: Int = 4,
                activeStageID: Int = 1,
                stages: [DesktopStage] = [],
                windows: [WindowEntry] = []) {
        self.id = id
        self.label = label
        self.layout = layout
        self.gapsOuter = gapsOuter
        self.gapsInner = gapsInner
        self.activeStageID = activeStageID
        self.stages = stages.isEmpty ? [DesktopStage(id: 1)] : stages
        self.windows = windows
    }

    /// Crée un desktop vierge avec un stage par défaut (invariant data-model).
    public static func blank(id: Int) -> RoadieDesktop {
        RoadieDesktop(id: id, stages: [DesktopStage(id: 1)])
    }
}
