# Tasks — SPEC-012 Unification du cycle de vie

## Fonctions de démarrage des contrôleurs simples

- [X] T001 [US2] Créer `startRestoreSafetyComponent()` et `startRailComponent()` dans `Sources/roadied/main.swift`
- [X] T002 [US2] Créer `startBorderComponent()` et `startFocusMouseComponent()` dans `Sources/roadied/main.swift`
- [X] T003 [US2] Créer `startTitlebarMenuComponent()` et `startTargetModeComponent()` dans `Sources/roadied/main.swift`
- [X] T004 [US2] Remplacer les sous-commandes `case "rail"|"border"|"focus-mouse"|"titlebar-menu"|"target-mode"|"restore-safety"` par `runComponent(name) { startXxxComponent() }`

## Fonction de démarrage du tiler + observer d'écran

- [X] T005 [US2] Créer `installDisplayChangeObserver(displaySettleSeconds:)` dans `Sources/roadied/main.swift`
- [X] T006 [US2] Créer `startTilerComponent(interval:ticks:displaySettleSeconds:enableLiveEvents:)` encapsulant MaintenanceTimerTarget + Timer + live observer AX + appel à installDisplayChangeObserver
- [X] T007 [US2] Remplacer le `case "tiler"` par `runComponent("tiler") { startTilerComponent(...) }`

## Réécriture du mode monolithique

- [X] T008 [US1] Réécrire `case "run"` pour appeler les fonctions de démarrage selon les flags `--no-*`, dans l'ordre historique (restore-safety, rail, border, focus-mouse, titlebar-menu, target-mode, tiler)
- [X] T009 [US3] Supprimer tout code de setup dupliqué résiduel ; vérifier qu'aucune instanciation de contrôleur n'apparaît deux fois

## Validation non-régression

- [X] T010 [US3] `swift build --product roadied` (PATH Xcode) sans erreur
- [X] T011 [US3] `swift test` complet : 428+ tests passants
- [X] T012 [US1] Smoke modulaire : `Scripts/start-modular` → `roadie query components` retourne 7 composants ; provoquer une ouverture de fenêtre + un changement de focus → vérifier un `live_tick` dans events.jsonl
- [X] T013 [US3] Documenter le résultat dans `specs/012-component-lifecycle-unification/implementation.md` (statut par tâche, commits)
