# Tasks: Roadie Ecosystem Upgrade

**Input**: Design documents from `/specs/002-roadie-ecosystem-upgrade/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/
**Branch**: `002-roadie-ecosystem-upgrade`
**Worktree**: `.worktrees/002-roadie-ecosystem-upgrade/`

**Tests**: Inclus. Chaque tranche doit être testable indépendamment. Pour Roadie, les gates projet sont `swift build`, `swift test` et les validations CLI manuelles indiquées.

**Execution Rule**: Une seule tâche à la fois, une tâche validée = un commit dédié, journalisée dans `specs/002-roadie-ecosystem-upgrade/implementation.md`.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Préparer les fixtures, la traçabilité et la matrice de couverture avant le code.

- [X] T001 Créer les fixtures d'événements Spec 002 dans `Tests/RoadieDaemonTests/Fixtures/Spec002Events.jsonl`
- [X] T002 [P] Créer les fixtures de snapshot Spec 002 dans `Tests/RoadieDaemonTests/Fixtures/Spec002Snapshot.json`
- [X] T003 [P] Créer les fixtures de règles valides et invalides dans `Tests/RoadieDaemonTests/Fixtures/Spec002Rules.toml`
- [X] T004 Créer la matrice de couverture yabai/AeroSpace/Hyprland dans `specs/002-roadie-ecosystem-upgrade/automation-coverage.md`
- [X] T005 Initialiser le journal d'implémentation par tâche dans `specs/002-roadie-ecosystem-upgrade/implementation.md`
- [X] T006 Ajouter une section de suivi Spec 002 dans `docs/decisions/001-roadie-automation-contract.md`
- [X] T007 Vérifier que `Package.swift` expose les targets de test nécessaires pour les nouveaux fichiers `Tests/RoadieDaemonTests/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Définir les types et services partagés qui bloquent tous les scénarios.

**Critical**: Aucun scénario utilisateur ne doit commencer avant la fin de cette phase.

- [X] T008 Créer le modèle versionné `RoadieEventEnvelope` dans `Sources/RoadieCore/AutomationEvent.swift`
- [X] T009 Créer les types `AutomationSubject`, `AutomationScope`, `AutomationCause` et `AutomationPayload` dans `Sources/RoadieCore/AutomationEvent.swift`
- [X] T010 [P] Créer le modèle `RoadieStateSnapshot` dans `Sources/RoadieCore/AutomationSnapshot.swift`
- [X] T011 [P] Créer le modèle `LayoutCommandIntent` dans `Sources/RoadieCore/LayoutCommandIntent.swift`
- [X] T012 Adapter `Sources/RoadieDaemon/EventLog.swift` pour écrire et relire `RoadieEventEnvelope` sans casser l'ancien journal
- [X] T013 Ajouter les helpers de compatibilité legacy `RoadieEvent` vers `RoadieEventEnvelope` dans `Sources/RoadieDaemon/EventLog.swift`
- [X] T014 Ajouter les tests de sérialisation et compatibilité événementielle dans `Tests/RoadieDaemonTests/AutomationEventTests.swift`
- [X] T015 Ajouter les tests de snapshot contractuel dans `Tests/RoadieDaemonTests/AutomationSnapshotTests.swift`
- [X] T016 Lancer `swift build` puis `swift test --filter AutomationEventTests` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: Les types automation sont disponibles, testés, et le journal existant reste lisible.

---

## Phase 3: User Story 1 - Observer Roadie en temps réel (Priority: P1) MVP

**Goal**: Un outil externe peut recevoir les événements Roadie en direct avec un snapshot initial optionnel.

**Independent Test**: Démarrer un abonnement, provoquer des événements fenêtre/stage/desktop, vérifier les lignes JSONL émises, leur ordre et leur latence.

### Tests for User Story 1

