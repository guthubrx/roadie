import SwiftUI
import AppKit

// SPEC-019 — Protocole de rendu d'une cellule de stage dans le rail.
// Pattern reproduit de `Tiler` / `TilerRegistry` (RoadieTiler) — Article I' constitution-002.

/// Contexte transmis au renderer pour produire la View d'une cellule de stage.
/// Stateless : pure fonction du contexte → View.
public struct StageRenderContext {
    public let stage: StageVM
    public let windows: [CGWindowID: WindowVM]
    public let thumbnails: [CGWindowID: ThumbnailVM]
    public let haloColorHex: String
    public let haloIntensity: Double
    public let haloRadius: Double
    // SPEC-019 — paramètres scatter pour StackedPreviewsRenderer (ignorés par
    // les autres renderers). Configurables via [fx.rail.stacked] TOML.
    public let stackedOffsetX: Double
    public let stackedOffsetY: Double
    public let stackedRotation: Double
    public let stackedScale: Double
    public let stackedOpacity: Double
    public let stackedScatterMode: String
    // SPEC-019 — paramètres renderer "parallax-45" (ignorés par les autres
    // renderers). Configurables via [fx.rail.parallax] TOML.
    public let parallaxRotation: Double
    public let parallaxOffsetX: Double
    public let parallaxOffsetY: Double
    public let parallaxScale: Double
    public let parallaxOpacity: Double
    // SPEC-019 — taille des vignettes (WindowPreview). Configurables via [fx.rail.preview].
    public let previewWidth: Double
    public let previewHeight: Double
    public let leadingPadding: Double
    public let trailingPadding: Double
    public let verticalPadding: Double
    // SPEC-019 — bordure des vignettes (per-renderer override possible).
    public let borderColor: String              // bordure du stage ACTIF (défaut)
    public let borderColorInactive: String      // bordure des stages INACTIFS
    public let borderWidth: Double
    public let borderStyle: String              // "solid" | "dashed" | "dotted"
    public let stageBorderOverrides: [String: String]  // stage_id → couleur active spécifique
    public let haloEnabled: Bool                // on/off du halo (en plus de stage.isActive)
    // SPEC-019 — assombrissement par couche pour parallax (0..1, 0 = désactivé).
    public let parallaxDarkenPerLayer: Double
    // SPEC-028 — moyens de summon (bouton et/ou menu contextuel) sur les
    // vignettes des stages INACTIVES. Lus depuis [fx.rail].
    public let summonButtonEnabled: Bool
    public let summonDoubleClickEnabled: Bool
    /// SPEC-028 — ID de la stage AFFICHÉE juste avant la stage courante dans
    /// le rail. nil = première stage du rail (pas de précédente). Sert au
    /// chevron.up de WindowPreview pour déplacer la fenêtre une cellule au-
    /// dessus, en sautant les stages absentes du rail.
    public let prevStageID: String?
    /// SPEC-028 — idem pour la stage AFFICHÉE juste après. nil = dernière.
    public let nextStageID: String?
    /// SPEC-028 — true = chevrons toujours visibles (mode "always" TOML).
    /// false = visibles seulement quand curseur en zone de proximité.
    public let chevronsAlwaysVisible: Bool
    /// SPEC-028 — largeur (px) de la bande gauche dans la vignette qui
    /// déclenche l'apparition des chevrons move-window (up/right/down).
    public let chevronsMoveZoneWidth: Double
    /// SPEC-028 — hauteur (px) des bandes au-dessus/au-dessous de la vignette
    /// frontmost qui déclenchent les chevrons reorder-stage (up/down).
    public let chevronsReorderZoneHeight: Double
    /// SPEC-028 — délai (ms) avant masquage après sortie de zone.
    public let chevronsFadeoutMs: Int

