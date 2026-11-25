# Implementation Plan: Spec 165 — Tabbed BSP (`spatialBsp`)

**Branch**: `feat/165-tabbed-bsp` | **Date**: 2026-11-25 | **Spec**: `specs/165-tabbed-bsp/spec.md`

---

## Architecture & Découpage par couches

### Lot A — Noyau géométrique & arbre (`RoadieTiler` + `StageProjects`)

1. **`Sources/RoadieTiler/BSPTree.swift`**
   - Ajouter `public struct BSPTabBarPlacement: Equatable, Sendable { public let windowIDs: [WindowID]; public let active: WindowID; public let barFrame: CGRect; public let tileFrame: CGRect }`.
   - Ajouter `case tabGroup(windowIDs: [WindowID], active: WindowID)` à `BSPTree`.
   - Helper interne de normalisation `BSPTree.normalizedTabGroup(_ ids: [WindowID], active: WindowID?) -> BSPTree` (0 → `.empty`, 1 → `.leaf`, dédoublonnage ordonné, fallback `active = deduped[0]`).
   - Constante partagée `BSPTree.tabBarGap: CGFloat = 4` et `BSPTree.minimumContentHeightForTabBar: CGFloat = 120`.
   - Mettre à jour `place(in:innerGap:tabBarHeight:minimumSizes:)` (défaut `tabBarHeight: CGFloat = 0` pour compatibilité source 100 %) et ajouter `tabBarFrames(in:innerGap:tabBarHeight:minimumSizes:) -> [BSPTabBarPlacement]`.
   - Mettre à jour `SizedTree` pour calculer le minimum d'un `.tabGroup` (largeur max des membres, hauteur max des membres + hauteur de barre réservée si applicable).
   - Mettre à jour toutes les méthodes existantes de `BSPTree` pour gérer `.tabGroup` sans perte d'invariant :
     - `windowIDs`, `contains`, `projected(excluding:)`, `removing(_:)`, `inserting(_:nextTo:side:containerIsWide:)`, `replacingLeaf`, `swapping`, `relabelling`, `collectSplits`, `adoptingSplits`, `balanced`, `togglingSplit`, `settingSplit`, `adjustingFence`, `correctingForMinimumSize`, `ancestors(of:)`, `rotated90`, `mirrored`.
     - Note importante sur `inserting(_ window:, nextTo target:, ...)` : lorsque `target` appartient à un `.tabGroup`, on découpe la **tuile entière** du `.tabGroup` (en plaçant `.split(..., tabGroup, .leaf(window))`), et non en détruisant le groupe !
     - Note sur `swapping(a, b)` : si `a` et `b` sont dans le même `.tabGroup`, permuter leurs positions dans `windowIDs` ; sinon `relabelling` échange leurs emplacements respectifs en mettant à jour `active` proprement.
   - Ajouter les opérations pures d'onglets :
     - `stacking(_ source: WindowID, onto target: WindowID) -> BSPTree`
     - `unstacking(_ window: WindowID, side: BSPInsertionSide, containerIsWide: Bool) -> BSPTree`
     - `unstacking(_ window: WindowID, side: BSPInsertionSide, in container: CGRect, innerGap: CGFloat, excluding absent: Set<WindowID>) -> BSPTree`
     - `selectingTab(_ window: WindowID) -> BSPTree`
     - `cyclingTab(from window: WindowID, delta: Int) -> (tree: BSPTree, nextActive: WindowID)?`
     - `reorderingTab(_ window: WindowID, delta: Int) -> BSPTree`
     - `reorderingTab(_ window: WindowID, toIndex: Int) -> BSPTree`
     - `tabGroup(containing window: WindowID) -> (windowIDs: [WindowID], active: WindowID)?`
     - `tabGroups: [(windowIDs: [WindowID], active: WindowID)]`
     - `activeWindowIDs: Set<WindowID>` (pour chaque `.leaf(id)` → `id`, pour chaque `.tabGroup(_, active)` → `active`).

