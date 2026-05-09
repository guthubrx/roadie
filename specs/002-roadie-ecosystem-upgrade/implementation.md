# Journal d'Implémentation - Roadie Ecosystem Upgrade

## Métadonnées

- **Spec** : `002-roadie-ecosystem-upgrade`
- **Branche** : `002-roadie-ecosystem-upgrade`
- **Worktree** : `.worktrees/002-roadie-ecosystem-upgrade/`
- **Démarré** : Non démarré
- **Terminé** : En cours

## Règle d'exécution

Chaque tâche de `tasks.md` doit suivre le cycle constitutionnel :

1. marquer une seule tâche en cours.
2. implémenter uniquement cette tâche.
3. exécuter les gates Roadie applicables : `swift build`, `swift test`, puis test CLI manuel si demandé.
4. documenter les fichiers modifiés, tests lancés et résultat dans ce journal.
5. committer une tâche validée dans un commit dédié.

## Progression

### T001 : Fixtures d'événements Spec 002

- **Statut** : Complété
- **Commit** : `a204915` - test(002): Add event fixture
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/Fixtures/Spec002Events.jsonl` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T001 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Validation JSONL via `jq`
  - [x] `swift build`
  - [ ] `swift test` : non requis pour fixture seule
- **Notes** : La fixture couvre snapshot initial, fenêtre créée/détruite, focus, desktop, stage, règle appliquée et commande appliquée.

### T002 : Fixture de snapshot Spec 002

- **Statut** : Complété
- **Commit** : `63ee8af` - test(002): Add snapshot fixture
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/Fixtures/Spec002Snapshot.json` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T002 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Validation JSON via `jq`
  - [x] `swift build`
  - [ ] `swift test` : non requis pour fixture seule
- **Notes** : La fixture couvre display, desktops, stages, fenêtres et champs actifs attendus par `RoadieStateSnapshot`.

### T003 : Fixture de règles Spec 002

- **Statut** : Complété
- **Commit** : `225ce75` - test(002): Add rules fixture
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/Fixtures/Spec002Rules.toml` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T003 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : non requis pour fixture seule
- **Notes** : La fixture contient deux règles valides et trois exemples invalides pour parsing, conflits et regex invalide.

### T004 : Matrice de couverture automation

- **Statut** : Complété
- **Commit** : `465e648` - docs(002): Track automation coverage task
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/automation-coverage.md` (existant, validé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T004 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Relecture de couverture SC-002
  - [ ] `swift build` : non applicable, documentation seule
- **Notes** : La matrice justifie le seuil SC-002 à 93,3 % hors refus documentés.

### T005 : Initialisation du journal d'implémentation

- **Statut** : Complété
- **Commit** : `49a4169` - docs(002): Initialize implementation journal
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal initialisé et enrichi)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T005 cochée)
- **Tests exécutés** :
  - [x] Relecture du protocole `1 tâche = 1 commit`
  - [ ] `swift build` : non applicable, documentation seule
- **Notes** : Le journal contient la règle d'exécution et l'historique des premières tâches.

### T006 : Suivi fonctionnel Spec 002

- **Statut** : Complété
- **Commit** : `d486852` - docs(002): Add implementation tracking
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T006 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Relecture de cohérence plan/tasks/journal
  - [ ] `swift build` : non applicable, documentation seule
- **Notes** : Le journal rappelle le worktree, les gates Swift, le commit atomique et les points de livraison à surveiller.

### T007 : Déclaration des fixtures dans Package.swift

- **Statut** : Complété
- **Commit** : `3a7fe41` - test(002): Register daemon fixtures
- **Fichiers modifiés** :
  - `Package.swift` (ressources `Fixtures` pour `RoadieDaemonTests`)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T007 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : réservé à la phase fondation
- **Notes** : Les fixtures JSONL/JSON/TOML sont maintenant déclarées comme ressources SwiftPM du target de test.

### T008 : Modèle RoadieEventEnvelope

