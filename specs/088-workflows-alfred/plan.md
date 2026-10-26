# Plan 088

| Zone | Fichier | Changement |
|---|---|---|
| Modèle | `Sources/RoadieDaemon/AlfredWorkflow.swift` (nouveau) | `PlistValue`, `AlfredWorkflow`, objets, connexions, réglages ; lecture d'un dossier |
| Index | `Sources/RoadieDaemon/AlfredWorkflowIndex.swift` (nouveau) | sources (Alfred, Roadie), cache par date de modification, entrées par mot-clé |
| Script | `Sources/RoadieDaemon/AlfredScriptRunner.swift` (nouveau) | interpréteurs, `{query}` et échappement, environnement, arrêt, plafond de sortie |
| Réponse | `Sources/RoadieDaemon/AlfredScriptFilterResponse.swift` (nouveau) | JSON et XML d'un Script Filter, sortie JSON d'un Run Script |
| Schéma | `Sources/RoadieDaemon/AlfredWorkflowEngine.swift` (nouveau) | parcours des connexions, briques de l'étape 1, remplacements ; effets injectés |
| Fiche | `Sources/RoadieDaemon/AlfredCompatibility.swift` (nouveau) | briques prises en charge, état d'un workflow, relevé d'un dossier |
| Liste | `Sources/RoadieDaemon/LauncherList.swift` | `Row.workflowItem`, `Row.workflowKeyword`, section Workflows |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift` | mot-clé tapé, script en fond, modificateurs, Retour, Tab, ⌘C, ⌘Y |
| Contexte | `Sources/RoadieDaemon/LauncherSearchContext.swift`, `TargetModeRuntimeController.swift` | entrées, lancement du Script Filter, exécution du schéma avec les vrais effets |
| Réglages | `Sources/RoadieCore/Config.swift`, `Sources/RoadieDaemon/SettingsCatalog.swift` | `workflows_enabled`, `alfred_workflows` |
| CLI | `Sources/RoadieDaemon/CLICommandRouter.swift` | `roadie workflow list|check|install|remove` (sans démon) |

Choix : un moteur unique, sans dépendance, dont les effets (ouvrir, copier, notifier, lancer un
script, fermer ou rouvrir la barre) passent par un protocole : le schéma se teste sans écran et
la 089 n'ajoute que des briques. Le modèle garde la configuration brute (`PlistValue`) : chaque
brique lit ses clés, le reste est ignoré sans perte.
Complexité : index O(W × o) au rechargement seulement ; mot-clé O(k) entrées par frappe ; schéma
O(o + c) objets et connexions par exécution (détection de cycle, 200 étapes au plus).
Tests : `Spec088WorkflowModelTests`, `Spec088ScriptRunnerTests`, `Spec088EngineTests`,
`Spec088LauncherTests` (fichiers de test écrits pour l'occasion, aucun workflow tiers copié).