2. **`Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift`**
   - Passer `tabBarHeight: CGFloat(request.tabbedBarHeight)` à `tree.place(in: rect, innerGap: gap, tabBarHeight: CGFloat(request.tabbedBarHeight), minimumSizes: request.minimumSizes)`.

3. **`Sources/RoadieTiler/BSPDivider.swift` & `Sources/RoadieTiler/BSPNativeResize.swift`**
   - `BSPDividerNode`: traiter `.tabGroup(let ids, _)` comme visible dès qu'au moins un id n'est pas dans `absent`.
   - `BSPNativeResize`: ajouter un cas `.tabGroup([WindowID], WindowID, CGSize)` à `Node` (toutes les fenêtres visibles du groupe reçoivent la même frame de contenu, minimum agrégé avec barre réservée si ≥ 2 visibles, et la tuile entière réagit au resize natif de son onglet actif).

4. **`Sources/RoadieDaemon/StageProjects.swift`**
   - `StageProject.renamed`: gérer `.tabGroup(let ids, let active)` en renommant les membres présents et en normalisant.

### Lot B — Réconciliation daemon, `CommandTreeGeometry` et multi-barres `StageTabBarController`

5. **`Sources/RoadieDaemon/DaemonSnapshot.swift`**
   - Dans `reconciledTree(...)` : après réconciliation des feuilles, si `focus = globalFocus ?? stage.focusedWindowID` appartient à un `.tabGroup`, synchroniser `tree = tree.selectingTab(focus)`.
   - Dans `treeApplyPlan` / `layoutPlan`: déjà alimenté par `config.tiling.tabbedBarHeight` via `LayoutRequest`.

6. **`Sources/RoadieDaemon/WindowCommands.swift`**
   - `CommandTreeGeometry`: ajouter `var tabBarHeight: CGFloat = 0`, le propager dans `frames(of:)` et exposer `tabBarFrames(of:) -> [BSPTabBarPlacement]`.
   - `SnapshotService.commandTreeGeometry(for:tree:in:)`: renseigner `tabBarHeight: CGFloat(config.tiling.tabbedBarHeight)`.
   - `treeNeighbor(of:direction:frames:activeIDs:)`: filtrer les candidats par `activeIDs` afin que `focus <dir>`, `move`, `warp`, `tab stack` ciblent toujours l'onglet actif d'une tuile voisine et ne soient jamais piégés par les co-onglets.
   - Synchroniser `stage.bspTree = tree.selectingTab(windowID)` dans `focus(windowID:)` lorsqu'une fenêtre d'un `.tabGroup` est focalisée.
   - Ajouter les méthodes de commande d'onglets sur `WindowCommandService` :
     - `tabCycle(delta: Int) -> WindowCommandResult` (fonctionne sur `.tabGroup` en `spatialBsp` ET en mode `.tabbed` global !)
     - `tabStack(direction: Direction) -> WindowCommandResult`
     - `tabUnstack(direction: Direction?) -> WindowCommandResult`
     - `tabMove(delta: Int) -> WindowCommandResult`
     - `tabReorder(windowID: WindowID, toIndex: Int) -> WindowCommandResult` (pour le drag horizontal dans la barre).

