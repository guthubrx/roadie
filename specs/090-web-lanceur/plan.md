# Plan 090

| Zone | Fichier | Changement |
|---|---|---|
| Web | `Sources/RoadieDaemon/LauncherSearchContext.swift` (`LauncherWeb`) | adresse tapée, recherches par mot-clé, lignes de repli |
| Historique | `Sources/RoadieDaemon/LauncherHistory.swift` (nouveau) | magasin des 20 dernières saisies, reprise sous 5 minutes |
| Liste | `Sources/RoadieDaemon/LauncherList.swift` | `Row.web(LauncherWebRow)`, section « Web » en fin, adresse et mot-clé en tête, `Row.history` |
| Verbes | `Sources/RoadieDaemon/LauncherActions.swift` | `LauncherSubject.url`, verbes Ouvrir, Ouvrir dans…, Amener ici, Copier l'adresse |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift`, `SearchInputPanel.swift` | lignes web, reprise de la saisie sélectionnée, recherches récentes |
| Effets | `Sources/RoadieDaemon/TargetModeRuntimeController.swift` | ouvrir une adresse, nouvelle fenêtre du navigateur placée (R2), historique |
| Réglages | `Sources/RoadieCore/Config.swift`, `SettingsCatalog.swift` | `web_searches`, `fallback_searches` |
| CLI | `Sources/RoadieDaemon/CLICommandRouter.swift` | `roadie launcher history [--clear]` |

Complexité : reconnaissance d'adresse O(q) ; recherches par mot-clé O(k) ; historique O(1) par
action (20 entrées). Tests : `Spec090WebTests`, `Spec090HistoryTests`.
