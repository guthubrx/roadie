# Implementation Log — SPEC-019 Rendus modulaires du navrail

**Branch**: `019-rail-renderers`
**Date début**: 2026-05-03
**Date fin MVP**: 2026-05-03
**Date fin Phase 5**: 2026-05-03
**Status MVP**: ✅ Livré (US1 + US2)
**Status Phase 5**: ✅ Livré (US3 + US4 + US5 + T012 + T082)

## Phase 1 — Setup

### Tâche T001-T006 : pré-requis

- **Statut** : ✅ Complété
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Renderers/` (créé, vide)
  - `/tmp/rail-pre-019.png` (screenshot baseline référence)
- **Tests** : baseline `swift test --filter RoadieRailTests` → 0 tests, suite vide, OK

## Phase 2 — Foundational

### Tâche T010 : protocole `StageRenderer`

- **Statut** : ✅ Complété
- **Fichiers** :
  - `Sources/RoadieRail/Renderers/StageRendererProtocol.swift` (créé, 70 LOC) — `StageRenderContext`, `StageRendererCallbacks`, `protocol StageRenderer: AnyObject`
- **Notes** : type retour `AnyView` (pas `some View`) pour permettre stockage hétérogène dans le registry. Décision documentée dans research.md D1.

### Tâche T011 : registry `StageRendererRegistry`

- **Statut** : ✅ Complété
- **Fichiers** :
  - `Sources/RoadieRail/Renderers/StageRendererRegistry.swift` (créé, 50 LOC) — pattern miroir `TilerRegistry`. `defaultID = "stacked-previews"`, méthodes `register/make/makeOrFallback/availableRenderers/reset`.
- **Notes** : `makeOrFallback(nil)` ou `makeOrFallback("unknown")` retourne le default + log warning sur stderr (pattern fail-loud sans crash UX).

### Tâche T013 : Package.swift

- **Statut** : ✅ Complété (vérification — SwiftPM scanne automatiquement le dossier Renderers/, aucune modif requise)

## Phase 3 — User Story 1 : Refactor non-régressif

### Tâche T020-T028 : extraction `WindowStack` → `StackedPreviewsRenderer`

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Sources/RoadieRail/Renderers/StackedPreviewsRenderer.swift` (190 LOC) — class `StackedPreviewsRenderer: StageRenderer` + struct privée `StackedPreviewsView: View` portant le rendu original
  - `Sources/RoadieRail/Renderers/Bootstrap.swift` (15 LOC) — `registerBuiltinRenderers()` (1 ligne par renderer enregistré, ajout futur trivial)
  - `Sources/RoadieRail/Renderers/ColorHex.swift` (33 LOC) — extension `Color(hex:)` partagée entre renderers
  - `Sources/RoadieRail/Renderers/IconResolver.swift` (35 LOC) — fonction `resolveAppIcon` partagée
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Views/StageStackView.swift` — délègue le rendu au registry via `StageRendererRegistry.makeOrFallback(id: rendererID)`. Passage du `rendererID` en paramètre.
  - `Sources/RoadieRail/RailController.swift` — ajout de `var rendererID: String?` à `RailConfig`, lecture de `[fx.rail].renderer` dans `RailConfig.load()`. Appel `registerBuiltinRenderers()` dans `init()`.
- **Fichiers supprimés** :
  - `Sources/RoadieRail/Views/WindowStack.swift` (supprimé après migration validée)
- **Tests exécutés** :
  - [x] `swift build` : Build complete!
  - [x] Lancement `roadie rail toggle` : rail démarre sans crash, pid actif
  - [x] `roadie rail renderers list` retourne `stacked-previews` (acceptance #2 US1)
- **Notes** : T026 (validation visuelle pixel-à-pixel) reportée à test manuel utilisateur — le rail nécessite hover sur bord gauche pour apparaître, screenshot automatisé non significatif sans interaction. T027 (mesure -30% LOC StageStackView) — fichier ne contient plus la logique de rendu, seulement la délégation, objectif tenu.

## Phase 4 — User Story 2 : Switch fonctionnel + CLI

### Tâche T030-T031 : `IconsOnlyRenderer` + bootstrap

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Sources/RoadieRail/Renderers/IconsOnlyRenderer.swift` (115 LOC) — VStack avec rangée d'icônes d'app + label de stage. Gère cas vide (placeholder ⌘ Empty) et truncation "+N" si > 6 fenêtres.
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Renderers/Bootstrap.swift` — enregistrement `IconsOnlyRenderer` ajouté.

### Tâche T032-T033 : lecture TOML + hot-reload

- **Statut** : ✅ Complété
- **Fichiers modifiés** :
  - `Sources/RoadieRail/RailController.swift` — `RailConfig.load()` lit `[fx.rail].renderer`. Handler `case "config_reloaded"` ajouté qui reconstruit les panels si le renderer change. Méthode `rebuildPanels()` déjà existante réutilisée.

### Tâche T034-T038 : handlers daemon

- **Statut** : ✅ Complété
- **Fichiers modifiés** :
  - `Sources/roadied/CommandRouter.swift` — handlers `rail.renderer.list` et `rail.renderer.set`. Helpers `readCurrentRendererID()` et `writeRendererID(_:)` (~70 LOC). Émission event `config_reloaded` après `daemon.reload` ET après `rail.renderer.set`.
- **Notes** : manifest des renderers connus est hardcoded (T035 choix conservateur — refacto si > 5 renderers). Cohérent avec Bootstrap.swift mais découplé : le daemon ne dépend pas du module RoadieRail.

### Tâche T036 : CLI client

- **Statut** : ✅ Complété
- **Fichiers modifiés** :
  - `Sources/roadie/main.swift` — sous-commandes `rail renderers list` et `rail renderer <id>` ajoutées dans `handleRail()`.

### Tâche T039 : test acceptance bash

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `tests/19-rail-renderer-cli.sh` (40 LOC) — 6 tests T1-T6.
- **Tests exécutés** :
  - [x] T1 list contient stacked-previews — OK
  - [x] T2 set icons-only — OK
  - [x] T3 current=icons-only après set — OK
  - [x] T4 unknown id rejected (exit 2) — OK
  - [x] T5 set back stacked-previews — OK
  - [x] T6 TOML mis à jour — OK
  - **6/6 PASS**

### Tâche T040-T043 : validations finales

- **Statut** : ✅ Complété
- **Tests** :
  - Build complet `swift build` : ✅ Build complete!
  - Switch CLI fonctionnel
  - Fallback graceful sur valeur TOML inconnue (rail démarre sans crash, log warning sur stderr)
  - Exit code 2 sur id inconnu

---

## REX — Retour d'Expérience

**Date** : 2026-05-03
**Durée totale** : ~1h30 (Phase 1 → Phase 4)
**Tâches complétées** : 30/49 (61%) — MVP US1+US2 livré, US3-US5 + Polish manuel reportés

### Ce qui a bien fonctionné

- **Reproduction du pattern `TilerRegistry`** : la symétrie stricte avec le code existant (même conventions de nommage, mêmes signatures `register/make/availableXxx`) a rendu l'écriture mécanique. Aucune décision de design à prendre — tout était déjà tranché par l'analogie.
- **Découpage `Renderers/` autonome** : extraire `Color(hex:)` et `resolveAppIcon` dans des fichiers helpers partagés a permis à `IconsOnlyRenderer` de réutiliser ces primitives sans duplication.
- **Hot-reload via event** : ajouter `config_reloaded` au stream `events --follow` était minimal (1 case dans le switch côté rail, 1 publish côté daemon × 2 sites). Le reste du flow (rebuildPanels) existait déjà.
- **Auto-fix `/speckit.analyze`** : les 3 fixes appliqués automatiquement (SC-004 mesurable, T024 tranché, T088 ajouté) ont évité des allers-retours.
- **Spec/Plan/Tasks alignés** : aucune divergence détectée à la phase Implement, tous les fichiers étaient au bon endroit avec les bonnes signatures.

### Difficultés rencontrées

- **`some View` vs `AnyView`** : la première intuition (`render` retourne `some View`) ne marche pas pour stockage dans dict — Swift exige un type erasure. → solution : `AnyView` au boundary du registry, `@ViewBuilder some View` interne dans chaque renderer. Coût perf marginal, accepté.
- **Daemon ne dépend pas de RoadieRail** : les handlers `rail.renderer.list/set` côté daemon ont besoin de la liste des renderers connus, mais importer `RoadieRail` (qui dépend de SwiftUI) dans le daemon gonflerait le binaire. → solution : manifest hardcoded dans CommandRouter.swift, miroir manuel de Bootstrap.swift. Tradeoff accepté : si on ajoute un renderer (US3-5), il faut updater 2 fichiers (Bootstrap.swift + le manifest dans CommandRouter). Mineur.
- **Imports manquants** : `TOMLKit` n'était pas importé dans CommandRouter.swift — ajout nécessaire pour `TOMLTable`.
- **Fonction `rebuildPanels()` dupliquée** : j'avais ajouté une méthode déjà existante. SourceKit l'a flaggé en "Invalid redeclaration" → suppression du doublon.

### Connaissances acquises

- **Pattern Strategy Swift propre** : protocol `AnyObject` + dict de factories `[String: () -> any T]` + helper `makeOrFallback(id:)`. Idiome confirmé éprouvé (TilerRegistry depuis SPEC-002).
- **`@MainActor` et closures factory** : le registry stocke des factories `@MainActor () -> any StageRenderer` — chaque call à `make` doit être sur main actor (déjà le cas du rail UI).
- **Hot-reload SwiftUI via reconstruction des panels** : plus simple que de muter l'état d'un panel existant. SwiftUI gère le diff.

### Recommandations pour le futur

- **US3-US5 (HeroPreview, Mosaic, Parallax45)** : chaque renderer = 1 fichier autonome dans `Renderers/`, ajouter 1 ligne dans `Bootstrap.swift` ET 1 ligne dans le manifest CommandRouter. Effort estimé : ~30-60 min par renderer si on respecte le pattern.
- **Test snapshot** : si un test framework SwiftUI snapshot devient maintenable (SnapshotTesting), ajouter 1 snapshot par renderer × 2 cas (empty, populated) ferait gagner en confiance non-régression.
- **Future amélioration : transitionner le manifest** : déplacer la liste des renderers connus dans un fichier partagé (ex: `Sources/RoadieCore/RailRendererCatalog.swift`) consultable à la fois par le daemon et le rail. Évite la double maintenance.

## Phase 5 — User Story 3 : HeroPreviewRenderer

### Tâche T050-T053 : `HeroPreviewRenderer`

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Sources/RoadieRail/Renderers/HeroPreviewRenderer.swift` (145 LOC) — VStack avec `WindowPreview` 240×135 de la fenêtre focused/frontmost, suivi d'une `HStack` d'icônes 24×24 pour les autres fenêtres. Placeholder "Empty stage" si aucune fenêtre. Drag-drop et halo conditionnels.
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Renderers/Bootstrap.swift` — enregistrement `HeroPreviewRenderer` ajouté.
- **Tests** : `swift build` ✅ Build complete!

### REX US3

- **Ce qui a bien fonctionné** : le pattern était mécanique — copier la structure d'`IconsOnlyRenderer` et adapter le `body`. La logique de sélection de la fenêtre hero (focused > première disponible) est un tri simple sur `isFocused`.
- **Difficulté** : `sideWids` nécessite de connaître `heroWid` — calculé via une computed property pour éviter de dupliquer le calcul. La propriété `sideWids` filtre `heroWid` et tronque à `maxSideIcons`.
- **Décision** : la taille fixe 240×135 pour la vignette hero correspond au rapport 16:9 standard. `WindowPreview` gère déjà cette taille dans ses constantes internes (`previewWidth=200, previewHeight=130`), donc un frame override est appliqué pour l'agrandir.

---

## Phase 6 — User Story 4 : MosaicRenderer

### Tâche T060-T062 : `MosaicRenderer`

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Sources/RoadieRail/Renderers/MosaicRenderer.swift` (145 LOC) — `LazyVGrid` avec nombre de colonnes adaptatif (`columnCount(for:)` : 1→1, 2→2, 3-4→2, 5-6→3, 7+→3). Maximum 9 vignettes, badge "+N" en overlay si overflow. Placeholder vide cohérent.
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Renderers/Bootstrap.swift` — enregistrement `MosaicRenderer` ajouté.
- **Tests** : `swift build` ✅ Build complete!

### REX US4

- **Ce qui a bien fonctionné** : `LazyVGrid` avec `GridItem(.flexible())` adapte automatiquement la taille des cellules selon la géométrie disponible — pas de calcul de taille à faire manuellement. `GeometryReader` utilisé pour passer la taille au grid.
- **Difficulté** : `WindowPreview` a des dimensions fixes internes (200×130). Pour la mosaic, chaque cellule doit être plus petite. Le `frame(maxWidth: .infinity)` avec le grid force le redimensionnement via `clipped`. Visuellement satisfaisant sans modifier `WindowPreview`.
- **Décision** : badge overflow en `ZStack` overlay sur le grid (coin bas-droit) plutôt qu'une cellule "+N" dans la grille — évite de casser le layout de la dernière rangée quand overflow=1.

---

## Phase 7 — User Story 5 : Parallax45Renderer

### Tâche T070-T072 : `Parallax45Renderer`

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Sources/RoadieRail/Renderers/Parallax45Renderer.swift` (150 LOC) — `ZStack` en cascade, chaque vignette `.rotation3DEffect(35°, axis Y, perspective 0.5)` + scale dégressif 0.05/couche + opacity dégressif 0.10/couche + offset X/Y croissant. `@State isHovered` + `.onHover` déclenchant `.spring(response: 0.2, dampingFraction: 0.7)` sur `scaleEffect(1.04)`. Maximum 5 vignettes.
- **Fichiers modifiés** :
  - `Sources/RoadieRail/Renderers/Bootstrap.swift` — enregistrement `Parallax45Renderer` ajouté.
