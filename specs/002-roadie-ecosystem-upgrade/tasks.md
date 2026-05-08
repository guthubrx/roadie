# Tasks: Roadie Ecosystem Upgrade

**Input**: Design documents from `/specs/002-roadie-ecosystem-upgrade/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/
**Branch**: `002-roadie-ecosystem-upgrade`

**Tests**: Inclus. La spec exige que chaque tranche livrable soit testable indépendamment, et le plan impose des tests Swift Testing plus des validations CLI observables.

**Organization**: Les tâches sont groupées par scénario utilisateur pour permettre une livraison incrémentale. Le MVP est le scénario 1 : événements et abonnement temps réel.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Préparer les points d'entrée et fixtures nécessaires sans changer encore le comportement utilisateur.

- [ ] T001 Créer les fixtures d'événements Spec 002 dans `Tests/RoadieDaemonTests/Fixtures/Spec002Events.jsonl`
- [ ] T002 [P] Créer les fixtures de snapshot Spec 002 dans `Tests/RoadieDaemonTests/Fixtures/Spec002Snapshot.json`
- [ ] T003 [P] Créer les fixtures de règles valides et invalides dans `Tests/RoadieDaemonTests/Fixtures/Spec002Rules.toml`
- [ ] T004 Ajouter une section de suivi Spec 002 dans `docs/decisions/001-roadie-automation-contract.md`
- [ ] T005 Vérifier que `Package.swift` expose les targets de test nécessaires pour les nouveaux fichiers `Tests/RoadieDaemonTests/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Définir les types et services partagés qui bloquent tous les scénarios.

**Critical**: Aucun scénario utilisateur ne doit commencer avant la fin de cette phase.

- [ ] T006 Créer le modèle versionné `RoadieEventEnvelope` dans `Sources/RoadieCore/AutomationEvent.swift`
- [ ] T007 [P] Créer les types `AutomationSubject`, `AutomationScope`, `AutomationCause` et `AutomationPayload` dans `Sources/RoadieCore/AutomationEvent.swift`
- [ ] T008 [P] Créer le modèle `RoadieStateSnapshot` contractuel dans `Sources/RoadieCore/AutomationSnapshot.swift`
- [ ] T009 [P] Créer le modèle `LayoutCommandIntent` dans `Sources/RoadieCore/LayoutCommandIntent.swift`
- [ ] T010 Adapter `Sources/RoadieDaemon/EventLog.swift` pour écrire et relire `RoadieEventEnvelope` sans casser l'ancien journal
- [ ] T011 Ajouter les helpers de compatibilité legacy `RoadieEvent` vers `RoadieEventEnvelope` dans `Sources/RoadieDaemon/EventLog.swift`
- [ ] T012 Ajouter les tests de sérialisation et compatibilité événementielle dans `Tests/RoadieDaemonTests/AutomationEventTests.swift`
- [ ] T013 Ajouter les tests de snapshot contractuel dans `Tests/RoadieDaemonTests/AutomationSnapshotTests.swift`
- [ ] T014 Lancer `swift test --filter AutomationEventTests` et corriger les échecs liés aux fichiers `Sources/RoadieCore/AutomationEvent.swift` et `Sources/RoadieDaemon/EventLog.swift`

**Checkpoint**: Les types automation sont disponibles, testés, et le journal existant reste lisible.

---

## Phase 3: User Story 1 - Observer Roadie en temps réel (Priority: P1) MVP

**Goal**: Un outil externe peut recevoir les événements Roadie en direct avec un snapshot initial optionnel.

**Independent Test**: Démarrer un abonnement, provoquer des événements fenêtre/stage/desktop, vérifier les lignes JSONL émises et leur ordre.

### Tests for User Story 1

- [ ] T015 [P] [US1] Ajouter les tests du catalogue minimal d'événements dans `Tests/RoadieDaemonTests/EventCatalogTests.swift`
- [ ] T016 [P] [US1] Ajouter les tests de suivi `subscribe --from-now` dans `Tests/RoadieDaemonTests/EventSubscriptionTests.swift`
- [ ] T017 [P] [US1] Ajouter le test `subscribe --initial-state` dans `Tests/RoadieDaemonTests/EventSubscriptionTests.swift`

### Implementation for User Story 1

