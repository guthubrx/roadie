# Tâches 088

## US1 Lire les workflows (P1)
- [ ] T001 Tests puis `PlistValue` et `AlfredWorkflow` (`Sources/RoadieDaemon/AlfredWorkflow.swift`) :
  objets, connexions, variables, réglages et `prefs.plist`, workflow d'essai écrit pour le test
  (`Tests/RoadieDaemonTests/Spec088WorkflowModelTests.swift`). FR-001.
- [ ] T002 `AlfredWorkflowIndex` : sources Alfred (`prefs.json` › `current`) et Roadie, désactivés
  ignorés, cache par date, entrées par mot-clé (`AlfredWorkflowIndex.swift`). FR-001, FR-002.
- [ ] T003 Réglages `workflows_enabled`, `alfred_workflows` (`Config.swift`, `SettingsCatalog.swift`,
  décomptes des tests du catalogue). FR-001.

## US2 Lancer un Script Filter (P1)
- [ ] T004 Tests puis `AlfredScriptRunner` (`AlfredScriptRunner.swift`) : interpréteurs par type,
  argv et `{query}` avec les 7 bits d'échappement, environnement `alfred_*`, dossier courant,
  annulation, délai de 10 s, plafond 5 Mo, interpréteur absent
  (`Tests/RoadieDaemonTests/Spec088ScriptRunnerTests.swift`). FR-004, FR-009.
- [ ] T005 Tests puis `AlfredScriptFilterResponse` (JSON, XML, sortie `alfredworkflow` d'un Run
  Script), filtrage par la barre. FR-005.

## US3 Le schéma (P1)
- [ ] T006 Tests puis `AlfredWorkflowEngine` (`AlfredWorkflowEngine.swift`) : connexions et
  modificateurs (repli sans modificateur, R6), remplacements `{query}` `{var:}`, variables, briques
  de l'étape 1 avec effets factices ; brique manquante arrêtée et signalée ; cycle borné
  (`Tests/RoadieDaemonTests/Spec088EngineTests.swift`). FR-007, FR-008.
- [ ] T007 `AlfredCompatibility` : état d'un workflow et relevé d'un dossier. FR-010.

## US4 Dans la barre (P1)
- [ ] T008 Lignes `workflowKeyword` et `workflowItem` (`LauncherList.swift`), section Workflows,
  mot-clé tapé : seules ses lignes (`Tests/RoadieDaemonTests/Spec088LauncherTests.swift`). FR-002, FR-003.
- [ ] T009 Barre : script en fond, réponses périmées ignorées, sous-titre du modificateur tenu,
  Retour, Tab (`autocomplete`), ⌘C, ⌘Y, raccourcis 1 à 9 (`TargetOverlayPresenter.swift`). FR-004 à FR-007.
- [ ] T010 Contexte et effets réels (`LauncherSearchContext.swift`, `TargetModeRuntimeController.swift`) :
  ouvrir, copier, notifier, sons, parole, écrire, fermer/rouvrir la barre, journal sans saisie. FR-008, FR-011.

## US5 Commandes (P2)
- [ ] T011 `roadie workflow list [--json]`, `check DOSSIER`, `install FICHIER [--replace]`,
  `remove ID` (`CLICommandRouter.swift`). FR-010.

## Livraison
- [ ] T012 Suite complète, installation signée, santé ; essai réel Emoji search par la commande
  et mesure du corpus ; mesure `AXIsProcessTrusted` d'un script lancé par Roadie (R8) ; docs FR/EN,
  CHANGELOG, index, `validation.md`.