- **Statut** : Complété
- **Commit** : `ca7af2f` - feat(002): Add event envelope model
- **Fichiers modifiés** :
  - `Sources/RoadieCore/AutomationEvent.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T008 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T014/T016
- **Notes** : Enveloppe versionnée créée avec champs contractuels. Les types dédiés scope/subject/cause/payload seront enrichis dans T009.

### T009 : Types d'événements automation

- **Statut** : Complété
- **Commit** : `cac75bd` - feat(002): Add automation event types
- **Fichiers modifiés** :
  - `Sources/RoadieCore/AutomationEvent.swift` (types scope, subject, cause, payload)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T009 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T014/T016
- **Notes** : `AutomationPayload` supporte les valeurs JSON primitives, objets, tableaux et null pour éviter les payloads string-only.

### T010 : Modèle RoadieStateSnapshot

- **Statut** : Complété
- **Commit** : `3ad5b75` - feat(002): Add automation snapshot model
- **Fichiers modifiés** :
  - `Sources/RoadieCore/AutomationSnapshot.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T010 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T015/T016
- **Notes** : Le snapshot contractuel est découplé des types AX et expose displays, desktops, stages, windows, groups et rules.

### T011 : Modèle LayoutCommandIntent

- **Statut** : Complété
- **Commit** : `daf3481` - feat(002): Add layout command intent model
- **Fichiers modifiés** :
  - `Sources/RoadieCore/LayoutCommandIntent.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T011 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec les commandes power-user
- **Notes** : Le modèle capture commande, cible, arguments, source, corrélation et horodatage.

### T012 : EventLog compatible RoadieEventEnvelope

- **Statut** : Complété
- **Commit** : `3de38ea` - feat(002): Support event envelopes in log
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/EventLog.swift` (append/read enveloppes)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T012 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T014/T016
- **Notes** : `append(RoadieEvent)` reste disponible ; `append(RoadieEventEnvelope)` et `envelopes(limit:)` ajoutent la nouvelle surface sans rupture.

### T013 : Conversion legacy RoadieEvent

- **Statut** : Complété
- **Commit** : `4b51cd3` - feat(002): Convert legacy events
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/EventLog.swift` (conversion legacy)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T013 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T014/T016
- **Notes** : `envelopes(limit:)` tente d'abord le format enveloppe, puis convertit les anciennes lignes `RoadieEvent`.

### T014 : Tests AutomationEvent

- **Statut** : Complété
- **Commit** : `e715f1a` - test(002): Cover automation events
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/AutomationEventTests.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T014 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter AutomationEventTests`
- **Notes** : Les tests couvrent round-trip JSON payloads et lecture mixte enveloppe + legacy event.

### T015 : Tests AutomationSnapshot

- **Statut** : Complété
- **Commit** : `80116ff` - test(002): Cover automation snapshots
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/AutomationSnapshotTests.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T015 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter AutomationSnapshotTests`
- **Notes** : Les tests couvrent round-trip du snapshot contractuel et décodage de la fixture Spec002Snapshot.

### T016 : Checkpoint fondation AutomationEvent

- **Statut** : Complété
- **Commit** : `a270a41` - test(002): Validate event foundation
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T016 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [x] `swift test --filter AutomationEventTests`
- **Notes** : Checkpoint fondation validé. SwiftPM a attendu la fin du build parallèle puis les 2 tests AutomationEvent sont passés.

### T017 : Tests du catalogue minimal d'événements

- **Statut** : Complété
- **Commit** : `55d4f3b` - test(002): Cover event catalog
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/EventCatalogTests.swift` (créé)
  - `Sources/RoadieCore/AutomationEventCatalog.swift` (catalogue minimal compilable)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T017 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventCatalogTests`
- **Notes** : Le catalogue minimal est ajouté avec les tests pour conserver un commit vert ; T021 reste responsable de l'intégration complète du catalogue dans l'implémentation US1.

### T018 : Tests subscribe --from-now

- **Statut** : Complété
- **Commit** : `068e5d3` - test(002): Cover subscribe from now
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/EventSubscriptionTests.swift` (créé)
  - `Sources/RoadieDaemon/EventSubscriptionService.swift` (service minimal)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T018 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventSubscriptionTests`
- **Notes** : Le test valide qu'un abonnement démarré avec `fromNow` ignore les événements déjà écrits.

### T019 : Tests subscribe --initial-state

- **Statut** : Complété
- **Commit** : `0540cc0` - test(002): Cover initial state subscription
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/EventSubscriptionTests.swift` (test initial-state)
  - `Sources/RoadieDaemon/EventSubscriptionService.swift` (option initialState)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T019 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventSubscriptionTests`
- **Notes** : Le service peut émettre un événement synthétique `state.snapshot` depuis un `RoadieStateSnapshot`.

### T020 : Test de latence subscription

- **Statut** : Complété
- **Commit** : `9b008aa` - test(002): Cover subscription latency
- **Fichiers modifiés** :
  - `Tests/RoadieDaemonTests/EventSubscriptionTests.swift` (test latence)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T020 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventSubscriptionTests`