- [ ] T018 [US1] Créer le catalogue d'événements `AutomationEventCatalog` dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [ ] T019 [US1] Créer `EventSubscriptionService` pour suivre `events.jsonl` dans `Sources/RoadieDaemon/EventSubscriptionService.swift`
- [ ] T020 [US1] Créer `AutomationSnapshotService` pour produire `state.snapshot` dans `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [ ] T021 [US1] Intégrer `AutomationSnapshotService` avec `DaemonSnapshot` dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [ ] T022 [US1] Ajouter la commande `roadie events subscribe` dans `Sources/roadie/main.swift`
- [ ] T023 [US1] Ajouter les filtres `--from-now`, `--initial-state`, `--type` et `--scope` dans `Sources/roadie/main.swift`
- [ ] T024 [US1] Publier `command.received`, `command.applied` et `command.failed` depuis les commandes CLI concernées dans `Sources/roadie/main.swift`
- [ ] T025 [US1] Documenter le comportement final de subscription dans `specs/002-roadie-ecosystem-upgrade/contracts/events.md`
- [ ] T026 [US1] Lancer `swift test --filter EventSubscriptionTests` et corriger les échecs dans `Sources/RoadieDaemon/EventSubscriptionService.swift`

**Checkpoint**: US1 est livrable seule comme MVP observable par CLI.

---

## Phase 4: User Story 2 - Automatiser les fenêtres par règles (Priority: P2)

**Goal**: L'utilisateur peut déclarer, valider, expliquer et appliquer des règles fenêtre déterministes.

**Independent Test**: Charger une config TOML de règles, valider les erreurs, simuler une fenêtre, puis vérifier l'action et l'événement `rule.*`.

### Tests for User Story 2

- [ ] T027 [P] [US2] Ajouter les tests de parsing `[[rules]]` dans `Tests/RoadieDaemonTests/WindowRuleConfigTests.swift`
- [ ] T028 [P] [US2] Ajouter les tests de validation de conflits dans `Tests/RoadieDaemonTests/WindowRuleValidationTests.swift`
- [ ] T029 [P] [US2] Ajouter les tests de matching app/title/role/stage dans `Tests/RoadieDaemonTests/WindowRuleMatcherTests.swift`
- [ ] T030 [P] [US2] Ajouter les tests CLI `rules validate` et `rules explain` dans `Tests/RoadieDaemonTests/RulesCommandTests.swift`

### Implementation for User Story 2

- [ ] T031 [US2] Ajouter les modèles `WindowRule`, `RuleMatch`, `RuleAction` et `RuleEvaluation` dans `Sources/RoadieCore/WindowRule.swift`
- [ ] T032 [US2] Étendre le parsing TOML de `[[rules]]` dans `Sources/RoadieCore/Config.swift`
- [ ] T033 [US2] Créer `WindowRuleValidator` dans `Sources/RoadieDaemon/WindowRuleValidator.swift`
- [ ] T034 [US2] Créer `WindowRuleMatcher` dans `Sources/RoadieDaemon/WindowRuleMatcher.swift`
- [ ] T035 [US2] Créer `WindowRuleEngine` pour évaluer et appliquer les actions dans `Sources/RoadieDaemon/WindowRuleEngine.swift`
- [ ] T036 [US2] Intégrer les règles à la détection ou actualisation fenêtre dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [ ] T037 [US2] Publier `rule.matched`, `rule.applied`, `rule.skipped` et `rule.failed` via `Sources/RoadieDaemon/EventLog.swift`
- [ ] T038 [US2] Ajouter les commandes `roadie rules validate`, `roadie rules list` et `roadie rules explain` dans `Sources/roadie/main.swift`
- [ ] T039 [US2] Mettre à jour le contrat TOML réel dans `specs/002-roadie-ecosystem-upgrade/contracts/config-rules.toml.md`
- [ ] T040 [US2] Lancer `swift test --filter WindowRule` et corriger les échecs dans `Sources/RoadieCore/WindowRule.swift` et `Sources/RoadieDaemon/WindowRuleEngine.swift`

**Checkpoint**: US2 fonctionne sans dépendre des futures commandes d'arbre ou groupes.

---

## Phase 5: User Story 3 - Piloter l'arbre de layout comme power-user (Priority: P3)

**Goal**: Exposer les primitives de layout et de focus attendues par les power-users sans casser les memberships existants.

**Independent Test**: Sur un état contrôlé, exécuter chaque commande et vérifier focus, stage, desktop, layout et événements `command.*`.

### Tests for User Story 3

- [ ] T041 [P] [US3] Ajouter les tests `focus back-and-forth` dans `Tests/RoadieDaemonTests/PowerUserFocusCommandTests.swift`
- [ ] T042 [P] [US3] Ajouter les tests `desktop back-and-forth` et `desktop summon` dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`
- [ ] T043 [P] [US3] Ajouter les tests `layout split`, `flatten`, `insert` et `zoom-parent` dans `Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift`