- [X] T017 [P] [US1] Ajouter les tests du catalogue minimal d'événements dans `Tests/RoadieDaemonTests/EventCatalogTests.swift`
- [X] T018 [US1] Ajouter les tests de suivi `subscribe --from-now` dans `Tests/RoadieDaemonTests/EventSubscriptionTests.swift`
- [X] T019 [US1] Ajouter le test `subscribe --initial-state` dans `Tests/RoadieDaemonTests/EventSubscriptionTests.swift`
- [X] T020 [US1] Ajouter le test de latence sous une seconde dans `Tests/RoadieDaemonTests/EventSubscriptionTests.swift`

### Implementation for User Story 1

- [X] T021 [US1] Créer le catalogue d'événements `AutomationEventCatalog` dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [X] T022 [US1] Créer `EventSubscriptionService` pour suivre `events.jsonl` dans `Sources/RoadieDaemon/EventSubscriptionService.swift`
- [X] T023 [US1] Créer `AutomationSnapshotService` pour produire `state.snapshot` dans `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [X] T024 [US1] Intégrer `AutomationSnapshotService` avec `DaemonSnapshot` dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T025 [US1] Ajouter la commande `roadie events subscribe` dans `Sources/roadie/main.swift`
- [X] T026 [US1] Ajouter les filtres `--from-now`, `--initial-state`, `--type` et `--scope` dans `Sources/roadie/main.swift`
- [X] T027 [US1] Publier `command.received`, `command.applied` et `command.failed` depuis les commandes CLI concernées dans `Sources/roadie/main.swift`
- [X] T028 [US1] Documenter le comportement final de subscription dans `specs/002-roadie-ecosystem-upgrade/contracts/events.md`
- [ ] T029 [US1] Lancer `swift build` puis `swift test --filter EventSubscriptionTests` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: US1 est livrable seule comme MVP observable par CLI.

---

## Phase 4: User Story 2 - Automatiser les fenêtres par règles (Priority: P2)

**Goal**: L'utilisateur peut déclarer, valider, expliquer et appliquer des règles fenêtre déterministes.

**Independent Test**: Charger une config TOML de règles, valider les erreurs, simuler une fenêtre, puis vérifier l'action, le marqueur scratchpad et l'événement `rule.*`.

### Tests for User Story 2

- [ ] T030 [P] [US2] Ajouter les tests de parsing `[[rules]]` dans `Tests/RoadieDaemonTests/WindowRuleConfigTests.swift`
- [ ] T031 [P] [US2] Ajouter les tests de validation de conflits dans `Tests/RoadieDaemonTests/WindowRuleValidationTests.swift`
- [ ] T032 [P] [US2] Ajouter les tests de matching app/title/role/stage dans `Tests/RoadieDaemonTests/WindowRuleMatcherTests.swift`
- [ ] T033 [P] [US2] Ajouter les tests CLI `rules validate` et `rules explain` dans `Tests/RoadieDaemonTests/RulesCommandTests.swift`
- [ ] T034 [P] [US2] Ajouter les tests du marqueur `scratchpad` dans `Tests/RoadieDaemonTests/WindowRuleScratchpadTests.swift`

### Implementation for User Story 2

- [ ] T035 [US2] Ajouter les modèles `WindowRule`, `RuleMatch`, `RuleAction` et `RuleEvaluation` dans `Sources/RoadieCore/WindowRule.swift`
- [ ] T036 [US2] Étendre le parsing TOML de `[[rules]]` dans `Sources/RoadieCore/Config.swift`
- [ ] T037 [US2] Créer `WindowRuleValidator` dans `Sources/RoadieDaemon/WindowRuleValidator.swift`
- [ ] T038 [US2] Créer `WindowRuleMatcher` dans `Sources/RoadieDaemon/WindowRuleMatcher.swift`
- [ ] T039 [US2] Créer `WindowRuleEngine` pour évaluer et appliquer les actions dans `Sources/RoadieDaemon/WindowRuleEngine.swift`
- [ ] T040 [US2] Intégrer les règles à la détection ou actualisation fenêtre dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [ ] T041 [US2] Publier `rule.matched`, `rule.applied`, `rule.skipped` et `rule.failed` via `Sources/RoadieDaemon/EventLog.swift`
- [ ] T042 [US2] Ajouter les commandes `roadie rules validate`, `roadie rules list` et `roadie rules explain` dans `Sources/roadie/main.swift`
- [ ] T043 [US2] Stocker et exposer le marqueur `scratchpad` dans `Sources/RoadieDaemon/WindowRuleEngine.swift`
- [ ] T044 [US2] Mettre à jour le contrat TOML réel dans `specs/002-roadie-ecosystem-upgrade/contracts/config-rules.toml.md`
- [ ] T045 [US2] Lancer `swift build` puis `swift test --filter WindowRule` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: US2 fonctionne sans dépendre des futures commandes d'arbre ou groupes.

---

## Phase 5: User Story 3 - Piloter l'arbre de layout comme power-user (Priority: P3)

**Goal**: Exposer les primitives de layout, focus, desktop et stage attendues par les power-users.

**Independent Test**: Sur un état contrôlé, exécuter chaque commande et vérifier focus, stage, desktop, layout, erreurs propres et événements `command.*`.

### Tests for User Story 3

- [ ] T046 [P] [US3] Ajouter les tests `focus back-and-forth` dans `Tests/RoadieDaemonTests/PowerUserFocusCommandTests.swift`
- [ ] T047 [P] [US3] Ajouter les tests `desktop back-and-forth`, `desktop summon`, `stage summon` et `stage move-to-display` dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`
- [ ] T048 [P] [US3] Ajouter les tests `layout split`, `flatten`, `insert` et `zoom-parent` dans `Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift`
- [ ] T049 [P] [US3] Ajouter les tests de fenêtres, écrans, stages et états obsolètes dans `Tests/RoadieDaemonTests/PowerUserCommandEdgeCaseTests.swift`

