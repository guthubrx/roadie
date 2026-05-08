# Tâches : Roadie Control & Safety

**Entrée**: Documents de design dans `specs/003-roadie-control-safety/`  
**Prérequis**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md  
**Tests**: Obligatoires pour chaque user story car la fonctionnalite touche la securite du daemon, la config, la restauration d'etat et des controles visibles utilisateur.

## Format : `[ID] [P?] [Story] Description`

- **[P]**: Peut etre execute en parallele avec d'autres taches de la meme phase
- **[Story]**: Mapping vers une user story de spec.md
- Chaque tache d'implementation reference des chemins de fichiers exacts

## Phase 1 : Setup (Infrastructure Partagée)

**Objectif**: Preparer la structure package, l'ADR et les fixtures de test sans changer le comportement runtime.

- [X] T001 Ajouter l'ADR de frontiere API publique Roadie Control & Safety dans `docs/decisions/002-control-safety-public-api-boundary.md`
- [X] T002 Mettre a jour les targets package pour le target dedie `RoadieControlCenter` et ses tests dans `Package.swift`
- [X] T003 [P] Creer le repertoire de fixtures partagees de la session 003 dans `Tests/RoadieDaemonTests/Fixtures/Spec003/`
- [X] T004 [P] Creer le journal d'implementation dans `specs/003-roadie-control-safety/implementation.md`

---

## Phase 2 : Fondations (Prérequis Bloquants)

**Objectif**: Fondations partagees de modeles/evenements/config utilisees par toutes les stories.

**CRITIQUE**: Aucun travail de user story ne peut commencer avant la fin de cette phase.

- [X] T005 Definir les sections de config control/safety dans `Sources/RoadieCore/Config.swift`
- [X] T006 Definir les nouvelles entrees du catalogue d'evenements automation dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [X] T007 [P] Ajouter les modeles core `ControlCenterState`, `ConfigReloadState`, `RestoreSafetySnapshot`, `WindowIdentityV2`, `TransientWindowState` et `WidthAdjustmentIntent` dans `Sources/RoadieCore/ControlSafetyModels.swift`
- [X] T008 [P] Ajouter des fixtures JSON/TOML pour config control safety valide et invalide dans `Tests/RoadieDaemonTests/Fixtures/Spec003/`
- [X] T009 Ajouter les tests baseline de decodage config dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [X] T010 Executer `make build` et `make test`, puis consigner les resultats dans `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: Fondations pretes ; les user stories peuvent demarrer.

---

## Phase 3 : User Story 1 - Piloter Roadie depuis macOS (Priorité : P1) MVP

**Objectif**: La barre de menus et la fenetre de reglages exposent l'etat Roadie et les actions courantes.

**Test indépendant**: `roadie control status --json` renvoie le meme etat que celui consomme par le menu ; les tests de rendu d'etat UI couvrent les cas arrete, actif, degrade et erreur de config.

### Tests pour User Story 1

- [X] T011 [P] [US1] Ajouter les tests du service `ControlCenterState` dans `Tests/RoadieDaemonTests/ControlCenterStateTests.swift`
- [X] T012 [P] [US1] Ajouter les tests de rendu/etat Control Center dans `Tests/RoadieControlCenterTests/ControlCenterStateRenderingTests.swift`
- [X] T013 [P] [US1] Ajouter les tests de contrat CLI pour `roadie control status --json` dans `Tests/RoadieDaemonTests/ControlCommandTests.swift`

### Implémentation pour User Story 1

- [X] T014 [US1] Implementer `ControlCenterStateService` dans `Sources/RoadieDaemon/ControlCenterStateService.swift`
- [X] T015 [US1] Ajouter le routage de commande `control status` dans `Sources/roadie/main.swift`
- [X] T016 [US1] Creer le shell app barre de menus dans `Sources/RoadieControlCenter/ControlCenterApp.swift`
- [X] T017 [US1] Creer le modele menu et les actions dans `Sources/RoadieControlCenter/ControlCenterMenu.swift`
- [X] T018 [US1] Creer le shell fenetre de reglages dans `Sources/RoadieControlCenter/SettingsWindow.swift`
- [X] T019 [US1] Raccorder le cycle de vie du Control Center depuis le chemin d'entree app packagee/manuelle dans `Sources/roadied/main.swift`
- [X] T020 [US1] Publier les evenements Control Center via `Sources/RoadieDaemon/EventLog.swift`
- [X] T021 [US1] Mettre a jour README et docs d'usage Control Center dans `README.md`, `README.fr.md`, `docs/en/features.md` et `docs/fr/features.md`
- [X] T022 [US1] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: L'utilisateur peut inspecter et piloter Roadie depuis la barre de menus ou l'etat CLI.

---

## Phase 4 : User Story 2 - Recharger la configuration sans casser la session (Priorité : P1)

**Objectif**: Le reload atomique conserve la config valide precedente en cas d'erreur.

**Test indépendant**: Un reload TOML/rules invalide renvoie `failed_keeping_previous`, laisse la config active inchangee et emet des evenements d'echec.

### Tests pour User Story 2

- [X] T023 [P] [US2] Ajouter les tests succes/echec de reload config dans `Tests/RoadieDaemonTests/ConfigReloadTests.swift`
- [X] T024 [P] [US2] Ajouter les assertions d'evenements reload dans `Tests/RoadieDaemonTests/AutomationEventTests.swift`
- [X] T025 [P] [US2] Ajouter les tests CLI pour `roadie config reload --json` dans `Tests/RoadieDaemonTests/ConfigCommandTests.swift`

### Implémentation pour User Story 2

- [X] T026 [US2] Implementer `ConfigReloadService` dans `Sources/RoadieDaemon/ConfigReloadService.swift`
- [X] T027 [US2] Ajouter l'etat de reload config aux snapshots query dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [X] T028 [US2] Raccorder le safe reload dans l'usage config du daemon dans `Sources/RoadieDaemon/DaemonSnapshot.swift` et `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T029 [US2] Ajouter la commande `config reload` dans `Sources/roadie/main.swift`
- [X] T030 [US2] Ajouter le comportement debounce du watcher config si active dans `Sources/RoadieDaemon/ConfigReloadService.swift`
- [X] T031 [US2] Mettre a jour les docs config dans `docs/en/configuration-rules.md` et `docs/fr/configuration-rules.md`
- [X] T032 [US2] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: Une config invalide ne peut pas remplacer la config active.

