# Recherche de variantes - session 048 readonly

Racine : `/private/tmp/roadie-audit-048`.

## Lecture périodique d'un fichier d'état (F2, F4 réfutés)

Motif : `grep -rn "\.state()\|\.load()\|JSONPersistence\.\|Data(contentsOf" Sources/RoadieDaemon/{RailController,DividerResizeRuntime,BorderController,FocusFollowsMouseController}.swift`.

| Site | Cadence | Chemin de lecture | Verdict |
|---|---|---|---|
| RailController.swift:932 `store.state()` | 1 s | JSONPersistence.read (cache + fstat) | sain |
| RailController.swift:936 `railRuntimeStateStore.load()` | 1 s | JSONPersistence.read | sain |
| RailController.swift `RailSettings.load` | 1 s | cache par empreinte (`RailSettings.swift:131`) | sain |
| DividerResizeRuntime.swift:167 `effectiveStageStore.state()` | 0,15 s | JSONPersistence.read | sain |
| DividerResizeRuntime.swift:271 `state()` | pendant un glisser | JSONPersistence.read | sain |
| `JSONPersistence.loadThrowing` (`:183-191`) | lecture sans cache | appelants hors lecteurs périodiques (aucune correspondance dans les quatre lecteurs) | hors repos, non retenu |
| BorderController, FocusFollowsMouseController | - | aucune correspondance | sain |

## Cache lié au cycle de vie non remis à zéro (ancien F1)

`grep -n "removeAll()\|= nil$\|= true$" Sources/RoadieDaemon/RailController.swift` (l. 120-140) :
`lastThumbnailSignatures`, `recordingStatusCache/Dirty`, `contentCache`, `lastConfigRefresh*`
remis à zéro dans `stop()`. `RailThumbnailStore.shareableWindows/absentUntil` auto-corrigés par
`prune` et retrait sur capture nil. Aucun défaut.
