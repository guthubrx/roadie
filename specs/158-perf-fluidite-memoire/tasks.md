# Tâches — Spec 158 (Performance, fluidité, mémoire et hygiène)

- [x] T001 — Auditer les chemins chauds (`AXWindowFrameWriter.setFrames`, `RailPanel.render`, `StageCardView`, `RailThumbnailStore`, `OverviewWallpaper`, `JSONPersistence`, `CommandSocketServer`) et recenser les avertissements du compilateur.
- [x] T002 — Paralléliser `AXWindowFrameWriter.setFrames` par PID distinct (`DispatchQueue.concurrentPerform`) et sécuriser `SpyAXFrameIO` avec un verrou dans les tests AX.
- [x] T003 — Créer `SharedAppIconCache` avec cache borné à éviction progressive et court-circuit BFS, puis brancher `StageCardView` et `RailThumbnailStore`.
- [x] T004 — Ajouter `update(...)` sur `StageCardView`, `RailHeaderView` et `FixedHeightSpacer`, et réutiliser les vues en place dans `RailPanel.render(...)`.
- [x] T005 — Ajouter `OverviewWallpaper.purge()` + borne de cache, purger dans `OverviewController.hide()` et libérer les images dans `OverviewPanel.dismiss`, et aligner `captureDragSource` sur `sceneCapturePixelBudget`.
- [x] T006 — Réutiliser des instances statiques `JSONEncoder`/`JSONDecoder` dans `JSONPersistence` et `CommandSocketServer`.
- [x] T007 — Corriger les 4 avertissements de compilation (`RoadieCore` × 3, `DaemonSnapshot.swift`).
- [x] T008 — Exécuter les suites Swift et Python complètes, passer la revue Bridget, documenter la session 176 et livrer.
