# Tasks: Stage Display Move

**Input**: Design documents from `/specs/003-stage-display-move/`  
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: inclus, car la specification demande des tests independants par user story et la fonctionnalite touche au focus, aux stages et au multi-ecran.

**Organization**: les taches sont groupees par user story pour permettre une implementation et une validation incrementales.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Preparer les tests et les points d'entree communs sans changer encore le comportement utilisateur.

- [x] T001 Creer le fichier de tests multi-ecran `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift` avec des fixtures stage/display reutilisables
- [x] T002 [P] Ajouter les tests de decode/default de `focus.stage_move_follows_focus` dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T003 [P] Documenter les contrats de sortie attendus pour les cas moved/noop/invalid/partial dans `specs/003-stage-display-move/contracts/cli-stage-display-move.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Mettre en place la configuration et la primitive unique de deplacement qui bloquent toutes les user stories.

**CRITICAL**: aucune user story ne doit dupliquer la logique de deplacement en dehors de cette primitive.

- [x] T004 Ajouter `stageMoveFollowsFocus` avec cle TOML `stage_move_follows_focus` dans `Sources/RoadieCore/Config.swift`
- [x] T005 Introduire les types internes de cible/resultat de deplacement de stage dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T006 Refactorer `moveActiveStageToDisplay(index:)` vers une primitive partagee `moveStageToDisplay(...)` dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T007 Garantir que la primitive partagee invalide les layout intents source/cible sans supprimer de state non concerne dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T008 Exposer une methode daemon capable de deplacer une stage explicite par `stageID` et `sourceDisplayID` dans `Sources/RoadieDaemon/StageCommands.swift`

**Checkpoint**: configuration decodee, primitive centrale disponible, ancienne commande par index toujours routable.

---

## Phase 3: User Story 1 - Envoyer la stage active vers un autre ecran (Priority: P1) MVP

**Goal**: Deplacer la stage active vers un autre ecran par index ou direction, sans perte de fenetres et sans etat source incoherent.

**Independent Test**: Creer une stage active contenant plusieurs fenetres sur l'ecran A, l'envoyer vers l'ecran B, puis verifier que les fenetres suivent la stage, que l'ecran source reste utilisable et que les stages cible existantes ne sont pas fusionnees.

### Tests for User Story 1

- [x] T009 [P] [US1] Ajouter un test de deplacement par index visible preservant membres et stage source active dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T010 [P] [US1] Ajouter un test de deplacement par direction `left/right/up/down` via `DisplayTopology` dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T011 [P] [US1] Ajouter un test de collision d'identifiant qui conserve la stage cible non vide dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T012 [P] [US1] Ajouter un test cible invalide/cible courante sans mutation dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`

### Implementation for User Story 1

- [x] T013 [US1] Implementer la resolution de cible par index visible et le no-op ecran courant dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T014 [US1] Implementer la resolution de cible par direction avec `DisplayTopology.neighbor` dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T015 [US1] Implementer le transfert de stage source vers cible avec fallback de stage active sur l'ecran source dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T016 [US1] Implementer la protection collision d'ID sans fusion ni suppression de stage cible non vide dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T017 [US1] Mettre a jour le parsing CLI `roadie stage move-to-display TARGET` pour accepter index et directions dans `Sources/roadie/main.swift`
- [x] T018 [US1] Standardiser les messages CLI moved/noop/invalid/partial pour `stage move-to-display` dans `Sources/roadie/main.swift`
- [x] T019 [US1] Publier un evenement `stage_move_display` avec status et compteurs de fenetres dans `Sources/RoadieDaemon/StageCommands.swift`

**Checkpoint**: US1 fonctionnelle en CLI par index et direction, testable sans menu rail ni preference no-follow.

---

## Phase 4: User Story 2 - Choisir si le focus suit la stage deplacee (Priority: P2)

**Goal**: Permettre le choix global et ponctuel du follow focus lors d'un deplacement de stage.

**Independent Test**: Configurer `stage_move_follows_focus = false`, envoyer une stage vers un autre ecran, puis verifier que la stage est deplacee mais que le contexte actif reste sur l'ecran source.

### Tests for User Story 2

- [x] T020 [P] [US2] Ajouter un test no-follow qui conserve le focus display source dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T021 [P] [US2] Ajouter un test follow explicite qui active le display cible dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T022 [P] [US2] Ajouter un test de precedence `--follow/--no-follow` sur la config dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`

### Implementation for User Story 2

- [x] T023 [US2] Brancher la valeur effective `stageMoveFollowsFocus` dans `StageCommandService` depuis `Sources/RoadieDaemon/StageCommands.swift`
- [x] T024 [US2] Implementer les flags CLI `--follow` et `--no-follow` pour `stage move-to-display` dans `Sources/roadie/main.swift`
- [x] T025 [US2] Garantir que le mode no-follow ne declenche pas de `state.focusDisplay(targetDisplay.id)` dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T026 [US2] Ajouter l'exemple TOML no-follow dans `docs/fr/cli.md`

**Checkpoint**: US1 et US2 fonctionnent ensemble, avec comportement par defaut follow et configuration utilisateur no-follow.

---

## Phase 5: User Story 3 - Envoyer une stage depuis le menu contextuel du rail (Priority: P3)

**Goal**: Ajouter un menu clic droit sur une stage du navrail pour l'envoyer vers un autre ecran, y compris si elle est inactive.

**Independent Test**: Ouvrir le menu contextuel d'une carte de stage, choisir un ecran cible valide, puis verifier que cette stage precise est deplacee sans activer une autre stage par accident.

### Tests for User Story 3

- [x] T027 [P] [US3] Ajouter un test action rail deplace une stage inactive par `stageID` et `sourceDisplayID` dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [x] T028 [P] [US3] Ajouter un test menu rail exclut l'ecran courant et gere le cas mono-ecran dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`