---

## Phase 5 : User Story 3 - Restaurer les fenetres apres arret ou crash (Priorité : P1)

**Objectif**: Le snapshot de securite et le watcher recuperent les fenetres gerees.

**Test indépendant**: Des fenetres de fixtures sont restaurees sur le chemin arret normal et sur le chemin watcher crash sans dependre des fenetres utilisateur reelles.

### Tests pour User Story 3

- [X] T033 [P] [US3] Ajouter les tests encodage/decodage du snapshot restore dans `Tests/RoadieDaemonTests/RestoreSafetyTests.swift`
- [X] T034 [P] [US3] Ajouter les tests du service restore sur arret normal dans `Tests/RoadieDaemonTests/RestoreSafetyTests.swift`
- [X] T035 [P] [US3] Ajouter les tests de cycle de vie crash watcher avec etat processus simule dans `Tests/RoadieDaemonTests/RestoreWatcherTests.swift`

### Implémentation pour User Story 3

- [X] T036 [US3] Documenter la decision de cycle de vie du crash watcher dans `docs/decisions/002-control-safety-public-api-boundary.md`
- [X] T037 [US3] Implementer `RestoreSafetyService` dans `Sources/RoadieDaemon/RestoreSafetyService.swift`
- [X] T038 [US3] Implementer le chemin commande crash watcher dans `Sources/roadied/main.swift`
- [X] T039 [US3] Ecrire les snapshots restore pendant l'application du layout dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T040 [US3] Appliquer restore-on-exit depuis le chemin shutdown daemon dans `Sources/roadied/main.swift`
- [X] T041 [US3] Ajouter les commandes `roadie restore ...` dans `Sources/roadie/main.swift`
- [X] T042 [US3] Ajouter les evenements restore et l'etat query dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [X] T043 [US3] Documenter restore safety dans `docs/en/features.md` et `docs/fr/features.md`
- [X] T044 [US3] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: Roadie peut echouer sans pieger les fenetres gerees.

---

## Phase 6 : User Story 4 - Respecter les fenetres systeme transitoires (Priorité : P2)

**Objectif**: Suspendre et recuperer autour des sheets/dialogues/popovers/menus/panneaux open-save.

**Test indépendant**: Des roles/subroles AX simules marquent Roadie en pause et empechent les mutations de layout.