7. **`Sources/RoadieDaemon/StageTabBarController.swift`**
   - Étendre `StageTabBarTarget` avec `barID: String` (défaut compatible `"\(scope.description)#stage"`) et `isTileGroup: Bool` (défaut `false`).
   - Dans `computeTargets(...)`:
     - Conserver la génération pour `stage.mode == .tabbed` (`barID: "\(activeScope.description)#stage"`, `isTileGroup: false`).
     - Ajouter la génération pour `stage.mode.usesTreeEngine`: projeter l'arbre sur les fenêtres vivantes du scope, appeler `projected.tabBarFrames(in: container, innerGap: CGFloat(config.tiling.gapsInner), tabBarHeight: CGFloat(config.tiling.tabbedBarHeight))`, et émettre un `StageTabBarTarget` par `.tabGroup` (≥ 2 fenêtres vivantes), avec `barID: "\(activeScope.description)#tile-\(placement.windowIDs.map(\.rawValue).min() ?? 0)"` et `isTileGroup: true`.
   - `StageTabBarPanelPool`: indexer les panneaux par `String` (`target.barID`) au lieu de `StageScope` afin d'afficher simultanément plusieurs barres d'onglets dans une même stage `spatialBsp`.
   - Interaction avancée dans `StageTabBarPanel` (sous-classe `DraggableTabButton: NSView`) :
     - Clic (`dist < 6 pt`) → `onSelect(tab.windowID)`.
     - Drag horizontal dans la barre (`abs(dy) < 26 pt` et dans la largeur étendue de la barre) → calcul de l'index cible, surbrillance visuelle d'insertion, et appel `onReorder(tab.windowID, targetIndex)` au relâchement (pour les tuiles `.tabGroup` et même en mode `.tabbed`).
     - Drag **hors** de la barre (pour `isTileGroup == true`) → démarre une session `DropPreviewController` via `onTabDragBegin` / `onTabDragMove` / `onTabDragEnd` / `onTabDragCancel`, qui affiche l'aperçu de dépôt BSP en direct et exécute `StageCommandService.place(...)` + focus de la fenêtre détachée au relâchement !

### Lot C — Empilement par glisser-déposer (`DropPreviewController`)

