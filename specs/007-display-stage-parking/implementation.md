# Journal d'Implémentation - Parking et restauration des stages d'écrans

## Métadonnées

- **Spec** : `007-display-stage-parking`
- **Branche** : `031-display-stage-parking`
- **Démarré** : 2026-05-12
- **Terminé** : En cours

## Garde-fous de session

- **Worktree dédié** : non utilisé pour cette reprise, car la branche `031-display-stage-parking` et plusieurs correctifs préparatoires étaient déjà présents dans le worktree courant avant `$speckit-implement`.
- **Mitigation** : conserver l'état courant par commits de phase avant merge, ne pas supprimer les branches/stash de sauvegarde existants, et limiter les changements aux fichiers listés par `tasks.md`.

## Progression

### Phase 1 : Mise en place

- **Statut** : Terminé
- **Fichiers créés** :
  - `Sources/RoadieDaemon/DisplayParkingService.swift`
  - `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
  - `Tests/RoadieDaemonTests/Fixtures/DisplayParkingFixtures.json`
  - `specs/007-display-stage-parking/implementation.md`
- **Tests exécutés** : inclus dans la validation fondation ci-dessous
- **Notes** : Le service démarre par un rapport `noop` minimal pour permettre l'intégration progressive.

### Phase 2 : Fondations bloquantes

- **Statut** : Terminé
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/StageStore.swift`
  - `Sources/RoadieDaemon/DisplayTopology.swift`
  - `Sources/RoadieDaemon/StateAudit.swift`
  - `Sources/RoadieDaemon/DaemonSnapshot.swift`
  - `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
  - `Tests/RoadieDaemonTests/DisplayTopologyTests.swift`
  - `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- **Décisions** :
  - Les scopes d'écrans absents sont conservés comme état récupérable, pas fusionnés automatiquement.
  - La reconnaissance d'écran privilégie l'ancien `DisplayID`, puis un score conservateur sur empreinte.
  - Une égalité de score bloque la restauration automatique et produit un état ambigu.
- **Tests exécutés** :
  - `./scripts/with-xcode swift test --filter PersistentStageStateTests --filter DisplayTopologyTests --filter DisplayParkingServiceTests/serviceCanReturnStableNoopReport --filter SnapshotServiceTests/staleDisplayMembershipIsReassignedWithoutMigratingDisconnectedScope`
- **Résultat** : 23 tests passés.

### Phase 3 : US1 - Rapatrier les stages d'un écran débranché

- **Statut** : Terminé
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/DisplayParkingService.swift`
  - `Sources/RoadieDaemon/DaemonHealth.swift`
  - `Sources/roadied/main.swift`
  - `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- **Décisions** :
  - Les stages non vides d'un écran absent sont copiées sur l'écran hôte comme stages `parked` distinctes.
  - L'ancien scope d'écran absent reste présent comme métadonnée cachée, sans membres dupliqués.
  - L'écran hôte est choisi par priorité : écran actif vivant, écran principal, premier écran vivant.
  - Le heal de changement d'écran exécute le parking avant l'audit et le layout.
- **Tests exécutés** :
  - `./scripts/with-xcode swift test --filter DisplayParkingServiceTests --filter SnapshotServiceTests/staleDisplayMembershipIsReassignedWithoutMigratingDisconnectedScope`
- **Résultat** : 7 tests passés.

### Phase 4 : US2 - Restaurer les stages quand l'écran revient

- **Statut** : Terminé
- **Fichiers modifiés** :
  - `Sources/RoadieDaemon/DisplayParkingService.swift`
  - `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- **Décisions** :
  - La restauration utilise la stage `parked` courante, pas le snapshot d'origine.
  - Si l'ID système de l'écran a changé, l'empreinte d'écran décide la restauration.
  - En cas de plusieurs candidats équivalents, aucune restauration automatique n'est faite.
- **Tests exécutés** :
  - `./scripts/with-xcode swift test --filter DisplayParkingServiceTests`
- **Résultat** : 11 tests passés.

### Phase 5 : US3 - Stabilité, récupération et diagnostics

- **Statut** : Terminé
- **Fichiers modifiés** :
  - `Sources/roadied/main.swift`
  - `Sources/RoadieDaemon/DaemonHealth.swift`
  - `Sources/RoadieDaemon/StateAudit.swift`
  - `Sources/RoadieDaemon/Formatters.swift`
  - `Sources/RoadieCore/AutomationEventCatalog.swift`
  - `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
  - `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
  - `Tests/RoadieDaemonTests/FormattersTests.swift`
  - `Tests/RoadieDaemonTests/EventCatalogTests.swift`
- **Décisions** :
  - Les notifications d'écran restent débouncées dans `roadied/main.swift`, et les ticks sont suspendus pendant la stabilisation.
  - Les rapports de parking sont journalisés dans `events.jsonl` avec un type public `display.parking_*`.
  - Les scopes/stages parkés incomplets sont un état récupérable et restent en `warn`, pas en `fail`.
- **Tests exécutés** :
  - `./scripts/with-xcode swift test --filter DisplayParkingServiceTests --filter EventCatalogTests --filter FormattersTests/displayParkingFormatsDiagnosticFields --filter SnapshotServiceTests/parkedStagesAreWarnNotFail --filter SnapshotServiceTests/lostWindowRiskFailsOnlyWhenUnrecoverable --filter SnapshotServiceTests/stateHealRepairsDuplicateStaleAndBrokenFocusState`
- **Résultat** : 21 tests passés.

### Phase 6 : Finition transversale

- **Statut** : Terminé côté code et tests automatisés ; quickstart matériel non exécuté faute de débranchement/rebranchement réel dans cette passe.
- **Fichiers modifiés** :
  - `README.md`
  - `README.fr.md`
  - `docs/en/README.md`
  - `docs/en/features.md`
  - `docs/en/events-query.md`
  - `docs/fr/README.md`
  - `docs/fr/features.md`
  - `docs/fr/events-query.md`
  - `Sources/RoadieDaemon/StageStore.swift`
- **Décisions** :
  - L'ancien chemin `migrateDisconnectedDisplays` est supprimé : aucun appel restant dans `Sources/` ou `Tests/`.
  - La documentation décrit le comportement utilisateur, sans référence aux specs internes.
- **Validations exécutées** :
  - `make build`
  - `./scripts/roadie config validate`
  - `./scripts/with-xcode swift test --filter DisplayParkingServiceTests --filter DisplayTopologyTests --filter PersistentStageStateTests --filter EventCatalogTests --filter FormattersTests/displayParkingFormatsDiagnosticFields --filter SnapshotServiceTests/parkedStagesAreWarnNotFail --filter SnapshotServiceTests/lostWindowRiskFailsOnlyWhenUnrecoverable --filter SnapshotServiceTests/staleDisplayMembershipIsReassignedWithoutMigratingDisconnectedScope --filter SnapshotServiceTests/stateHealRepairsDuplicateStaleAndBrokenFocusState`
  - `make test`
  - `rg -n "migrateDisconnectedDisplays" Sources Tests || true`
- **Résultat** :
  - Build OK, avec l'avertissement existant `CGWindowListCreateImage` déprécié.
  - Config OK, avec warnings existants sur tables TOML connues/non supportées.
  - 43 tests ciblés passés.
  - Suite complète OK : 296 tests passés.
  - Aucun appel restant à `migrateDisconnectedDisplays`.
