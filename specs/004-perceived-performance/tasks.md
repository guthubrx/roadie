# Tasks: Performance ressentie Roadie

**Input**: Design documents from `specs/004-perceived-performance/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Inclus car la spec exige des tests de régression stage, desktop, AltTab, lectures read-only et seuils mesurables.

**Organization**: Les tâches sont groupées par user story pour permettre une implémentation progressive et testable indépendamment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Peut être exécutée en parallèle avec une autre tâche qui touche des fichiers différents.
- **[Story]**: User story concernée (`US1` à `US5`).
- Chaque tâche indique des chemins exacts.

## Phase 1: Setup (Infrastructure partagée)

**Purpose**: Préparer les points d'intégration performance sans changer encore le comportement utilisateur.

- [ ] T001 Ajouter les types publics `PerformanceInteraction`, `PerformanceStep`, `PerformanceSnapshot`, `PerformanceThreshold`, `PerformanceThresholdBreach` et `PerformanceTargetContext` dans `Sources/RoadieCore/PerformanceModels.swift`
- [ ] T002 [P] Ajouter les tests d'encodage/agrégation des modèles performance dans `Tests/RoadieDaemonTests/PerformanceModelTests.swift`
- [ ] T003 Ajouter `PerformanceStore` avec historique borné et persistance locale dans `Sources/RoadieDaemon/PerformanceStore.swift`
- [ ] T004 Ajouter `PerformanceRecorder` pour démarrer/terminer une interaction et enregistrer des étapes dans `Sources/RoadieDaemon/PerformanceRecorder.swift`
- [ ] T005 Ajouter les seuils par défaut stage/desktop/AltTab/display/focus/rail dans `Sources/RoadieCore/Config.swift`
- [ ] T006 Exposer les types performance au build Swift Package sans nouveau target dans `Package.swift`

---

## Phase 2: Foundational (Pré-requis bloquants)

**Purpose**: Rendre la mesure consultable et read-only avant d'optimiser les chemins critiques.

**⚠️ CRITICAL**: Aucune optimisation stage/desktop/AltTab ne doit commencer avant cette phase.

- [ ] T007 [P] Ajouter les tests query read-only `roadie query performance` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T008 [P] Ajouter les tests CLI `performance summary`, `performance recent` et `performance thresholds` dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T009 [P] Ajouter les tests du catalogue d'événements performance dans `Tests/RoadieDaemonTests/EventCatalogTests.swift`
- [ ] T010 Brancher `PerformanceStore` dans `AutomationQueryService` pour `query performance` dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T011 Ajouter les formats texte performance dans `Sources/RoadieDaemon/Formatters.swift`
- [ ] T012 Ajouter les commandes CLI `roadie performance summary|recent|thresholds` dans `Sources/roadie/main.swift`
- [ ] T013 Ajouter les événements `performance.interaction_completed` et `performance.threshold_breached` au catalogue dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [ ] T014 Vérifier que les chemins performance utilisent uniquement des snapshots read-only dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [ ] T015 Lancer `make test` via `Makefile` et corriger toute régression liée aux modèles/query performance dans `Tests/RoadieDaemonTests/`

**Checkpoint**: Les diagnostics performance existent, sont consultables, et ne modifient pas l'état Roadie.

---

## Phase 3: User Story 1 - Comprendre où Roadie perd du temps (Priorité: P1) 🎯 MVP

**Goal**: L'utilisateur peut voir quelles interactions sont lentes et quelle étape domine.

**Independent Test**: Déclencher des interactions simulées, consulter `roadie performance summary`, `roadie performance recent --json` et `roadie query performance`, puis vérifier durée totale, étapes, seuils et dépassements.

### Tests for User Story 1

- [ ] T016 [P] [US1] Ajouter un test d'interaction stage mesurée avec étapes et total dans `Tests/RoadieDaemonTests/PerformanceRecorderTests.swift`
- [ ] T017 [P] [US1] Ajouter un test de dépassement de seuil avec `dominantStep` dans `Tests/RoadieDaemonTests/PerformanceRecorderTests.swift`
- [ ] T018 [P] [US1] Ajouter un test de résumé médiane/p95/slow_count dans `Tests/RoadieDaemonTests/PerformanceModelTests.swift`

### Implementation for User Story 1

- [ ] T019 [US1] Instrumenter `StageCommandService.switchDisplay` avec étapes `state_update`, `hide_previous`, `restore_target`, `layout_apply`, `focus` dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T020 [US1] Instrumenter `DesktopCommandService.switchDisplay` avec les mêmes étapes dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T021 [US1] Instrumenter `DisplayCommandService.focus` avec étapes `state_update`, `focus` et `layout_apply` si applicable dans `Sources/RoadieDaemon/DisplayCommands.swift`
- [ ] T022 [US1] Instrumenter le focus directionnel dans `WindowCommandService.focus` sans modifier la logique de sélection dans `Sources/RoadieDaemon/WindowCommands.swift`
- [ ] T023 [US1] Publier les événements de performance depuis `PerformanceRecorder` via `EventLog` dans `Sources/RoadieDaemon/PerformanceRecorder.swift`
- [ ] T024 [US1] Ajouter le diagnostic des interactions lentes dans les sorties CLI performance dans `Sources/RoadieDaemon/Formatters.swift`
- [ ] T025 [US1] Lancer `make test` via `Makefile` et vérifier les commandes de quickstart dans `specs/004-perceived-performance/quickstart.md`

**Checkpoint**: User Story 1 est complète et fournit une baseline mesurable avant optimisations.

---

## Phase 4: User Story 2 - Changer de stage ou desktop sans attente visible (Priorité: P1)

**Goal**: Les raccourcis Roadie stage/desktop activent directement la cible, sans activation intermédiaire visible ni dépendance au prochain tick.

**Independent Test**: Créer plusieurs stages/desktops avec fenêtres, lancer les commandes directes et cycliques, puis vérifier que seule la cible devient active et que l'interaction mesurée reste sous seuil dans les fixtures.

### Tests for User Story 2

- [ ] T026 [P] [US2] Ajouter un test stage direct sans activation intermédiaire dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [ ] T027 [P] [US2] Ajouter un test desktop direct sans activation intermédiaire dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`
- [ ] T028 [P] [US2] Ajouter un test qui vérifie qu'un switch stage ne dépend pas d'un tick ultérieur dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`

### Implementation for User Story 2

- [ ] T029 [US2] Extraire un helper de bascule stage à scope limité dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T030 [US2] Réduire le second snapshot global après switch stage en réutilisant le contexte cible dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T031 [US2] Extraire un helper de bascule desktop à scope limité dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T032 [US2] Réduire le second snapshot global après switch desktop en réutilisant le contexte cible dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T033 [US2] Garantir que les commandes stage positionnelles utilisent l'ordre utilisateur sans conversion par ID dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T034 [US2] Enregistrer les mesures `stage_switch` et `desktop_switch` sous les seuils attendus dans les tests dans `Tests/RoadieDaemonTests/PerformanceRecorderTests.swift`
- [ ] T035 [US2] Lancer `make test` via `Makefile` puis valider les commandes stage/desktop listées dans `specs/004-perceived-performance/quickstart.md`

**Checkpoint**: Les switchs Roadie restent stables et ne dépendent plus du timer pour l'expérience principale.

---

## Phase 5: User Story 3 - Basculer via AltTab avec la même fluidité qu'un raccourci Roadie (Priorité: P1)

**Goal**: AltTab vers une fenêtre gérée active directement le stage/desktop propriétaire avec anti-oscillation.

**Independent Test**: Simuler un focus externe vers une fenêtre de stage ou desktop inactif et vérifier activation directe, déduplication des focus rapprochés et mesure `alt_tab_activation`.

### Tests for User Story 3

- [ ] T036 [P] [US3] Ajouter un test AltTab vers stage inactif avec interaction `alt_tab_activation` dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [ ] T037 [P] [US3] Ajouter un test AltTab vers desktop inactif avec interaction `alt_tab_activation` dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`
- [ ] T038 [P] [US3] Ajouter un test de coalescing des focus rapprochés dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`

### Implementation for User Story 3

- [ ] T039 [US3] Ajouter un résolveur de contexte propriétaire d'une fenêtre focus externe dans `Sources/RoadieDaemon/FocusStageActivationObserver.swift`
- [ ] T040 [US3] Ajouter un mécanisme de coalescing d'intentions focus rapprochées dans `Sources/RoadieDaemon/FocusStageActivationObserver.swift`
- [ ] T041 [US3] Déclencher une activation directe stage/desktop depuis l'observer sans passer par un tick global complet dans `Sources/RoadieDaemon/FocusStageActivationObserver.swift`
- [ ] T042 [US3] Publier les mesures `alt_tab_activation` et les dépassements de seuil dans `Sources/RoadieDaemon/FocusStageActivationObserver.swift`
- [ ] T043 [US3] Préserver les grâces de switch explicite pour éviter les oscillations dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [ ] T044 [US3] Lancer `make test` via `Makefile` puis valider AltTab vers stage inactif et desktop inactif selon `specs/004-perceived-performance/quickstart.md`

**Checkpoint**: AltTab devient un chemin utilisateur prioritaire, mesuré et anti-oscillation.

---

## Phase 6: User Story 4 - Éviter les mouvements inutiles de fenêtres (Priorité: P2)

**Goal**: Roadie évite les `setFrame` redondants et les corrections visuellement inutiles.

**Independent Test**: Dans un état proche de la cible, exécuter une commande et vérifier que le nombre de déplacements inutiles baisse tout en conservant le layout final.

### Tests for User Story 4

- [ ] T045 [P] [US4] Ajouter un test de tolérance de frame équivalente dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [ ] T046 [P] [US4] Ajouter un test de switch stage qui ne déplace pas les fenêtres déjà à la cible dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [ ] T047 [P] [US4] Ajouter un test de layout apply qui expose le nombre de commandes évitées dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`

