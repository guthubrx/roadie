# Plan 076

| Zone | Fichier | Changement |
|---|---|---|
| Mémoire par stage | `Sources/RoadieDaemon/LauncherRanking.swift` | `Entry.contexts: [String: Context]?` (ancre + abréviations), `exactUses(_:query:context:)`, `frecency(_:at:context:)`, `recordVisit(_:query:at:context:)`, borne 6 |
| Ordre | `Sources/RoadieDaemon/LauncherList.swift` | `init(…, context:)` ; comparaison FR-002 |
| Contexte | `Sources/RoadieDaemon/LauncherSearchContext.swift`, `TargetModeRuntimeController.swift` | `rankingContext` (nom de la stage active ou sa place) ; `recordVisit` avec contexte |
| Vignettes | `Sources/RoadieDaemon/SlashCommandModel.swift`, `SearchBarRenderer.swift`, `TargetOverlayPresenter.swift` | icône `.window(id, app:)` ; dessin : `RailThumbnailStore.shared.detailedImage` puis `cachedImage` si capturée, pastille de l'application |

Complexité : classement O(1) de plus par comparaison (dictionnaires) ; dessin O(r) lignes montrées.
Réutilisation : `RailThumbnailStore.shared` (cache commun rail, sélecteur, vue d'ensemble),
`WindowSwitcherService.stageLabels` (noms de stages). Aucune dépendance.

Tests : `Tests/RoadieDaemonTests/Spec076ContextTests.swift` (ordre par stage, borne, compatibilité
du format dans les deux sens).
