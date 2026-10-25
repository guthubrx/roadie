# Audit de réutilisation 077

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Recherche Spotlight | aucun `NSMetadataQuery` dans `Sources` | CRÉER `LauncherFileSearch` (`LauncherFiles.swift`) |
| Document d'une fenêtre | aucun `kAXDocumentAttribute` ; `axWindowElements(pid:)` (RoadieAX) | RÉUTILISER l'index, CRÉER la lecture `axDocumentPath` |
| Stage d'un dossier | `LauncherRanking` contextes (076) | RÉUTILISER, clé `folder:` |
| Placement d'une nouvelle fenêtre | `openWindow` (074, boucle 10 s) | RÉUTILISER, boucle mise en commun |
| Icône de fichier | `SlashSuggestion.Icon.file` | RÉUTILISER |
| Chemin abrégé | `LauncherList.shortPath` | RÉUTILISER |
| Commande | `queueTargetModeRuntimeCommand` | RÉUTILISER |
| Quick Look | aucun | CRÉER appel `qlmanage -p` (R4) |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
