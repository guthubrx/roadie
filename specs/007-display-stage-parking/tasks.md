# Tâches : Parking et restauration des stages d'écrans

**Entrée**: artefacts de conception dans `/specs/007-display-stage-parking/`  
**Prérequis**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: tests obligatoires, car la spec et le plan exigent des tests unitaires sur parking, restauration, ambiguïté, rafales, scopes stale, stages vides, groupes/focus et non-fusion.

**Organisation**: les tâches sont regroupées par parcours utilisateur pour permettre une livraison incrémentale et testable.

## Phase 1 : Mise en place

**Objectif**: préparer les fichiers, la traçabilité et les garde-fous sans changer le comportement utilisateur.

- [x] T001 Vérifier que l'implémentation se fait dans un worktree dédié `.worktrees/031-display-stage-parking/` ou documenter l'écart dans `specs/007-display-stage-parking/implementation.md`
- [x] T002 Créer le fichier de service `Sources/RoadieDaemon/DisplayParkingService.swift` dans le target SwiftPM existant
- [x] T003 Créer le fichier de tests `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T004 [P] Ajouter les fixtures de base multi-écrans dans `Tests/RoadieDaemonTests/Fixtures/DisplayParkingFixtures.json`
- [x] T005 Créer le journal d'implémentation `specs/007-display-stage-parking/implementation.md`
- [x] T006 [P] Créer l'ADR de décision de parking/restauration d'écran dans `docs/decisions/`
- [x] T007 Ajouter une section de validation rapide dédiée au parking dans `specs/007-display-stage-parking/quickstart.md`

---

## Phase 2 : Fondations bloquantes

**Objectif**: installer le modèle commun, la reconnaissance d'écran et les invariants non destructifs. Cette phase bloque tous les parcours utilisateur.

- [x] T008 Ajouter `LogicalDisplayID`, `DisplayFingerprint`, `StageParkingState`, `StageOrigin` et `ParkingSessionState` dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T009 Ajouter les tests de compatibilité JSON ancien format dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [x] T010 Implémenter le décodage par défaut `native` pour les stages sans champs de parking dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T011 [P] Ajouter les tests de fingerprint d'écran et de match ambigu dans `Tests/RoadieDaemonTests/DisplayTopologyTests.swift`
- [x] T012 Implémenter le calcul d'empreinte et le scoring conservateur de reconnaissance dans `Sources/RoadieDaemon/DisplayTopology.swift`
- [x] T013 Modifier `Sources/RoadieDaemon/StateAudit.swift` pour conserver les scopes d'écrans absents et les signaler en `warn`
- [x] T014 Modifier `Sources/RoadieDaemon/DaemonSnapshot.swift` pour ne plus migrer implicitement les scopes absents vers un fallback
- [x] T015 Ajouter les tests de non-migration destructive des scopes stale dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [x] T016 Exécuter les tests fondation via `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`, `Tests/RoadieDaemonTests/DisplayTopologyTests.swift` et `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [x] T017 Mettre à jour `specs/007-display-stage-parking/implementation.md` avec les fichiers modifiés, tests exécutés et décisions de Phase 2

**Point de contrôle**: le modèle lit l'ancien état, conserve les scopes absents et sait reconnaître un écran revenu sans déplacer de stages.

---

## Phase 3 : Parcours utilisateur 1 - Rapatrier les stages d'un écran débranché (Priorité: P1)

**Objectif**: débrancher un écran sans perdre les fenêtres et sans fusionner toutes les stages dans la stage active de l'écran restant.

**Test indépendant**: deux écrans, trois stages non vides sur l'écran secondaire, débranchement simulé ; les trois stages deviennent trois stages rapatriées distinctes sur l'écran hôte.

### Tests du parcours utilisateur 1

- [x] T018 [US1] Ajouter le test `parksNonEmptyStagesAsDistinctStagesOnHostDisplay` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T019 [US1] Ajouter le test `doesNotMergeDisconnectedDisplayIntoActiveStage` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T020 [US1] Ajouter le test `preservesNameModeFocusGroupsAndRelativeOrderWhenParking` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T021 [US1] Ajouter le test `keepsEmptyDisconnectedStagesAsHiddenRestorableMetadata` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T022 [US1] Ajouter le test `preservesHostActiveStageAndNativeStageOrderWhenParking` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`

### Implémentation du parcours utilisateur 1

- [x] T023 [US1] Implémenter `DisplayParkingReport` et les raisons stables `display_removed`, `no_live_host`, `no_parked_stages` dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T024 [US1] Implémenter le choix d'écran hôte actif/principal/premier live dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T025 [US1] Implémenter le parking des stages non vides comme stages distinctes dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T026 [US1] Préserver nom, mode, membres, groupes, focus et ordre relatif pendant le parking dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T027 [US1] Conserver les stages vides d'écran absent sans les afficher comme stages hôtes visibles dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T028 [US1] Préserver la stage active et l'ordre des stages natives de l'écran hôte dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T029 [US1] Intégrer le parking dans `Sources/RoadieDaemon/DaemonHealth.swift` sans réintroduire `migrateDisconnectedDisplays`
- [x] T030 [US1] Exécuter les tests US1 via `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T031 [US1] Mettre à jour `specs/007-display-stage-parking/implementation.md` avec les fichiers modifiés, tests exécutés et résultat US1

