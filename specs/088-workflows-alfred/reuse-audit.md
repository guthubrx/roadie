# Audit de réutilisation 088

Statut : `OK`. Repli manuel (`rg`), 26 octobre 2026.

| Élément | Existant | Issue |
|---|---|---|
| Lecture de plist | aucun (`PropertyListSerialization` absent) | CRÉER `PlistValue` (Foundation, sans dépendance) |
| Lancer un script avec délai | `LauncherBrowsers.run` (`LauncherOpenItems.swift:128`) : osascript, 2 s, sans environnement ni annulation | CRÉER `AlfredScriptRunner` (environnement, dossier, annulation par frappe, plafond de sortie) ; motif repris |
| Notification | `TargetMacroService.swift:474` (`display notification` par osascript) | RÉUTILISER le moyen (osascript) |
| Ouvrir une adresse, un fichier, Finder, copie | `NSWorkspace.open`, `performFile` (077), `NSPasteboard` | RÉUTILISER dans les effets réels |
| Lignes, icônes de fichier | `SlashSuggestion.Icon.file`, `.symbol` | RÉUTILISER ; icône d'image du workflow par `.file(chemin png)` |
| Classement appris | `LauncherRanking` (`recordVisit`) | RÉUTILISER, clé `wf:<bundle>:<uid>` |
| Commandes CLI locales | `project list` (lecture locale dans le routeur) | RÉUTILISER le motif |
| Décompression | aucun | CRÉER appel `/usr/bin/ditto -x -k` (outil système) |
| Réglages | `TargetModeConfig`, `SettingsCatalog` | RÉUTILISER |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
- `AlfredScriptRunner` à côté de `LauncherBrowsers.run` : besoins différents (environnement,
  annulation, plafond, interpréteurs) ; fusionner rendrait `run` plus complexe pour 3 appels.