### Tests pour User Story 4

- [X] T045 [P] [US4] Ajouter les tests du detecteur transitoire dans `Tests/RoadieDaemonTests/TransientWindowDetectorTests.swift`
- [X] T046 [P] [US4] Ajouter les tests d'integration pause layout dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`
- [X] T047 [P] [US4] Ajouter les tests query/evenement pour le statut transitoire dans `Tests/RoadieDaemonTests/QueryCommandTests.swift`

### Implémentation pour User Story 4

- [X] T048 [US4] Implementer `TransientWindowDetector` dans `Sources/RoadieDaemon/TransientWindowDetector.swift`
- [X] T049 [US4] Etendre les abstractions AX provider pour roles/subroles et element UI focus dans `Sources/RoadieAX/SystemSnapshotProvider.swift`
- [X] T050 [US4] Garder les actions layout/focus non essentielles dans `Sources/RoadieDaemon/LayoutMaintainer.swift` et `Sources/RoadieDaemon/FocusFollowsMouseController.swift`
- [X] T051 [US4] Ajouter la recuperation sure hors ecran pour fenetres transitoires dans `Sources/RoadieDaemon/TransientWindowDetector.swift`
- [X] T052 [US4] Ajouter `roadie transient status --json` dans `Sources/roadie/main.swift`
- [X] T053 [US4] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: Roadie reste en retrait pendant les dialogues systeme.

---

## Phase 7 : User Story 5 - Restaurer un layout via identite stable (Priorité : P2)

**Objectif**: Persister et restaurer les associations de layout malgre les IDs de fenetres volatils.

**Test indépendant**: Des fixtures avec IDs modifies restaurent les appartenances stage/desktop/group non ambiguës et rejettent les correspondances ambiguës.

### Tests pour User Story 5

- [X] T054 [P] [US5] Ajouter les tests de scoring `WindowIdentityV2` dans `Tests/RoadieDaemonTests/WindowIdentityTests.swift`
- [X] T055 [P] [US5] Ajouter les tests de fixtures restore persistence v2 dans `Tests/RoadieDaemonTests/LayoutPersistenceV2Tests.swift`
- [X] T056 [P] [US5] Ajouter les tests CLI dry-run pour `state restore-v2` dans `Tests/RoadieDaemonTests/StateRestoreCommandTests.swift`

### Implémentation pour User Story 5

- [X] T057 [US5] Implementer `WindowIdentityService` dans `Sources/RoadieDaemon/WindowIdentityService.swift`
- [X] T058 [US5] Etendre la persistance d'etat stage avec identity v2 dans `Sources/RoadieStages/RoadieState.swift`
- [X] T059 [US5] Etendre les migrations/healing `StageStore` pour identity v2 dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T060 [US5] Ajouter le service dry-run/apply restore aware identity dans `Sources/RoadieDaemon/LayoutPersistenceV2Service.swift`
- [X] T061 [US5] Ajouter les commandes `roadie state identity inspect` et `roadie state restore-v2` dans `Sources/roadie/main.swift`
- [X] T062 [US5] Exposer les resumes restore identity dans `Sources/RoadieDaemon/AutomationQueryService.swift`
- [X] T063 [US5] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: La recuperation apres redemarrage ne depend plus seulement des IDs de fenetres volatils.

---

## Phase 8 : User Story 6 - Ajuster les largeurs par presets/nudge (Priorité : P3)

**Objectif**: Commandes width preset/nudge pour les layouts compatibles.

**Test indépendant**: Les commandes appliquent des ratios valides aux layouts compatibles BSP/master et renvoient un rejet structure pour les modes incompatibles.

### Tests pour User Story 6

- [X] T064 [P] [US6] Ajouter les tests de decodage config width dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [X] T065 [P] [US6] Ajouter les tests du service width adjustment dans `Tests/RoadieDaemonTests/WidthAdjustmentTests.swift`
- [X] T066 [P] [US6] Ajouter les tests de commandes CLI dans `Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift`

### Implémentation pour User Story 6

