# Plan — Spec 167 : Onglets universels par slot & premier placement apps lentes

## Découpage architectural

1. **Lot A — Premier placement apps lentes (`Sources/RoadieDaemon/LayoutMaintainer.swift`)**
   - `schedulePreAXPlacementRetry(for:now:)` appelé dans `recordTransition` et `applyPass` sur échec pré-AX (`writtenFrames.entry == nil`).
   - `unreadyPlacementScopes` inclut `retryTrackedNonTreeScopes` (scopes tuilés non-arbre contenant une fenêtre en `preAXFailedTransitionWindows` ou `unreadyPlacementWindows`).
   - `reconcileStableVisibleDisplayDrift` exclut toute fenêtre encore en `preAXFailedTransitionWindows` ou `unreadyPlacementWindows`.

2. **Lot B — Moteur de slots à onglets pur (`Sources/RoadieTiler/`)**
   - Nouveau fichier `Sources/RoadieTiler/LayoutTabSlots.swift` :
     - `LayoutTabGroup` (`windowIDs: [WindowID]`, `activeWindowID: WindowID?`).
     - `LayoutTabSlot` (ancre + `windowIDs` + `activeWindowID` + `isTabGroup`).
     - `LayoutTabBarPlacement` (ou réutilisation de `BSPTabBarPlacement` / alias commun).
     - `LayoutTabSlots.resolve(windowIDs:tabGroups:focusedWindowID:)` : déduplication, repli `< 2 → simple`, conservation de l’ordre des slots.
     - `LayoutTabSlots.plan(_:using:)` : délègue les représentants à la stratégie (`ScrollingLayoutStrategy`, `MasterStackLayoutStrategy`, `BSPLayoutStrategy`), puis applique la réserve `tabBarHeight + 4 pt` aux groupes ≥ 2.
     - `LayoutTabSlots.tabBarFrames(for:)` : retourne les cadres exacts de barre d’onglets (`barFrame`, `tileFrame`, `windowIDs`, `active`).
   - `Sources/RoadieTiler/LayoutTypes.swift` : ajout de `tabGroups: [LayoutTabGroup] = []` dans `LayoutRequest`, et routage de `.scrolling`, `.masterStack`, `.bsp` via `LayoutTabSlots.plan(...)` quand `!request.tabGroups.isEmpty`.

3. **Lot C — Persistance & synchronisation (`Sources/RoadieDaemon/StageStore.swift`, `DaemonSnapshot.swift`)**
   - Méthodes pures sur `PersistentStageState` pour manipuler `PersistentStage.groups` (`presentation == "tabbed"`) :
     - `tabbedGroups(for:)`, `tabbedGroup(containing:in:)`, `stackTab(_:onto:in:)`, `unstackTab(_:direction:in:)`, `selectTab(_:in:)`, `cycleTab(from:delta:liveWindowIDs:in:)`, `reorderTab(_:delta:in:)`, `reorderTab(_:toIndex:in:)`.
   - `WindowManagementMode.supportsSlotTabGroups` (`.scrolling`, `.masterStack`, `.bsp`) et `supportsTileTabGroups` (`usesTreeEngine || supportsSlotTabGroups`).
   - `DaemonSnapshot.swift` : propagation de `stage.groups` dans `LayoutRequest.tabGroups` (y compris pour `layoutPlan` et `previewPlacements`) + synchro de `activeWindowID` au changement de focus.

4. **Lot D — Commandes, UI barres d’onglets, Drag & Drop et menu clic droit**
   - `Sources/RoadieDaemon/WindowCommands.swift` :
     - `activeAndNeighbor` : navigation entre slots (saute les onglets inactifs des autres slots en `.scrolling`, `.masterStack`, `.bsp`).
     - `focus(windowID:)` : synchronise `selectTab` pour `supportsSlotTabGroups`.
     - `tabCycle`, `tabStack`, `tabUnstack`, `tabMove`, `tabReorder`, `availableTabStackDirections` : branche `supportsSlotTabGroups` (réapplique le plan + recentrage fluide en `.scrolling`).
   - `Sources/RoadieDaemon/StageTabBarController.swift` : branche `supportsSlotTabGroups` utilisant `LayoutTabSlots.tabBarFrames(...)` avec topologie complète `scrollingClipEdges`.
   - `Sources/RoadieDaemon/DropPreviewController.swift` : détection `.stackTab` (`⌥ Option` au centre ou dépôt sur barre existante) + commit `stackTab` / `unstackTab` pour `supportsSlotTabGroups`.
   - `Sources/RoadieDaemon/TitlebarContextMenuController.swift` : sous-menu **Onglets** étendu à `supportsTileTabGroups`.

5. **Lot E — Tests, validation, docs & livraison**
   - Tests unitaires & intégration dans `Tests/RoadieDaemonTests/Spec167UniversalTabsTests.swift` + tests multi-écrans & premier placement dans `Spec164TabbedScrollingTests.swift`.
   - Suite complète `./scripts/test --no-parallel`, `python3 -I -B -m unittest discover -s scripts/tests`, `make install`, `make restart`, vérification signature `roadied-cert` & santé 5/5 `ok`, mise à jour docs/changelog/journal, commit/push `main`, nettoyage `.build/`.
