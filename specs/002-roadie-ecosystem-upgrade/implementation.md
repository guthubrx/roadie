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

### T006 : Suivi Spec 002 dans l'ADR

- **Statut** : Complété
- **Commit** : `d486852` - docs(002): Add ADR implementation tracking
- **Fichiers modifiés** :
  - `docs/decisions/001-roadie-automation-contract.md` (section suivi Spec 002)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T006 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] Relecture de cohérence ADR/plan/tasks
  - [ ] `swift build` : non applicable, documentation seule
- **Notes** : L'ADR rappelle le worktree, les gates Swift, le commit atomique et les points de décision à surveiller.

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
- **Commit** : En attente
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/EventLog.swift` (conversion legacy)
  - `specs/002-roadie-ecosystem-upgrade/tasks.md` (T013 cochée)
  - `specs/002-roadie-ecosystem-upgrade/implementation.md` (journal)
- **Tests exécutés** :
  - [x] `swift build`
  - [ ] `swift test` : prévu avec T014/T016
- **Notes** : `envelopes(limit:)` tente d'abord le format enveloppe, puis convertit les anciennes lignes `RoadieEvent`.
