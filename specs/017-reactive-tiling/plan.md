# Implementation Plan: Tiling réactif façon yabai

**Branch**: `017-reactive-tiling` | **Date**: 2026-10-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/017-reactive-tiling/spec.md`

## Summary

Roadie passe d'un modèle « relevé toutes les 500 ms et corrections successives » à un modèle « événement, puis une seule passe », comme yabai. Quatre changements portent l'essentiel :

1. **L'arbre `spatialBsp` fait foi et devient l'unique moteur à arbre.** `mutableBsp` devient un alias, avec migration de l'état.
2. **Un ordonnanceur réagit aux événements.** Il ne perd plus d'événement, n'impose plus d'attente fixe, et relance une passe dès qu'une attente expire.
3. **Un registre des frames écrites** distingue l'écho de nos placements, la réponse de l'application et le geste réel de l'utilisateur, ce dernier étant reconnu à la souris.
4. **L'écriture AX suit la méthode de yabai** : taille, position, taille, avec `AXEnhancedUserInterface` neutralisé, une seule relecture, une seule nouvelle tentative en cas de refus de taille.

S'y ajoutent :
- un cache de l'état persisté, pour ne plus le décoder plusieurs fois par passe ;
- une instrumentation à la milliseconde, pour mesurer avant et après ;
- la suppression du code `mutableBsp` devenu inutile.

Les décisions sont détaillées dans [research.md](./research.md), de R1 à R15.

## Technical Context

**Language/Version**: Swift 6.0, macOS 14+
**Primary Dependencies**: AppKit, ApplicationServices (AX), CoreGraphics. Aucune dépendance nouvelle.
**Storage**: `~/.roadies/stages.json` et `layout-intents.json`, en écriture atomique avec `flock` (ADR-008). Le schéma est inchangé, sauf la valeur de mode migrée.
**Testing**: swift-testing via `./scripts/test` ; outil `scripts/measure-layout-reactivity` sur le journal réel.
**Target Platform**: macOS 14 Sonoma et suivants (poste de l'utilisateur : Darwin 25).
**Project Type**: daemon + CLI (Swift Package).
**Performance Goals**: SC-001 à SC-007. Placement stable en moins de 150 ms au p90, une passe dans 95 % des épisodes, 0 placement au repos.
**Constraints**: thread principal pour AX et AppKit ; SIP actif ; aucune API privée sauf justification par ADR (R7).
**Scale/Scope**: environ 15 fichiers sources, environ 45 tests à réécrire. Suppression nette attendue de plusieurs centaines de lignes.

## Constitution Check

| Article | Statut | Note |
|---|---|---|
| III SpecKit | PASS | spec, plan, tasks, implement, converge, audit |
| VII ADR | PASS | ADR 009 « arbre qui fait autorité et passe unique », à créer. ADR 010 seulement si une API privée de bureau devient nécessaire (R7) |
| XV Test-before-next | PASS | build et tests complets après chaque vague ; commits par lot autorisés par l'utilisateur |
| XVI Worktree | DÉROGATION | checkout principal, comme pour la 016 : un seul utilisateur, branche dédiée, agents sur fichiers exclusifs |
| XVIII Complexité | PASS | supprime les relectures O(k × taille du fichier) par passe et les passes répétées ; le placement d'un arbre est O(n) |
| XIX Minimalisme | PASS | nouvelles abstractions : `TickScheduler` (remplace une logique ad hoc), `WrittenFrameRegistry` (au moins 3 usages : écrivain, maintainer, commandes). Le reste étend l'existant. Suppression nette de code |
| XX Vertus LLM | PASS | contre-revue Codex sur le plan et l'implémentation ; mesure avant et après |
| XXII Optimisation | PASS | mesure de référence faite (research.md) ; mesure finale avec le même outil et à la milliseconde |

## Project Structure

### Documentation (this feature)

```text
specs/017-reactive-tiling/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── layout-events.md
├── checklists/requirements.md
├── reuse-audit.md
├── agent-brief.md
└── tasks.md
```

### Source Code (fichiers touchés, par lot)

```text
Sources/RoadieCore/       WindowManagementMode.swift, LayoutTolerance.swift, AutomationEvent.swift
Sources/RoadieTiler/      BSPTree.swift, SpatialBSPLayoutStrategy.swift, MutableBSPLayoutStrategy.swift (supprimé), LayoutTypes.swift
Sources/RoadieAX/         SystemSnapshotProvider.swift, AXWindowEventObserver.swift, WrittenFrameRegistry.swift (nouveau)
Sources/RoadieDaemon/     LayoutMaintainer.swift, DaemonSnapshot.swift, TickScheduler.swift (nouveau), JSONPersistence.swift,
                          StageStore.swift, LayoutIntentStore.swift, LayoutCommandActivity.swift, EventLog.swift,
                          WindowCommands.swift, LayoutCommandService.swift, WidthAdjustmentService.swift,
                          CLICommandRouter.swift, DropPreviewController.swift, StageCommands.swift, RailController.swift,
                          FocusFollowsMouseController.swift