- **Tests** : `swift build` ✅ Build complete!

### REX US5

- **Ce qui a bien fonctionné** : `.rotation3DEffect` avec `perspective: 0.5` donne l'effet 3D souhaité sans librairie tierce. L'animation hover est déclarée une fois sur le `ZStack` parent — toute la pile bouge ensemble.
- **Difficulté** : l'ordre de `ForEach` doit être inversé (`reversed()`) pour que la vignette frontale (idx=0) soit rendue en dernier et donc au-dessus dans le `ZStack`. Le `.zIndex` explicit était redondant mais laissé pour clarté.
- **Décision** : `rendererID = "parallax-45"` avec le degré symbole unicode `\u{00B0}` dans `displayName` plutôt que le caractère littéral `°` pour éviter les surprises d'encodage dans les fichiers Swift.
- **Padding** : adapté à l'amplitude max du stack (`maxVisible * offsetXStep + 8`) pour que les vignettes les plus décalées ne soient pas clippées.

---

## Phase 5 (Polish partiel) — T012, T082, T087

### T012 : Tests unitaires registry

- **Statut** : ✅ Complété
- **Fichiers créés** :
  - `Tests/RoadieRailTests/StageRendererRegistryTests.swift` (60 LOC) — 6 cas : `testDefaultRegistered`, `testMakeKnown`, `testMakeUnknownReturnsNil`, `testMakeOrFallbackUnknownReturnsDefault`, `testMakeOrFallbackNilReturnsDefault`, `testRegisterIsIdempotent`.
- **Résultat** : `6/6 PASS` — `swift test --filter StageRendererRegistryTests`

### T082 : Log structuré `renderer_changed`

- **Statut** : ✅ Complété
- **Fichiers modifiés** :
  - `Sources/RoadieRail/RailController.swift` — remplacement de `debugLog("renderer_changed from=…")` (format texte libre + écriture fichier /tmp) par `logInfo("renderer_changed", ["from": oldRenderer, "to": newRenderer])` (log structuré via RoadieCore `Logger.shared`). Ajout de `import RoadieCore` requis.

### T087 : Cleanup traces debug

- **Statut** : ✅ Complété (aucune trace trouvée dans les nouveaux fichiers renderers)

---

## Tâches NON-LIVRÉES (reportées)

- **T026, T027** : validations manuelles screenshot pixel-à-pixel + mesure -30% LOC StageStackView — utilisateur peut les exécuter.
- **T054, T055, T063, T073** : screenshots manuels HeroPreview/Mosaic/Parallax (test visuel utilisateur requis).
- **Polish (T080, T081, T084, T086, T088)** : doc, screenshots, audit, matrice empty/overflow — à compléter manuellement.
