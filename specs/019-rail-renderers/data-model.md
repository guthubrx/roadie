# Data Model — SPEC-019 Rendus modulaires du navrail

**Date**: 2026-05-03
**Plan**: [plan.md](plan.md)

## Vue d'ensemble

Pas d'entité métier ni persistée. Les structures introduites sont des **types de la couche View** (Swift/SwiftUI). Aucune mutation d'état persistant ; les renderers sont stateless.

## Entités

### `StageRenderContext` (struct, value)

Contexte transmis au renderer pour produire la View d'une cellule de stage.

| Champ | Type | Source | Notes |
|---|---|---|---|
| `stage` | `StageVM` | `RailController.state.stages[i]` | VM existante SPEC-014 (id, displayName, isActive, windowIDs) |
| `windows` | `[CGWindowID: WindowVM]` | `RailController.state.windows` | dict app/pid/bundle/floating/title pour résolution icônes et tri |
| `thumbnails` | `[CGWindowID: ThumbnailVM]` | `RailController.state.thumbnails` | dict pngData (peut être vide pour wid sans capture) |
| `haloColorHex` | `String` | TOML `[fx.rail].halo_color` | hex `#RRGGBB` ou `#RRGGBBAA` |
| `haloIntensity` | `Double` | TOML `[fx.rail].halo_intensity` | 0.0..1.0 |
| `haloRadius` | `Double` | TOML `[fx.rail].halo_radius` | px |

### `StageRendererCallbacks` (struct, value)

Callbacks passés par le consommateur, orchestration des actions UI.

| Champ | Signature | Description |
|---|---|---|
| `onTap` | `() -> Void` | Switch vers ce stage |
| `onDropAssign` | `(CGWindowID, String) -> Void` | (widDropée, sourceStageID) → réassigne |
| `onRename` | `(String, String) -> Void` | (stageID, newName) |
| `onAddFocused` | `(String) -> Void` | (stageID) |
| `onDelete` | `(String) -> Void` | (stageID) |

### `StageRenderer` (protocol, AnyObject)

Contrat que toute implémentation de renderer doit satisfaire.

```text
protocol StageRenderer: AnyObject {
    static var rendererID: String { get }      // "stacked-previews", "icons-only", ...
    static var displayName: String { get }     // "Stacked previews", "Icons only", ...

    @MainActor
    func render(context: StageRenderContext,
                callbacks: StageRendererCallbacks) -> AnyView
}
```

**Invariants** :
- `rendererID` est unique dans le registre, lowercase-kebab-case.
- `render` est une fonction pure du contexte (pas d'état interne mutable).
- `render` ne déclenche aucun side-effect (pas d'appel IPC, pas d'écriture disque).
- Tout drag-drop de fenêtre DOIT passer par `callbacks.onDropAssign` (le renderer ne gère pas la persistance).

### `StageRendererRegistry` (enum, static)

Registre central. Mêmes signatures que `TilerRegistry`.

```text
enum StageRendererRegistry {
    static func register(id: String, factory: @escaping () -> any StageRenderer)
    static func make(id: String) -> (any StageRenderer)?
    static var availableRenderers: [String]   // tri lex
    static func reset()                       // tests only
    static var defaultID: String { "stacked-previews" }

    /// Helper : `make(id) ?? make(defaultID)!` avec log warning si fallback déclenché.
    static func makeOrFallback(id: String?) -> any StageRenderer
}
```

### `RailRendererConfig` (struct, value, lecture seule)

Reflet en mémoire de la clé TOML `[fx.rail].renderer`. Lu au boot et à chaque event `config_reloaded`.

| Champ | Type | Default |
|---|---|---|
| `rendererID` | `String?` | `nil` (= `defaultID`) |

## Relations

```text
RailController
  └── owns RailRendererConfig
  └── on event "config_reloaded" → reload RailRendererConfig
  └── passes activeRenderer = StageRendererRegistry.makeOrFallback(config.rendererID) to StageStackView

StageStackView
  └── for each stage in state.stages :
       └── activeRenderer.render(context: ..., callbacks: ...) → AnyView

StageRendererRegistry (singleton)
  └── { "stacked-previews": () -> StackedPreviewsRenderer(), ... }
  └── populated at boot by registerBuiltinRenderers() in RailController init

StageRenderer (protocol)
  ├── StackedPreviewsRenderer (concrete, US1)
  ├── IconsOnlyRenderer (concrete, US2)
  ├── HeroPreviewRenderer (concrete, US3)
  ├── MosaicRenderer (concrete, US4)
  └── Parallax45Renderer (concrete, US5)
```

## Validation rules

- **VR-01** : `rendererID` est non-vide, longueur ≤ 32, charset `[a-z0-9-]`.
- **VR-02** : registration d'un id déjà présent OVERRIDE silencieusement (idempotent, cohérent avec `TilerRegistry`).
- **VR-03** : si `RailRendererConfig.rendererID` non `nil` mais introuvable dans le registry, log warning et fallback sur `defaultID`.
- **VR-04** : `defaultID` (= `"stacked-previews"`) DOIT toujours être enregistré (vérifié au boot par assertion fail-loud si registre vide).

## State transitions

Pas de transition d'état. Le seul changement d'état est la rotation du `activeRenderer` quand `config_reloaded` est consommé. Diagramme :

```text
[Boot]
   │
   ▼
[Read TOML] → rendererID = config["fx.rail.renderer"] ?? defaultID
   │
   ▼
[activeRenderer ← StageRendererRegistry.makeOrFallback(rendererID)]
   │
   ▼
[Render stages cells via activeRenderer]
   │
   │  (event "config_reloaded" reçu)
   ▼
[Re-read TOML] → nouvel rendererID
   │
   ▼
[activeRenderer ← StageRendererRegistry.makeOrFallback(newID)]
   │
   ▼
[State.stages SwiftUI redraw → cells rendues par le nouveau renderer]
```
