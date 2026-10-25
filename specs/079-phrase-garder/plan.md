# Plan 079

| Zone | Fichier | Changement |
|---|---|---|
| Phrase | `Sources/RoadieDaemon/LauncherPhrase.swift` (nouveau) | mots FR/EN, analyse, action, titre |
| Abréviations | `Sources/RoadieDaemon/LauncherAliases.swift` (nouveau) | alias codable, magasin, commande `roadie launch` |
| Liste | `Sources/RoadieDaemon/LauncherList.swift` | lignes `phrase` et `alias` en tête |
| Action | `Sources/RoadieDaemon/LauncherActions.swift` | `LauncherPosition`, `LauncherAction.position` |
| Barre | `TargetOverlayPresenter.swift`, `SearchInputPanel.swift` | analyse à la frappe, ⌘S, étape « Garder », ⌘C de la commande |
| Effets | `TargetModeRuntimeController.swift` | position après placement, alias, `--position` |
| CLI | `CLICommandRouter.swift` | `--position` |

Tests : `Tests/RoadieDaemonTests/Spec079PhraseTests.swift`.