8. **`Sources/RoadieDaemon/DropPreviewController.swift`**
   - Ajouter `case stackTab` à `DropPreviewOperation` :
     - `applied(to:source:target:)` → `tree.stacking(source, onto: target)`.
     - `tint` → `NSColor.systemTeal`.
   - Ajouter `optionHeld: Bool? = nil` (défaut `nil` → lit `NSEvent.modifierFlags.contains(.option)` en runtime, injectable dans les tests) à `DropPreviewEngine.candidate(...)` et `treeCandidate(...)`.
   - Dans `treeCandidate(...)`:
     1. Vérifier d'abord si `axPoint` tombe dans une `barFrame` de `currentGeometry?.tabBarFrames(of: tree)` dont les membres ne contiennent pas `sourceWindowID` (ou contiennent d'autres fenêtres distinctes) → propose `.stackTab` ciblant `placement.active`, avec la frame de prévisualisation égale à la tuile complète `placement.tileFrame` (ou `placements[sourceWindowID]`).
     2. Filtrer les fenêtres cibles de `currentFrames` aux onglets actifs (ou aux fenêtres hors `sourceWindowID`, en privilégiant l'onglet actif d'une tuile). Si `sourceWindowID` et `target.key` appartiennent déjà au **même** `.tabGroup` (cas du drag-out sur sa propre tuile) : autoriser les 4 bords (`insertLeft/Right/Up/Down`) pour détacher en tuile à côté, mais retourner `nil` au centre (annulation propre au lieu d'un swap/stack sur soi-même).
     3. Sinon, si `optionHeld` est vrai et le pointeur est dans la zone centrale (`!isEdge`), retourner `.stackTab` au lieu de `.swap` !
   - Dans `DropPreviewOverlayWindow` / `DropPreviewOverlayView`:
     - Pour `.stackTab` : dessiner une bande supérieure stylisée (simulateur de mini barre d'onglets) + badge centré lisible (« Empiler en onglet » / « Stack as tab »).
     - Pour `.swap` en mode arbre (`isTreeMode`): afficher un badge discret « Échanger · ⌥ Onglet » / « Swap · ⌥ Tab » pour rendre le raccourci immédiatement découvrable.
   - Dans `WindowDragReorderController.handleMouseUp`: lorsque `candidate.operation == .stackTab` (ou après un drag-out d'onglet), focaliser `candidate.sourceWindowID` après `commandService.place(...)` pour que l'onglet nouvellement empilé/détaché apparaisse immédiatement au premier plan !
   - Bonus `WindowDragReorderController.capture`: écouter aussi `.flagsChanged` pendant un drag actif (`owned` ou `pending?.didDrag`) pour que presser ou relâcher `⌥ Option` sans bouger la souris mette à jour l'aperçu immédiatement en temps réel !

### Lot D — CLI, Lanceur, Menu barre de titre, Complétion & Documentation

9. **CLI (`Sources/RoadieDaemon/CLICommandRouter.swift` + complétion shell)**
   - Ajouter la commande `tab` :
     - `roadie tab next`
     - `roadie tab prev`
     - `roadie tab stack <left|right|up|down>`
     - `roadie tab unstack [left|right|up|down]`
     - `roadie tab move <left|right>`
   - Ajouter l'entrée dans `CLICommandSpec` (aide) et dans la complétion zsh/bash/fish (`CLICompletionGenerator` ou équivalent).

10. **Lanceur (`Sources/RoadieDaemon/LauncherSystemCommands.swift`)**
    - Ajouter les commandes système Roadie :
      - `roadie-tab-next` (« Onglet suivant » / « Next tab »)
      - `roadie-tab-prev` (« Onglet précédent » / « Previous tab »)
      - `roadie-tab-stack-left/right/up/down` (« Empiler en onglet à gauche/droite/haut/bas »)
      - `roadie-tab-unstack` (« Détacher l'onglet en tuile » / « Detach tab to tile »)

11. **Menu contextuel barre de titre (`TitlebarContextMenuController.swift` + `WindowContextActions.swift`)**
    - Ajouter `WindowContextActionKind`: `.tabStack`, `.tabUnstack`.
    - Dans `TitlebarContextMenuController.buildMenu`, si la fenêtre est dans une stage `usesTreeEngine`, ajouter un sous-menu « Onglets » / « Tabs » :
      - « Empiler dans la tuile de gauche / droite / haut / bas » (uniquement pour les directions où une voisine existe),
      - « Détacher cet onglet en tuile » (uniquement si la fenêtre appartient à un `.tabGroup`).

12. **Documentation FR & EN & Journal**
    - Mettre à jour `README.md`, `README.fr.md`, `docs/fr/{cli,features,use-cases}.md`, `docs/en/{cli,features,use-cases}.md`, et ajouter le bilan de session dans `.specify/memory/sessions/journal.md`.

---

## Plan de tests (TDD strict)

1. `Tests/RoadieTilerTests/Spec165TabbedBSPTreeTests.swift` :
   - Normalisation, `Codable` rétrocompatible et round-trip `.tabGroup`.
   - `place(tabBarHeight:)` & `tabBarFrames` (géométrie exacte, plancher hauteur 120 pt, arbre sans tabGroup inchangé).
   - `stacking`, `unstacking`, `selectingTab`, `cyclingTab`, `reorderingTab`, `removing` (repli 2→1 et conservation 3→2 + choix d'onglet adjacent), `projected(excluding:)`, `inserting(nextTo:)`, `swapping`, `rotated90`, `mirrored`, `balanced`, `SizedTree`.
   - `BSPDivider` + `movingDivider` + `BSPNativeResize` sur arbre contenant `.tabGroup`.
   - `SpatialBSPLayoutStrategy.plan` avec `tabbedBarHeight`.
2. `Tests/RoadieDaemonTests/Spec165TabbedBSPDaemonTests.swift` :
   - `StageProject.capture` + `tree(for:)` avec `.tabGroup`.
   - `SnapshotService.reconciledTree` synchronisation de `active` + fermeture/repli.
   - `DropPreviewEngine` : `.stackTab` avec `optionHeld: true` au centre, `.swap` avec `optionHeld: false` au centre, `.stackTab` en déposant sur une `barFrame` sans Option, drag-out d'un onglet sur le bord de sa propre tuile (`.insertRight`) et annulation au centre de sa propre tuile (`nil`).
   - `StageTabBarController.computeTargets` : multi-barres simultanées en `spatialBsp` (zéro barre pour `.leaf`, une barre par `.tabGroup` ≥ 2), coexistence avec mode `.tabbed` global sur un autre écran.
   - `WindowCommandService` : `focus` non piégé (atterrit sur l'onglet actif de la voisine), `tabCycle`, `tabStack`, `tabUnstack`, `tabMove`, `tabReorder`.
   - `CLICommandRouter` : `roadie tab next|prev|stack|unstack|move` + erreurs d'usage.
   - `LauncherSystemCommands` & `WindowContextActions` (`.tabStack`, `.tabUnstack`).
