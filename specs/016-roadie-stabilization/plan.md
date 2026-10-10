# Implementation Plan: Stabilisation de Roadie

**Branch**: `016-roadie-stabilization` | **Date**: 2026-10-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/016-roadie-stabilization/spec.md`

## Summary

Corriger les 39 constats de [review-findings.md](./review-findings.md) en s'attaquant d'abord aux six causes racines (C1 à C6). L'approche reste incrémentale : transaction sur les fichiers d'état, délai Accessibility, cache limité aux attributs stables, plein écran déterminé par macOS ou par une commande explicite, identité des fenêtres prudente, restauration systématique à l'arrêt. Viennent ensuite la performance (snapshot partagé, rail sans travail inutile), l'exploitation (installation, `doctor`, CLI via le daemon) et la maintenabilité (gardes par scope, seuils centralisés, découpage du rail).

## Technical Context

**Language/Version**: Swift 6.0 (swift-tools-version 6.0), macOS 14+
**Primary Dependencies**: AppKit, ApplicationServices (AX), CoreGraphics, ScreenCaptureKit (ajout système, pas de dépendance tierce), TOMLKit (existant)
**Storage**: fichiers JSON sous `~/.roadies/` (stages, intents, rail runtime, restore), écriture atomique + `flock`
**Testing**: swift-testing via `./scripts/test` ; doubles existants (`PowerUserProvider`, fixtures)
**Target Platform**: macOS 14 Sonoma et suivants
**Project Type**: daemon + CLI (Swift Package)
**Performance Goals**: au repos 0 écriture d'état ; ≤ 1 snapshot complet par cycle et par processus ; commande < 1 s même avec une application gelée
**Constraints**: SIP actif, aucune API privée en écriture ; modes monolithique et modulaire supportés
**Scale/Scope**: 39 constats, ~30 fichiers sources touchés, 8 user stories

## Constitution Check

| Article | Statut | Note |
|---|---|---|
| III SpecKit | PASS | spec → plan → tasks → implement |
| VII ADR | PASS | ADR 007 (canal CLI-daemon) et ADR 008 (transactions d'état) à créer |
| XV Test-before-next | PASS | build + tests après chaque vague ; commits réguliers autorisés par l'utilisateur |
| XVI Worktree | DÉROGATION | travail dans le checkout principal, voir Complexity Tracking |
| XVIII Complexité | PASS | supprime O(n²) dans `apply` et la réparation ; snapshots répétés supprimés |
| XIX Minimalisme | PASS sous condition | nouvelles abstractions limitées à : `mutate`, `ConfigReloadService.shared` (extension de l existant), `CLICommandRouter`, `LayoutTolerance`, registre AX ; chacune a ≥ 3 usages réels |
| XX Vertus LLM | PASS | chaque vague relue par un agent distinct ; suppression de code mort prévue |

## Project Structure

### Documentation (this feature)

```text
specs/016-roadie-stabilization/
├── spec.md
├── review-findings.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── reuse-audit.md
├── contracts/
│   ├── cli-daemon-socket.md
│   └── daemon-status.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/       Config.swift, LayoutTolerance.swift (nouveau)
├── RoadieAX/         SystemSnapshotProvider.swift, AXWindowEventObserver.swift, PermissionSnapshot.swift
├── RoadieTiler/      BSPTree.swift, MutableBSPLayoutStrategy.swift
├── RoadieStages/
├── RoadieDaemon/     JSONPersistence, StageStore, LayoutIntentStore, DaemonSnapshot, LayoutMaintainer,
│                     StageCommands, WindowCommands, RailController (+ fichiers découpés), Border/FocusFollowsMouse,
│                     RestoreSafetyService, ComponentLockFile, CLICommandRouter (nouveau), CommandSocketServer (nouveau)
├── roadied/main.swift
└── roadie/main.swift
Tests/ RoadieDaemonTests, RoadieTilerTests, RoadieStagesTests, RoadieAXTests (nouveau)
scripts/, Makefile, examples/ (nouveau), docs/en, docs/fr, docs/decisions/
```

**Structure Decision** : pas de nouveau module. Les nouveaux types vont dans le module qui possède déjà la responsabilité.

## Lots de travail (parallélisation par propriété de fichiers)

Un lot = un propriétaire unique pour ses fichiers. Deux lots ne modifient jamais le même fichier dans la même vague.

| Lot | Modèle | Fichiers possédés | Constats |
|---|---|---|---|
| **A Persistance** | Opus | `JSONPersistence.swift`, `StageStore.swift`, `LayoutIntentStore.swift`, `RailRuntimeState.swift`, `EventLog.swift`, `EventSubscriptionService.swift`, `FileLock.swift` | 5, 6, 10, 21, moteur 12, EventLog |
| **B Accessibility** | Opus | `Sources/RoadieAX/*`, `Package.swift`, `Tests/RoadieAXTests/*` | 7, C3, 39 (activation), observer AX, apply O(n²) |
| **C Moteur** | Opus | `LayoutMaintainer.swift`, `Sources/RoadieCore/LayoutTolerance.swift` | 1, 2, 3, 4, 12 (souris), 14, 16, 36, 37, moteur 15 |
| **D Commandes** | Opus | `StageCommands.swift`, `WindowCommands.swift`, `Sources/RoadieTiler/*` | 1 (StageCommands), 4 (copie), 13, 15, moteur 7 et 11 |
| **E Snapshot et composants** | Opus | `DaemonSnapshot.swift`, `BorderController.swift`, `FocusFollowsMouseController.swift`, `ConfigReloadService.swift`, `AutomationSnapshotService.swift` | 11, 13 (reload), 17, 20, 22, 24, intents grâce, display actif |
| **F Cycle de vie** | Opus | `Sources/roadied/main.swift`, `RestoreSafetyService.swift`, `ComponentLockFile.swift`, `HiddenWindowPlacement.swift`, `DaemonHealth.swift` | 8, 29, C6, veille/réveil, `--ticks`, daemon-status |
| **G Navrail** | Sonnet | `RailController.swift` (+ découpage), `RailSettings.swift`, `DropPreviewController.swift`, `WindowPresentationStateResolver.swift`, `TargetOverlayPresenter.swift`, `TitlebarContextMenuController.swift`, `TargetHintService.swift` | 9, 18, 19, 23, autres rail, 39 (capture) |
| **H CLI** | Opus | `Sources/roadie/main.swift`, `CLICommandRouter.swift`, `CommandSocketServer.swift`, `Formatters.swift`, `PermissionSnapshot` (lecture seule) | 25 (main.swift), 32, 33, 34 (`doctor`) |
| **I Config et exploitation** | Sonnet | `Config.swift`, `scripts/*`, `Makefile`, `README*.md`, `docs/**`, `examples/**` | 26, 27, 28, 30, 31, 35, 25 (scripts/doc) |
| **J Tests et revue** | Haiku | `Tests/**` hors fichiers créés par un lot ; relecture | 38 |

### Interfaces fixées à l'avance (pour travailler en parallèle)

- **A → E, D, G** : `StageStore.mutate<R>(_ body: (inout PersistentStageState) throws -> R) rethrows -> R` ; `LayoutIntentStore.mutate` idem ; `StageStore.save` conservé (compatibilité) mais sans écriture si inchangé. `StageStore.loadFailure: Error?` exposé.
- **C → D, E, G** : `LayoutTolerance` (enum statique) dans `RoadieCore` : `observedChange = 16`, `fullscreenFrame = 48`, `clampShrink = 24`, `growthMinimum = 64`, `growthRatio = 0.35`, fonctions `innerGapTolerance(gapsInner:)`. D et G remplacent leurs littéraux en vague 2.
- **E → F, G, H** : `ConfigReloadService.shared.currentConfig() -> RoadieConfig` (stat du fichier, rechargement si modifié, dernière config valide gardée), `ConfigReloadService.shared.state.lastError`.
- **F → H, I** : `~/.roadies/daemon-status.json` (voir [contracts/daemon-status.md](./contracts/daemon-status.md)).
- **H → F** : `CommandSocketServer.start(router:)` appelé par F dans `run` et `tiler` (une ligne, ajoutée par F en vague 2).
- **B → C, D, E, G** : `WindowSnapshot` inchangé ; `isNativeFullscreen` devient fiable ; `AXUnresponsiveApps.shared.isQuarantined(pid)`.

### Vagues

1. **Vague 1 (parallèle)** : A, B, C, E, F, G, H, I démarrent sur leurs constats propres. D démarre ses constats sans dépendance (BSP, stage vide, `toggleFullscreen`).
2. **Vague 2** : intégration des interfaces (D et G adoptent `LayoutTolerance` et `mutate` ; E adopte `mutate` dans `snapshot()` ; F branche `CommandSocketServer`). Build + tests complets.
3. **Vague 3** : J (tests manquants, nettoyage des tests décoratifs), relecture croisée, docs, ADR.

Après chaque vague : `./scripts/with-xcode swift build` puis `./scripts/test`, et un commit par lot.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Dérogation worktree (XVI) | Plusieurs agents parallèles doivent partager un même build Swift et intégrer leurs interfaces en continu | Un worktree par lot multiplie les builds complets et repousse les conflits à la fusion |
| Nouveau canal socket (R8) | Seule façon d'obtenir un écrivain unique et une CLI sans permission AX | `DistributedNotificationCenter` ne renvoie ni sortie ni code de retour |
| Nouvelle cible de tests `RoadieAXTests` | Le module AX n'a aucun test alors qu'il porte C2 et C3 | Tester via `RoadieDaemonTests` ne couvre pas le registre de mise de côté |