### Implementation for User Story 4

- [ ] T048 [US4] Ajouter un helper de comparaison de frames avec tolérance documentée dans `Sources/RoadieCore/Geometry.swift`
- [ ] T049 [US4] Utiliser la tolérance avant `setFrame` dans les bascules stage dans `Sources/RoadieDaemon/StageCommands.swift`
- [ ] T050 [US4] Utiliser la tolérance avant `setFrame` dans les bascules desktop dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [ ] T051 [US4] Appliquer le skip des frames équivalentes dans `SnapshotService.apply` ou le point d'application central dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [ ] T052 [US4] Ajouter les compteurs de mouvements évités aux mesures performance dans `Sources/RoadieDaemon/PerformanceRecorder.swift`
- [ ] T053 [US4] Lancer `make test` via `Makefile` et comparer les mesures avant/après selon `specs/004-perceived-performance/quickstart.md`

**Checkpoint**: Les actions proches de leur état cible évitent les mouvements inutiles sans casser les layouts.

---

## Phase 7: User Story 5 - Garder le rail et les tâches de fond hors du chemin critique (Priorité: P2)

**Goal**: Le rail, les bordures, métriques et tâches de fond ne bloquent pas la visibilité ou le focus de la cible.

**Independent Test**: Activer rail/diagnostics, déclencher des bascules rapides, puis vérifier que les timings stage/desktop restent dans les seuils et que les surfaces secondaires se rafraîchissent après l'action principale.

