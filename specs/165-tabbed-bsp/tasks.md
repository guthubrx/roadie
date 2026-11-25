# Tasks: Spec 165 — Tabbed BSP (`spatialBsp`)

## Lot A — Noyau `BSPTree.tabGroup` (`RoadieTiler` & `StageProjects`)
- [x] T001 Ajouter `BSPTabBarPlacement` et `BSPTree.tabGroup(windowIDs:active:)` avec normalisation, `Codable` rétrocompatible, `place(tabBarHeight:)`, `tabBarFrames(...)`, `SizedTree` et opérations pures (`stacking`, `unstacking`, `selectingTab`, `cyclingTab`, `reorderingTab`, `tabGroup(containing:)`, `tabGroups`, `activeWindowIDs`) dans `Sources/RoadieTiler/BSPTree.swift`.
- [x] T002 Mettre à jour `SpatialBSPLayoutStrategy.swift`, `BSPDivider.swift`, `BSPNativeResize.swift`, et `StageProjects.swift` pour supporter `.tabGroup`.
- [x] T003 Écrire les tests unitaires complets dans `Tests/RoadieTilerTests/Spec165TabbedBSPTreeTests.swift` et vérifier la compilation + exécution verte.

## Lot B — Daemon, Réconciliation & Multi-barres `StageTabBarController`
- [x] T004 Mettre à jour `DaemonSnapshot.swift` (`reconciledTree` sync `active`) et `WindowCommands.swift` (`CommandTreeGeometry.tabBarHeight`, `tabBarFrames`, `treeNeighbor` sur `activeWindowIDs`, `focus(windowID:)` sync `active`, et commandes `tabCycle`, `tabStack`, `tabUnstack`, `tabMove`, `tabReorder`).
- [x] T005 Généraliser `StageTabBarController.swift` (`barID`, `isTileGroup`, multi-barres `spatialBsp`, glisser horizontal de réordonnancement dans la barre, et glisser-sortir d'un onglet vers `DropPreviewController` pour le détacher en tuile BSP).

## Lot C — Empilement intuitif par glisser-déposer (`DropPreviewController`)
- [x] T006 Ajouter `DropPreviewOperation.stackTab`, détection sur `barFrame` ou centre + `⌥ Option`, gestion drag-out sur propre tuile, aperçu visuel dédié avec bandeau barre d'onglets et libellés FR/EN, réactivité temps réel à `⌥ Option` (`.flagsChanged`), et focus post-dépôt dans `Sources/RoadieDaemon/DropPreviewController.swift`.

## Lot D — CLI, Lanceur, Menu barre de titre, Tests Daemon & Documentation
- [x] T007 Exposer `roadie tab next|prev|stack|unstack|move` dans `CLICommandRouter.swift` (aide + complétion shell), ajouter les commandes dans `LauncherSystemCommands.swift` et le sous-menu « Onglets » dans `TitlebarContextMenuController.swift` / `WindowContextActions.swift`.
- [x] T008 Écrire les tests d'intégration daemon dans `Tests/RoadieDaemonTests/Spec165TabbedBSPDaemonTests.swift`.
- [x] T009 Mettre à jour la documentation FR & EN (`README.md`, `README.fr.md`, `docs/{fr,en}/{cli,features,use-cases}.md`) sans élision.

## Vérification, Revue & Livraison
- [x] T010 Exécuter la suite complète (`./scripts/test --no-parallel`, tests Python, `git diff --check`).
- [x] T011 Lancer la revue indépendante Bridget, corriger tous les constats jusqu'à `Approuvé`, puis accuser réception (`bridget_task_ack`).
- [x] T012 Fusionner `--ff-only` dans `main`, mettre à jour `.specify/memory/sessions/journal.md`, pousser `origin/main`, installer signé (`make install`), redémarrer, vérifier santé 5/5 `ok`, et effectuer le nettoyage obligatoire (worktree, branche, `.build`).