**Point de contrôle**: le débranchement d'un écran est non destructif et les stages rapatriées sont utilisables séparément.

---

## Phase 4 : Parcours utilisateur 2 - Restaurer les stages quand l'écran revient (Priorité: P2)

**Objectif**: rebrancher le même écran et restaurer les stages rapatriées vers cet écran en gardant leur état courant.

**Test indépendant**: après un parking, modifier une stage rapatriée, simuler le retour du même écran avec ID identique ou changé ; la stage courante retourne sur l'écran reconnu.

### Tests du parcours utilisateur 2

- [x] T032 [US2] Ajouter le test `restoresParkedStagesToRecognizedDisplay` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T033 [US2] Ajouter le test `restoresCurrentParkedStateInsteadOfOriginalSnapshot` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T034 [US2] Ajouter le test `refusesAutomaticRestoreWhenDisplayMatchIsAmbiguous` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T035 [US2] Ajouter le test `restoresDisplayWhenSystemDisplayIDChangedButFingerprintMatches` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T036 [US2] Ajouter le test `preservesRenameReorderMoveAndModeChangesMadeWhileParked` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`

### Implémentation du parcours utilisateur 2

- [x] T037 [US2] Implémenter la recherche de stages `parked` par origine logique dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T038 [US2] Implémenter la restauration conservatrice vers un écran reconnu dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T039 [US2] Implémenter le refus de restauration automatique si plusieurs candidats matchent dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T040 [US2] Préserver les renommages, réordonnancements, déplacements de fenêtres et changements de mode faits pendant l'absence dans `Sources/RoadieDaemon/DisplayParkingService.swift`
- [x] T041 [US2] Mettre à jour les scopes, `activeDisplayID` et sélections desktop après restauration dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T042 [US2] Exécuter les tests US2 via `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T043 [US2] Mettre à jour `specs/007-display-stage-parking/implementation.md` avec les fichiers modifiés, tests exécutés et résultat US2

**Point de contrôle**: les stages parkées reviennent automatiquement seulement quand l'écran revenu est reconnu sans ambiguïté.

---

## Phase 5 : Parcours utilisateur 3 - Garder un état compréhensible et récupérable (Priorité: P3)

**Objectif**: éviter les oscillations, rendre le parking observable, et garder les fenêtres récupérables même en cas de rafales ou d'échecs partiels.

**Test indépendant**: simuler plusieurs notifications de changement d'écran rapprochées, une restauration ambiguë et un échec de déplacement ; Roadie applique une seule transition stable et laisse les stages visibles.

### Tests du parcours utilisateur 3

- [x] T044 [US3] Ajouter le test `debouncesDisplayChangeNotificationsBeforeParking` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T045 [US3] Ajouter le test `keepsParkedStagesVisibleWhenWindowMoveFails` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T046 [US3] Ajouter le test `parkingAndRestoreCompleteWithinConfiguredFiveSecondBudget` dans `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`
- [x] T047 [US3] Ajouter les tests d'audit `parkedStagesAreWarnNotFail` et `lostWindowRiskFailsOnlyWhenUnrecoverable` dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [x] T048 [P] [US3] Ajouter les tests de formatage diagnostic parking dans `Tests/RoadieDaemonTests/FormattersTests.swift`

### Implémentation du parcours utilisateur 3

- [x] T049 [US3] Remplacer le heal immédiat de changement d'écran par un debounce annulable dans `Sources/roadied/main.swift`
- [x] T050 [US3] Suspendre les ticks de maintenance pendant la période de stabilisation dans `Sources/roadied/main.swift`
- [x] T051 [P] [US3] Émettre les événements `display.parking_started`, `display.parking_restored`, `display.parking_ambiguous` et `display.parking_noop` dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [x] T052 [P] [US3] Écrire les événements de parking/restauration dans `Sources/RoadieDaemon/EventLog.swift`
- [x] T053 [P] [US3] Ajouter le formatteur d'état native/parked/restored dans `Sources/RoadieDaemon/Formatters.swift`
- [x] T054 [US3] Exposer l'état de parking dans les commandes de diagnostic existantes dans `Sources/roadie/main.swift`
- [x] T055 [US3] Exécuter les tests US3 via `Tests/RoadieDaemonTests/DisplayParkingServiceTests.swift`, `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` et `Tests/RoadieDaemonTests/FormattersTests.swift`
- [x] T056 [US3] Mettre à jour `specs/007-display-stage-parking/implementation.md` avec les fichiers modifiés, tests exécutés et résultat US3