### Implementation for User Story 3

- [ ] T044 [US3] Ajouter le suivi du focus précédent dans `Sources/RoadieDaemon/WindowCommands.swift`
- [ ] T045 [US3] Ajouter le suivi du desktop précédent dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T046 [US3] Ajouter `LayoutCommandService` pour split/flatten/insert/zoom dans `Sources/RoadieDaemon/LayoutCommandService.swift`
- [ ] T047 [US3] Brancher `LayoutCommandService` sur `LayoutIntentStore` dans `Sources/RoadieDaemon/LayoutIntentStore.swift`
- [ ] T048 [US3] Ajouter les commandes `roadie layout split|join-with|flatten|insert|zoom-parent` dans `Sources/roadie/main.swift`
- [ ] T049 [US3] Ajouter les commandes `roadie focus back-and-forth`, `roadie desktop back-and-forth` et `roadie desktop summon` dans `Sources/roadie/main.swift`
- [ ] T050 [US3] Publier les résultats `command.*` des commandes power-user dans `Sources/RoadieDaemon/EventLog.swift`
- [ ] T051 [US3] Lancer `swift test --filter PowerUser` et corriger les échecs dans `Sources/RoadieDaemon/LayoutCommandService.swift`

**Checkpoint**: US3 est utilisable par BTT ou scripts shell sans intégrer les groupes.

---

## Phase 6: User Story 4 - Grouper des fenêtres dans un même emplacement (Priority: P3, ordre 4)

**Goal**: Créer un concept de groupe/stack Roadie persistant et pilotable.

**Independent Test**: Créer un groupe de deux fenêtres, naviguer entre membres, fermer un membre, redémarrer le daemon et vérifier la persistance.

### Tests for User Story 4

- [ ] T052 [P] [US4] Ajouter les tests du modèle `WindowGroup` dans `Tests/RoadieStagesTests/WindowGroupStateTests.swift`
- [ ] T053 [P] [US4] Ajouter les tests de persistance des groupes dans `Tests/RoadieDaemonTests/WindowGroupStoreTests.swift`
- [ ] T054 [P] [US4] Ajouter les tests de commandes `group create|add|remove|focus|dissolve` dans `Tests/RoadieDaemonTests/WindowGroupCommandTests.swift`

### Implementation for User Story 4

- [ ] T055 [US4] Ajouter le modèle `WindowGroup` dans `Sources/RoadieStages/RoadieState.swift`
- [ ] T056 [US4] Étendre la persistance des stages avec les groupes dans `Sources/RoadieDaemon/StageStore.swift`
- [ ] T057 [US4] Créer `WindowGroupCommands` dans `Sources/RoadieDaemon/WindowGroupCommands.swift`
- [ ] T058 [US4] Adapter le layout pour traiter un groupe comme un seul slot dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [ ] T059 [US4] Ajouter l'état groupé aux snapshots dans `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [ ] T060 [US4] Ajouter les commandes `roadie group create|add|remove|focus|dissolve|list` dans `Sources/roadie/main.swift`
- [ ] T061 [US4] Publier les événements `window.grouped` et `window.ungrouped` dans `Sources/RoadieDaemon/EventLog.swift`
- [ ] T062 [US4] Lancer `swift test --filter WindowGroup` et corriger les échecs dans `Sources/RoadieDaemon/WindowGroupCommands.swift`

**Checkpoint**: US4 fournit stack/tabbed côté Roadie sans dépendance à une API macOS privée.

---

## Phase 7: User Story 5 - Explorer l'état Roadie de manière stable (Priority: P3, ordre 5)

**Goal**: Fournir des lectures JSON stables pour fenêtres, écrans, desktops, stages, groupes, règles et contexte actif.

**Independent Test**: Appeler chaque commande `roadie query ... --json` sur un état contrôlé et valider les champs contractuels.

### Tests for User Story 5

- [ ] T063 [P] [US5] Ajouter les tests de schéma `query state` et `query windows` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T064 [P] [US5] Ajouter les tests de schéma `query displays|desktops|stages|groups|rules` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T065 [P] [US5] Ajouter les tests de compatibilité avec `state`, `tree` et `windows list --json` dans `Tests/RoadieDaemonTests/LegacyQueryCompatibilityTests.swift`

### Implementation for User Story 5