### Implementation for User Story 3

- [ ] T050 [US3] Ajouter le suivi du focus précédent dans `Sources/RoadieDaemon/WindowCommands.swift`
- [ ] T051 [US3] Ajouter le suivi du desktop précédent dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T052 [US3] Ajouter `stage summon` et `stage move-to-display` dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T053 [US3] Ajouter `LayoutCommandService` pour split/flatten/insert/zoom dans `Sources/RoadieDaemon/LayoutCommandService.swift`
- [ ] T054 [US3] Brancher `LayoutCommandService` sur `LayoutIntentStore` dans `Sources/RoadieDaemon/LayoutIntentStore.swift`
- [ ] T055 [US3] Ajouter les commandes `roadie layout split|join-with|flatten|insert|zoom-parent` dans `Sources/roadie/main.swift`
- [ ] T056 [US3] Ajouter les commandes `roadie focus back-and-forth`, `roadie desktop back-and-forth|summon` et `roadie stage summon|move-to-display` dans `Sources/roadie/main.swift`
- [ ] T057 [US3] Publier les résultats `command.*` des commandes power-user dans `Sources/RoadieDaemon/EventLog.swift`
- [ ] T058 [US3] Lancer `swift build` puis `swift test --filter PowerUser` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: US3 est utilisable par BTT ou scripts shell sans intégrer les groupes.

---

## Phase 6: User Story 4 - Grouper des fenêtres dans un même emplacement (Priority: P3, ordre 4)

**Goal**: Créer un concept de groupe/stack Roadie persistant, pilotable et visible.

**Independent Test**: Créer un groupe de deux fenêtres, naviguer entre membres, vérifier l'indicateur visuel, fermer un membre, redémarrer le daemon et vérifier la persistance.

### Tests for User Story 4

