import SwiftUI
import AppKit

// SPEC-019 — Protocole de rendu d'une cellule de stage dans le rail.
// Pattern reproduit de `Tiler` / `TilerRegistry` (RoadieTiler) — Article I' constitution-002.

/// Contexte transmis au renderer pour produire la View d'une cellule de stage.
/// Stateless : pure fonction du contexte → View.
public struct StageRenderContext {
    public let stage:         StageVM
    public let windows:       [CGWindowID: WindowVM]
    public let thumbnails:    [CGWindowID: ThumbnailVM]
    public let haloColorHex:  String
    public let haloIntensity: Double
    public let haloRadius:    Double

    public init(stage: StageVM,
                windows: [CGWindowID: WindowVM] = [:],
                thumbnails: [CGWindowID: ThumbnailVM] = [:],
                haloColorHex: String = "#34C759",
                haloIntensity: Double = 0.75,
                haloRadius: Double = 18) {
        self.stage = stage
        self.windows = windows
        self.thumbnails = thumbnails
        self.haloColorHex = haloColorHex
        self.haloIntensity = haloIntensity
        self.haloRadius = haloRadius
    }
}

/// Callbacks orchestration UI passés au renderer. Le renderer ne porte aucune
/// logique de mutation : il invoque les callbacks pour signaler une intention
/// (tap = switch, drop = réassign, rename, etc.). Le consommateur traduit ça
/// en commandes IPC vers le daemon.
public struct StageRendererCallbacks {
    public let onTap:          () -> Void
    public let onDropAssign:   (CGWindowID, String) -> Void
    public let onRename:       (String, String) -> Void
    public let onAddFocused:   (String) -> Void
    public let onDelete:       (String) -> Void

    public init(onTap:        @escaping () -> Void = {},
                onDropAssign: @escaping (CGWindowID, String) -> Void = { _, _ in },
                onRename:     @escaping (String, String) -> Void = { _, _ in },
                onAddFocused: @escaping (String) -> Void = { _ in },
                onDelete:     @escaping (String) -> Void = { _ in }) {
        self.onTap = onTap
        self.onDropAssign = onDropAssign
        self.onRename = onRename
        self.onAddFocused = onAddFocused
        self.onDelete = onDelete
    }
}

/// Contrat d'un rendu de cellule de stage.
///
/// Invariants :
/// - `rendererID` : lowercase-kebab-case `[a-z0-9-]`, ≤ 32 chars, unique dans le registre.
/// - `displayName` : human-readable, ≤ 40 chars.
/// - `render(...)` est **pure** : pas d'état mutable interne, pas de side-effect.
/// - Doit gérer le cas `context.stage.windowIDs.isEmpty` sans crash (placeholder).
public protocol StageRenderer: AnyObject {
    static var rendererID:  String { get }
    static var displayName: String { get }

    @MainActor
    func render(context: StageRenderContext,
                callbacks: StageRendererCallbacks) -> AnyView
}
