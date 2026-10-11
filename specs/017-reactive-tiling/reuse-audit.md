# Audit de réutilisation : Tiling réactif façon yabai

**Date** : 2026-10-11
**Statut** : OK
**Méthode** : audit manuel, car aucune primitive `speckit-audit-existing` n'existe dans `.agents/skills`. Pour chaque élément du plan : une recherche `rg` par nom et une par responsabilité dans `Sources/`, plus la lecture des specs 013, 014 et 016.

## Éléments du plan

| Élément proposé | Existant trouvé | Décision | Preuve |
|---|---|---|---|
| Moteur à arbre | `BSPTree`, `SpatialBSPLayoutStrategy` (SPEC-013/014) | RÉUTILISER, étendre | `Sources/RoadieTiler/BSPTree.swift:30-303` |
| Migration de l'arbre depuis la géométrie | logique de coupes `splitHorizontally` et `splitRatio` | RÉUTILISER (déplacée dans `BSPTree.inferred`) | `Sources/RoadieTiler/MutableBSPLayoutStrategy.swift:94-207` |
| Alias de mode | `WindowManagementMode` (le parsing accepte déjà `yabai`) | RÉUTILISER, étendre le décodage | `Sources/RoadieCore/WindowManagementMode.swift`, `SpatialBSPConfigTests.swift:65` |
| `TickScheduler` | logique ad hoc `pendingLiveTick`, coalescence 15/80 ms, règle des 200 ms | CRÉER en remplacement (le code ad hoc est supprimé) | `Sources/roadied/main.swift:320-356` |
| `WrittenFrameRegistry` | `lastObservedFrames` (relecture locale au maintainer), `revertedAppliedFrames` | CRÉER. L'existant est local au maintainer, alimenté par la relecture, et invisible des commandes CLI. Au moins 3 usages : écrivain AX, maintainer, commandes | `LayoutMaintainer.swift:53, 452, 1338-1347` |
| Signature de fichier pour le cache d'état | `fileModificationStamp` (mtime et taille) | RÉUTILISER, ajouter l'inode | `Sources/RoadieDaemon/ConfigReloadService.swift:273` |
| Cache de l'état persisté | aucun cache dans `JSONPersistence` ; `RailSettings.load` utilise un tampon | RÉUTILISER le modèle de `RailSettings` dans `JSONPersistence` | `Sources/RoadieDaemon/RailSettings.swift:123-135` |
| Snapshot partagé republié | `publish`, `recentSnapshot` avec `stateStamp` | RÉUTILISER : republier au lieu d'invalider | `Sources/RoadieDaemon/DaemonSnapshot.swift:1929-1936, 1607` |
| Dernier clic de souris | `UserInputActivity` (moniteur global, `lastInputAt`) | RÉUTILISER, étendre (mouseUp, lastMouseDownAt) | `Sources/RoadieDaemon/FocusFollowsMouseController.swift:64-87` |
| Bouton de souris enfoncé | `NSEvent.pressedMouseButtons` injecté dans `LayoutMaintainer` | RÉUTILISER | `LayoutMaintainer.swift:99` |
| Notifications AX supplémentaires | `AXWindowEventObserver` | RÉUTILISER, étendre | `Sources/RoadieAX/AXWindowEventObserver.swift:31-38` |
| Observateurs NSWorkspace | aucun pour le changement de bureau ni l'activation | CRÉER dans le lot L6 (quelques lignes dans le `TickScheduler` ou `main.swift`) | `rg activeSpaceDidChange` : vide |
| Écriture AX par lot | `AXWindowFrameWriter.setFrames` | RÉUTILISER, modifier | `Sources/RoadieAX/SystemSnapshotProvider.swift:811-1013` |
| Index des éléments AX par pid | `AXApplicationWindows` construit par le snapshot | RÉUTILISER, publier vers l'écrivain | `SystemSnapshotProvider.swift:457-478, 524-525` |
| Constantes de seuil | `LayoutTolerance` | RÉUTILISER ; `TickDuration` supprimé | `Sources/RoadieCore/LayoutTolerance.swift` |
| Instrumentation ms | `RoadieEvent`, `AutomationEvent` | RÉUTILISER, ajouter des champs | `Sources/RoadieDaemon/EventLog.swift:4-21` |
| Outil de mesure | aucun | CRÉER (`scripts/measure-layout-reactivity`, stdlib Python) | `ls scripts` |
| ADR | 001 à 008 | CRÉER 009 | `docs/decisions/` |

## Doublons évités

- Un deuxième moteur à arbre (`mutableBsp` avec arbre) : rejeté (R1).
- Un cache d'état séparé par store : le cache vit dans `JSONPersistence`, commun à `StageStore` et `LayoutIntentStore`.
- Une nouvelle notion d'« activité utilisateur » : on étend `UserInputActivity`.

## Arbitrages

Aucun arbitrage utilisateur requis.

## Gate avant tasks

- [x] Chaque élément nouveau a une recherche d'existant tranchée
- [x] Aucune duplication évidente non arbitrée
- [x] Les deux créations de fichier sont justifiées (Complexity Tracking du plan)
- [x] Aucune dépendance externe ajoutée
