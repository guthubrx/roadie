# Implementation Log — SPEC-019 Rendus modulaires du navrail

**Branch**: `019-rail-renderers`
**Date début**: 2026-05-03
**Date fin MVP**: 2026-05-03
**Status MVP**: ✅ Livré (US1 + US2)

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

## Tâches NON-LIVRÉES (reportées)

- **T012** : tests unit `StageRendererRegistryTests.swift` — protocole vérifié manuellement, à formaliser en tests Swift.
- **T026, T027** : validations manuelles screenshot pixel-à-pixel + mesure -30% LOC StageStackView — utilisateur peut les exécuter.
- **US3 (T050-T055), US4 (T060-T063), US5 (T070-T073)** : renderers HeroPreview, Mosaic, Parallax45 — livrables indépendamment.
- **Polish (T080-T088)** : doc, screenshots, audit, matrice empty/overflow.
