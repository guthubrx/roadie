# Tâches : Durcissement de stabilité layout

**Entrée** : reconstruction rétrospective depuis les commits et le worktree courant.
**Prérequis** : [spec.md](./spec.md), [plan.md](./plan.md), specs 003/007/008/009.
**Tests** : obligatoires car les correctifs touchent layout, focus, stages, écrans, preview drag/drop et politique de tiling.

## Phase 1 : Reconstruction et cadrage

- [x] T001 Identifier les correctifs transverses non rattachés proprement aux specs 003/007/008/009 `(commits 59425c7..f6b88e6 + worktree 2026-05-20)`
- [x] T002 Créer la spec rétrospective `specs/010-layout-stability-hardening/spec.md`
- [x] T003 Créer le plan rétrospectif `specs/010-layout-stability-hardening/plan.md`
- [x] T004 Créer les tâches rétrospectives `specs/010-layout-stability-hardening/tasks.md`

---

## Phase 2 : Mutable BSP et respect de l'intention utilisateur

- [x] T005 Ajouter la stabilisation `mutableBsp` et recovery display dans `Sources/RoadieDaemon/LayoutMaintainer.swift` `(commit 87b5934)`
- [x] T006 Corriger la stratégie `MutableBSPLayoutStrategy` pour préserver les choix utilisateur de split et de géométrie `(commit f92a151)`
- [x] T007 Ajouter l'adoption de géométrie `mutable_bsp_geometry_adopted` dans `Sources/RoadieDaemon/LayoutMaintainer.swift` `(commit f92a151)`
- [x] T008 Ajouter la propagation de resize `mutable_bsp_resize_propagated` dans `Sources/RoadieDaemon/LayoutMaintainer.swift` `(commit 87b5934)`
- [x] T009 Ajouter les tests de non-régression `LayoutMaintainerTests` sur suppression de relayout et géométrie mutable `(commits f92a151, 87b5934)`
- [x] T010 Ajouter la protection contre reprise de main après disparition de fenêtre dans `LayoutMaintainer` `(commit f6b88e6)`
- [x] T011 Ajouter le test de relayout après disparition d'une fenêtre dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift` `(commit f6b88e6)`

---

## Phase 3 : Activité de commande et suppression des corrections automatiques

- [x] T012 Créer `Sources/RoadieDaemon/LayoutCommandActivity.swift` pour partager l'activité de commande entre CLI/BTT et daemon `(worktree 2026-05-20)`
- [x] T013 Brancher `LayoutCommandActivity` dans `WindowCommands`, `StageCommands` et `DesktopCommands` `(worktree 2026-05-20)`
- [x] T014 Brancher la suppression `layout_command_activity_suppressed` dans `LayoutMaintainer` `(worktree 2026-05-20)`
- [x] T015 Ajouter le calcul `commandLayoutIntentNeedsApply` dans `DaemonSnapshot` pour éviter de valider trop tôt un intent partiellement appliqué `(worktree 2026-05-20)`
- [x] T016 Ajouter les tests d'activité de commande dans `PowerUserDesktopCommandTests` et `LayoutMaintainerTests` `(worktree 2026-05-20)`

---

## Phase 4 : Politique de tiling et fenêtres flottantes génériques

- [x] T017 Calculer `stageManagedWindowIDs` après application de `applyTilingPolicy` dans `DaemonSnapshot` `(worktree 2026-05-20)`
- [x] T018 Ajouter la détection générique `isShortNonFullscreenUtilityWindow` pour popups/progress standard courtes `(worktree 2026-05-20)`
- [x] T019 Ajouter le test `shortStandardProgressWindowWithoutFullscreenIsExcluded` dans `TilingPolicyTests` `(worktree 2026-05-20)`
- [x] T020 Ajouter le test `policyExcludedWindowDoesNotRemainStageManaged` dans `SnapshotServiceTests` `(worktree 2026-05-20)`
- [x] T021 Vérifier que les fenêtres flottantes non gérées ne déclenchent plus de relayout ni preview de drop `(worktree 2026-05-20)`

---

## Phase 5 : Preview drag/drop stable

- [x] T022 Durcir `DropPreviewController` pour ignorer les frames source transitoires en `mutableBsp` `(commit 87b5934)`
- [x] T023 Ajouter `WindowDragActivity` pour distinguer drag réel et drift de layout `(commit 87b5934)`
- [x] T024 Ajouter le test `mutableBspDragPreviewIgnoresTransientDraggedSourceFrame` dans `DropPreviewEngineTests` `(worktree 2026-05-20)`
- [x] T025 Corriger les previews de zones déséquilibrées en utilisant la composition persistée plutôt que la position temporaire `(commits 87b5934, worktree 2026-05-20)`

---