**Point de contrôle**: les changements d'écran rapides ne provoquent qu'une transition finale, et l'utilisateur peut diagnostiquer l'état des stages.

---

## Phase 6 : Finition et vérifications transverses

**Objectif**: vérification complète, documentation et nettoyage des anciennes migrations dangereuses.

- [x] T057 [P] Mettre à jour la documentation FR dans `docs/fr/` avec le comportement de parking d'écran
- [x] T058 [P] Mettre à jour la documentation EN dans `docs/en/` avec le comportement de parking d'écran
- [x] T059 [P] Mettre à jour le README fonctionnel dans `README.md`
- [x] T060 Supprimer ou déprécier l'ancien chemin `migrateDisconnectedDisplays` dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T061 Vérifier qu'aucun appel destructif à `migrateDisconnectedDisplays` ne reste dans `Sources/RoadieDaemon/`
- [x] T062 Exécuter `make build` via `Makefile`
- [x] T063 Exécuter `./scripts/roadie config validate` via `scripts/roadie`
- [ ] T064 Exécuter le quickstart manuel décrit dans `specs/007-display-stage-parking/quickstart.md`
- [x] T065 Finaliser `specs/007-display-stage-parking/implementation.md` avec le résumé des validations, commits et risques résiduels

---

## Dépendances et ordre d'exécution

### Dépendances de phases

- **Phase 1 Mise en place** : aucune dépendance.
- **Phase 2 Fondations** : dépend de Phase 1 et bloque tous les parcours utilisateur.
- **US1 Parking** : dépend de Phase 2 ; MVP.
- **US2 Restauration** : dépend de Phase 2 et utilise les états créés par US1.
- **US3 Stabilité/diagnostic** : dépend de Phase 2 ; peut être commencé après les signatures de rapport, mais doit intégrer US1/US2.
- **Phase 6 Finition** : dépend des parcours choisis pour la livraison.

### Dépendances par parcours utilisateur

- **US1 (P1)** : première livraison utile, aucun besoin fonctionnel de US2/US3.
- **US2 (P2)** : dépend conceptuellement de l'état `parked` produit par US1.
- **US3 (P3)** : peut avancer en parallèle sur diagnostics, mais l'intégration finale dépend des rapports US1/US2.

### À l'intérieur de chaque parcours

- Les tests du parcours sont écrits avant l'implémentation du parcours.
- Le modèle précède le service.
- Le service précède l'intégration daemon/health.
- L'intégration précède le quickstart manuel.
- Chaque tâche terminée met à jour `implementation.md` avant commit.

---

## Opportunités de parallélisation

- T004 et T006 peuvent être faits en parallèle après T001.
- T011 peut être fait en parallèle des tests JSON T009, car les fichiers sont distincts.
- T048 peut être fait en parallèle de T044 à T047, car il cible `FormattersTests.swift`.
- T051, T052 et T053 peuvent être faits en parallèle après stabilisation du rapport de service.
- T057, T058 et T059 peuvent être faits en parallèle après stabilisation du comportement.

## Exemple de parallélisation : fondations

```text
Task: "T009 Ajouter les tests de compatibilité JSON ancien format dans Tests/RoadieDaemonTests/PersistentStageStateTests.swift"
Task: "T011 Ajouter les tests de fingerprint d'écran et de match ambigu dans Tests/RoadieDaemonTests/DisplayTopologyTests.swift"
```

## Exemple de parallélisation : diagnostic US3

```text
Task: "T048 Ajouter les tests de formatage diagnostic parking dans Tests/RoadieDaemonTests/FormattersTests.swift"
Task: "T051 Émettre les événements display parking dans Sources/RoadieCore/AutomationEventCatalog.swift"
Task: "T052 Écrire les événements de parking/restauration dans Sources/RoadieDaemon/EventLog.swift"
Task: "T053 Ajouter le formatteur d'état native/parked/restored dans Sources/RoadieDaemon/Formatters.swift"
```

---

## Stratégie d'implémentation

### MVP d'abord : US1

1. Terminer Phase 1 et Phase 2.
2. Implémenter US1 uniquement.
3. Valider que le débranchement ne mélange plus les stages et ne perd pas les fenêtres.
4. Relancer Roadie pour test manuel.

### Livraison incrémentale

1. US1 : parking distinct et non destructif.
2. US2 : restauration conservatrice quand l'écran revient.
3. US3 : debounce, diagnostics et robustesse des rafales.
4. Finition : docs, build, quickstart et nettoyage des chemins obsolètes.

### Sécurité de rollback

Avant l'implémentation, conserver les changements actuels dans un commit ou une branche de sauvegarde et vérifier le worktree dédié. La zone est sensible car elle touche `StageStore`, `DaemonSnapshot`, `StateAudit`, `DaemonHealth` et `roadied/main.swift`, c'est-à-dire les mêmes composants que les régressions récentes de stages/bordures/layout.