- [ ] T066 [US5] Créer `AutomationQueryService` dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T067 [US5] Ajouter les projections fenêtres/écrans/desktops/stages dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T068 [US5] Ajouter les projections groupes et règles dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T069 [US5] Ajouter les commandes `roadie query state|windows|displays|desktops|stages|groups|rules` dans `Sources/roadie/main.swift`
- [ ] T070 [US5] Mettre à jour le contrat CLI final dans `specs/002-roadie-ecosystem-upgrade/contracts/cli.md`
- [ ] T071 [US5] Lancer `swift test --filter QueryCommandTests` et corriger les échecs dans `Sources/RoadieDaemon/AutomationQueryService.swift`

**Checkpoint**: US5 stabilise la surface de lecture pour intégrations externes.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Durcir l'ensemble, vérifier la non-régression et finaliser la documentation.

- [ ] T072 [P] Mettre à jour le quickstart final avec les commandes réelles dans `specs/002-roadie-ecosystem-upgrade/quickstart.md`
- [ ] T073 [P] Mettre à jour l'ADR avec les écarts décidés pendant l'implémentation dans `docs/decisions/001-roadie-automation-contract.md`
- [ ] T074 Ajouter les tests de non-régression existants Spec 002 dans `Tests/RoadieDaemonTests/Spec002RegressionTests.swift`
- [ ] T075 Lancer `swift test` et corriger les régressions dans `Sources/` et `Tests/`
- [ ] T076 Exécuter manuellement le scénario quickstart via `swift run roadie events subscribe --from-now --initial-state` et noter le résultat dans `specs/002-roadie-ecosystem-upgrade/quickstart.md`
- [ ] T077 Vérifier qu'aucune commande Spec 002 n'introduit API privée, SIP off, Spaces natifs Apple ou daemon hotkey dans `Sources/`
- [ ] T078 Mettre à jour le statut de session 002 dans `.specify/memory/sessions/index.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: démarre immédiatement.
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

---

## Parallel Opportunities

- T002 et T003 peuvent être faits en parallèle après T001.
- T007, T008 et T009 peuvent être faits en parallèle après T006.
- T015, T016 et T017 peuvent être faits en parallèle avant l'implémentation US1.
- T027, T028, T029 et T030 peuvent être faits en parallèle avant l'implémentation US2.
- T041, T042 et T043 peuvent être faits en parallèle avant l'implémentation US3.
- T052, T053 et T054 peuvent être faits en parallèle avant l'implémentation US4.
- T063, T064 et T065 peuvent être faits en parallèle avant l'implémentation US5.
- T072 et T073 peuvent être faits en parallèle pendant la phase de polish.

---

## Parallel Example: User Story 1

```bash
# Tâches de test parallélisables
Task: "T015 Ajouter les tests du catalogue minimal d'événements dans Tests/RoadieDaemonTests/EventCatalogTests.swift"
Task: "T016 Ajouter les tests de suivi subscribe --from-now dans Tests/RoadieDaemonTests/EventSubscriptionTests.swift"
Task: "T017 Ajouter le test subscribe --initial-state dans Tests/RoadieDaemonTests/EventSubscriptionTests.swift"
```

---

## Parallel Example: User Story 2

```bash
# Tâches de test parallélisables
Task: "T027 Ajouter les tests de parsing [[rules]] dans Tests/RoadieDaemonTests/WindowRuleConfigTests.swift"
Task: "T028 Ajouter les tests de validation de conflits dans Tests/RoadieDaemonTests/WindowRuleValidationTests.swift"
Task: "T029 Ajouter les tests de matching app/title/role/stage dans Tests/RoadieDaemonTests/WindowRuleMatcherTests.swift"
Task: "T030 Ajouter les tests CLI rules validate et rules explain dans Tests/RoadieDaemonTests/RulesCommandTests.swift"
```

---

## Implementation Strategy

### MVP First

1. Terminer Phase 1 et Phase 2.
2. Implémenter uniquement US1.
3. Valider `roadie events subscribe --from-now --initial-state`.
4. Stopper et vérifier que les commandes existantes continuent de fonctionner.

### Incremental Delivery

1. US1 : observation live.
2. US5 partiel : query state/windows si nécessaire pour stabiliser les intégrations.
3. US2 : règles.
4. US3 : commandes power-user.
5. US4 : groupes.
6. US5 complet : toutes les projections.

### Single Developer Strategy

Avancer séquentiellement : Phase 1 -> Phase 2 -> US1 -> validation -> US2 -> validation -> US3 -> validation -> US4 -> validation -> US5 -> polish.

### Multi-Agent Strategy

Après Phase 2 seulement, répartir sans chevauchement :

- Agent A : US1 events/subscription.
- Agent B : US2 rules engine.
- Agent C : US3 layout commands.
- Agent D : US5 query service, en attente des modèles groups/rules pour les projections finales.
