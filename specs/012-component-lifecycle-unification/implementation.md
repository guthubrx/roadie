# Journal d'Implémentation — SPEC-012 Unification du cycle de vie

## Métadonnées

- **Spec** : `012-component-lifecycle-unification`
- **Branche** : `main`
- **Démarré / Terminé** : 2026-05-22
- **Statut** : Implemented

## Résultat

Refactor pur du dispatch de `Sources/roadied/main.swift` : extraction de **7 fonctions de démarrage uniques** + 1 helper, appelées à la fois par le mode monolithique (`run`) et par les sous-commandes modulaires. Élimination totale de la duplication qui causait les divergences de comportement entre les deux modes.

## Fonctions créées (source unique par composant)

- `startRailComponent()`, `startBorderComponent()`, `startFocusMouseComponent()`, `startTitlebarMenuComponent()`, `startTargetModeComponent()`, `startRestoreSafetyComponent()`
- `startTilerComponent(interval:ticks:displaySettleSeconds:enableLiveEvents:)` — encapsule timer + live observer AX + observer d'écran
- `installDisplayChangeObserver(displaySettleSeconds:)`

## Avant / Après

- **Avant** : le setup du tiler (timer + live observer + display observer) existait en double (`case run` ET `case tiler`), idem chaque contrôleur instancié 2×. Source des 4 bugs de divergence du 2026-05-22.
- **Après** : chaque contrôleur instancié **une seule fois** (vérifié par grep : lignes 103-211, toutes dans les fonctions `start*`). `case run` et les sous-commandes appellent les mêmes fonctions.

## Tests

- `swift build --product roadied` : OK (PATH Xcode)
- `swift test` : **428/428 OK**
- Smoke modulaire : `Scripts/start-modular` → `roadie query components` = 7 composants (border, focus-mouse, rail, restore-safety, target-mode, tiler, titlebar-menu) ; `live_tick` émis après changement de focus → réactivité préservée.

## Couverture EF / SC

| Critère | Vérifié par |
|---|---|
| EF-001 (fonction unique par composant) | T001-T007, grep instanciations |
| EF-002 (run appelle selon flags) | T008 |
| EF-003 (sous-commandes appellent) | T004, T007 |
| EF-004 (observers tiler) | T005, T006 (dans startTilerComponent) |
| EF-005 (0 duplication) | T009, grep = 1 instanciation/composant |
| EF-006 (comportement identique) | T011 (428 tests), T012 (smoke) |
| SC-001 (0 bloc dupliqué) | grep : 1 instanciation par composant |
| SC-002 (428+ tests) | 428/428 OK |
| SC-003 (query components inchangé) | 7 composants |
| SC-004 (live_tick + heal 2 modes) | live_tick confirmé ; startTilerComponent installe l'observer d'écran dans les 2 modes |

## Changement de comportement documenté (research D2)

En monolithique avec `--no-tiler`, l'observer de changement d'écran n'est plus installé (il est désormais porté par `startTilerComponent`). Acceptable : sans tiler, il n'y a pas de re-layout à déclencher au changement d'écran.

## Prochaine étape

SPEC-013 (arbre BSP persistant yabai/i3) sera construit sur cette base de lifecycle unifiée.
