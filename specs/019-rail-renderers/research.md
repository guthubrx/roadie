# Research — SPEC-019 Rendus modulaires du navrail

**Date**: 2026-05-03
**Plan**: [plan.md](plan.md)

## Sources internes consultées

### `Sources/RoadieTiler/` — pattern de référence

Lecture intégrale de :
- `TilerProtocol.swift` (28 LOC) — protocole minimal `Tiler: AnyObject` avec 6 méthodes pures
- `TilerRegistry.swift` (38 LOC) — registre `[TilerStrategy: () -> any Tiler]` avec `register/make/availableStrategies/reset`
- `BSPTiler.swift`, `MasterStackTiler.swift` — implémentations concrètes
- `LayoutEngine.swift` — consommateur qui appelle `TilerRegistry.make(strategy)?` au boot et délègue layout/insert/remove

**Décision** : reproduire **textuellement** ce schéma pour les renderers. Mêmes signatures de `register`/`make`, mêmes conventions de nommage, même style de logs (`logInfo("renderer_registered", ["id": id])`).

**Différence assumée** : `Tiler` est class-bound et stateful (les tilers gardent l'état du tree BSP). Les `StageRenderer` sont **stateless** par construction (chaque appel à `render` est une fonction pure du contexte). Donc le registry stockera des **factories** mais on peut envisager de cacher l'instance créée si profilage le justifie. Pour le MVP, factory à chaque appel = OK (création d'un objet vide quasi-gratuite).

### `Sources/RoadieRail/Views/WindowStack.swift` — code à extraire

Lecture du fichier actuel (~270 LOC effectives). Structure observée :

```text
WindowStack (struct View)
├── Constantes (maxVisible, stackOffsetXY, stackScale, stackOpacity, halo colors)
├── État (@State isDropTargeted, renameSheet, etc.)
├── body (ZStack avec haloed + stackedPreviews + appIconBadge + dropHighlight)
├── visibleWids computed (filtrage + tri)
├── stackedPreviews @ViewBuilder (cascade ZStack)
├── activeDot @ViewBuilder
├── dropHighlight @ViewBuilder
├── dominantAppIcon
├── appIconBadge
├── contextMenuItems (Rename, Add focused, Delete)
├── renameSheetView
├── commitRename
└── resolveIcon (logique de résolution NSImage)
```

**Découpage proposé pour US1** :
- **Renderer responsabilité** : `body`, `stackedPreviews`, `visibleWids`, `dominantAppIcon`, `appIconBadge`, `haloed`, constantes de cascade — la logique de **rendu visuel pur**.
- **Consommateur (StageStackView) responsabilité** : drop targeting state, contextMenu (rename/delete), drag-drop hooking, callback orchestration. Sont liées à des comportements transverses qui restent au consommateur.

**Justification** : cohérent avec le principe « renderer = transformer pur du contexte → View ». Les comportements (drag-drop, rename via sheet) restent au niveau supérieur pour ne pas être dupliqués dans chaque renderer.

### `~/.config/roadies/roadies.toml` (config utilisateur) — section `[fx.rail]`

Section existante (cf. SPEC-014) avec clés actuelles : `enabled`, `width`, `halo_color`, `halo_intensity`, `halo_radius`, `wallpaper_click_to_stage`. Ajout d'une clé optionnelle `renderer = "<id>"` est non-breaking.

### Constitution-002 Article I' « Architecture pluggable obligatoire »

Citation pertinente : *« Toute fonctionnalité dont l'utilisateur peut raisonnablement attendre des variantes (ex: stratégies de tiling, formats de log, sources de configuration) DOIT être implémentée derrière un protocole + registre, jamais via if/switch interne. »*

→ Le rendu du rail est précisément ce cas. Cette spec est donc directement motivée par l'Article I'.

## Sources externes consultées

### SwiftUI `some View` + `@ViewBuilder` + boundary `AnyView`

- WWDC 2019 « SwiftUI Essentials » : `some View` retourne un type opaque déterminé à la compilation. Plus performant qu'`AnyView` (qui fait un type erasure runtime).
- Limite : `some View` rend impossible le stockage hétérogène (`[some View]` n'existe pas — chaque `some View` retourné peut avoir un type différent).
- **Compromis adopté** : chaque renderer interne utilise `@ViewBuilder` + `some View` (idiomatique, performant). Au boundary du registry/consommateur, on wrap dans `AnyView`. Coût : 1 indirection par cellule, négligeable.

### Pattern « Strategy + Registry » en Swift

- Article *« Strategy Pattern in Swift »* (Swift by Sundell, 2023) : recommande exactement la structure `protocol + dict de factories`, avec un type token (string id) pour la sélection.
- Confirmation que c'est l'idiome standard ; pas de surprise architecturale.

### Hot-reload de config TOML dans daemon Swift

- `Sources/RoadieCore/Config/ConfigLoader.swift` (existant) supporte déjà `ConfigLoader.load()` qui re-parse le TOML. Le daemon a déjà la logique `daemon.reload` qui re-lit la config.
- Côté rail (process séparé) : il consomme le stream `events --follow`. Il faut juste **ajouter un nouvel event** `config_reloaded` (publié quand `daemon.reload` réussit), puis brancher `RailController.handleEvent` pour relire `[fx.rail].renderer` et reconstruire les cellules.

## Décisions consolidées

| ID | Décision | Rationale | Alternatives |
|---|---|---|---|
| D1 | Protocole `StageRenderer: AnyObject` avec `func render(context: StageRenderContext) -> AnyView` | Stockage hétérogène dans dict, perf acceptable | `some View` (impossible en stockage hétérogène) ; struct value (incohérent avec `Tiler`) |
| D2 | Registry singleton statique `enum StageRendererRegistry` | Cohérence stricte avec `TilerRegistry` | DI container (over-engineering) |
| D3 | Sélection via `[fx.rail].renderer` TOML, default `"stacked-previews"` | Cohérence avec autres clés `[fx.rail]` | Variable d'env (moins persistant), CLI-only (moins découvrable) |
| D4 | Hot-reload via event `config_reloaded` consommé par RailController | Le rail est déjà abonné au stream events | Push direct daemon → rail (couplage inutile) |
| D5 | Erreur silencieuse + fallback `stacked-previews` | UX (l'utilisateur ne voit pas son rail crasher) ; warning loggé pour debug | Fail-fast strict (mauvaise UX power-user qui fait une faute de frappe) |
| D6 | Consommateur garde drag-drop, rename, contextMenu | Transverse, ne se duplique pas dans chaque renderer | Renderer prend tout (chaque renderer ré-implémenterait — DRY violé) |

## Red flags identifiés (et levés)

Aucun. Pattern éprouvé, framework existant, dépendances zéro nouvelles.
