# Plan 089

| Zone | Fichier | Changement |
|---|---|---|
| Moteur | `Sources/RoadieDaemon/AlfredWorkflowEngine.swift` | briques de l'étape 2 ; appel externe vers un autre workflow ; entrée par un objet quelconque |
| Effets | `Sources/RoadieDaemon/AlfredEffects.swift` (nouveau, extrait du contrôleur si > 150 lignes) | touches simulées, grand texte, Terminal, Raccourcis, dialogue, sélection macOS |
| Tâches | `Sources/RoadieDaemon/AlfredAutomationTasks.swift` (nouveau) | lecture des tâches, réglages fusionnés, exécution ; mise à jour de l'archive |
| Filtres | `Sources/RoadieDaemon/AlfredWorkflowIndex.swift`, `LauncherFiles.swift` | entrées liste et fichiers ; `LauncherFileSearch` paramétrée (portées, types, champs, limite) |
| Verbes | `Sources/RoadieDaemon/LauncherActions.swift` | ligne de verbe « Workflow : … » pour les actions sur fichier et universelles |
| Repli | `Sources/RoadieDaemon/LauncherList.swift` | section « Repli » avec les recherches de repli des workflows |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift` | filtres, verbes de workflow, repli, réouverture sur un texte |
| CLI | `Sources/RoadieDaemon/CLICommandRouter.swift`, `TargetModeRuntimeController.swift` | `workflow run`, `workflow trigger`, `workflow list --hotkeys`, `workflow tasks update` |
| Fiche | `Sources/RoadieDaemon/AlfredCompatibility.swift` | briques de l'étape 2 |

Complexité : verbes de workflow O(a) actions déclarées par fichier choisi ; repli O(f) ; filtre de
liste O(i) éléments par frappe ; tâche : une lecture de `alfredtask.json` mise en cache.
Tests : `Spec089TriggersTests`, `Spec089FiltersTests`, `Spec089AutomationTasksTests`
(tâche factice écrite pour le test), `Spec089BricksTests`.
Article XIX : pas de capture de raccourcis (BTT le fait) ; tâches téléchargées à la demande, pas
de copie dans le dépôt.
