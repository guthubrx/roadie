# Reuse Audit : Stabilisation de Roadie

**Date** : 2026-10-10
**Statut** : READY
**Méthode** : fallback manuel (pas de primitive `.agents/skills/speckit-audit-existing`) ; recherches `rg` sur `Sources/`, `scripts/`, `Makefile`, lecture de `AGENTS.md` et `.specify/memory/*`.

## Items proposés par le plan

| Item proposé | Recherche | Existant trouvé | Décision |
|---|---|---|---|
| Transaction `mutate` | `rg "mutate\(\|withLock"` | `FileLock.withLock` (`FileLock.swift`), `JSONPersistence.writeThrowing` | REUTILISER `FileLock` ; ajouter `mutate` dans `JSONPersistence` (pas de nouveau type) |
| Fournisseur de config | `rg "ConfigReload\|RoadieConfigLoader.load"` | `ConfigReloadService` (`ConfigReloadService.swift:70`) avec état `failedKeepingPrevious` | REUTILISER : étendre `ConfigReloadService` (instance partagée + stat) au lieu de créer `RoadieConfigProvider` |
| Seuils `LayoutTolerance` | `rg "Tolerance"` | `WindowPresentationStateResolver.maximizedTolerance`, paramètres `isClose(positionTolerance:)` (`DaemonSnapshot.swift:1546`) | CREER `LayoutTolerance` dans `RoadieCore` : aucun lieu central n'existe ; les littéraux existants y sont migrés (≥ 3 usages) |
| Registre AX `AXUnresponsiveApps` | `rg "Unresponsive\|quarantine"` | aucun | CREER dans `SystemSnapshotProvider.swift` (type privé au module si possible) |
| `CLICommandRouter` | `rg "CommandRouter"` | dispatch inline dans `Sources/roadie/main.swift` | CREER par déplacement (pas de duplication : `main.swift` devient un client mince) |
| `CommandSocketServer` | `rg "AF_UNIX\|daemon.sock"` | aucun serveur ; `DistributedNotificationCenter` pour le mode cible (`TargetModeRuntimeController.swift:73`) sans réponse | CREER (justifié en research R8) |
| Verrou d'instance | `rg "ComponentLockFile\|flock"` | `ComponentLockFile` (pid, non atomique), `FileLock` (flock) | REUTILISER : `ComponentLockFile` réécrit sur `flock` ; pas de nouveau type |
| Snapshot de restauration périodique | `rg "writeSnapshot"` | `RestoreSafetyService.writeSnapshot` | REUTILISER |
| `daemon-status.json` | `rg "daemon-status\|DaemonHealth"` | `DaemonHealthService` (lit pidfile) | REUTILISER `DaemonHealth.swift` pour écrire et lire le statut |
| `restore unhide-all` | `rg "unhide\|restore apply"` | `roadie restore apply` (`RestoreSafetyService`) | REUTILISER : nouvelle sous-commande dans le même service |
| Garde souris enfoncée | `rg "pressedMouseButtons"` | utilisé dans le rail | REUTILISER l'API AppKit, pas de wrapper |
| Rotation de logs | `rg "rotate"` | `EventLog` a une rotation | REUTILISER le principe pour les scripts (shell) ; pas de type Swift nouveau |
| `examples/` | `ls examples` | absent | CREER (documentation) |
| Cible `RoadieAXTests` | `Package.swift` | absente | CREER (justifié plan, Complexity Tracking) |
| Capture ScreenCaptureKit | `rg "ScreenCaptureKit\|SCScreenshot"` | aucun | CREER dans le store de vignettes du rail (remplacement, pas ajout) |

## Duplications existantes à résorber

- `clampedFramesCannotShareContainer` : `LayoutMaintainer.swift:1499` et `StageCommands.swift:1419` → une seule implémentation (lot C, adoptée par D).
- `hiddenFrame` ×5 → `HiddenWindowPlacement` (lot F) appelé partout.
- `NSColor(hex:)` (`RailController.swift`, `BorderController.swift`) → une seule extension.
- Heuristique maximisé dupliquée (`LayoutMaintainer.swift:1182`, `WindowPresentationStateResolver.swift`) → le resolver seul.

## Arbitrages

| Item | Existant proche | Choix | Justification |
|---|---|---|---|
| Fournisseur de config | `ConfigReloadService` | REUTILISER | Évite un second état de config concurrent |
| `CommandSocketServer` | `DistributedNotificationCenter` | CREER | Pas de réponse ni de code de retour possible avec l'existant |

## Gate avant tasks

- [x] Chaque item proposé a une recherche d'existant tranchée
- [x] Aucun doublon évident non arbitré
- [x] Les duplications existantes ont un propriétaire
- [x] Aucune nouvelle dépendance externe (ScreenCaptureKit est un framework système)
