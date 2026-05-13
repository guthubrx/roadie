# Tasks: Placement des fenêtres par règle

**Input**: `specs/008-window-rule-placement/spec.md`, `plan.md`, `data-model.md`, `contracts/toml-rules.md`

## Phase 1: Setup

- [X] T001 Mettre à jour le contexte SpecKit dans `AGENTS.md`

## Phase 2: Foundational

- [X] T002 Étendre le modèle de règle avec `assign_display` et `follow` dans `Sources/RoadieCore/WindowRule.swift`
- [X] T003 Mettre à jour la validation et les labels d'action dans `Sources/RoadieDaemon/WindowRuleValidator.swift` et `Sources/RoadieDaemon/WindowRuleEngine.swift`
- [X] T004 [P] Ajouter les tests de parsing TOML dans `Tests/RoadieDaemonTests/WindowRuleConfigTests.swift`

## Phase 3: User Story 1 - Stage cible (P1)

- [X] T005 [US1] Implémenter la résolution de stage par ID puis nom dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T006 [US1] Appliquer `assign_stage` comme placement effectif dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T007 [P] [US1] Ajouter le test placement vers stage dans `Tests/RoadieDaemonTests/WindowRuleMaintainerTests.swift`

## Phase 4: User Story 2 - Écran cible (P1)

- [X] T008 [US2] Implémenter la résolution d'écran par ID puis nom dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T009 [US2] Appliquer `assign_display` combiné à `assign_stage` dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T010 [US2] Émettre un événement deferred si l'écran cible est absent dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T011 [P] [US2] Ajouter les tests écran cible et écran absent dans `Tests/RoadieDaemonTests/WindowRuleMaintainerTests.swift`

## Phase 5: User Story 3 - Follow optionnel (P2)

- [X] T012 [US3] Implémenter `follow = false` par défaut et `follow = true` explicite dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T013 [P] [US3] Ajouter les tests follow/no-follow dans `Tests/RoadieDaemonTests/WindowRuleMaintainerTests.swift`

## Phase 6: Polish & Validation

- [X] T014 Mettre à jour les contrats ou exemples si la syntaxe finale change dans `specs/008-window-rule-placement/contracts/toml-rules.md`
- [X] T015 Exécuter `./scripts/with-xcode swift test --filter WindowRule`
- [X] T016 Exécuter `./scripts/roadie config validate`
- [X] T017 Committer la session `008-window-rule-placement`

## Dependencies

- T002-T004 avant US1/US2/US3.
- US1 avant US2 car l'écran cible réutilise la résolution de stage.
- US3 après US1/US2 car `follow` dépend de la destination résolue.

## Independent Test Criteria

- **US1**: Une fenêtre matching rejoint une stage cible sans action manuelle.
- **US2**: Une fenêtre matching rejoint une stage cible sur un écran cible, ou reporte proprement si l'écran est absent.
- **US3**: Le focus ne suit pas par défaut et suit uniquement avec `follow = true`.