- **Notes** : Le chemin append + lecture disponible reste sous 1 seconde dans le test local.

### T021 : Catalogue AutomationEventCatalog

- **Statut** : Complété
- **Commit** : `dd72521` - feat(002): Complete event catalog
- **Fichiers modifiés** :
  - `Sources/RoadieCore/AutomationEventCatalog.swift` (API contains/filter)
  - `Tests/RoadieDaemonTests/EventCatalogTests.swift` (test de filtrage)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T021 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventCatalogTests`
- **Notes** : Le catalogue expose la liste minimale, une vérification d'existence et un filtrage par scope.

### T022 : EventSubscriptionService

- **Statut** : Complété
- **Commit** : `b59e981` - feat(002): Complete event subscription service
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/EventSubscriptionService.swift` (service subscription)
  - `Tests/RoadieDaemonTests/EventSubscriptionTests.swift` (filtrage et lecture complète)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T022 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter EventSubscriptionTests`
- **Notes** : Le service expose `start`, `readAvailable`, `readAll`, filtres type/scope et chemin effectif.

### T023 : AutomationSnapshotService

- **Statut** : Complété
- **Commit** : `3e9fc18` - feat(002): Add automation snapshot service
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/AutomationSnapshotService.swift` (créé)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T023 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : couverture dédiée prévue par les tests de snapshot/query ultérieurs
- **Notes** : Le service projette `DaemonSnapshot` vers `RoadieStateSnapshot` avec displays, desktops, stages et windows.

### T024 : Projection automation depuis DaemonSnapshot

- **Statut** : Complété
- **Commit** : `cd7382f` - feat(002): Expose automation snapshot projection
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/DaemonSnapshot.swift` (extension `automationSnapshot`)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T024 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
- **Notes** : Les futurs endpoints CLI peuvent obtenir un `RoadieStateSnapshot` directement depuis un `DaemonSnapshot`.

### T025 : Commande roadie events subscribe

- **Statut** : Complété
- **Commit** : `5ddb6a1` - feat(002): Add events subscribe command
- **Fichiers modifiés** :
  - `Sources/roadie/main.swift` (commande `events subscribe`)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T025 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
- **Notes** : La commande suit le journal JSONL et écrit les enveloppes sur stdout jusqu'à interruption utilisateur.

### T026 : Options de subscription CLI

- **Statut** : Complété
- **Commit** : `d1c320a` - feat(002): Add subscribe filters
- **Fichiers modifiés** :
  - `Sources/roadie/main.swift` (parsing options subscription)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T026 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
- **Notes** : `events subscribe` supporte `--from-now`, `--initial-state`, `--type` et `--scope`.

### T027 : Événements command.* CLI

- **Statut** : Complété
- **Commit** : `7f1cdeb` - feat(002): Emit subscribe command events
- **Fichiers modifiés** :
  - `Sources/roadie/main.swift` (helper `emitCommandEvent`)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T027 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
- **Notes** : `events subscribe` publie `command.received` et `command.applied`; le helper commun permet d'ajouter `command.failed` sur les commandes suivantes.

### T028 : Contrat events subscription

- **Statut** : Complété
- **Commit** : `96a6e20` - docs(002): Document event subscription behavior
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/contracts/events.md` (comportement implémenté)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T028 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Relecture contrat vs implémentation US1
  - [ ] `swift build` : non applicable, documentation seule
- **Notes** : Le contrat documente `from-now`, replay par défaut, initial state, filtres, command events et conversion legacy.

### T029 : Checkpoint US1 EventSubscription

- **Statut** : Complété
- **Commit** : `7963b0b` - test(002): Validate event subscription
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T029 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [x] `swift test --filter EventSubscriptionTests`
- **Notes** : Les 4 tests EventSubscription sont passés. SwiftPM a attendu la fin du build parallèle avant d'exécuter les tests.

### T030 : Parsing `[[rules]]`

