# Plan d’implémentation — Spec 160 (Quick Wins WM & NavRail)

## Architecture et fichiers touchés

1. **`Sources/RoadieTiler/BSPTree.swift`** :
   - Ajouter `public enum BSPMirrorAxis: String, Codable, Equatable, Sendable { case x, y }`.
   - Ajouter `rotated90()`, `rotated(degrees:)` (`90`, `180`, `270`) et `mirrored(_ axis: BSPMirrorAxis)`.

2. **`Sources/RoadieAX/SystemSnapshotProvider.swift` & `Sources/RoadieDaemon/DaemonSnapshot.swift`** :
   - Ajouter `func close(_ window: WindowSnapshot) -> Bool` à `WindowFrameWriting` (défaut `false`), implémenté sur `AXWindowFrameWriter` via `press(kAXCloseButtonAttribute, of: window)`.
   - Exposer `func close(_ window: WindowSnapshot) -> Bool` sur `SnapshotService`.

3. **`Sources/RoadieDaemon/LayoutCommandService.swift`** :
   - Ajouter `rotate(_ degrees: Int) -> LayoutCommandResult` et `mirror(_ axis: String) -> LayoutCommandResult` via `treeCommand(...)`.

4. **`Sources/RoadieDaemon/WindowCommands.swift`** :
   - Ajouter `close(windowID: WindowID? = nil) -> WindowCommandResult`.
   - Ajouter `gatherApp(windowID: WindowID? = nil) -> WindowCommandResult` (transaction `stageStore.mutateChecked` + un seul `CommandPlacement`).

5. **`Sources/RoadieDaemon/StageCommands.swift` & `Sources/RoadieDaemon/DisplayCommands.swift`** :
   - Injecter `mouseFollower: MouseFollower = MouseFollower()` et appeler `mouseFollower.follow(window)` après un focus clavier réussi.

6. **`Sources/RoadieDaemon/StageCardView.swift`, `RailPanel.swift`, `RailController.swift`** :
   - Ajouter `hoveredAppIconWindowID`, `stageToolTip`, `updateHoveredAppIcon(at:)` et le rendu de mise en valeur dans `StageCardView.drawAppIconsRow()`.
   - Exposer `RailPanel.updateHoveredAppIcon(at screenPoint: CGPoint)` appelé depuis `RailController.updateRailHover()`.
   - Ajouter les actions `closeWindow`, `gatherAppWindows`, `rotateLayout`, `mirrorLayout` dans `RailAction` et les menus contextuels du rail.

7. **`Sources/RoadieDaemon/CLICommandRouter.swift` & `LauncherSystemCommands.swift`** :
   - Activer `window close`, ajouter `window gather-app`, `layout rotate 90|180|270`, `layout mirror x|y`.
   - Ajouter les commandes Lanceur (`roadie-window-close`, `roadie-window-gather-app`, `roadie-layout-rotate`, `roadie-layout-mirror-x`, `roadie-layout-mirror-y`).

8. **Tests & Documentation** :
   - Créer `Tests/RoadieDaemonTests/Spec160QuickWinsWMRailTests.swift` (couvrant BSPTree, LayoutCommandService, WindowCommands, MouseFollower, CLICommandRouter, StageCardView hover).
   - Mettre à jour `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md` et `.specify/memory/sessions/journal.md`.
