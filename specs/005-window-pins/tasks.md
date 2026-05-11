# Tâches : Pins de Fenêtres

**Entrée** : documents de conception dans `/specs/005-window-pins/`  
**Prérequis** : [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests** : inclus car la spécification exige des scénarios indépendants et le plan identifie des régressions critiques à couvrir.

**Organisation** : les tâches sont groupées par récit utilisateur pour permettre une implémentation et une validation indépendantes.

## Format : `[ID] [P?] [Récit] Description`

- **[P]** : tâche parallélisable avec d'autres tâches du même niveau si les dépendances sont satisfaites.
- **[Récit]** : récit utilisateur concerné (`US1`, `US2`, `US3`).
- Chaque tâche pointe vers un fichier précis.

## Phase 1 : Préparation (Infrastructure partagée)

**Objectif** : préparer le terrain sans changer le comportement runtime.

- [X] T001 Vérifier les artefacts SpecKit et aligner les références de feature dans `AGENTS.md`
- [X] T002 [P] Créer l'ADR de persistance des pins dans `docs/decisions/005-window-pins-persistence.md`
- [X] T003 [P] Identifier les tests existants à étendre pour pins dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [X] T004 [P] Identifier les tests existants à étendre pour pins dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T005 [P] Identifier les tests existants à étendre pour pins dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

---

## Phase 2 : Fondations (Prérequis bloquants)

**Objectif** : ajouter le modèle commun des pins et les helpers purs avant toute story utilisateur.

**Critique** : aucun récit utilisateur ne doit commencer avant cette phase.

- [X] T006 Ajouter `WindowPinScope` et `PersistentWindowPin` avec décodage rétrocompatible dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T007 Ajouter `windowPins` à `PersistentStageState` avec défaut vide et unicité par `windowID` dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T008 Ajouter les helpers purs `pin(for:)`, `setPin`, `removePin`, `pruneMissingPins`, `isPinned` dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T009 [P] Ajouter les tests de persistance et rétrocompatibilité `windowPins` absents dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [X] T010 [P] Ajouter les tests d'unicité et changement de scope d'un pin existant dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [X] T011 [P] Ajouter un test empêchant la duplication d'une fenêtre pinée entre plusieurs stages dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [X] T012 Ajouter les événements `window.pin_added`, `window.pin_scope_changed`, `window.pin_removed`, `window.pin_pruned` dans `Sources/RoadieCore/AutomationEventCatalog.swift`
- [X] T013 [P] Ajouter les tests catalogue pour les événements de pin dans `Tests/RoadieDaemonTests/AutomationEventTests.swift`

**Point de contrôle** : le modèle de pin est persistable, testable et sans impact visible sur Roadie.

---

## Phase 3 : Récit Utilisateur 1 - Pin sur le desktop courant (Priorité : P1) MVP

**Objectif** : une fenêtre peut rester visible sur toutes les stages du desktop courant, mais pas sur les autres desktops.

**Test indépendant** : pinner une fenêtre depuis le menu, changer 10 fois de stage dans le même desktop, puis changer de desktop ; la fenêtre reste visible dans le desktop d'origine et disparaît ailleurs.

### Tests pour Récit Utilisateur 1

- [X] T014 [P] [US1] Ajouter un test `desktop` pin visible sur stages du même desktop dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T015 [P] [US1] Ajouter un test `desktop` pin caché sur un autre desktop dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T016 [P] [US1] Ajouter un test `desktop` pin préserve le frame manuel entre snapshots dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T017 [P] [US1] Ajouter un test `hideInactiveStageWindows` ne cache pas un pin visible du desktop courant dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`
- [X] T018 [P] [US1] Ajouter un test `ApplyPlan` exclut une fenêtre pinée desktop du layout dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T019 [P] [US1] Ajouter un test menu non piné propose `Pin sur ce desktop` dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour Récit Utilisateur 1

- [X] T020 [US1] Ajouter une décision de visibilité `desktop` pin dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T021 [US1] Adapter `SnapshotService.snapshot` pour conserver le scope d'origine tout en permettant la visibilité desktop pin dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T022 [US1] Adapter `SnapshotService.applyPlan` ou l'état généré pour exclure les fenêtres pinées du layout actif dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T023 [US1] Adapter `LayoutMaintainer.hideInactiveStageWindows` pour ne pas cacher un pin visible dans le desktop courant dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [X] T024 [US1] Ajouter l'action `pinDesktop` au modèle d'action contextuelle dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [X] T025 [US1] Implémenter l'exécution `Pin sur ce desktop` dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [X] T026 [US1] Ajouter la section de menu `Fenêtre` avec `Pin sur ce desktop` dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [X] T027 [US1] Journaliser `window.pin_added` pour un pin desktop dans `Sources/RoadieDaemon/WindowContextActions.swift`

**Point de contrôle** : le Récit Utilisateur 1 est fonctionnel indépendamment et constitue le MVP.

---

## Phase 4 : Récit Utilisateur 2 - Pin sur tous les desktops Roadie du même écran (Priorité : P2)

**Objectif** : une fenêtre peut rester visible sur tous les desktops Roadie du même display, sans être dupliquée ni déplacer le layout.

**Test indépendant** : pinner une fenêtre en `all_desktops`, changer 10 fois de desktop et 10 fois de stage sur le même écran ; la fenêtre reste visible, conserve sa position, et n'apparaît pas deux fois dans les menus.

### Tests pour Récit Utilisateur 2

- [X] T028 [P] [US2] Ajouter un test `all_desktops` pin visible sur plusieurs desktops du même display dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T029 [P] [US2] Ajouter un test `all_desktops` pin non visible sur un autre display dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T030 [P] [US2] Ajouter un test `all_desktops` pin préserve le frame manuel entre snapshots dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T031 [P] [US2] Ajouter un test menu pin desktop propose changement vers `Pin sur tous les desktops` dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour Récit Utilisateur 2

- [X] T032 [US2] Étendre la décision de visibilité à `all_desktops` limité au même display dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T033 [US2] Adapter le nettoyage et la mise à jour de `lastFrame` pour pins `all_desktops` dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T034 [US2] Ajouter l'action `pinAllDesktops` au modèle d'action contextuelle dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [X] T035 [US2] Implémenter l'exécution `Pin sur tous les desktops` dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [X] T036 [US2] Afficher l'état courant et le changement de scope dans la section `Fenêtre` du menu dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [X] T037 [US2] Journaliser `window.pin_scope_changed` quand une fenêtre déjà pinée change de scope dans `Sources/RoadieDaemon/WindowContextActions.swift`

**Point de contrôle** : les Récits Utilisateur 1 et 2 fonctionnent indépendamment.

---

## Phase 5 : Récit Utilisateur 3 - Retirer un pin proprement (Priorité : P3)

**Objectif** : l'utilisateur peut retirer un pin depuis le même menu et retrouver un comportement normal sans perte de fenêtre ni saut de layout.

**Test indépendant** : pinner une fenêtre, retirer le pin, changer de stage et desktop ; la fenêtre redevient liée à un seul contexte et les autres fenêtres ne bougent pas.

### Tests pour Récit Utilisateur 3

- [X] T038 [P] [US3] Ajouter un test `Retirer le pin` supprime l'état persistant dans `Tests/RoadieDaemonTests/PersistentStageStateTests.swift`
- [X] T039 [P] [US3] Ajouter un test unpin depuis `desktop` laisse la fenêtre dans le contexte actif valide dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T040 [P] [US3] Ajouter un test unpin depuis `all_desktops` laisse la fenêtre dans un contexte unique dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T041 [P] [US3] Ajouter un test fenêtre fermée prune automatiquement le pin dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift`
- [X] T042 [P] [US3] Ajouter un test menu piné propose `Retirer le pin` dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`

### Implémentation pour Récit Utilisateur 3

- [X] T043 [US3] Ajouter l'action `unpin` au modèle d'action contextuelle dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift`
- [X] T044 [US3] Implémenter `Retirer le pin` dans `Sources/RoadieDaemon/WindowContextActions.swift`
- [X] T045 [US3] Garantir qu'un unpin réattache la fenêtre à un seul contexte valide dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T046 [US3] Appeler `pruneMissingPins` pendant le refresh normal dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [X] T047 [US3] Journaliser `window.pin_removed` et `window.pin_pruned` dans `Sources/RoadieDaemon/WindowContextActions.swift` et `Sources/RoadieDaemon/DaemonSnapshot.swift`

**Point de contrôle** : les trois récits utilisateur sont fonctionnels indépendamment.

---

## Phase 6 : Cohérence des déplacements de fenêtres pinées

**Objectif** : garantir qu'une fenêtre pinée déplacée vers une autre stage, un autre desktop ou un autre écran garde un état de pin cohérent.

- [X] T048 [P] Ajouter un test déplacement stage d'une fenêtre pinée dans `Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift`
- [X] T049 [P] Ajouter un test déplacement desktop d'une fenêtre pinée dans `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift`
- [X] T050 [P] Ajouter un test déplacement display d'une fenêtre pinée dans `Tests/RoadieDaemonTests/StageDisplayMoveTests.swift`
- [X] T051 Ajouter un helper commun de cohérence après déplacement de fenêtre pinée dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T052 Adapter `StageCommandService.assign` pour mettre à jour ou retirer le pin après déplacement stage dans `Sources/RoadieDaemon/StageCommands.swift`
- [X] T053 Adapter `DesktopCommandService.assign` pour mettre à jour ou retirer le pin après déplacement desktop dans `Sources/RoadieDaemon/DesktopCommands.swift`
- [X] T054 Adapter `WindowCommandService.send` pour mettre à jour ou retirer le pin après déplacement display dans `Sources/RoadieDaemon/WindowCommands.swift`

---

## Phase 7 : Stabilisation & Transversal

**Objectif** : stabilisation, documentation et validation globale.

- [X] T055 [P] Ajouter une sortie diagnostic des pins si utile dans `Sources/RoadieDaemon/Formatters.swift`
- [X] T056 [P] Documenter les pins en français dans `docs/fr/features.md`
- [X] T057 [P] Documenter les pins en anglais dans `docs/en/features.md`
- [X] T058 Mettre à jour le quickstart utilisateur si le libellé final du menu diffère dans `specs/005-window-pins/quickstart.md`
- [X] T059 Exécuter `make test` et corriger toute régression dans `Tests/RoadieDaemonTests`
- [X] T060 Exécuter `make build` et corriger toute erreur de compilation dans `Sources`
- [ ] T061 Réaliser le test manuel `desktop` pin du quickstart avec 10 changements de stage et 10 changements de desktop, puis consigner le résultat dans `specs/005-window-pins/implementation.md`
- [ ] T062 Réaliser le test manuel `all_desktops` pin du quickstart avec 10 changements de desktop, 10 changements de stage et seuil 95 % sans mouvement parasite, puis consigner le résultat dans `specs/005-window-pins/implementation.md`
- [ ] T063 Réaliser le test manuel unpin du quickstart avec vérification du retour en visibilité unique en moins de 2 secondes, puis consigner le résultat dans `specs/005-window-pins/implementation.md`

---

## Dépendances & Ordre d'Exécution

### Dépendances de phases

- **Préparation (Phase 1)** : démarre immédiatement.
- **Fondations (Phase 2)** : dépend de la préparation et bloque tous les récits.
- **US1 (Phase 3)** : dépend de la Phase 2 ; MVP.
- **US2 (Phase 4)** : dépend de la Phase 2, mais doit être intégrée après US1 pour réutiliser le même modèle de visibilité.
- **US3 (Phase 5)** : dépend de la Phase 2, mais se valide mieux après US1/US2.
- **Cohérence déplacements (Phase 6)** : dépend de US1-US3, car elle stabilise les interactions entre pin et assign/send.
- **Stabilisation (Phase 7)** : dépend des récits implémentés.

### Dépendances des récits utilisateur

- **US1** : base fonctionnelle et MVP.
- **US2** : dépend du modèle de pin et prolonge US1 avec un scope plus large.
- **US3** : dépend du modèle de pin ; peut être développée après US1 si besoin de réversibilité rapide.

### À l'intérieur de chaque récit utilisateur

- Tests avant implémentation.
- Modèle et helpers avant snapshot/maintainer.
- Snapshot/maintainer avant menu utilisateur.
- Événements après actions métier.
- Point de contrôle manuel avant passage au récit suivant.

## Opportunités de parallélisation

- T003, T004, T005 peuvent être faites en parallèle.
- T009, T010, T011, T013 peuvent être faites en parallèle après T006-T008.
- Les tests US1 T014-T019 peuvent être écrits en parallèle.
- Les tests US2 T028-T031 peuvent être écrits en parallèle.
- Les tests US3 T038-T042 peuvent être écrits en parallèle.
- Les tests de déplacement T048-T050 peuvent être écrits en parallèle.
- La documentation T056-T057 peut être faite en parallèle après stabilisation des libellés.

## Exemple parallèle : Récit Utilisateur 1

```bash
Tâche: "Ajouter un test desktop pin visible sur stages du même desktop dans Tests/RoadieDaemonTests/SnapshotServiceTests.swift"
Tâche: "Ajouter un test hideInactiveStageWindows ne cache pas un pin visible dans Tests/RoadieDaemonTests/LayoutMaintainerTests.swift"
Tâche: "Ajouter un test menu non piné propose Pin sur ce desktop dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift"
```

## Stratégie d'Implémentation

### MVP d'abord (Récit Utilisateur 1 uniquement)

1. Terminer Phase 1.
2. Terminer Phase 2.
3. Implémenter US1.
4. Exécuter `make test`.
5. Relancer Roadie et valider le scénario "pin sur ce desktop".

### Livraison incrémentale

1. US1 : pin visible sur stages du desktop courant.
2. US2 : élargir à tous les desktops du même display.
3. US3 : retrait et nettoyage automatique.
4. Phase 6 : déplacements stage/desktop/display d'une fenêtre pinée.
5. Stabilisation : docs, quickstart manuel, build final.

### Stratégie anti-risque

1. Ne jamais modifier le comportement des fenêtres non pinées sans test de régression.
2. Valider `hideInactiveStageWindows` avant de tester le menu.
3. Garder les actions de pin séparées des actions `send/assign`.
4. Après chaque story, vérifier bordures, changement de stage et changement de desktop.
