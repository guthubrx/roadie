# Tâches 089

## US1 Déclencheurs (P1)
- [ ] T001 Tests puis entrée par un objet quelconque et déclencheurs externes (moteur, `Call
  External Trigger` vers soi ou un autre workflow) (`Tests/RoadieDaemonTests/Spec089TriggersTests.swift`). FR-001.
- [ ] T002 Commandes `roadie workflow run|trigger` vers le démon, `list --hotkeys` avec la
  commande BTT ; argument « sélection macOS » (AX puis ⌘C simulé). FR-001, FR-002.
- [ ] T003 Actions sur fichier et universelles comme verbes « Workflow : … » (`LauncherActions.swift`,
  barre). FR-003.
- [ ] T004 Recherches de repli des workflows en bas de liste (`LauncherList.swift`). FR-004.

## US2 Filtres (P1)
- [ ] T005 Tests puis filtre de liste et filtre de fichiers (`LauncherFileSearch` paramétrée)
  (`Tests/RoadieDaemonTests/Spec089FiltersTests.swift`). FR-005, FR-006.

## US3 Tâches d'automatisation (P1)
- [ ] T006 Tests puis `AlfredAutomationTasks` (tâche factice : réglages fusionnés, `{var:}`,
  entrée multiple, dossier courant) ; `roadie workflow tasks update` (archive publique, licence
  gardée) (`Tests/RoadieDaemonTests/Spec089AutomationTasksTests.swift`). FR-007.

## US4 Autres briques (P2)
- [ ] T007 Touches simulées, grand texte, Terminal, Raccourcis Apple, dialogue, utilitaire de
  fichier, Browse/Action in Alfred (barre rouverte) ; fiche mise à jour
  (`Tests/RoadieDaemonTests/Spec089BricksTests.swift`). FR-008, FR-009.

## Livraison
- [ ] T008 Suite complète, installation, santé ; mesure du corpus (≥ 90 % / 80 %), essai réel
  Audio Switcher par la commande ; docs FR/EN, CHANGELOG, index, `validation.md`.
