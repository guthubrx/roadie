# Tasks — SPEC-011 Composants atomiques

## Fondation

- [X] T001 [P] Créer `Tests/RoadieDaemonTests/ComponentLockFileTests.swift` avec 4 cas (acquire neuf, double-lock détecté, PID stale écrasé, registry liste vide)
- [X] T002 Créer `Sources/RoadieDaemon/ComponentLockFile.swift` (struct publique, acquire/release/isAlive/registry)
- [X] T003 Faire passer `ComponentLockFileTests` via `swift test --filter ComponentLockFile`
- [X] T004 Documenter le pattern lock PID dans `specs/011-atomic-components/contracts/component-lock.md`

## User Story 1 — Sous-commande Rail seul (P1)

- [X] T005 [P] [US1] Créer `Tests/RoadieDaemonTests/ComponentSubcommandTests.swift` avec parser test pour `roadied rail`
- [X] T006 [US1] Ajouter le case `"rail"` dans `Sources/roadied/main.swift` (dispatch → ComponentLockFile + RailController.start + NSApplication.shared.run)
- [X] T007 [US1] Ajouter signal handler SIGTERM/SIGINT dans `Sources/roadied/main.swift` pour release lock
- [X] T008 [US1] Faire passer `swift build --product roadied` avec PATH Xcode et vérifier `roadied rail` démarre + lock présent + lock supprimé à l'arrêt

## User Story 2 — Sous-commandes restantes (P1-P2)

- [X] T009 [P] [US2] Ajouter le case `"tiler"` dans `main.swift` (LayoutMaintainer seul + MaintenanceTimerTarget + RunLoop)
- [X] T010 [P] [US2] Ajouter le case `"border"` dans `main.swift` (BorderController seul + NSApplication run)
- [X] T011 [P] [US2] Ajouter le case `"focus-mouse"` dans `main.swift` (FocusFollowsMouseController + RunLoop)
- [X] T012 [P] [US2] Ajouter le case `"titlebar-menu"` dans `main.swift` (TitlebarContextMenuController + NSApplication run)
- [X] T013 [P] [US2] Ajouter le case `"target-mode"` dans `main.swift` (TargetModeRuntimeController + NSApplication run)
- [X] T014 [P] [US2] Ajouter le case `"restore-safety"` dans `main.swift` (RestoreSafetyRuntimeController seul)
- [X] T015 [US2] Étendre `ComponentSubcommandTests.swift` avec parser tests pour les 6 sous-commandes ci-dessus

## User Story 3 — Flags `--no-*` opt-out (P1)

- [X] T016 [US3] Ajouter dans `Sources/roadied/main.swift` mode `run` les variables `shouldStartTiler`, `shouldStartBorder`, `shouldStartFocusMouse`, `shouldStartTitlebarMenu`, `shouldStartTargetMode` selon flags `--no-*`
- [X] T017 [US3] Conditionner l'instanciation de chaque contrôleur sur sa variable `shouldStart*`
- [X] T018 [US3] Mettre à jour `printUsage()` avec les nouveaux flags et sous-commandes
- [X] T019 [US3] Ajouter `Tests/RoadieDaemonTests/RoadiedRunFlagsTests.swift` qui vérifie le parsing des flags `--no-tiler`, `--no-border`, etc. (test du parser uniquement, pas du runtime)

## User Story 4 — Query components (P3)

- [X] T020 [P] [US4] Ajouter `Tests/RoadieDaemonTests/QueryComponentsTests.swift` avec 2 cas (registry vide, registry avec 2 composants simulés)
- [X] T021 [US4] Ajouter case `"components"` dans `AutomationQueryService.query(_:)` qui appelle `ComponentLockFile.registry()` et encode le résultat en `AutomationPayload`
- [X] T022 [US4] Faire passer `swift test --filter QueryComponents`
- [X] T023 [US4] Mettre à jour la documentation CLI dans `Sources/roadie/main.swift` (printUsage) pour lister `components` dans les queries disponibles

## Rétro-compatibilité

- [X] T024 Vérifier que `roadied run --yes` (sans aucun flag `--no-*`) démarre exactement les composants attendus (test smoke manuel + lecture du code)
- [X] T025 Vérifier que `Scripts/start` continue à fonctionner sans modification

## Orchestration et documentation

- [X] T026 [P] Créer `Scripts/start-modular` (bash) qui lance chaque composant dans une session tmux séparée
- [X] T027 [P] Créer `specs/011-atomic-components/quickstart.md` avec exemples d'usage des nouveaux modes
- [X] T028 Lancer `swift test` complet (PATH Xcode) et documenter le résultat dans `specs/011-atomic-components/implementation.md`
- [X] T029 Mettre à jour `specs/011-atomic-components/implementation.md` avec le journal final (statut par tâche, commits)
