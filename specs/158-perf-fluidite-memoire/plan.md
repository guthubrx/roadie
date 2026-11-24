# Plan d’implémentation — Spec 158 (Performance, fluidité, mémoire et hygiène)

## Architecture et fichiers touchés

1. **`Sources/RoadieAX/SystemSnapshotProvider.swift`** :
   - Extraire le corps par PID de `AXWindowFrameWriter.setFrames(_:generation:isCurrent:)` dans une méthode privée `applyPIDGroup(...) -> [WindowID: CGRect?]`.
   - Retourner `[:]` immédiatement si `updates.isEmpty`.
   - Si `groups.count == 1`, exécuter directement `applyPIDGroup` sur le thread courant.
   - Si `groups.count > 1`, utiliser `DispatchQueue.concurrentPerform(iterations: groups.count)` avec un stockage de résultats protégé par `OSAllocatedUnfairLock`, puis fusionner dans le dictionnaire final.
   - Mettre à jour `SpyAXFrameIO` dans `Tests/RoadieAXTests/ReactiveTilingAXTests.swift` avec un `NSLock` pour garantir l’absence de data race sur les tests multi-PIDs.

2. **`Sources/RoadieDaemon/SharedAppIconCache.swift`** (nouveau) :
   - `@MainActor final class SharedAppIconCache` (`shared`, `maxCount = 64`).
   - Cache borné avec éviction progressive (quart le plus ancien) pour `cleanedIcons`, `fallbackCards` et cache de résolution `bundleID -> URL` (max 128).
   - `cleanEdgeWhiteBackground(of:)` en sRGB 64×64 avec pré-scan des 4 bords court-circuitant le BFS si aucun pixel blanc n’est présent sur le périmètre.

3. **`Sources/RoadieDaemon/StageCardView.swift` & `Sources/RoadieDaemon/RailPanel.swift` & `Sources/RoadieDaemon/RailThumbnailStore.swift`** :
   - Ajouter `update(...)` sur `StageCardView` et `RailHeaderView` en conservant des références vers `widthConstraint` et `heightConstraint`.
   - Faire passer `StageCardView.appIcon(for:)` et `RailThumbnailStore.fallbackIcon(for:)` par `SharedAppIconCache.shared`.
   - Dans `RailPanel.render(...)`, réutiliser les `StageCardView` existants par `StageID` et mettre à jour `RailHeaderView` et `FixedHeightSpacer` en place lorsque la structure est identique.
   - Dans `RailThumbnailStore.captureDragSource`, aligner le budget pixels sur `Self.sceneCapturePixelBudget`.

4. **`Sources/RoadieDaemon/OverviewWallpaper.swift`, `OverviewPanel.swift`, `OverviewController.swift`** :
   - Ajouter borne de cache (max 4 miniatures) et `OverviewWallpaper.purge()` (`thumbnails.removeAll()`, `blurredCache = nil`, `context.clearCaches()`), et `autoreleasepool` autour de la création `CGImage`.
   - Appeler `OverviewWallpaper.purge()` dans `OverviewController.hide()`.
   - Libérer `backdrop.layer?.contents`, `appliedBlur`, `canvas.images`, `canvas.icons`, `canvas.appIcons` à la fin de l’animation de fermeture dans `OverviewPanel.dismiss`.

5. **`Sources/RoadieDaemon/JSONPersistence.swift` & `CommandSocketServer.swift`** :
   - Réutiliser des instances statiques `JSONDecoder` et `JSONEncoder` sur les chemins par défaut.

6. **Hygiène compilation** :
   - Retirer `import RoadieCore` dans `Sources/RoadieCore/Config.swift`, `WindowSwitcherConfig.swift`, `WindowSwitcherPresentation.swift`.
   - Déplacer `func currentRailSettings()` hors de `private extension SnapshotService` dans `Sources/RoadieDaemon/DaemonSnapshot.swift`.

## Stratégie de vérification

- Nouveaux tests unitaires dédiés dans `Tests/RoadieDaemonTests/Spec158PerfMemoireTests.swift` et `Tests/RoadieAXTests/ReactiveTilingAXTests.swift` (parallélisme multi-PID prouvé par barrière de concurrence, réutilisation d’instances `StageCardView` dans `RailPanel.render`, nettoyage d’icônes avec et sans bord blanc, éviction progressive `SharedAppIconCache`, purge `OverviewWallpaper`).
- Exécution de la suite complète `./scripts/test --no-parallel` et `python3 -I -B -m unittest discover -s scripts/tests`.
- Revue indépendante Bridget jusqu’à `Approuvé`, puis livraison, installation signée et vérification santé 5/5.
