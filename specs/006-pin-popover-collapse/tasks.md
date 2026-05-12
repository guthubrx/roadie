# Tâches : Menu Pin et Repliage

**Entrée** : documents de conception dans `/specs/006-pin-popover-collapse/`  
**Prérequis** : [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests** : inclus car la spécification demande des validations répétées de placement, repliage/restauration et non-régression focus/layout.

**Organisation** : les tâches sont groupées par récit utilisateur pour permettre une implémentation et une validation indépendantes.

## Format : `[ID] [P?] [Récit] Description`

- **[P]** : tâche parallélisable si elle touche des fichiers distincts et ne dépend pas d'une tâche incomplète.
- **[Récit]** : récit utilisateur concerné (`US1`, `US2`, `US3`, `US4`).
- Chaque tâche indique un chemin de fichier précis.

## Phase 1 : Préparation

**Objectif** : aligner le contexte projet et préparer les points d'extension sans comportement runtime visible.

- [x] T001 Vérifier que `AGENTS.md` pointe vers `specs/006-pin-popover-collapse/plan.md`
- [x] T002 [P] Ajouter un journal d'implémentation initial dans `specs/006-pin-popover-collapse/implementation.md`
- [x] T003 [P] Identifier les surfaces de tests config dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T004 [P] Identifier les surfaces de tests menu existantes dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T005 [P] Créer le fichier de tests dédié `Tests/RoadieDaemonTests/PinPopoverTests.swift`

---

## Phase 2 : Fondations

**Objectif** : ajouter configuration, modèle de présentation et primitives pures avant tout affichage.

**Critique** : aucun récit utilisateur ne doit commencer avant cette phase.

- [x] T006 Ajouter `PinPopoverConfig` dans `Sources/RoadieCore/Config.swift`
- [x] T007 Ajouter `pinPopover` à `ExperimentalConfig` dans `Sources/RoadieCore/Config.swift`
- [x] T008 Ajouter la validation TOML de `[experimental.pin_popover]` dans `Sources/RoadieCore/Config.swift`
- [x] T009 [P] Ajouter les tests de décodage et défauts `PinPopoverConfig` dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T010 [P] Ajouter les tests de validation des bornes de config dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T011 Ajouter `PinPresentationMode` et `PinPresentationState` dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T012 Ajouter le stockage persistant des états de présentation de pin dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T013 Ajouter les helpers `presentation(for:)`, `setPresentation`, `removePresentation`, `prunePinPresentations` dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T014 [P] Ajouter les tests de persistance et rétrocompatibilité de présentation dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [x] T015 [P] Ajouter les tests de nettoyage des présentations orphelines dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [x] T016 Ajouter les événements `pin_popover.shown`, `pin_popover.ignored`, `pin_popover.action`, `window.pin_collapsed`, `window.pin_restored` dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [x] T017 [P] Ajouter les tests catalogue des événements pin popover dans `Tests/RoadieDaemonTests/AutomationEventTests.swift`

**Point de contrôle** : modèle, config et événements sont testables sans afficher d'UI.

---

## Phase 3 : Récit Utilisateur 1 - Bouton visible sur fenêtre pinée (Priorité : P1)

**Objectif** : afficher un bouton circulaire bleu sûr sur les fenêtres pinées.

**Test indépendant** : pinner une fenêtre, activer `experimental.pin_popover.enabled`, vérifier qu'un bouton apparaît sur une fenêtre éligible et qu'il est omis si le placement est risqué.

### Tests pour Récit Utilisateur 1

- [x] T018 [P] [US1] Ajouter un test de placement sûr du bouton dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T019 [P] [US1] Ajouter un test d'affichage paramétrable pour fenêtre non pinée dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T020 [P] [US1] Ajouter un test d'omission pour fenêtre trop petite ou plein écran dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T021 [P] [US1] Ajouter un test d'omission quand la fonctionnalité est désactivée dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`

### Implémentation pour Récit Utilisateur 1

- [x] T022 [US1] Créer `PinPopoverController` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T023 [US1] Ajouter les types purs `PinPopoverSettings` et `PinPopoverPlacement` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T024 [US1] Implémenter le calcul pur de placement sûr du bouton dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T025 [US1] Implémenter le rendu du bouton circulaire bleu Roadie dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T026 [US1] Démarrer conditionnellement `PinPopoverController` dans `Sources/roadied/main.swift`
- [x] T027 [US1] Journaliser `pin_popover.ignored` quand le bouton est omis pour sûreté dans `Sources/RoadieDaemon/PinPopoverController.swift`

**Point de contrôle** : le bouton existe pour une fenêtre gérée éligible sans modifier l'état des fenêtres non pinées.

---

## Phase 4 : Récit Utilisateur 2 - Menu cohérent avec le clic droit (Priorité : P1)

**Objectif** : ouvrir depuis le bouton un menu compact qui reprend les actions du clic droit de barre de titre.

**Test indépendant** : ouvrir le menu du bouton sur une fenêtre pinée et vérifier que les destinations et actions de pin correspondent aux actions disponibles dans le menu de barre de titre.

### Tests pour Récit Utilisateur 2

- [x] T028 [P] [US2] Ajouter un test de construction de menu avec section Pin dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T029 [P] [US2] Ajouter un test de cohérence des destinations avec `WindowContextActions.destinations` dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T030 [P] [US2] Ajouter un test d'état actif `desktop` et `all_desktops` dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T031 [P] [US2] Ajouter un test d'exécution d'action qui réutilise `WindowContextActions` dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`

### Implémentation pour Récit Utilisateur 2

- [x] T032 [US2] Extraire ou partager les helpers de destinations du menu de barre de titre dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [x] T033 [US2] Ajouter un modèle de menu compact `PinPopoverMenuModel` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T034 [US2] Implémenter les sections `Pin`, `Fenêtre`, `Déplacer` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T035 [US2] Router les actions stage/desktop/display vers `WindowContextActions` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T036 [US2] Router les actions de scope pin et unpin vers `WindowContextActions` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T037 [US2] Journaliser `pin_popover.shown` et `pin_popover.action` dans `Sources/RoadieDaemon/PinPopoverController.swift`

**Point de contrôle** : le menu bouton peut remplacer le clic droit pour les actions existantes sans logique métier dupliquée.

---

## Phase 5 : Récit Utilisateur 3 - Repliage en proxy Roadie (Priorité : P2)

**Objectif** : permettre de replier une fenêtre pinée pour voir et utiliser ce qui se trouve dessous, puis restaurer la fenêtre.

**Test indépendant** : replier une fenêtre pinée qui recouvre une autre fenêtre, vérifier que le proxy apparaît, que la vraie fenêtre ne masque plus le dessous, puis restaurer au frame précédent.

### Tests pour Récit Utilisateur 3

- [x] T038 [P] [US3] Ajouter un test `collapse` qui mémorise le frame de restauration dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T039 [P] [US3] Ajouter un test `restore` qui repasse le pin en présentation visible dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T040 [P] [US3] Ajouter un test de proxy exclu du layout dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`
- [x] T041 [P] [US3] Ajouter un test de nettoyage d'un proxy quand la fenêtre live disparaît dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [x] T042 [P] [US3] Ajouter un test de stabilité stage/desktop avec pin replié dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`

### Implémentation pour Récit Utilisateur 3

- [x] T043 [US3] Ajouter les actions `collapsePin` et `restorePin` dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T044 [US3] Ajouter la mutation de présentation repliée dans `Sources/RoadieDaemon/StageStore.swift`
- [x] T045 [US3] Adapter `LayoutMaintainer` pour ne pas restaurer automatiquement une vraie fenêtre volontairement repliée dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [x] T046 [US3] Implémenter le proxy compact de pin replié dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T047 [US3] Implémenter la restauration depuis le proxy dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T048 [US3] Nettoyer l'état replié quand le pin est retiré dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [x] T049 [US3] Journaliser `window.pin_collapsed` et `window.pin_restored` dans `Sources/RoadieDaemon/PinPopoverController.swift`

**Point de contrôle** : une fenêtre pinée peut être repliée/restaurée sans saut de layout ni perte de frame.

---

## Phase 6 : Récit Utilisateur 4 - Zone évolutive pour modes de pin (Priorité : P3)

**Objectif** : organiser le menu pour accueillir les modes de pin actuels et futurs sans refonte.

**Test indépendant** : ouvrir le menu et vérifier que les modes de pin sont regroupés séparément des déplacements, avec l'état actif lisible.

### Tests pour Récit Utilisateur 4

- [x] T050 [P] [US4] Ajouter un test d'ordre des sections de menu dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T051 [P] [US4] Ajouter un test d'extension de mode désactivée sans casser les modes actuels dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`

### Implémentation pour Récit Utilisateur 4

- [x] T052 [US4] Structurer les modes de pin dans une section dédiée du modèle de menu dans `Sources/RoadieDaemon/PinPopoverController.swift`
- [x] T053 [US4] Ajouter un état utilisateur explicite visible/replié/scope dans `Sources/RoadieDaemon/Formatters.swift`
- [x] T054 [US4] Ajouter une sortie diagnostic des présentations de pin dans `Sources/roadie/main.swift`

**Point de contrôle** : la zone Pin du menu est stable et prête à recevoir de futurs modes.

---

## Phase 7 : Stabilisation & Documentation

**Objectif** : vérifier les régressions et documenter l'expérience utilisateur.

- [x] T055 [P] Documenter le menu pin et le repliage en français dans `docs/fr/features.md`
- [x] T056 [P] Documenter le menu pin et le repliage en anglais dans `docs/en/features.md`
- [x] T057 Mettre à jour `specs/006-pin-popover-collapse/quickstart.md` si les libellés finaux changent
- [x] T058 Exécuter `./scripts/with-xcode swift test --filter PinPopoverTests` et corriger toute régression
- [x] T059 Exécuter `make test` et corriger toute régression
- [x] T060 Exécuter `make build` et corriger toute erreur de compilation
- [ ] T061 Réaliser le scénario manuel bouton visible du quickstart et consigner le résultat dans `specs/006-pin-popover-collapse/implementation.md`
- [ ] T062 Réaliser le scénario manuel repliage/restauration 20 cycles et consigner le résultat dans `specs/006-pin-popover-collapse/implementation.md`
- [ ] T063 Réaliser le scénario manuel changement stage/desktop avec pin replié et consigner le résultat dans `specs/006-pin-popover-collapse/implementation.md`
- [x] T064 [P] Ajouter un test de proxy replié affichant titre ou application reconnaissable dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T065 [P] Ajouter un test de désactivation `pin_popover` conservant le menu de barre de titre existant dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [x] T066 [P] Ajouter un test de non-régression garantissant qu'une fenêtre non pinée ne reçoit aucun état de présentation dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T067 [P] Ajouter un test vérifiant que le repliage ne redimensionne pas la fenêtre applicative comme mécanisme principal dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T068 [P] Ajouter un test garantissant que les fenêtres overlay Roadie du bouton/menu/proxy ne sont pas traitées comme fenêtres gérées dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [x] T069 [P] Ajouter un test de menu minimal du proxy replié pour restaurer ou retirer le pin dans `Tests/RoadieDaemonTests/PinPopoverTests.swift`
- [x] T070 Ajouter l'action de menu minimal du proxy replié pour restaurer ou retirer le pin dans `Sources/RoadieDaemon/PinPopoverController.swift`

---

## Dépendances & Ordre d'Exécution

### Dépendances de phases

- **Préparation (Phase 1)** : démarre immédiatement.
- **Fondations (Phase 2)** : dépend de Phase 1 et bloque tous les récits.
- **US1 (Phase 3)** : dépend des fondations; MVP visuel minimal.
- **US2 (Phase 4)** : dépend de US1 pour le point d'entrée bouton.
- **US3 (Phase 5)** : dépend de US1 et US2 pour exposer l'action de repliage dans le menu.
- **US4 (Phase 6)** : dépend de US2, peut être fait avant ou après US3 mais doit conserver la compatibilité du menu.
- **Stabilisation (Phase 7)** : dépend des récits implémentés.

### Dépendances des récits utilisateur

- **US1** : bouton visible et placement sûr, indépendant du contenu complet du menu.
- **US2** : menu complet, dépend du bouton et des actions existantes.
- **US3** : repliage/restauration, dépend de la présence du menu et du modèle de présentation.
- **US4** : organisation évolutive des modes, dépend du modèle de menu.

### Opportunités de parallélisation

- T002, T003, T004, T005 peuvent être faites en parallèle.
- T009, T010, T014, T015, T017 peuvent être faites en parallèle après les modèles/configs.
- Les tests T018 à T021 peuvent être écrits en parallèle.
- Les tests T028 à T031 peuvent être écrits en parallèle.
- Les tests T038 à T042 peuvent être écrits en parallèle.
- La documentation T055 et T056 peut être faite en parallèle.

## Exemple parallèle : Récit Utilisateur 1

```bash
Tâche: "Ajouter un test de placement sûr du bouton dans Tests/RoadieDaemonTests/PinPopoverTests.swift"
Tâche: "Ajouter un test d'affichage paramétrable pour fenêtre non pinée dans Tests/RoadieDaemonTests/PinPopoverTests.swift"
Tâche: "Ajouter un test d'omission pour fenêtre trop petite ou plein écran dans Tests/RoadieDaemonTests/PinPopoverTests.swift"
```

## Stratégie d'Implémentation

### MVP d'abord

1. Terminer Phase 1.
2. Terminer Phase 2.
3. Implémenter US1.
4. Valider que le bouton apparaît seulement sur les fenêtres pinées éligibles.
5. Stopper pour test manuel rapide avant d'ajouter menu et repliage.

### Livraison incrémentale

1. US1 : bouton visible sûr.
2. US2 : menu cohérent avec le clic droit.
3. US3 : repliage/restauration via proxy.
4. US4 : zone de modes de pin évolutive.
5. Stabilisation : docs, quickstart, tests globaux.

### Stratégie anti-risque

1. Commencer par des fonctions pures de placement et de modèle de menu.
2. Ne jamais faire dépendre les bordures ou le navrail de cette UI.
3. Réutiliser `WindowContextActions` pour éviter deux logiques de déplacement.
4. Garder la configuration désactivable.
5. Après chaque récit, vérifier focus, bordures, stage switch et fenêtres non pinées.