- **Statut** : Complété
- **Commit** : `1ff4100` - test(002): Cover rule config parsing
- **Fichiers modifiés** :
  - `Sources/RoadieCore/WindowRule.swift` (modèles minimum)
  - `Sources/RoadieCore/Config.swift` (champ `rules`)
  - `Tests/RoadieDaemonTests/WindowRuleConfigTests.swift` (test fixture TOML)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T030 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter WindowRuleConfigTests`
- **Notes** : La config décode `[[rules]]`, `[rules.match]` et `[rules.action]` depuis la fixture Spec 002.

### T031/T037 : Validation des rules

- **Statut** : Complété
- **Commit** : `4dd8d35` - test(002): Cover rule validation
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/WindowRuleValidator.swift` (validateur)
  - `Tests/RoadieDaemonTests/WindowRuleValidationTests.swift` (tests conflits)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T031/T035/T036/T037 cochées)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter WindowRuleValidationTests`
- **Notes** : Le validateur refuse les rules sans matcher, les IDs dupliqués, les regex invalides et `exclude` combiné à des actions de layout/placement.

### T032/T038 : Matching des rules

- **Statut** : Complété
- **Commit** : `f9fb6d1` - test(002): Cover rule matching
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/WindowRuleMatcher.swift` (matcher)
  - `Tests/RoadieDaemonTests/WindowRuleMatcherTests.swift` (tests matcher)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T032/T038 cochées)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter WindowRuleMatcherTests`
- **Notes** : Le matcher combine les critères par AND, supporte exact/regex, stage/role via contexte, ignore les rules désactivées et priorise `priority` puis `id`.

### T033/T042 : Commandes rules

- **Statut** : Complété
- **Commit** : `c20bcd6` - feat(002): Add rules commands
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/RulesCommandService.swift` (service validate/list/explain)
  - `Sources/RoadieDaemon/Formatters.swift` (format texte rules)
  - `Sources/roadie/main.swift` (commande `rules`)
  - `Tests/RoadieDaemonTests/RulesCommandTests.swift` (tests commandes)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T033/T042 cochées)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter RulesCommandTests`
- **Notes** : `rules validate`, `rules list` et `rules explain` supportent `--json` et `--config PATH`; `explain` accepte les critères synthétiques `--app`, `--title`, `--role`, `--stage`, etc.

### T034/T039/T043 : Moteur rules et marqueur scratchpad

- **Statut** : Complété
- **Commit** : `b3d8d10` - feat(002): Add rule engine scratchpad markers
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/WindowRuleEngine.swift` (évaluation et marqueurs scratchpad)
  - `Sources/RoadieDaemon/RulesCommandService.swift` (réutilisation des noms d'actions)
  - `Sources/roadie/main.swift` (ID synthétique valide pour explain)
  - `Tests/RoadieDaemonTests/WindowRuleScratchpadTests.swift` (tests scratchpad)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T034/T039/T043 cochées)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter WindowRuleScratchpadTests`
- **Notes** : Le moteur conserve les marqueurs scratchpad par `WindowID` et expose un snapshot de ces marqueurs pour les futures queries.

### T040/T041 : Intégration maintainer et événements rule.*

- **Statut** : Complété
- **Commit** : `7a1c1d3` - feat(002): Publish rule events from maintainer
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/LayoutMaintainer.swift` (évaluation rules par tick)
  - `Sources/RoadieDaemon/WindowRuleEngine.swift` (erreurs de validation exposées)
  - `Tests/RoadieDaemonTests/WindowRuleMaintainerTests.swift` (tests événements)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T040/T041 cochées)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift test --filter WindowRuleMaintainerTests`
- **Notes** : Le maintainer publie `rule.matched`, `rule.applied`, `rule.skipped` et `rule.failed` dans le journal d'événements automation.

### T044 : Contrat TOML rules

- **Statut** : Complété
- **Commit** : `100c83a` - docs(002): Update rules config contract
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/contracts/config-rules.toml.md` (contrat réel)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T044 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Relecture contrat vs implémentation US2
- **Notes** : Le contrat documente les champs supportés, l'ordre de priorité réel, les conflits validés, les commandes CLI et les événements runtime.

### T045 : Checkpoint US2 WindowRule

- **Statut** : Complété
- **Commit** : Ce commit - test(002): Validate window rules checkpoint
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T045 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (résultats validation)
- **Tests exécutés** :
  - [x] `swift build`
  - [x] `swift test --filter WindowRule` : 16 tests, 5 suites, succès
  - [x] `swift test --filter RulesCommandTests` : 4 tests, 1 suite, succès
