# Diff des corrections (révision 0 -> 1)

```diff
--- /dev/fd/12	2026-10-18 19:34:22
+++ /dev/fd/13	2026-10-18 19:34:22
@@ -34,8 +34,10 @@
         lastRenderedSettings = nil
         lastConfigRefreshPath = nil
         lastConfigRefreshStamp = nil
+        // Watcher arrêté : un changement pendant l'arrêt ne serait jamais signalé (SPEC-048 C-02).
+        recordingStatusCache = nil
+        recordingStatusDirty = true
     }
 
     private func startWatchers() {
         configWatcher = RailFileWatcher(
-            path: { ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath() },
--- /dev/fd/12	2026-10-18 19:34:22
+++ specs/048-consommation-repos/plan.md	2026-10-18 19:14:27
@@ -4,9 +4,11 @@
 
 1. A-01 `Sources/RoadieDaemon/DaemonSnapshot.swift` : `SnapshotProcessState` garde une
    génération d'observation globale (`noteObservationChange()`), mémorisée à la
-   publication. `recentSnapshot(..., quietMaxAge:)` accepte un relevé plus ancien que
-   `maxAge` si la génération est inchangée et l'âge inférieur à `quietMaxAge`.
-   `readerSnapshot` passe `quietMaxAge = 1 s` ; `sharedSnapshot` garde 0.
+   publication. `recentSnapshot(..., allowQuietReuse:)` accepte un relevé plus ancien que
+   `maxAge` si la génération est inchangée et l'âge inférieur au plafond `quietReuseCap`.
+   `readerSnapshot` passe `allowQuietReuse: true` ; `sharedSnapshot` garde la règle des 150 ms.
+   Le plafond vaut 0 tant que le tiler ne l'active pas (`enableQuietReaderReuse`, événements en
+   direct seulement) ; il est égal au filet du tiler, 2 s par défaut (revue du plan, ADR 015).
    L'acquisition lecteur capture la génération à son départ.
    `Sources/RoadieDaemon/TickScheduler.swift` : `request` appelle `noteObservationChange()`
    pour toute demande hors filet de sécurité.
--- /dev/fd/12	2026-10-18 19:34:22
+++ specs/048-consommation-repos/tasks.md	2026-10-18 19:14:29
@@ -1,7 +1,7 @@
 # Tâches
 
 - [x] T001 Mesurer l'état de départ au repos (`mesures/avant.json`).
-- [x] T002 Tests rouges A-01 : relevé lecteur réutilisé sans changement jusqu'à 1 s, refusé après un changement ou au-delà de 1 s ; commandes inchangées à 150 ms ; demande de passe hors filet incrémente la génération (`Tests/RoadieDaemonTests/Spec048QuietReaderTests.swift`).
+- [x] T002 Tests rouges A-01 : relevé lecteur réutilisé sans changement jusqu'au filet (1 s dans la version initiale, 2 s après revue, ADR 015), refusé après un changement ou au-delà du filet ; commandes inchangées à 150 ms ; demande de passe hors filet incrémente la génération (`Tests/RoadieDaemonTests/Spec048QuietReaderTests.swift`).
 - [x] T003 Implémenter A-01 dans `Sources/RoadieDaemon/DaemonSnapshot.swift` et `Sources/RoadieDaemon/TickScheduler.swift`.
 - [x] T004 Tests puis implémentation C-01 : énumération seulement si un identifiant manque (`Sources/RoadieDaemon/RailThumbnailStore.swift`).
 - [x] T005 Implémenter C-02 : statut d'enregistrement mémorisé (`Sources/RoadieDaemon/RailController.swift`).
```