### Implementation for User Story 3

- [x] T029 [US3] Etendre `RailAction` avec une action de deplacement de stage vers display dans `Sources/RoadieDaemon/RailController.swift`
- [x] T030 [US3] Ajouter le menu contextuel `Envoyer vers` sur les cartes `StageCardView` dans `Sources/RoadieDaemon/RailController.swift`
- [x] T031 [US3] Construire la liste des displays cibles valides en excluant l'ecran courant dans `Sources/RoadieDaemon/RailController.swift`
- [x] T032 [US3] Router la selection du menu vers `StageCommandService.moveStageToDisplay(...)` sans activer la stage avant l'action dans `Sources/RoadieDaemon/RailController.swift`
- [x] T033 [US3] Gerer les retours succes/echec/noop du menu rail sans faire disparaitre la carte source en cas d'echec dans `Sources/RoadieDaemon/RailController.swift`

**Checkpoint**: toutes les user stories sont fonctionnelles et independamment testables.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation complete et non-regression avant merge.

- [x] T034 [P] Mettre a jour la documentation CLI anglaise pour `stage move-to-display` dans `docs/en/cli.md`
- [x] T035 [P] Mettre a jour la documentation CLI francaise pour `stage move-to-display` dans `docs/fr/cli.md`
- [x] T036 [P] Mettre a jour la documentation fonctionnelle anglaise multi-display/stages dans `docs/en/features.md`
- [x] T037 [P] Mettre a jour la documentation fonctionnelle francaise multi-display/stages dans `docs/fr/features.md`
- [x] T038 [P] Mettre a jour le README avec les commandes stage display move dans `README.md`
- [x] T039 Executer `swift test` et noter le resultat de validation dans `specs/003-stage-display-move/quickstart.md`
- [ ] T040 Executer les scenarios manuels multi-ecran du quickstart et consigner les ecarts dans `specs/003-stage-display-move/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: peut commencer immediatement.
- **Foundational (Phase 2)**: depend de Phase 1 et bloque toutes les user stories.
- **US1 (Phase 3)**: depend de Phase 2 ; MVP livrable seul.
- **US2 (Phase 4)**: depend de Phase 2 et s'integre naturellement apres US1 pour valider le no-follow.
- **US3 (Phase 5)**: depend de Phase 2 ; peut etre developpee apres US1 ou en parallele si la primitive daemon est stable.
- **Polish (Phase 6)**: depend des user stories retenues pour la livraison.

### User Story Dependencies

- **US1**: aucune dependance fonctionnelle sur US2/US3.
- **US2**: depend de la primitive US1 pour exercer follow/no-follow sur un vrai deplacement.
- **US3**: depend de la primitive commune, mais ne doit pas dependre du parsing CLI.

### Parallel Opportunities

- T002 et T003 peuvent etre faits en parallele.
- T009 a T012 sont des tests differents et peuvent etre ecrits en parallele.
- T020 a T022 peuvent etre ecrits en parallele apres US1.
- T027 et T028 peuvent etre ecrits en parallele avec l'implementation CLI, car ils visent le rail.
- T034 a T038 peuvent etre faits en parallele une fois les contrats definitifs.

---

## Parallel Example: User Story 1

```text
Task: "T009 Ajouter un test de deplacement par index visible preservant membres et stage source active dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T010 Ajouter un test de deplacement par direction left/right/up/down via DisplayTopology dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T011 Ajouter un test de collision d'identifiant qui conserve la stage cible non vide dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T012 Ajouter un test cible invalide/cible courante sans mutation dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
```

## Parallel Example: User Story 2

```text
Task: "T020 Ajouter un test no-follow qui conserve le focus display source dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T021 Ajouter un test follow explicite qui active le display cible dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T022 Ajouter un test de precedence --follow/--no-follow sur la config dans Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift"
```

## Parallel Example: User Story 3

```text
Task: "T027 Ajouter un test action rail deplace une stage inactive par stageID et sourceDisplayID dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
Task: "T028 Ajouter un test menu rail exclut l'ecran courant et gere le cas mono-ecran dans Tests/RoadieDaemonTests/StageDisplayMoveTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completer Phase 1 et Phase 2.
2. Implementer US1 jusqu'a `roadie stage move-to-display 2|right`.
3. Valider les tests de `StageDisplayMoveTests.swift`.
4. Tester manuellement le deplacement d'une stage active avec au moins trois fenetres.

### Incremental Delivery

1. US1 : deplacement fiable par CLI.
2. US2 : preference follow/no-follow et flags CLI.
3. US3 : menu contextuel rail pour usage decouvrable.
4. Polish : docs, README, validation complete.

### Guardrails

- Ne jamais supprimer une stage cible non vide pour resoudre une collision d'ID.
- Ne jamais activer une stage inactive uniquement pour pouvoir la deplacer depuis le rail.
- Ne jamais forcer `focusDisplay(target)` quand la politique effective est no-follow.
- Toute cible invalide doit retourner un resultat clair sans mutation.
