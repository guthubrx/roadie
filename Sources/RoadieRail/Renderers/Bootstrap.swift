import Foundation

// SPEC-019 — Bootstrap des renderers livrés.
// Appelé une fois au démarrage du rail (dans `RailController.init`).
// Article I' constitution-002 : fonction-pivot d'enregistrement, ajouter un
// renderer = ajouter une ligne ici.

@MainActor
public func registerBuiltinRenderers() {
    StageRendererRegistry.register(
        id: StackedPreviewsRenderer.rendererID,
        factory: { StackedPreviewsRenderer() }
    )
    StageRendererRegistry.register(
        id: IconsOnlyRenderer.rendererID,
        factory: { IconsOnlyRenderer() }
    )
    StageRendererRegistry.register(
        id: HeroPreviewRenderer.rendererID,
        factory: { HeroPreviewRenderer() }
    )
    StageRendererRegistry.register(
        id: MosaicRenderer.rendererID,
        factory: { MosaicRenderer() }
    )
    StageRendererRegistry.register(
        id: Parallax45Renderer.rendererID,
        factory: { Parallax45Renderer() }
    )
}