## Phase 6 : Isolation focus, stage et display

- [x] T026 Ajouter la protection contre stale focus reactivation dans `StageCommands` `(commit 1b6fd36)`
- [x] T027 Stabiliser le focus restore et l'isolation des tests dans `LayoutMaintainer`, `StageCommands`, `roadied/main.swift` `(commit 15f5a65)`
- [x] T028 Supprimer le suivi de focus caché cross-display après fenêtre manquante dans `DaemonSnapshot` `(worktree 2026-05-20)`
- [x] T029 Limiter `hideInactiveStageWindows` au display concerné dans `LayoutMaintainer` `(worktree 2026-05-20)`
- [x] T030 Ajouter les tests `snapshotSuppressesHiddenCrossDisplayFocusWhenAWindowJustWentMissing` et `focusedStageRestoreOnlyHidesInactiveWindowsOnSameDisplay` `(worktree 2026-05-20)`
- [x] T031 Stabiliser le relayout après disparition de fenêtre sans modifier les autres scopes `(commit f6b88e6)`

---

## Phase 7 : Parking invisible des fenêtres cachées

- [x] T032 Créer `Sources/RoadieDaemon/HiddenWindowPlacement.swift` `(worktree 2026-05-20)`
- [x] T033 Remplacer les calculs de parking caché dans `LayoutMaintainer`, `StageCommands`, `DesktopCommands`, `WindowBookmarkCommands` et `WindowContextActions` `(worktree 2026-05-20)`
- [x] T034 Remplacer la détection legacy `isHiddenCorner` par `HiddenWindowPlacement.isHidden` dans `DaemonSnapshot` `(worktree 2026-05-20)`
- [x] T035 Ajouter le test `inactiveWindowParkedOnOldBottomLeftIsReparkedToBottomRight` `(worktree 2026-05-20)`

---

## Phase 8 : Display parking recovery

- [x] T036 Stabiliser le parking et les events display dans `DisplayParkingService`, `StateAudit` et logs `(commit 836d997)`
- [x] T037 Ajouter la récupération de stages parkées anciennes `parkedStagesRecovered` dans `DisplayParkingService` `(worktree 2026-05-20)`
- [x] T038 Ajouter les tests de matérialisation de stages parkées anciennes et de délai de reconnexion rapide dans `DisplayParkingServiceTests` `(worktree 2026-05-20)`
- [x] T039 Garantir que les stages parkées fraîches restent temporaires pour permettre un rebranchement rapide `(worktree 2026-05-20)`

---

## Phase 9 : Navigation visible et navrail

- [x] T040 Ajouter les commandes de navigation visible de stage dans `StageCommands` et `roadie/main.swift` `(commit 5cac231)`
- [x] T041 Aligner la navigation visible sur le navrail réel plutôt que sur les IDs internes `(commit 0d17274)`
- [x] T042 Ignorer les stages non tileables dans la navigation visible `(commit ce98577)`
- [x] T043 Rafraîchir le navrail immédiatement après changement de stage dans `RailController` `(commit 05915fc)`
- [x] T044 Ajouter les tests `PowerUserDesktopCommandTests` pour switch visible, filtrage et activité commande `(commits 5cac231, 0d17274, ce98577, worktree 2026-05-20)`

---

## Phase 10 : Stabilisation finale

- [x] T045 Rattacher les correctifs bookmarks/pins/rail drops déjà livrés à la stabilité layout plutôt qu'à une UI pin-popover abandonnée `(commit 59425c7)`
- [x] T046 Vérifier que Target Mode garde grille, record et app targets isolés du tiler `(commits f92a151, 9180786, 006c49b)`
- [x] T047 Mettre à jour les artefacts SpecKit pour refléter les correctifs livrés et les abandons/reverts associés `(worktree 2026-05-20)`

## Dépendances

- Phases 2 et 3 bloquent toute stabilisation fiable du `mutableBsp`.
- Phase 4 bloque Phase 5 car la preview ne doit cibler que des fenêtres réellement gérées.
- Phase 6 dépend de Phase 3 pour distinguer action explicite et focus macOS transitoire.
- Phase 7 doit être partagée par tous les chemins qui cachent des fenêtres.
- Phase 9 dépend des filtres de visibilité déjà utilisés par le navrail.

## Validation

- Tests ciblés référencés dans les commits : `LayoutMaintainerTests`, `SnapshotServiceTests`, `DropPreviewEngineTests`, `DisplayParkingServiceTests`, `PowerUserDesktopCommandTests`, `TilingPolicyTests`.
- Build de référence dans les commits récents : `make build`.
- Validation runtime attendue : relancer Roadie, tester resize mutable BSP, drag/drop, fermeture fenêtre, popup système, stage switch visible et débranchement/rebranchement écran.
