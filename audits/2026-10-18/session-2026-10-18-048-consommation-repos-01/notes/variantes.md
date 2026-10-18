# Recherche de variantes

Racine : `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability`.

## F1 - cache 048 lié à un watcher ou au cycle de vie, non remis à zéro

Motifs : `grep -n "removeAll()\|= nil$\|= RailDisplayContentCache()" Sources/RoadieDaemon/RailController.swift`
(l. 100-145), nouveaux états du diff (`git diff d32105c8 -- Sources/`).

| Cache | Remis à zéro / auto-correction | Verdict |
|---|---|---|
| `lastThumbnailSignatures` (048) | `stop()` l. 131 | sain |
| `recordingStatusCache/Dirty` (048) | absent en r0 | F1 |
| `RailThumbnailStore.shareableWindows/absentUntil` (048) | `prune` à chaque rendu ; capture nil retire l'entrée | sain (auto-correction) |
| `SnapshotProcessState.quietReuseCap` (048) | activé une fois par le tiler, jamais arrêté avant la fin du processus | sain |
| `SnapshotProcessState.observation` (048) | compteur monotone `&+=` | sain |
| `lastConfigRefreshStamp`, `pendingStageStoreRailSignature` (antérieurs) | `stop()` l. 116, 135 | sain |

## F2 - lecteur périodique qui relit un fichier inchangé

Motifs : `grep -n "\.state()\|\.load()\|\.load(path\|contentsOfFile\|JSONPersistence"` sur les quatre
lecteurs de `readerSnapshot` (BorderController, FocusFollowsMouseController, DividerResizeRuntime,
RailController).

| Site | Cadence | Verdict |
|---|---|---|
| RailController.swift:929 `store.state()` | 1 s | F2 |
| RailController.swift:933 `railRuntimeStateStore.load()` | 1 s | F2 (même constat) |
| RailController.swift:931 `RailSettings.load` | 1 s | sain : cache par empreinte (RailSettings.swift:131) |
| DividerResizeRuntime.swift:167 `effectiveStageStore.state()` | 0,15 s | F4 (hors diff) |
| DividerResizeRuntime.swift:271 `state()` dans `valid` | pendant un glisser seulement | hors repos, non retenu |
| BorderController, FocusFollowsMouseController | aucune correspondance | sain |
| `readerSnapshot` : `fileModificationStamp` (stat) | à chaque appel | coût O(1), accepté (contrôle d'empreinte requis par ADR 015) |

## F3 - texte du plan contredit par le code

Motifs : `grep -rn "quietMaxAge\|jusqu'à 1 s"` sur ADR 015, `specs/048-consommation-repos/*.md`,
`DaemonSnapshot.swift`, tests 048. Correspondances : plan.md, tasks.md, research.md (corrigés).
ADR 015, validation.md, code et tests : cohérents (2 s / filet). research.md l. 14 (« rail 1 s ») décrit
la cadence de la minuterie du rail : exact, non retenu.
