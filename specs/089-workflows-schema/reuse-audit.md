# Audit de réutilisation 089

Statut : `OK`. Repli manuel (`rg`), 26 octobre 2026.

| Élément | Existant | Issue |
|---|---|---|
| Moteur, exécution de scripts | 088 | RÉUTILISER, briques ajoutées |
| Recherche de fichiers | `LauncherFileSearch` (077) | RÉUTILISER, paramétrée (portées, types, champs, limite) |
| Verbes d'un fichier | `LauncherActionList` (074, 077) | RÉUTILISER, nouvelle ligne `workflow` |
| Commandes vers le démon | `queueTargetModeRuntimeCommand` | RÉUTILISER (`workflow.run`, `workflow.trigger`) |
| Touches simulées | `postNewWindowShortcut` (CGEvent, 074) | RÉUTILISER le motif |
| Sélection de texte | aucun `kAXSelectedTextAttribute` | CRÉER lecture AX, repli ⌘C simulé |
| Grand texte | aucun panneau | CRÉER un `NSPanel` simple |
| Raccourcis BTT | skill `bettertouch` (documentation) | RÉUTILISER, aucune capture dans Roadie |
| Téléchargement | aucun | CRÉER `URLSession` + `ditto` vers `~/.roadies/alfred-tasks/` |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
- Filtre de fichiers (implémentation) : `mdfind` lancé par `AlfredScriptRunner` plutôt que
  `LauncherFileSearch` paramétrée. Raison : la recherche devient annulable par la frappe, bornée en
  temps et en sortie comme un Script Filter, sans toucher à la recherche 077 (`LauncherFiles.swift:58`).