- [ ] T059 [P] [US4] Ajouter les tests du modèle `WindowGroup` dans `Tests/RoadieStagesTests/WindowGroupStateTests.swift`
- [ ] T060 [P] [US4] Ajouter les tests de persistance des groupes dans `Tests/RoadieDaemonTests/WindowGroupStoreTests.swift`
- [ ] T061 [P] [US4] Ajouter les tests de commandes `group create|add|remove|focus|dissolve` dans `Tests/RoadieDaemonTests/WindowGroupCommandTests.swift`
- [ ] T062 [P] [US4] Ajouter les tests d'état visuel groupe dans `Tests/RoadieDaemonTests/WindowGroupIndicatorTests.swift`

### Implementation for User Story 4

- [ ] T063 [US4] Ajouter le modèle `WindowGroup` dans `Sources/RoadieStages/RoadieState.swift`
- [ ] T064 [US4] Étendre la persistance des stages avec les groupes dans `Sources/RoadieDaemon/StageStore.swift`
- [ ] T065 [US4] Créer `WindowGroupCommands` dans `Sources/RoadieDaemon/WindowGroupCommands.swift`
- [ ] T066 [US4] Adapter le layout pour traiter un groupe comme un seul slot dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [ ] T067 [US4] Ajouter l'état groupé aux snapshots dans `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [ ] T068 [US4] Ajouter un indicateur visuel minimal de groupe et membre actif dans `Sources/RoadieDaemon/BorderController.swift`
- [ ] T069 [US4] Ajouter les commandes `roadie group create|add|remove|focus|dissolve|list` dans `Sources/roadie/main.swift`
- [ ] T070 [US4] Publier les événements `window.grouped` et `window.ungrouped` dans `Sources/RoadieDaemon/EventLog.swift`
- [ ] T071 [US4] Lancer `swift build` puis `swift test --filter WindowGroup` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: US4 fournit stack/tabbed côté Roadie sans dépendance à une API macOS privée.

---

## Phase 7: User Story 5 - Explorer l'état Roadie de manière stable (Priority: P3, ordre 5)

**Goal**: Fournir des lectures JSON stables pour fenêtres, écrans, desktops, stages, groupes, règles, santé et événements récents.

**Independent Test**: Appeler chaque commande `roadie query ... --json` sur un état contrôlé et valider les champs contractuels.

### Tests for User Story 5

- [ ] T072 [US5] Ajouter les tests de schéma `query state` et `query windows` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T073 [US5] Ajouter les tests de schéma `query displays|desktops|stages|groups|rules` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T074 [P] [US5] Ajouter les tests de schéma `query health` et `query events` dans `Tests/RoadieDaemonTests/QueryHealthEventsTests.swift`
- [ ] T075 [P] [US5] Ajouter les tests de compatibilité avec `state`, `tree` et `windows list --json` dans `Tests/RoadieDaemonTests/LegacyQueryCompatibilityTests.swift`

### Implementation for User Story 5

- [ ] T076 [US5] Créer `AutomationQueryService` dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T077 [US5] Ajouter les projections fenêtres/écrans/desktops/stages dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T078 [US5] Ajouter les projections groupes et règles dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T079 [US5] Ajouter les projections santé et événements récents dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T080 [US5] Ajouter les commandes `roadie query state|windows|displays|desktops|stages|groups|rules|health|events` dans `Sources/roadie/main.swift`
- [ ] T081 [US5] Mettre à jour le contrat CLI final dans `specs/002-roadie-ecosystem-upgrade/contracts/cli.md`
- [ ] T082 [US5] Lancer `swift build` puis `swift test --filter Query` et documenter le résultat dans `specs/002-roadie-ecosystem-upgrade/implementation.md`

**Checkpoint**: US5 stabilise la surface de lecture pour intégrations externes.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Durcir l'ensemble, vérifier la non-régression et finaliser la documentation.

