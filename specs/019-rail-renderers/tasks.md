# Tasks — SPEC-019 Rendus modulaires du navrail

**Status**: Draft
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)
**Created**: 2026-05-03

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichiers indépendants, aucune dépendance sur tâche en cours)
- `[US<k>]` = appartient à user story k

## Path Conventions

Tous les chemins relatifs à la racine du repo `/Users/moi/Nextcloud/10.Scripts/39.roadies/`.

---

## Phase 1 — Setup

- [X] T001 Vérifier que la branche `019-rail-renderers` est checkout (`git branch --show-current`)
- [X] T002 [P] Confirmer la dépendance SPEC-014 effective : `test -f Sources/RoadieRail/RailController.swift` doit réussir (sinon abort spec)
- [X] T003 [P] Confirmer le pattern de référence : lire `Sources/RoadieTiler/TilerProtocol.swift` et `TilerRegistry.swift` pour reproduire les conventions de nommage et style
- [X] T004 [P] Bench baseline `swift test` doit passer 100% AVANT modification (filet de sécurité régression)
- [X] T005 Créer le dossier `Sources/RoadieRail/Renderers/` (vide pour le moment)
- [X] T006 Capturer un screenshot de référence du rail dans son état actuel : `screencapture -x /tmp/rail-pre-019.png` avec au moins 2 stages contenant chacun ≥ 2 fenêtres ; conserver pour validation US1

**Critère de fin Phase 1** : pré-conditions vérifiées, baseline tests verts, screenshot référence pris.

---

## Phase 2 — Foundational (blocant pour toutes les user stories)

- [X] T010 Créer `Sources/RoadieRail/Renderers/StageRendererProtocol.swift` (~60 LOC) avec : `struct StageRenderContext`, `struct StageRendererCallbacks`, `protocol StageRenderer: AnyObject` conformes au contrat [contracts/stage-renderer-protocol.md](contracts/stage-renderer-protocol.md)
- [X] T011 Créer `Sources/RoadieRail/Renderers/StageRendererRegistry.swift` (~50 LOC) avec : `enum StageRendererRegistry`, `defaultID`, `register/make/makeOrFallback/availableRenderers/reset` conformes au contrat [contracts/registry-api.md](contracts/registry-api.md)
- [ ] T012 [P] Créer `Tests/RoadieRailTests/StageRendererRegistryTests.swift` couvrant : default registered, makeKnown, makeUnknownReturnsNil, makeOrFallbackUnknownReturnsDefault, makeOrFallbackNilReturnsDefault, registerIsIdempotent (cf [contracts/registry-api.md](contracts/registry-api.md) Tests unit)
- [X] T013 Vérifier que `Package.swift` inclut bien `Sources/RoadieRail/Renderers/` dans la target `RoadieRail` (par défaut SwiftPM scanne tout le dossier — vérification seulement)

**Critère de fin Phase 2** : protocol + registry compilent, tests unit registry passent.

---

## Phase 3 — User Story 1 : Refactor non-régressif (P1, MVP)

**Goal** : extraire la logique de rendu de `WindowStack.swift` dans `StackedPreviewsRenderer.swift`, brancher le consommateur `StageStackView` sur le registry, livrer un rail visuellement identique à l'avant-refactor.

**Independent test** : screenshot pixel-à-pixel du rail avant/après doit montrer < 1% de différence (SC-002).

- [X] T020 [US1] Créer `Sources/RoadieRail/Renderers/StackedPreviewsRenderer.swift` (~200 LOC) en y déplaçant le code de `WindowStack.swift` :
  - constantes (maxVisible, stackOffsetXY, stackScale, stackOpacity, halo colors)
  - struct `WindowStack` renommée en `final class StackedPreviewsRenderer: StageRenderer`
  - `static var rendererID: String { "stacked-previews" }`, `static var displayName: String { "Stacked previews" }`
  - méthode `render(context:callbacks:) -> AnyView` qui retourne `AnyView(StackedPreviewsView(context: context, callbacks: callbacks))`
  - struct interne `StackedPreviewsView: View` qui contient le `body` actuel + computed properties (visibleWids, dominantAppIcon, appIconBadge, haloed, dropHighlight, stackedPreviews)
  - extension `Color(hex:)` (déplacée ou rendue partagée)
- [X] T021 [US1] Modifier `Sources/RoadieRail/Views/StageStackView.swift` :
  - importer le module Renderers
  - remplacer l'instanciation `WindowStack(...)` par `currentRenderer.render(context: ..., callbacks: ...)` où `currentRenderer = StageRendererRegistry.makeOrFallback(id: railRendererID)`
  - lire `railRendererID` depuis l'état (initialement nil → fallback default)
  - vérifier que toutes les callbacks (onTap, onDropAssign, onRename, onAddFocused, onDelete) sont passées correctement