Sources/roadied/          main.swift
scripts/                  measure-layout-reactivity (nouveau)
docs/decisions/           009-authoritative-tree-single-pass.md (nouveau)
```

**Structure Decision**: on garde la structure actuelle et on n'ajoute pas de module. Les deux nouveaux fichiers sources correspondent à des responsabilités qui n'existent nulle part (vérifié dans `reuse-audit.md`).

## Interfaces fixées (contrat entre lots parallèles)

Ces signatures sont fixées avant la vague 2, pour que les lots compilent ensemble.

```swift
// RoadieAX/WrittenFrameRegistry.swift (lot L3)
public struct WrittenFrame: Sendable, Equatable {
    public var requested: CGRect; public var readBack: CGRect?; public var accepted: CGRect?; public var writtenAt: Date
}
public final class WrittenFrameRegistry: @unchecked Sendable {   // verrou interne
    public static let shared: WrittenFrameRegistry
    public func record(windowID: UInt32, requested: CGRect, readBack: CGRect?, at: Date)
    public func accept(windowID: UInt32, frame: CGRect)
    public func entry(for windowID: UInt32) -> WrittenFrame?
    public func forget(windowID: UInt32)
    public enum Classification: Equatable { case echo, appResponse, manualGesture, unknown }
    public func classify(windowID: UInt32, observed: CGRect, now: Date, lastMouseDownAt: Date?) -> Classification
}

// RoadieCore/LayoutTolerance.swift (posé par l'orchestrateur avant la vague 2)
public static let frameMatch: CGFloat = 2            // tolérance unique (R9)
public static let echoWindow: TimeInterval = 1.0      // R6
public static let settleQuiet: TimeInterval = 0.2     // R7
public static let settleCap: TimeInterval = 1.5       // R7
public static let followUpPassLimit = 3               // R5

// RoadieDaemon/LayoutMaintainer.swift (lot L7)
public struct TickOutcome: Equatable { public var acted: Bool; public var cause: String }
public func tick(cause: String) -> TickOutcome         // garde tick() -> Void comme enveloppe pour les appelants existants
public func nextDeadline(now: Date) -> Date?

// RoadieDaemon/TickScheduler.swift (lot L6)
@MainActor public final class TickScheduler {
    public init(maintainer: LayoutMaintainer, clock: @escaping () -> Date = Date.init)
    public func request(cause: String, delay: TimeInterval)
    public func mouseDown(); public func mouseUp()
}