### Tests for User Story 5

- [ ] T054 [P] [US5] Ajouter un test indiquant que `RailController` ne déclenche pas de snapshot mutateur pendant une commande critique dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`
- [ ] T055 [P] [US5] Ajouter un test de métriques performance read-only pendant interaction critique dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`
- [ ] T056 [P] [US5] Ajouter un test de tick maintainer conservé comme filet de sécurité dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`

### Implementation for User Story 5

- [ ] T057 [US5] Auditer les appels snapshot du rail et les basculer en read-only quand ils ne pilotent pas une action dans `Sources/RoadieDaemon/RailController.swift`
- [ ] T058 [US5] Reporter les rafraîchissements rail non essentiels après la fin des interactions critiques dans `Sources/RoadieDaemon/RailController.swift`
- [ ] T059 [US5] Garantir que `MetricsService` et `ControlCenterStateService` restent read-only pendant les mesures dans `Sources/RoadieDaemon/Metrics.swift` et `Sources/RoadieDaemon/ControlCenterStateService.swift`
- [ ] T060 [US5] Ajouter une mesure `secondary_work` pour rail/diagnostics quand ils suivent une commande dans `Sources/RoadieDaemon/PerformanceRecorder.swift`
- [ ] T061 [US5] Conserver le timer `LayoutMaintainer` comme correction périodique sans réduire l'intervalle par défaut dans `Sources/roadied/main.swift`
- [ ] T062 [US5] Lancer `make test`, `make build` via `Makefile` et vérifier `./bin/roadie daemon health` selon `specs/004-perceived-performance/quickstart.md`

**Checkpoint**: Les surfaces secondaires restent utiles mais hors chemin critique.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation finale et préparation au merge.

- [ ] T063 [P] Mettre à jour la documentation FR performance dans `docs/fr/features.md`
- [ ] T064 [P] Mettre à jour la documentation EN performance dans `docs/en/features.md`
- [ ] T065 [P] Ajouter les exemples CLI performance FR dans `docs/fr/cli.md`
- [ ] T066 [P] Ajouter les exemples CLI performance EN dans `docs/en/cli.md`
- [ ] T067 Créer ou mettre à jour l'ADR de politique "chemin critique utilisateur et observabilité performance" dans `docs/decisions/003-perceived-performance-critical-path.md`
- [ ] T068 Exécuter la validation quickstart complète dans `specs/004-perceived-performance/quickstart.md`
- [ ] T069 Lancer `make test` et `make build` via `Makefile` avant commit final
- [ ] T070 Relancer Roadie sans Control Center et vérifier `./scripts/status` puis `./bin/roadie daemon health` selon `specs/004-perceived-performance/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: aucune dépendance.
- **Phase 2 Foundational**: dépend de Phase 1 et bloque toutes les user stories.
- **US1 (Phase 3)**: dépend de Phase 2, MVP recommandé.
- **US2 (Phase 4)**: dépend de US1 pour disposer des mesures de stage/desktop.
- **US3 (Phase 5)**: dépend de US1 et des garanties read-only de Phase 2.
- **US4 (Phase 6)**: dépend de US1 pour prouver les déplacements évités et de US2 pour éviter de perturber les switchs directs.
- **US5 (Phase 7)**: dépend de US1 et peut être faite après US2/US3 pour mesurer le surcoût réel.
- **Polish (Phase 8)**: dépend des stories effectivement livrées.