- [ ] T083 [P] Mettre à jour le quickstart final avec les commandes réelles dans `specs/002-roadie-ecosystem-upgrade/quickstart.md`
- [ ] T084 [P] Mettre à jour l'ADR avec les écarts décidés pendant l'implémentation dans `docs/decisions/001-roadie-automation-contract.md`
- [ ] T085 Ajouter les tests de non-régression existants Spec 002 dans `Tests/RoadieDaemonTests/Spec002RegressionTests.swift`
- [ ] T086 Lancer `swift build` puis `swift test` et corriger les régressions dans `Sources/` et `Tests/`
- [ ] T087 Exécuter manuellement le scénario quickstart via `swift run roadie events subscribe --from-now --initial-state` et noter le résultat dans `specs/002-roadie-ecosystem-upgrade/quickstart.md`
- [ ] T088 Vérifier qu'aucune commande Spec 002 n'introduit API privée, SIP off, Spaces natifs Apple ou daemon hotkey dans `Sources/`
- [ ] T089 Mettre à jour le statut de session 002 dans `.specify/memory/sessions/index.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: démarre dans `.worktrees/002-roadie-ecosystem-upgrade/`.
- **Phase 2 Foundational**: dépend de Phase 1 et bloque toutes les stories.
- **Phase 3 US1**: démarre après Phase 2 ; MVP recommandé.
- **Phase 4 US2**: dépend de Phase 2 et bénéficie des événements US1 pour l'observabilité.
- **Phase 5 US3**: dépend de Phase 2 ; peut commencer après US1 si les événements `command.*` sont disponibles.
- **Phase 6 US4**: dépend de US3 pour les primitives layout et de US1 pour les événements.
- **Phase 7 US5**: dépend de Phase 2 ; les projections groupes/règles dépendent de US2 et US4 si elles sont incluses.
- **Phase 8 Polish**: dépend des stories choisies pour la livraison.

### User Story Dependencies

- **US1 (P1)**: aucune dépendance autre que Phase 2.
- **US2 (P2)**: peut être développée après Phase 2, mais les événements `rule.*` sont mieux validés après US1.
- **US3 (P3)**: peut être développée après Phase 2, mais publication `command.*` dépend de US1.
- **US4 (P3 ordre 4)**: dépend conceptuellement de US3 pour les commandes de layout et de US1 pour les événements.
- **US5 (P3 ordre 5)**: lecture state de base possible après Phase 2 ; lecture complète dépend de US2 et US4.

### Within Each User Story

- Écrire les tests de story avant l'implémentation.
- Modèles avant services.
- Services avant CLI.
- CLI avant documentation finale.
- Événements avant validation quickstart.
- Une tâche validée doit être journalisée puis committée seule.

---

## Parallel Opportunities

- T002 et T003 peuvent être faits en parallèle après T001.
- T010 et T011 peuvent être faits en parallèle après T008-T009.
- T017 peut être fait en parallèle des tests subscription T018-T020 si les fichiers restent séparés.
- T030, T031, T032, T033 et T034 peuvent être faits en parallèle avant l'implémentation US2.
- T046, T047, T048 et T049 peuvent être faits en parallèle avant l'implémentation US3.
- T059, T060, T061 et T062 peuvent être faits en parallèle avant l'implémentation US4.
- T074 et T075 peuvent être faits en parallèle des tests `QueryCommandTests.swift`.
- T083 et T084 peuvent être faits en parallèle pendant la phase de polish.

---

## Implementation Strategy

### MVP First

1. Travailler uniquement dans `.worktrees/002-roadie-ecosystem-upgrade/`.
2. Terminer Phase 1 et Phase 2.
3. Implémenter uniquement US1.
4. Valider `roadie events subscribe --from-now --initial-state`.
5. Stopper et vérifier que les commandes existantes continuent de fonctionner.

### Incremental Delivery

1. US1 : observation live.
2. US5 partiel : query state/windows/health/events si nécessaire pour stabiliser les intégrations.
3. US2 : règles.
4. US3 : commandes power-user.
5. US4 : groupes.
6. US5 complet : toutes les projections.

### Single Developer Strategy

Avancer séquentiellement : Phase 1 -> Phase 2 -> US1 -> validation -> US2 -> validation -> US3 -> validation -> US4 -> validation -> US5 -> polish.