- **Notes** : US2 est livrable : parsing, validation, matching, commandes CLI, moteur scratchpad et événements runtime sont couverts.

### T046-T058 : US3 commandes power-user

- **Statut** : Complété
- **Commit** : Ce commit - feat(002): Add power user commands
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/StageStore.swift` (focus précédent persistant)
  - `Sources/RoadieDaemon/WindowCommands.swift` (`focusBackAndForth`)
  - `Sources/RoadieDaemon/DesktopCommands.swift` (`backAndForth`, `summon`)
  - `Sources/RoadieDaemon/StageCommands.swift` (`moveActiveStageToDisplay`)
  - `Sources/RoadieDaemon/LayoutCommandService.swift` (split/flatten/insert/join/zoom)
  - `Sources/roadie/main.swift` (CLI power-user)
  - `Tests/RoadieDaemonTests/PowerUser*.swift` (8 tests)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T046-T058 cochées)
- **Tests exécutés** :
  - [x] `swift build`
  - [x] `swift test --filter PowerUser` : 8 tests, 4 suites, succès
- **Notes** : Les commandes layout persistantes utilisent `LayoutIntentStore` avec source `command`; `stage summon` existait déjà et `stage move-to-display` complète le scénario multi-écran.

### T059-T071 : US4 window groups

- **Statut** : Complété
- **Commit** : Ce commit - feat(002): Add window groups
- **Fichiers modifiés** :
  - `Sources/RoadieStages/RoadieState.swift` (`WindowGroup`)
  - `Sources/RoadieDaemon/StageStore.swift` (persistance groupes)
  - `Sources/RoadieDaemon/WindowGroupCommands.swift` (commandes groupes)
  - `Sources/RoadieDaemon/AutomationSnapshotService.swift` (projection groupes)
  - `Sources/RoadieDaemon/BorderController.swift` (indicateur minimal)
  - `Sources/roadie/main.swift` (`roadie group ...`)
  - `Tests/RoadieStagesTests/WindowGroupStateTests.swift`
  - `Tests/RoadieDaemonTests/WindowGroup*.swift`
- **Tests exécutés** :
  - [x] `swift test --filter WindowGroup` : 5 tests, 4 suites, succès
- **Notes** : Le layout reste compatible en gardant les membres dans le stage; l'état groupé est persistant, commandable et exposé aux snapshots automation.

### T072-T082 : US5 query API

- **Statut** : Complété
- **Commit** : Ce commit - feat(002): Add automation query API
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/AutomationQueryService.swift`
  - `Sources/roadie/main.swift` (`roadie query ...`)
  - `Tests/RoadieDaemonTests/QueryCommandTests.swift`
  - `Tests/RoadieDaemonTests/QueryHealthEventsTests.swift`
  - `Tests/RoadieDaemonTests/LegacyQueryCompatibilityTests.swift`
  - `specs/002-roadie-ecosystem-upgrade/contracts/cli.md`
- **Tests exécutés** :
  - [x] `swift test --filter Query` : 4 tests, 3 suites, succès
- **Notes** : Les queries retournent un wrapper JSON stable `{kind,data}` et gardent les commandes legacy disponibles.

### T083-T089 : Finitions Spec 002

- **Statut** : Complété
- **Commit** : Ce commit - chore(002): Finalize ecosystem upgrade
- **Fichiers modifiés** :
  - `specs/002-roadie-ecosystem-upgrade/quickstart.md`
  - `Tests/RoadieDaemonTests/Spec002RegressionTests.swift`
  - `.specify/memory/sessions/index.md`
  - `specs/002-roadie-ecosystem-upgrade/tasks.md`
  - `specs/002-roadie-ecosystem-upgrade/implementation.md`
- **Tests exécutés** :
  - [x] `swift build`
  - [x] `swift test` : 138 tests, 27 suites, succès
  - [x] `swift run roadie events subscribe --from-now --initial-state` : flux JSONL démarré, `state.snapshot`, `command.received`, `command.applied` observés avant interruption automatique.
  - [x] Scan `rg` API privée/SIP/Spaces/hotkey : aucune API privée, SIP off, SkyLight/CGS, hotkey daemon ou Carbon ajoutés; seules occurrences `canJoinAllSpaces` correspondent aux overlays NSWindow existants.
- **Notes** : Session 002 marquée implémentée.