- [X] T022 [US1] Modifier `Sources/RoadieRail/RailController.swift` :
  - dans `init()`, appeler `registerBuiltinRenderers()` (à créer ou inline T024)
  - exposer `state.rendererID: String?` lu depuis TOML `[fx.rail].renderer` (peut rester nil pour l'instant, US2 active la lecture)
- [X] T023 [US1] Supprimer `Sources/RoadieRail/Views/WindowStack.swift` une fois la migration validée (le contenu est entièrement déplacé dans StackedPreviewsRenderer)
- [X] T024 [US1] Créer le fichier `Sources/RoadieRail/Renderers/Bootstrap.swift` (~15 LOC) avec une fonction publique `public func registerBuiltinRenderers()` qui enregistre `StackedPreviewsRenderer` au boot. Choix tranché : fichier dédié (pas inline dans `StageRendererRegistry.swift`) pour faciliter l'ajout futur des autres renderers (US2-US5) sans toucher au registry
- [X] T025 [US1] Build complet : `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin swift build` doit retourner `Build complete!`
- [ ] T026 [US1] Re-démarrer rail + capturer screenshot : `screencapture -x /tmp/rail-post-019-us1.png`. Comparer visuellement avec `/tmp/rail-pre-019.png` — différence visuelle nulle ou < 1% (SC-002)
- [ ] T027 [P] [US1] Vérifier que `wc -l Sources/RoadieRail/Views/StageStackView.swift` retourne au moins 30% LOC en moins par rapport au baseline (SC-006)
- [X] T028 [US1] Vérifier `roadie rail renderers list` retourne au minimum `stacked-previews` (test acceptance scenario US1#2)

**Critère de fin US1** : refactor compile, rail visuellement identique, registry expose `stacked-previews`. **MVP partiel livrable.**

---

## Phase 4 — User Story 2 : Switch fonctionnel (P1, MVP)

**Goal** : livrer le second renderer (`IconsOnlyRenderer`), brancher la lecture TOML `[fx.rail].renderer`, ajouter les commandes CLI `roadie rail renderer/renderers`, brancher le hot-reload via event `config_reloaded`.

**Independent test** : `roadie rail renderer icons-only` + observation visuelle → rail bascule sur icônes en < 1s (acceptance #1).

- [X] T030 [US2] Créer `Sources/RoadieRail/Renderers/IconsOnlyRenderer.swift` (~80 LOC) :
  - `static var rendererID: String { "icons-only" }`, `static var displayName: String { "Icons only" }`
  - `render(context:callbacks:)` qui dessine pour chaque cellule : un VStack avec icônes d'app (taille 32×32, jusqu'à 6 visibles puis "+N"), nom du stage en label, halo si actif
  - reuse la fonction `resolveIcon(pid:bundleID:appName:)` extraite de StackedPreviewsRenderer (déplacée dans helper partagé `Renderers/IconHelper.swift` si non déjà fait)
  - gérer cas vide : afficher icône générique ⌘ + texte "Empty"
  - drop targeting : `.dropDestination` qui appelle `callbacks.onDropAssign`
- [X] T031 [US2] Modifier `registerBuiltinRenderers()` pour ajouter `IconsOnlyRenderer`
- [X] T032 [US2] Modifier `Sources/RoadieRail/RailController.swift` pour lire `[fx.rail].renderer` depuis TOML au boot et stocker dans `state.rendererID`. Brancher la résolution dans `StageStackView` (T021 bis)
- [X] T033 [US2] Ajouter handler `case "config_reloaded"` dans `RailController.handleEvent(...)` qui : relit le TOML, met à jour `state.rendererID`, déclenche un redraw SwiftUI
- [X] T034 [US2] Modifier `Sources/roadied/CommandRouter.swift` :
  - ajouter `case "rail.renderer.list"` qui retourne `{default, current, renderers: [{id, display_name}]}` selon [contracts/cli-protocol.md](contracts/cli-protocol.md). Le `current` est lu depuis le TOML config courant ; les `renderers` sont une liste hardcoded ou extraite via un fichier de manifest (cf T035)
  - ajouter `case "rail.renderer.set"` qui : valide l'id contre la liste connue, écrit `renderer = "<id>"` dans `[fx.rail]` du TOML utilisateur (préservation du reste), publie event `config_reloaded`
- [X] T035 [US2] Définir un manifest des renderers connus côté daemon (~20 LOC) — soit hardcoded en CommandRouter (liste statique), soit shared dans un module commun (`Sources/RoadieCore/RailRendererCatalog.swift` exposant `[id, displayName]` paires). Choix : hardcoded au plus simple, refacto si la liste dépasse 5
- [X] T036 [US2] Modifier `Sources/roadie/main.swift` :
  - ajouter dans le routing `case "rail"` les sous-commandes `renderers list` et `renderer <id>`
  - support `--json` flag pour `renderers list`
  - exit codes 0/2/3/5 selon [contracts/cli-protocol.md](contracts/cli-protocol.md)
- [X] T037 [US2] Modifier `Sources/RoadieDesktops/EventBus.swift` (ou équivalent) pour ajouter un helper `DesktopEvent.configReloaded()` qui retourne un event de nom `"config_reloaded"` avec payload vide
- [X] T038 [US2] Au handler `daemon.reload` existant, publier l'event `config_reloaded` après que la config est rechargée
- [X] T039 [P] [US2] Test acceptance bash `tests/19-rail-renderer-cli.sh` couvrant T1-T6 de [contracts/cli-protocol.md](contracts/cli-protocol.md)
- [X] T040 [US2] Build complet OK
- [X] T041 [US2] Test manuel : `roadie rail renderer icons-only` → rail bascule visuellement (icônes au lieu de previews) en moins d'1s. Screenshot `/tmp/rail-us2-icons.png`
- [X] T042 [US2] Test manuel : valeur inconnue dans TOML → warning loggé, fallback `stacked-previews` (acceptance #2)
- [X] T043 [US2] Test manuel : `roadie rail renderer parallax-99` → exit code 5 + message clair (acceptance #3 ajusté)

**Critère de fin US2** : switch CLI fonctionnel, hot-reload OK, fallback graceful. **MVP livrable.**

---

## Phase 5 — User Story 3 : HeroPreviewRenderer (P2)

**Goal** : livrer `hero-preview` — 1 grande capture frontmost + barre d'icônes app dessous.

- [ ] T050 [US3] Créer `Sources/RoadieRail/Renderers/HeroPreviewRenderer.swift` (~100 LOC) :
  - `rendererID = "hero-preview"`, `displayName = "Hero preview"`
  - `render` : VStack avec en haut WindowPreview de la wid frontmost (taille 240×135), en bas HStack d'icônes app (24×24) pour les autres wids du stage
  - placeholder « Empty stage » + icône générique si stage vide
  - drag-drop sur l'ensemble de la cellule
  - halo conditionnel si stage actif
- [ ] T051 [US3] Enregistrer dans `registerBuiltinRenderers()`
- [ ] T052 [US3] Mettre à jour le manifest CommandRouter (T035) pour exposer `hero-preview` dans `rail.renderer.list`
- [ ] T053 [US3] Build OK
- [ ] T054 [US3] Test manuel `roadie rail renderer hero-preview` → screenshot `/tmp/rail-us3-hero.png` montrant 1 grande vignette + barre d'icônes (acceptance #1)
- [ ] T055 [US3] Test manuel stage vide → placeholder neutre (acceptance #2)

**Critère de fin US3** : `hero-preview` sélectionnable via CLI, comportement conforme à l'acceptance.

---

## Phase 6 — User Story 4 : MosaicRenderer (P3)

**Goal** : livrer `mosaic` — toutes vignettes en grille à plat (1×1, 2×1, 2×2, 3×2 selon nombre).

- [ ] T060 [US4] Créer `Sources/RoadieRail/Renderers/MosaicRenderer.swift` (~120 LOC) :
  - `rendererID = "mosaic"`, `displayName = "Mosaic"`
  - `render` : LazyVGrid avec colonnes adaptatives selon `windowIDs.count` (1→1, 2→2, 3-4→2, 5-6→3, >6→3 cols + truncation à 6 + indicateur "+N")
  - chaque cellule = WindowPreview taille adaptée
  - placeholder vide cohérent
  - halo conditionnel
- [ ] T061 [US4] Enregistrer dans `registerBuiltinRenderers()`, mettre à jour manifest
- [ ] T062 [US4] Build OK
- [ ] T063 [US4] Test manuel : 1 fenêtre → grande vignette unique (acceptance #2). 4 fenêtres → 2×2 (acceptance #1). Screenshot `/tmp/rail-us4-mosaic.png`

**Critère de fin US4** : `mosaic` sélectionnable, layout responsive au nombre.

---

## Phase 7 — User Story 5 : Parallax45Renderer (P3)

**Goal** : livrer `parallax-45` — vignettes empilées avec rotation 3D 45° axe Y + micro-anim hover.

- [ ] T070 [US5] Créer `Sources/RoadieRail/Renderers/Parallax45Renderer.swift` (~150 LOC) :
  - `rendererID = "parallax-45"`, `displayName = "Parallax 45°"`
  - `render` : ZStack avec WindowPreview successifs en cascade `.rotation3DEffect(45°, axis: (x: 0, y: 1, z: 0)) + .perspective`
  - offset croissant + scale dégressive entre les couches
  - `@State isHovered` + `.onHover` qui déclenche `withAnimation(.spring(response: 0.2)) { scale = 1.04 }`
  - max 5 vignettes visibles
- [ ] T071 [US5] Enregistrer + manifest
- [ ] T072 [US5] Build OK
- [ ] T073 [US5] Test manuel : effet visuel 3D présent (acceptance #1). Hover → micro-anim < 200 ms (acceptance #2). Screenshot `/tmp/rail-us5-parallax.png`

**Critère de fin US5** : `parallax-45` sélectionnable, effet visible.

---

## Phase 8 — Polish & cross-cutting

- [ ] T080 [P] [POLISH] Documentation utilisateur : compléter `quickstart.md` avec captures d'écran de chaque rendu (PNG dans `docs/screenshots/spec-019/`) — **MANUEL post-livraison**
- [ ] T081 [P] [POLISH] Mise à jour `README.md` projet : ajouter section « Rendus modulaires du rail » pointant vers SPEC-019
- [ ] T082 [POLISH] Logger structuré : `logInfo("renderer_changed", ["from": old, "to": new])` à chaque switch effectif côté rail
- [X] T083 [POLISH] Régression : re-jouer toute la suite `swift test` → tous tests verts, en particulier `RoadieRailTests` et `RoadieCoreTests`
- [ ] T084 [POLISH] Mise à jour `implementation.md` avec REX de chaque user story livrée
- [X] T085 [POLISH] Audit `/audit 019-rail-renderers` mode fix, viser score ≥ A- — **PHASE 6 PIPELINE** (à lancer après commit en session dédiée)
- [ ] T086 [P] [POLISH] Vérifier mesure SC-006 : `wc -l Sources/RoadieRail/Views/StageStackView.swift` doit avoir diminué d'au moins 30% par rapport au baseline initial
- [ ] T087 [POLISH] Cleanup : supprimer toute trace temporaire (logs debug, `print`, `try!`) introduite pendant l'implémentation
- [ ] T088 [POLISH] Matrice de validation FR-010 : pour chaque renderer livré (au minimum stacked-previews + icons-only), vérifier manuellement par screenshot 2 cas — (a) stage vide (0 fenêtre) → placeholder neutre visible et pas de crash, (b) stage avec plus de fenêtres que la limite du renderer → indicateur de truncation lisible (ex. "+N"). Documenter chaque screenshot dans `docs/screenshots/spec-019/edge-cases/`

**Critère de fin Polish** : tous tests verts, audit ≥ A-, doc complète.

---

## Dependencies (DAG)

```
T001..T006 (Setup)
   ↓
T010..T013 (Foundational : Protocol + Registry)
   ↓
   ├──► T020..T028 (US1 refactor) ════════ MVP partiel
   │       ↓
   │       T030..T043 (US2 switch + CLI) ─► MVP V1 livrable
   │       ↓
   │       ├──► T050..T055 (US3 hero-preview)
   │       ├──► T060..T063 (US4 mosaic)            (parallèles entre eux)
   │       └──► T070..T073 (US5 parallax-45)
   │              ↓
   │              T080..T087 (Polish)
```

**MVP livrable** : T001 → T043 inclus (US1 + US2 complets). Effort estimé : ~3-5 heures pour développeur Swift familier de SPEC-014/Tiler.

## Parallélisme

Tâches marquées `[P]` peuvent tourner en parallèle :
- T002, T003, T004 (vérifications baseline indépendantes)
- T012 (test registry) ‖ T013 (vérif Package.swift)
- T027 (mesure LOC) en parallèle avec T026 (screenshot manuel)
- T039 (test acceptance bash) en parallèle avec T040-T043 (tests manuels)
- T080, T081, T086 (polish doc + mesure) tous parallèles

US3, US4, US5 sont **strictement indépendantes entre elles** (chaque renderer dans son propre fichier, aucun touchant aux autres) — elles peuvent être livrées dans n'importe quel ordre une fois US1+US2 complets.

Tâches sur `Sources/RoadieRail/RailController.swift` et `Sources/roadied/CommandRouter.swift` doivent être séquentielles (un fichier modifié plusieurs fois).

## Total

- **49 tâches** réparties sur 8 phases
- **MVP** = T001-T043 (35 tâches) couvrant Setup + Foundational + US1 + US2
- **Bonus** = +T050-T073 (12 tâches) US3+US4+US5
- **Polish** = +T080-T088 (9 tâches)

**Effort total estimé** : ~4 heures MVP, ~7-8 heures complet (US1-US5), hors screenshots manuels et audits.