- [X] T067 [US6] Implementer `WidthAdjustmentService` dans `Sources/RoadieDaemon/WidthAdjustmentService.swift`
- [X] T068 [US6] Persister les intentions width adjustment dans `Sources/RoadieDaemon/LayoutIntentStore.swift`
- [X] T069 [US6] Ajouter les commandes width au routage de commandes layout dans `Sources/RoadieDaemon/LayoutCommandService.swift` et `Sources/roadie/main.swift`
- [X] T070 [US6] Exposer les evenements width adjustment dans `Sources/RoadieDaemon/EventLog.swift`
- [X] T071 [US6] Documenter width presets/nudge dans `docs/en/cli.md` et `docs/fr/cli.md`
- [X] T072 [US6] Executer `make build` et `make test`, puis mettre a jour `specs/003-roadie-control-safety/implementation.md`

**Checkpoint**: Les commandes width fonctionnent ou rejettent surement.

---

## Phase 9 : Finition & Sujets Transverses

**Objectif**: Validation finale, documentation et preparation release.

- [X] T073 [P] Mettre a jour `README.md` et `README.fr.md` avec les workflows Control Center, safe reload et restore safety
- [X] T074 [P] Mettre a jour `docs/en/use-cases.md` et `docs/fr/use-cases.md` avec des exemples securite et recuperation
- [X] T075 Mettre a jour `docs/en/events-query.md` et `docs/fr/events-query.md` avec les nouvelles surfaces event/query
- [X] T076 Ajouter une garde de validation sans animations et sans imports SkyLight/MultitouchSupport, puis consigner le scan dans `specs/003-roadie-control-safety/implementation.md`
- [X] T077 Executer la validation quickstart depuis `specs/003-roadie-control-safety/quickstart.md`
- [X] T078 Executer le `make build` et `make test` final
- [X] T079 Mettre a jour `.specify/memory/sessions/index.md` pour le statut session 003
- [X] T080 Relire finallement `specs/003-roadie-control-safety/implementation.md`

---

## Dépendances & Ordre d'Exécution

### Dépendances de Phase

- **Phase 1 Setup**: Aucune dependance.
- **Phase 2 Fondations**: Depend de la Phase 1 et bloque toutes les stories.
- **US1, US2, US3**: Peuvent demarrer apres la Phase 2 ; ordre recommande US1 -> US2 -> US3 car le Control Center affiche les statuts reload/restore.
- **US4, US5**: Peuvent demarrer apres la Phase 2 mais s'integrent mieux apres US2/US3.
- **US6**: Derniere par decision explicite de perimetre.
- **Finition**: Apres completion des user stories retenues.

### Dépendances de User Story

- **US1**: Requiert les modeles/evenements fondamentaux.
- **US2**: Requiert les extensions du modele config.
- **US3**: Requiert la baseline identity et le modele restore snapshot.
- **US4**: Requiert l'extension d'abstraction AX.
- **US5**: Requiert les fondations restore et persistance d'etat.
- **US6**: Requiert le service de commandes layout et l'extension config.

### Opportunités de Parallélisation

- Les fixtures setup et le journal d'implementation peuvent avancer en parallele.
- Les fichiers de tests d'une story peuvent etre ecrits avant l'implementation et en parallele.
- Le detecteur US4 et le scoring identity US5 peuvent etre developpes en parallele apres les fondations.
- Les taches documentaires de Phase 9 peuvent avancer en parallele apres stabilisation des APIs.

## Exemple Parallèle : US4

```text
Tache : "Ajouter les tests du detecteur transitoire dans Tests/RoadieDaemonTests/TransientWindowDetectorTests.swift"
Tache : "Ajouter les tests query/evenement pour le statut transitoire dans Tests/RoadieDaemonTests/QueryCommandTests.swift"
Tache : "Implementer TransientWindowDetector dans Sources/RoadieDaemon/TransientWindowDetector.swift"
```

## Stratégie d'Implémentation

### MVP d'Abord

1. Completer la Phase 1 et la Phase 2.
2. Completer US1 Control Center state/menu shell.
3. Completer US2 reload de configuration securise.
4. Completer US3 restauration de securite.
5. Valider avec `make build`, `make test` et les scenarios quickstart 1-3.

### Livraison Incrémentale

1. Livrer status/actions Control Center.
2. Ajouter safe reload avec rollback.
3. Ajouter restauration a l'arret et watcher de crash.
4. Ajouter fenetres systeme transitoires.
5. Ajouter identity persistence v2.
6. Ajouter width presets/nudge en dernier.

### Notes

- Chaque tache complete doit mettre a jour `implementation.md`.
- Chaque commit doit passer `make build` et `make test`.
- Aucun usage d'animations ou APIs privees dans cette session.
