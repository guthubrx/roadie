# Tâches : Menu Contextuel de Barre de Titre

**Entrée** : documents de conception depuis `/specs/004-titlebar-context-menu/`  
**Prérequis** : [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests** : inclus, car la specification demande des tests independants par recit utilisateur et la fonctionnalite intercepte des clics droits globaux.

**Organisation** : les taches sont groupees par recit utilisateur pour permettre une implementation incrementale, avec US1 comme MVP.

## Phase 1 : Préparation (Infrastructure Partagée)

**Objectif** : Preparer les tests, fixtures et points d'observation sans modifier encore le comportement utilisateur.

- [x] T001 Creer le fichier de tests `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift` avec fixtures de fenetres, stages, desktops et displays reutilisables
- [x] T002 [P] Ajouter les tests de valeurs par defaut et de decodage de `[experimental.titlebar_context_menu]` dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T003 [P] Creer un journal d'implementation pour les validations manuelles dans `specs/004-titlebar-context-menu/implementation.md`

---

## Phase 2 : Socle Commun (Prérequis Bloquants)

**Objectif** : Mettre en place la configuration, les modeles purs et les primitives communes necessaires a tous les recits utilisateur.

**Critique** : aucun recit utilisateur ne doit intercepter un clic droit ou deplacer une fenetre avant que ces primitives fail-open soient en place.

- [x] T004 Ajouter la configuration `experimental.titlebar_context_menu` et ses valeurs par defaut dans `Sources/RoadieCore/Config.swift`
- [x] T005 Ajouter la validation de `height`, `leading_exclusion`, `trailing_exclusion` et familles de destinations dans `Sources/RoadieCore/Config.swift`
- [x] T006 Definir les types `TitlebarContextMenuSettings`, `TitlebarHitTest`, `WindowDestination` et `WindowContextAction` dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T007 Implementer la fonction pure de hit-test titlebar sans capture d'evenement dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T008 Implementer le service de destinations/actions explicites de fenetre dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [x] T009 Brancher le demarrage conditionnel du controleur depuis la configuration dans `Sources/roadied/main.swift`
- [x] T010 Ajouter les noms d'evenements `titlebar_context_menu.*` et leur formatage diagnostic dans `Sources/RoadieDaemon/WindowContextActions.swift`

**Point de contrôle** : la config est chargee, les tests purs peuvent cibler la detection, et aucun clic droit n'est capture si la fonctionnalite est desactivee.

---

## Phase 3 : Récit Utilisateur 1 - Ouvrir un menu Roadie depuis la barre de titre (Priorité : P1) MVP

**But** : Afficher le menu Roadie uniquement pour un clic droit dans la zone haute eligible d'une fenetre geree, sans intercepter le contenu applicatif.

**Test indépendant** : Activer la fonctionnalite, clic droit dans la zone haute d'une fenetre geree, verifier le menu ; clic droit dans le contenu de la meme fenetre, verifier que Roadie ne montre rien.

### Tests pour le Récit Utilisateur 1

- [x] T011 [P] [US1] Ajouter un test fonctionnalite desactivee ne consomme jamais le clic dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T012 [P] [US1] Ajouter un test clic contenu retourne `not_titlebar` sans menu dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T013 [P] [US1] Ajouter un test clic titlebar eligible retourne `eligible` avec fenetre cible dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T014 [P] [US1] Ajouter un test fenetre non geree, popup ou transient retourne une raison ignoree dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour le Récit Utilisateur 1

- [x] T015 [US1] Implementer le moniteur AppKit de clic droit global fail-open dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T016 [US1] Resoudre la fenetre sous le curseur depuis le snapshot Roadie sans changer le focus dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T017 [US1] Construire le menu Roadie minimal seulement apres hit-test eligible dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T018 [US1] Garantir que les clics ignores ne sont pas consommes et restent disponibles pour l'application dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T019 [US1] Journaliser `titlebar_context_menu.shown` et les `ignored` peu bruyants dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`

**Point de contrôle** : US1 fonctionne seule ; le menu existe mais peut encore contenir des destinations limitees ou inactives.

---

## Phase 4 : Récit Utilisateur 2 - Configurer la zone experimentale de detection (Priorité : P2)

**But** : Permettre d'activer/desactiver et d'ajuster la zone de detection par TOML, avec reload de configuration sans redemarrage de session.

**Test indépendant** : Modifier la hauteur ou les marges dans le TOML, recharger la configuration, puis verifier que les points eligibles changent ou que la fonctionnalite se coupe totalement.

### Tests pour le Récit Utilisateur 2

- [x] T020 [P] [US2] Ajouter un test TOML complet active la configuration experimentale dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T021 [P] [US2] Ajouter un test valeurs invalides refusees ou ramenees a une valeur sure dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T022 [P] [US2] Ajouter un test `height` modifie la bande eligible dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T023 [P] [US2] Ajouter un test `leading_exclusion` et `trailing_exclusion` excluent les zones de controle dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour le Récit Utilisateur 2

- [x] T024 [US2] Appliquer `enabled`, `height`, `leading_exclusion` et `trailing_exclusion` dans le hit-test de `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T025 [US2] Appliquer `managed_windows_only` et `tile_candidates_only` aux fenetres candidates dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T026 [US2] Recharger les reglages du controleur lors de `roadie config reload` sans redemarrer `roadied` dans `Sources/roadied/main.swift`
- [x] T027 [US2] Garantir que toutes les familles de destinations desactivees empechent l'affichage du menu dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`

**Point de contrôle** : US1 et US2 fonctionnent ensemble, et la fonctionnalite reste reversible par TOML.

---

## Phase 5 : Récit Utilisateur 3 - Envoyer la fenetre vers un autre contexte Roadie (Priorité : P3)

**But** : Proposer les destinations utiles dans le menu et envoyer la fenetre cible vers une autre stage, un autre desktop ou un autre display.

**Test indépendant** : Depuis le menu Roadie d'une fenetre cible, choisir une destination stage, desktop ou display, puis verifier que seule cette fenetre bouge et que les destinations courantes ne sont pas executables.

### Tests pour le Récit Utilisateur 3

- [x] T028 [P] [US3] Ajouter un test de construction des destinations stage excluant la stage courante dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T029 [P] [US3] Ajouter un test de construction des destinations desktop excluant le desktop courant dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T030 [P] [US3] Ajouter un test de construction des destinations display excluant le display courant dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T031 [P] [US3] Ajouter un test action avec fenetre ou destination disparue retourne un echec sans mutation dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour le Récit Utilisateur 3

- [x] T032 [US3] Construire les destinations stage, desktop et display depuis l'etat courant dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [x] T033 [US3] Ajouter une action explicite de fenetre vers stage en reutilisant `StageCommandService` dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T034 [US3] Ajouter une action explicite de fenetre vers desktop sans passer par la fenetre active dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [x] T035 [US3] Ajouter une action explicite de fenetre vers display sans passer par la fenetre active dans `Sources/RoadieDaemon/WindowCommands.swift`
- [x] T036 [US3] Construire les sous-menus `Envoyer vers stage`, `Envoyer vers desktop` et `Envoyer vers ecran` dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T037 [US3] Router chaque selection de menu vers `WindowContextActions` en validant a nouveau fenetre et destination dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T038 [US3] Journaliser `titlebar_context_menu.action` et `titlebar_context_menu.failed` avec cause claire dans `Sources/RoadieDaemon/WindowContextActions.swift`

**Point de contrôle** : tous les recits utilisateur sont fonctionnels et testables independamment.

---

## Phase 6 : Finition et Sujets Transverses

**Objectif** : Documentation, validation complete et non-regression avant merge.

- [x] T039 [P] Documenter la section TOML experimentale en francais dans `docs/fr/features.md`
- [x] T040 [P] Documenter la section TOML experimentale en anglais dans `docs/en/features.md`
- [x] T041 [P] Mettre a jour le README avec l'existence experimentale du menu de barre de titre dans `README.md`
- [x] T042 Mettre a jour `specs/004-titlebar-context-menu/quickstart.md` avec les resultats de `TitlebarContextMenuTests` et `ConfigTests`
- [x] T043 Executer `./scripts/with-xcode swift test --filter TitlebarContextMenuTests` et consigner le resultat dans `specs/004-titlebar-context-menu/implementation.md`
- [x] T044 Executer `./scripts/with-xcode swift test --filter ConfigTests` et consigner le resultat dans `specs/004-titlebar-context-menu/implementation.md`
- [x] T045 Executer `make build` et consigner le resultat dans `specs/004-titlebar-context-menu/implementation.md`
- [ ] T046 Valider manuellement iTerm2, Finder, Firefox/Electron et popup/dialogue systeme selon `specs/004-titlebar-context-menu/quickstart.md`
- [x] T047 Ajouter les evenements `titlebar_context_menu.*` au catalogue public dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [x] T048 [P] Ajouter une validation de non-regression navrail drag-and-drop dans `specs/004-titlebar-context-menu/implementation.md`
- [x] T049 [P] Ajouter une validation de non-regression raccourcis Roadie/BTT dans `specs/004-titlebar-context-menu/implementation.md`
- [x] T050 Appliquer la politique de limitation des evenements `ignored` dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T051 Creer une decision courte pour le controleur global AppKit dans `docs/decisions/004-titlebar-context-menu-controller.md`

---

## Dépendances et Ordre d'Exécution

### Dépendances de Phase

- **Préparation (Phase 1)** : peut commencer immediatement.
- **Socle commun (Phase 2)** : depend de Phase 1 et bloque tous les recits utilisateur.
- **US1 (Phase 3)**: depend de Phase 2 ; MVP livrable seul.
- **US2 (Phase 4)**: depend de Phase 2 et peut etre developpee apres ou en parallele d'US1 si le hit-test pur est stable.
- **US3 (Phase 5)**: depend de Phase 2 ; l'integration menu complete est plus sure apres US1.
- **Finition (Phase 6)** : depend des recits utilisateur retenus pour la livraison.

### Dépendances des Récits Utilisateur

- **US1**: aucune dependance fonctionnelle sur US2/US3.
- **US2**: depend des primitives de configuration et de hit-test, mais reste independante des actions de deplacement.
- **US3**: depend du controleur US1 pour exposer le menu, mais ses destinations/actions peuvent etre testees sans UI.

### Opportunités de Parallélisation

- T002 et T003 peuvent etre faits en parallele.
- T011 a T014 peuvent etre ecrits en parallele dans la phase US1.
- T020 a T023 peuvent etre ecrits en parallele dans la phase US2.
- T028 a T031 peuvent etre ecrits en parallele dans la phase US3.
- T039 a T041 peuvent etre faits en parallele une fois les noms de config stabilises.

---

## Exemple de Parallélisation : Récit Utilisateur 1

```text
Tache: "T011 Ajouter un test fonctionnalite desactivee ne consomme jamais le clic dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T012 Ajouter un test clic contenu retourne not_titlebar sans menu dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T013 Ajouter un test clic titlebar eligible retourne eligible avec fenetre cible dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T014 Ajouter un test fenetre non geree, popup ou transient retourne une raison ignoree dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
```

## Exemple de Parallélisation : Récit Utilisateur 2

```text
Tache: "T020 Ajouter un test TOML complet active la configuration experimentale dans Tests/RoadieDaemonTests/ConfigTests.swift"
Tache: "T021 Ajouter un test valeurs invalides refusees ou ramenees a une valeur sure dans Tests/RoadieDaemonTests/ConfigTests.swift"
Tache: "T022 Ajouter un test height modifie la bande eligible dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T023 Ajouter un test leading_exclusion et trailing_exclusion excluent les zones de controle dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
```

## Exemple de Parallélisation : Récit Utilisateur 3

```text
Tache: "T028 Ajouter un test de construction des destinations stage excluant la stage courante dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T029 Ajouter un test de construction des destinations desktop excluant le desktop courant dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T030 Ajouter un test de construction des destinations display excluant le display courant dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
Tache: "T031 Ajouter un test action avec fenetre ou destination disparue retourne un echec sans mutation dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
```

---

## Stratégie d'Implémentation

### MVP d'Abord (Récit Utilisateur 1 Uniquement)

1. Completer Phase 1 et Phase 2.
2. Implementer US1 avec la fonctionnalite activee seulement par TOML.
3. Valider que les clics contenus applicatifs ne sont jamais consommes.
4. Stopper et tester manuellement iTerm2/Finder avant d'ajouter les actions.

### Livraison Incrémentale

1. US1 : menu experimental non intrusif.
2. US2 : configuration fine et reload.
3. US3 : destinations stage/desktop/display.
4. Finition : docs, build, validation manuelle multi-applications.

### Garde-fous

- Ne jamais capturer un clic si `enabled = false`.
- Ne jamais capturer un clic hors zone eligible.
- Ne jamais afficher le menu pour popup, dialogue, transient ou fenetre non geree.
- Ne jamais changer le focus avant selection d'une action.
- Ne jamais deplacer une fenetre si la cible ou destination a disparu.
- Ne pas ajouter de polling ou de latence dans le chemin focus/bordure.
