# Tâches — Spec 167

- [x] **T001** Corriger le débordement `.scrolling` multi-écrans (`clipsLeft`/`clipsRight`, topologie complète `allDisplays`, butée de geste `allowCrossDisplay: false`).
- [x] **T002** Corriger le premier placement pré-AX sur apps lentes (`schedulePreAXPlacementRetry`, `retryTrackedNonTreeScopes`, garde `reconcileStableVisibleDisplayDrift`).
- [x] **T003** Ajouter `LayoutTabSlots.swift` dans `RoadieTiler` et raccorder `LayoutRequest.tabGroups` / `LayoutPlanner` pour `scrolling`, `masterStack` et `bsp`.
- [x] **T004** Ajouter les mutations `stackTab`/`unstackTab`/`selectTab`/`cycleTab`/`reorderTab` sur `PersistentStageState` (`StageStore.swift`) et propager `tabGroups` dans `DaemonSnapshot.swift`.
- [x] **T005** Étendre `WindowCommands.swift` (`tabCycle`, `tabStack`, `tabUnstack`, `tabMove`, `tabReorder`, `availableTabStackDirections`, `activeAndNeighbor`, `focus(windowID:)`).
- [x] **T006** Étendre `StageTabBarController.swift`, `DropPreviewController.swift` et `TitlebarContextMenuController.swift` aux modes `scrolling`, `masterStack` et `bsp`.
- [x] **T007** Écrire les tests complets (`Spec167UniversalTabsTests.swift` + régression premier placement apps lentes), lancer la suite complète Swift + Python.
- [x] **T008** Installer build Release signé `roadied-cert`, redémarrer, vérifier santé 5/5 `ok`, mettre à jour docs/CHANGELOG/journal, commiter, pousser et nettoyer.
