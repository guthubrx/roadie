# Implementation Plan: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Branch**: `022-multi-display-isolation` | **Date**: 2026-05-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `spec.md`

## Summary

Refactor du modèle d'état actif des stages pour qu'il soit scopé par tuple `(display, desktop)` au lieu d'un scalaire global `currentStageID`. Conséquence directe : un click sur le rail panel d'un display X n'affecte que ce display. En parallèle, les renderers du rail cessent de dessiner un placeholder pour les stages vides — ils rendent un cellule vide mais reste interactive.

Approche minimaliste : on **réutilise** `activeStageByDesktop[DesktopKey]` qui existe déjà dans `StageManager` (introduit par SPEC-018). On le promeut au rang de source de vérité, et `currentStageID` devient un wrapper backward-compat dérivé du `currentDesktopKey`. Les renderers gagnent un check `windowIDs.isEmpty` qui rend une `EmptyView`.

## Technical Context

**Language/Version**: Swift 6 (existing toolchain)
**Primary Dependencies**: SwiftUI macOS 14+, AppKit, ApplicationServices (AX), TOMLKit
**Storage**: TOML on disk (per-display NestedStagePersistence existante)
**Testing**: XCTest (Swift unit tests), bash acceptance scripts (`Tests/`)
**Target Platform**: macOS 14+ (Sonoma/Sequoia/Tahoe)
**Project Type**: Single Swift Package Manager (multi-product : roadied, roadie, roadie-rail)
**Performance Goals**: Switch stage < 50 ms (idem aujourd'hui — pas de régression). Render rail panel < 16 ms (60 fps).
**Constraints**:
- Zéro régression SPEC-013 / 018 / 019 (tests acceptance bash)
- L'invariant SPEC-019 "1 stage par (display, desktop) minimum" reste true
- Pas de migration de schema disque (le format TOML existant supporte déjà l'état per-(display, desktop))
**Scale/Scope**: 2-4 displays, 1-10 desktops par display, 1-10 stages par desktop = ~400 entries max théoriques

## Constitution Check

| Article | Status | Justification |
|---|---|---|
| Article 0 (minimalisme) | ✅ | Réutilise `activeStageByDesktop` existant, ne crée pas de nouvelle structure. Renderers : ajout d'un seul `if isEmpty` par fichier. |
| Article anti-osax (catégorie D) | ✅ | Pas de SkyLight write privé, pas de patch macOS. |
| Article fail-loud | ✅ | Si `currentDesktopKey == nil` (cas pathologique post-boot), `currentStageID` getter logge un warn et retourne `nil`. |
| Article test-coverage | ✅ | Plan inclut tests acceptance pour US1/US2/US3 + tests unitaires pour le nouveau scoping de `switchTo`. |
| Article no-secret | ✅ | Aucune information sensible. |

**Gates** : toutes vertes. Pas de violation à justifier.

## Project Structure

### Documentation (this feature)

```
specs/022-multi-display-isolation/
├── spec.md              ✅ déjà fait
├── plan.md              ← ce fichier
├── research.md          ← R-001 à R-005
├── data-model.md        ← types touchés
├── checklists/
│   └── requirements.md  ✅ déjà fait
└── tasks.md             ← Phase 3
```

### Source Code Touch Points

```
Sources/
├── RoadieStagePlugin/
│   └── StageManager.swift         # currentStageID → derived, switchTo scopé, ensureDefault tous écrans
├── roadied/
│   ├── CommandRouter.swift        # stage.switch propage le scope vers switchTo
│   └── main.swift                 # appelle setCurrentDesktopKey au boot/reload (idem)
└── RoadieRail/
    └── Renderers/
        ├── Parallax45Renderer.swift     # if isEmpty → EmptyView
        ├── StackedPreviewsRenderer.swift  # idem
        ├── MosaicRenderer.swift           # idem
        ├── HeroPreviewRenderer.swift      # idem
        └── IconsOnlyRenderer.swift        # idem
```

### Tests Touch Points

```
Tests/
├── RoadieStagePluginTests/
│   └── StageManagerScopedSwitchTests.swift   ← nouveau, US1
└── 22-*.sh                                    ← acceptance scripts US1/US2/US3
```

## Phase 0 — Research (résolu inline, voir research.md)

Aucun NEEDS CLARIFICATION dans Technical Context. Les décisions architecturales sont :
- R-001 : promouvoir `activeStageByDesktop` au rang de source de vérité
- R-002 : `currentStageID` reste comme propriété calculée (compat ascendante)
- R-003 : renderers utilisent `EmptyView()` SwiftUI pour le cas vide (zéro coût render)
- R-004 : pas de migration disque (format `_active.toml` per (display, desktop) déjà compatible)
- R-005 : hide/show scope-aware via filter sur `windowState.displayUUID`

## Phase 1 — Design & Contracts

**Data Model** : voir `data-model.md`. Pas de nouveaux types, mutation de `StageManager.currentStageID` de stored → computed property.

**Contracts** : aucun changement d'API IPC. `stage.switch` accepte déjà `display` et `desktop` (depuis SPEC-018). Sémantique du handler change (scope honoré, pas global), mais le wire-format est identique.

**Quickstart** : `quickstart.md` montre 3 scénarios en CLI :
1. `roadie stage 3 --display 2` ne change que display 2
2. Empty stage = panel vide visuellement (screenshot avant/après)
3. `roadie desktop focus 5 --display 1` indépendant

## Phase 2 — Tasks

Voir `tasks.md` (généré en Phase 3 du pipeline).

## Risks & Mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Régression hide/show cross-display lors du switch scopé | Moyenne | Haute | Tests acceptance avec captures CGWindowList avant/après, sur 2 displays |
| `currentStageID` getter retournant `nil` casse code legacy qui assume non-nil | Basse | Moyenne | Audit des call sites (grep), fallback sur `StageID("1")` si aucun scope courant |
| Renderers qui rendaient un placeholder pour debug : perte de visibilité dev | Très basse | Très basse | Conserver le `emptyPlaceholder` view dans le code, juste ne plus l'appeler ; commentaire pour le dev mode |
| Persistence TOML : `_active.toml` mal sync entre disk et memory après refactor | Basse | Haute | Tests : restart daemon → restore active stage exact. Couvert par SC-006. |

## Out of Scope (Phase 1)

- Animation transition entre stages d'un même display (SPEC-020)
- Drag-drop visuel d'une window entre displays (workflow existant via `roadie window display N`)
- Multi-monitor mirroring (cas natif macOS, hors roadie)