### User Story Dependencies

- **US1**: indépendante après foundation. C'est le MVP.
- **US2**: dépend de l'instrumentation US1.
- **US3**: dépend de l'instrumentation US1 et des contrats de performance.
- **US4**: dépend de l'instrumentation US1 et doit préserver US2.
- **US5**: dépend de l'instrumentation US1 et des chemins critiques déjà mesurés.

### Within Each User Story

- Les tests marqués dans la story doivent être écrits avant l'implémentation de la story.
- Les modèles et services partagés précèdent la CLI/query/events.
- Une story doit passer `make test` avant de passer à la suivante.
- Chaque checkpoint doit pouvoir être validé indépendamment.

## Parallel Opportunities

- T002 peut être fait en parallèle de T003 après T001 si les types sont stables.
- T007, T008 et T009 peuvent être écrits en parallèle.
- Les tests d'une même story marqués [P] peuvent être écrits en parallèle.
- Les documentations FR/EN T063 à T066 peuvent être faites en parallèle après stabilisation des contrats.
- US2 et US3 ne doivent pas être codées en parallèle dans les mêmes fichiers `StageCommands.swift`, `DesktopCommands.swift`, `FocusStageActivationObserver.swift` sans coordination.

## Parallel Example: User Story 1

```bash
# Tests pouvant être préparés en parallèle :
Task: "T016 Ajouter un test d'interaction stage mesurée avec étapes et total dans Tests/RoadieDaemonTests/PerformanceRecorderTests.swift"
Task: "T017 Ajouter un test de dépassement de seuil avec dominantStep dans Tests/RoadieDaemonTests/PerformanceRecorderTests.swift"
Task: "T018 Ajouter un test de résumé médiane/p95/slow_count dans Tests/RoadieDaemonTests/PerformanceModelTests.swift"
```

## Parallel Example: User Story 4

```bash
# Tests pouvant être préparés en parallèle :
Task: "T045 Ajouter un test de tolérance de frame équivalente dans Tests/RoadieDaemonTests/SnapshotServiceTests.swift"
Task: "T046 Ajouter un test de switch stage qui ne déplace pas les fenêtres déjà à la cible dans Tests/RoadieDaemonTests/SnapshotServiceTests.swift"
Task: "T047 Ajouter un test de layout apply qui expose le nombre de commandes évitées dans Tests/RoadieDaemonTests/LayoutMaintainerTests.swift"
```

## Implementation Strategy

### MVP First (US1 uniquement)

1. Compléter Phase 1 et Phase 2.
2. Implémenter US1 pour produire les mesures et diagnostics.
3. Exécuter `make test`, `make build`, puis valider les commandes `roadie performance`.
4. Stopper et comparer la baseline avant d'optimiser.

### Incremental Delivery

1. US1 : instrumentation et diagnostics.
2. US2 : stage/desktop directs et mesurés.
3. US3 : AltTab prioritaire et anti-oscillation.
4. US4 : réduction des déplacements inutiles.
5. US5 : rail et tâches secondaires hors chemin critique.
6. Polish : docs FR/EN, ADR, quickstart, validation runtime.

### Commit Strategy

- Committer après chaque phase ou story validée.
- Ne pas mélanger instrumentation et optimisation dans le même commit si cela rend le diagnostic difficile.
- Chaque commit doit passer `make test`; les phases finales doivent aussi passer `make build`.

## Notes

- Les tâches performance ne doivent pas réintroduire de snapshots read/write dans les commandes de query/diagnostic.
- Les seuils de performance sont des objectifs de test contrôlé, pas une garantie universelle sur toute machine macOS.
- Le Control Center reste désactivé dans les validations runtime actuelles.
- Les changements doivent rester compatibles avec BetterTouchTool et les raccourcis CLI existants.