// RoadieTiler/BSPTree.swift (lot L4)
func inserting(_ id: WindowID, at anchor: WindowID?, side: InsertionSide, in container: CGRect) -> BSPTree  // sens selon la feuille
func layout(in container: CGRect, excluding absent: Set<WindowID>) -> [WindowID: CGRect]
func balanced() -> BSPTree; func togglingSplit(of id: WindowID) -> BSPTree
func settingSplit(of id: WindowID, to orientation: BSPOrientation) -> BSPTree
func adjustingFence(of id: WindowID, edge: Direction, to frame: CGRect, in container: CGRect) -> BSPTree
static func inferred(from frames: [WindowID: CGRect], in container: CGRect) -> BSPTree   // migration (R1)
```

Les noms exacts des types existants (`WindowID`, `BSPOrientation`, `Direction`, `InsertionSide`) sont ceux du code actuel. Le lot L4 adapte ces signatures aux types réels et publie la version finale dans son rapport, avant la vague 2.

## Lots et vagues

Les lots d'une même vague tournent en parallèle, chacun sur des fichiers exclusifs. Chaque lot compile avec son propre `--scratch-path`, et l'orchestrateur commite par lot. Le modèle choisi suit la complexité du lot.

### Vague 1 (indépendants)

| Lot | Objet | Fichiers exclusifs | Modèle |
|---|---|---|---|
| L1 | Instrumentation ms (R14), outil de mesure | `EventLog.swift`, `AutomationEvent.swift`, `scripts/measure-layout-reactivity`, tests EventLog | Sonnet |
| L2 | Cache de l'état persisté (R10) | `JSONPersistence.swift`, `StageStore.swift` (load et state seulement), `LayoutIntentStore.swift`, `LayoutCommandActivity.swift`, `StatePersistenceTests`, `FileLockTests` | Opus |
| L3 | Écriture AX et événements AX (R5, R6, R8) | `SystemSnapshotProvider.swift`, `AXWindowEventObserver.swift`, `WrittenFrameRegistry.swift`, `Tests/RoadieAXTests/*` | Opus |
| L4 | Moteur à arbre (R1, R3, R13, R12 côté arbre) | `BSPTree.swift`, `SpatialBSPLayoutStrategy.swift`, `MutableBSPLayoutStrategy.swift`, `LayoutTypes.swift`, `WindowManagementMode.swift`, parsing du mode dans la config, `Tests/RoadieTilerTests/*`, `SpatialBSPConfigTests` | Opus |

Entre les deux vagues, l'orchestrateur ajoute les constantes de `LayoutTolerance`, vérifie que tout compile et commite.

### Vague 2 (dépend de la vague 1)

| Lot | Objet | Fichiers exclusifs | Modèle |
|---|---|---|---|
| L6 | Ordonnanceur et sources d'événements (R5) | `main.swift`, `TickScheduler.swift`, `FocusFollowsMouseController.swift` (UserInputActivity : mouseUp, lastMouseDownAt), tests de l'ordonnanceur | Opus |
| L7 | Cœur du maintainer (R4, R6, R7, R9, durées absolues, suppressions R15) | `LayoutMaintainer.swift`, `LayoutTolerance.swift`, `LayoutMaintainerTests.swift` | Opus |
| L8 | Arbre qui fait foi dans le snapshot (R2, R11, R13, migration R1) | `DaemonSnapshot.swift`, `SnapshotServiceTests.swift`, tests de migration | Opus |
| L9 | Commandes sur l'arbre (R12) | `WindowCommands.swift`, `LayoutCommandService.swift`, `WidthAdjustmentService.swift`, `CLICommandRouter.swift`, `DropPreviewController.swift`, `StageCommands.swift`, `RailController.swift`, `PowerUser*Tests`, `DropPreviewEngineTests` | Opus |

### Vague 3 (intégration, séquentielle)

- Build et suite complète.
- Correction des écarts entre lots.
- ADR 009, README (alias `mutableBsp`), exemples de config.
- Mesure finale avec `scripts/measure-layout-reactivity`.
- Contre-revue Codex de l'implémentation, Converge, audit.

## Risques et parades

| Risque | Parade |
|---|---|
| Boucle d'auto-déclenchement après l'ajout des événements moved et resized | Le registre (L3) précède leur usage. Limite de 3 passes chaînées. Test de non-rebouclage |
| Régression FR-017 (SPEC-016) : double réorganisation pendant une rafale | Période calme avec plafond ; tests existants conservés (`tiledScopeMembershipChurnSettlesBeforeRelayout`, T203 à deux écrans) |
| Saut visuel à la migration de l'utilisateur | Arbre initial déduit de la géométrie actuelle, sauvegarde de `stages.json`, test de migration sur une copie anonymisée de l'état réel |
| Applications qui réagissent mal à la bascule `AXEnhancedUserInterface` | Remise systématique à la valeur d'origine, même en cas d'échec ; journalisé |
| Masterstack et float régressent | Les protections partagées deviennent conditionnelles au mode au lieu d'être supprimées ; tests existants conservés |
| Conflits entre lots sur les signatures | Interfaces fixées ci-dessus ; constantes posées par l'orchestrateur ; vague 2 seulement après le commit de la vague 1 |

## Complexity Tracking

| Écart | Pourquoi | Alternative plus simple rejetée parce que |
|---|---|---|
| Travail dans le checkout principal (Article XVI) | Mêmes conditions que la 016, validées par l'usage : un utilisateur, une branche dédiée | Un worktree imposerait de reconstruire l'outillage (signature, LaunchAgent) pour un gain nul |
| Deux nouveaux fichiers sources | Responsabilités absentes du code : file d'événements unique, mémoire des écritures | Les loger dans `main.swift` ou `LayoutMaintainer.swift`, qui font déjà 672 et 3 103 lignes, aggraverait la dette relevée par l'audit 016 |
