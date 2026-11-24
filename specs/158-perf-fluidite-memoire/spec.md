# Spec 158 — Performance, fluidité, mémoire et hygiène de compilation

## Contexte

L’audit complet du dépôt et de la télémétrie en production (`events.jsonl` + `vmmap` sur `roadied` actif) a identifié cinq leviers concrets d’optimisation sans changement de comportement fonctionnel :

1. **Écritures AX séquentielles inter-applications** : `AXWindowFrameWriter.setFrames(_:generation:isCurrent:)` traite chaque `pid` séquentiellement. Sur une bascule de stage contenant 3 applications distinctes, les allers-retours IPC Accessibility s’additionnent (`layoutMs` jusqu’à 181 ms).
2. **Reconstruction complète du NavRail à chaque rendu et duplication du cache d’icônes** : `RailPanel.render(...)` détruit et recrée l’intégralité des vues `StageCardView` et `RailHeaderView` ainsi que leurs contraintes AutoLayout à chaque rafraîchissement. Parallèlement, `StageCardView` et `RailThumbnailStore` maintiennent des caches d’icônes séparés avec traitement pixel-par-pixel synchrone sur `@MainActor` même pour les icônes à bords déjà transparents.
3. **Mémoire graphique conservée après fermeture d’Overview** : `OverviewWallpaper` conserve ses miniatures `CGImage`, son image floutée et les tampons internes de son `CIContext` Metal indéfiniment après `OverviewController.hide()`. `OverviewPanel` conserve également ses images en mémoire jusqu’à la prochaine ouverture. `RailThumbnailStore.captureDragSource` utilise encore un budget de 2 Mpx contre 1,2 Mpx pour `captureScene`.
4. **Allocations répétées de `JSONEncoder` / `JSONDecoder`** sur les chemins chauds (`JSONPersistence` et `CommandSocketServer`/`CommandSocketClient`), alors que `EventLog` réutilise déjà des instances statiques.
5. **Avertissements du compilateur Swift** : 3 `import RoadieCore` redondants dans `Sources/RoadieCore/` et un modificateur `internal` dans une `private extension SnapshotService` de `DaemonSnapshot.swift`.

## Exigences fonctionnelles et techniques

- **FR-001 (Parallélisation AX par PID)** : `AXWindowFrameWriter.setFrames(_:generation:isCurrent:)` exécute les groupes de fenêtres appartenant à des `pid` distincts en parallèle lorsque `groups.count > 1`, tout en préservant :
  - l’ordre séquentiel strict des mises à jour au sein d’un même `pid` ;
  - le cycle `AXEnhancedUserInterface` (lecture, désactivation, restauration) par `pid` ;
  - la vérification d’annulation `isCurrent()` et les garanties de thread-safety de `AXWindowIndexCache`, `WrittenFrameRegistry`, `AXUnresponsiveApps` et `AXFrameIO` ;
  - l’exécution directe sans surcoût lorsqu’un lot ne concerne qu’un seul `pid` ou est vide.
- **FR-002 (Cache d’icônes unifié `SharedAppIconCache`)** : Un cache `@MainActor` borné (64 entrées avec éviction partielle des plus anciennes entrées au lieu d’un vidage total brutal) unifie les icônes nettoyées de `StageCardView` et les cartes de repli de `RailThumbnailStore`, détache les bitmaps en sRGB et évite l’allocation/parcours BFS lorsque aucun pixel du bord de l’icône n’est blanc.
- **FR-003 (Réutilisation en place des vues du NavRail)** : `RailPanel.render(...)` met à jour en place les `StageCardView` et `RailHeaderView` existants lorsque la structure de stages/en-tête correspond, et réutilise les cartes par `StageID` lors d’une réorganisation, afin d’éliminer les destructions/recréations répétées de hiérarchie AppKit.
- **FR-004 (Purge mémoire graphique Overview & captures)** : `OverviewWallpaper.purge()` libère `thumbnails`, `blurredCache` et appelle `CIContext.clearCaches()` à la fermeture dans `OverviewController.hide()`. Les miniatures de `OverviewWallpaper` sont bornées (max 4 entrées). `OverviewPanel.dismiss` libère les références d’images (`backdrop.layer?.contents`, `canvas.images`, `canvas.icons`, `canvas.appIcons`) dès la fin du fondu de fermeture. `RailThumbnailStore.captureDragSource` s’aligne sur `sceneCapturePixelBudget` (`1_200_000`).
- **FR-005 (Réutilisation JSON sur les chemins chauds)** : `JSONPersistence` et `CommandSocketServer`/`CommandSocketClient` réutilisent des instances statiques de `JSONEncoder` / `JSONDecoder` sur leurs chemins par défaut, sans altérer aucun contrat d’encodage/décodage ni de concurrence.
- **FR-006 (Hygiène de compilation)** : Suppression des 3 `import RoadieCore` redondants et correction de `currentRailSettings()` hors de `private extension SnapshotService` pour 0 avertissement sur ces fichiers.

## Critères d’acceptation

- `setFrames` sur 2+ PIDs parallèles s’exécute de façon concurrente et produit le même dictionnaire de résultats que l’exécution séquentielle, sans data race ni violation du budget de génération.
- `RailPanel.render` sur un ensemble inchangé de stages conserve exactement les mêmes instances `StageCardView` (`ObjectIdentifier`) tout en mettant à jour état actif, libellé, vignettes et hauteur.
- `SharedAppIconCache` préserve la suppression du cadre blanc de bord, évite le BFS pour les icônes à bord transparent et évince progressivement au-delà de sa limite.
- `OverviewWallpaper.purge()` vide ses caches et libère les tampons CoreImage sans erreur lors des réouvertures suivantes.
- 0 régression sur les suites complètes Swift (`./scripts/test --no-parallel`) et Python (`unittest`).