    public init(stage: StageVM,
                windows: [CGWindowID: WindowVM] = [:],
                thumbnails: [CGWindowID: ThumbnailVM] = [:],
                haloColorHex: String = "#34C759",
                haloIntensity: Double = 0.75,
                haloRadius: Double = 18,
                stackedOffsetX: Double = 60,
                stackedOffsetY: Double = 80,
                stackedRotation: Double = 12,
                stackedScale: Double = 0.06,
                stackedOpacity: Double = 0.10,
                stackedScatterMode: String = "compass",
                parallaxRotation: Double = 35,
                parallaxOffsetX: Double = 18,
                parallaxOffsetY: Double = 8,
                parallaxScale: Double = 0.05,
                parallaxOpacity: Double = 0.10,
                previewWidth: Double = 200,
                previewHeight: Double = 130,
                leadingPadding: Double = 8,
                trailingPadding: Double = 16,
                verticalPadding: Double = 20,
                borderColor: String = "#FFFFFF26",
                borderColorInactive: String = "#80808033",
                borderWidth: Double = 0.5,
                borderStyle: String = "solid",
                stageBorderOverrides: [String: String] = [:],
                haloEnabled: Bool = true,
                parallaxDarkenPerLayer: Double = 0.0,
                summonButtonEnabled: Bool = true,
                summonDoubleClickEnabled: Bool = true,
                prevStageID: String? = nil,
                nextStageID: String? = nil,
                chevronsAlwaysVisible: Bool = false,
                chevronsMoveZoneWidth: Double = 30,
                chevronsReorderZoneHeight: Double = 30,
                chevronsFadeoutMs: Int = 200) {
        self.stage = stage
        self.windows = windows
        self.thumbnails = thumbnails
        self.haloColorHex = haloColorHex
        self.haloIntensity = haloIntensity
        self.haloRadius = haloRadius
        self.stackedOffsetX = stackedOffsetX
        self.stackedOffsetY = stackedOffsetY
        self.stackedRotation = stackedRotation
        self.stackedScale = stackedScale
        self.stackedOpacity = stackedOpacity
        self.stackedScatterMode = stackedScatterMode
        self.parallaxRotation = parallaxRotation
        self.parallaxOffsetX = parallaxOffsetX
        self.parallaxOffsetY = parallaxOffsetY
        self.parallaxScale = parallaxScale
        self.parallaxOpacity = parallaxOpacity
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.verticalPadding = verticalPadding
        self.borderColor = borderColor
        self.borderColorInactive = borderColorInactive
        self.borderWidth = borderWidth
        self.borderStyle = borderStyle
        self.stageBorderOverrides = stageBorderOverrides
        self.haloEnabled = haloEnabled
        self.parallaxDarkenPerLayer = parallaxDarkenPerLayer
        self.summonButtonEnabled = summonButtonEnabled
        self.summonDoubleClickEnabled = summonDoubleClickEnabled
        self.prevStageID = prevStageID
        self.nextStageID = nextStageID
        self.chevronsAlwaysVisible = chevronsAlwaysVisible
        self.chevronsMoveZoneWidth = chevronsMoveZoneWidth
        self.chevronsReorderZoneHeight = chevronsReorderZoneHeight
        self.chevronsFadeoutMs = chevronsFadeoutMs
    }
}

/// Callbacks orchestration UI passés au renderer. Le renderer ne porte aucune
/// logique de mutation : il invoque les callbacks pour signaler une intention
/// (tap = switch, drop = réassign, rename, etc.). Le consommateur traduit ça
/// en commandes IPC vers le daemon.
public struct StageRendererCallbacks {
    public let onTap: () -> Void
    public let onDropAssign: (CGWindowID, String) -> Void
    public let onRename: (String, String) -> Void
    public let onAddFocused: (String) -> Void
    public let onDelete: (String) -> Void
    /// SPEC-028 alt — clic bouton « → » bas-gauche d'une vignette = amener
    /// cette wid dans la stage active du display courant. Le renderer
    /// l'expose via WindowPreview.onSummon uniquement sur stages INACTIVES
    /// (sur la stage active il serait un no-op visuel).
    public let onSummonWindow: (CGWindowID) -> Void
    /// SPEC-028 — réordonnancement de la stage entière. Args : (sourceID,
    /// targetID) — la source vient se placer juste avant la target. Bind
    /// par StageStackView vers RailController.reorderStage.
    public let onReorderStages: (String, String) -> Void

    public init(onTap: @escaping () -> Void = {},
                onDropAssign: @escaping (CGWindowID, String) -> Void = { _, _ in },
                onRename: @escaping (String, String) -> Void = { _, _ in },
                onAddFocused: @escaping (String) -> Void = { _ in },
                onDelete: @escaping (String) -> Void = { _ in },
                onSummonWindow: @escaping (CGWindowID) -> Void = { _ in },
                onReorderStages: @escaping (String, String) -> Void = { _, _ in }) {
        self.onTap = onTap
        self.onDropAssign = onDropAssign
        self.onRename = onRename
        self.onAddFocused = onAddFocused
        self.onDelete = onDelete
        self.onSummonWindow = onSummonWindow
        self.onReorderStages = onReorderStages
    }
}

// MARK: - Helpers partagés

public extension StageRenderContext {
    /// Couleur de bordure effective pour la stage courante.
    /// - Stage actif : `stageBorderOverrides[stage.id]` si présent, sinon `borderColor`
    /// - Stage inactif : `borderColorInactive`
    func resolvedBorderColor() -> String {
        if stage.isActive {
            return stageBorderOverrides[stage.id] ?? borderColor
        }
        return borderColorInactive
    }

    /// Indique si le halo doit être appliqué : actif global ET stage actuel actif.
    var shouldApplyHalo: Bool { haloEnabled && stage.isActive }
}

/// Contrat d'un rendu de cellule de stage.
///
/// Invariants :
/// - `rendererID` : lowercase-kebab-case `[a-z0-9-]`, ≤ 32 chars, unique dans le registre.
/// - `displayName` : human-readable, ≤ 40 chars.
/// - `render(...)` est **pure** : pas d'état mutable interne, pas de side-effect.
/// - Doit gérer le cas `context.stage.windowIDs.isEmpty` sans crash (placeholder).
public protocol StageRenderer: AnyObject {
    static var rendererID: String { get }
    static var displayName: String { get }

    @MainActor
    func render(context: StageRenderContext,
                callbacks: StageRendererCallbacks) -> AnyView
}
