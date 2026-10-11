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
**Constraints**: thread principal pour AX et AppKit ; SIP actif ; une seule API privée nouvelle, en lecture seule, avec repli (A5, ADR 010).
**Scale/Scope**: environ 15 fichiers sources, environ 45 tests à réécrire. Suppression nette attendue de plusieurs centaines de lignes.

## Constitution Check

| Article | Statut | Note |
|---|---|---|
| III SpecKit | PASS | spec, plan, tasks, implement, converge, audit |
| VII ADR | PASS | ADR 009 (arbre qui fait foi, passe unique) et ADR 010 (lecture privée en lecture seule du type de bureau, avec repli public) |
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

Ces signatures sont fixées avant la vague 2. Les amendements A1 à A12 de `research.md` priment sur les décisions R1 à R15.

```swift
// RoadieAX/WrittenFrameRegistry.swift (lot L3)
public struct WrittenFrame: Sendable, Equatable {
    public var requested: CGRect; public var readBack: CGRect?; public var accepted: CGRect?
    public var writtenAt: Date; public var layoutVersion: UInt64; public var writesInVersion: Int
}
public final class WrittenFrameRegistry: @unchecked Sendable {      // verrou interne
    public static let shared: WrittenFrameRegistry
    public func record(windowID: UInt32, requested: CGRect, readBack: CGRect?, layoutVersion: UInt64, at: Date)
    public func accept(windowID: UInt32, frame: CGRect)
    public func entry(for windowID: UInt32) -> WrittenFrame?
    public func forget(windowID: UInt32)
    public enum Classification: Equatable { case echo, appResponse, external }
    public func classify(windowID: UInt32, observed: CGRect, now: Date) -> Classification
}
// La session de geste (A4) est tenue par UserInputActivity (lot L6) : fenêtre, frame initiale, relâchement.

// RoadieAX/SpaceProbe.swift (lot L3) - lecture seule, dlsym, repli si absent (A5, ADR 010)
public enum SpaceProbe { public static func isUserSpaceActive(displayUUID: String) -> Bool? }   // nil = indisponible

// RoadieAX/AXWindowEventObserver.swift (lot L3)
public struct AXWindowEvent: Sendable, Equatable { public var name: String; public var pid: pid_t; public var windowID: UInt32? }

// RoadieCore/LayoutTolerance.swift (posé par l'orchestrateur entre les vagues)
public static let frameMatch: CGFloat = 2
public static let echoWindow: TimeInterval = 1.0
public static let burstWindow: TimeInterval = 0.3, burstQuiet: TimeInterval = 0.1, burstCap: TimeInterval = 1.0
public static let spaceGuardPoll: TimeInterval = 0.05, spaceGuardCap: TimeInterval = 1.5
public static let writeBudgetPerVersion = 2

// RoadieDaemon/LayoutMaintainer.swift (stubs posés par l'orchestrateur, remplis par L7)
public func tick(cause: String) -> MaintenanceTick          // tick() délègue avec cause "legacy"
public func nextDeadline(now: Date) -> Date?
public func spaceDidChange(displayUUID: String?)            // signal NSWorkspace transmis par L6

// RoadieDaemon/DaemonSnapshot.swift (stub posé par l'orchestrateur, rempli par L8)
public func applyTreeScope(_ scope: StageScope, cause: String) -> MaintenanceTick   // application immédiate pour les commandes (L9)

// RoadieDaemon/StageStore.swift (lot L2)
public func migrateLegacyTreeModes(infer: ([(WindowID, CGRect?)], CGRect) -> BSPTree, container: (StageScope) -> CGRect?) throws -> Int

// RoadieTiler/BSPTree.swift (lot L4) - noms des types existants
func inserting(_ id: WindowID, at anchor: WindowID?, side: InsertionSide, in container: CGRect) -> BSPTree
func projected(excluding absent: Set<WindowID>) -> BSPTree   // A9 : mêmes identités de split
func layout(in container: CGRect) -> [WindowID: CGRect]
func balanced() -> BSPTree; func togglingSplit(of id: WindowID) -> BSPTree
func settingSplit(of id: WindowID, to orientation: BSPOrientation) -> BSPTree
func adjustingFence(of id: WindowID, edge: Direction, to frame: CGRect, in container: CGRect) -> BSPTree
func correctingForMinimumSize(of id: WindowID, minimum: CGSize, in container: CGRect) -> BSPTree?   // nil = infaisable (A2)
static func inferred(from ordered: [(WindowID, CGRect?)], in container: CGRect) -> BSPTree
```

Les noms exacts des types existants (`WindowID`, `BSPOrientation`, `Direction`, `InsertionSide`) sont ceux du code actuel. Le lot L4 publie dans son rapport la version finale des signatures, avant la vague 2.

## Lots et vagues

Les lots d'une même vague tournent en parallèle, chacun sur des fichiers exclusifs. Chaque lot compile avec son propre `--scratch-path`, et l'orchestrateur commite par lot. Aucun lot ne supprime un symbole encore utilisé par un autre lot (A10).

### Vague 1 (indépendants)

| Lot | Objet | Fichiers exclusifs | Modèle |
|---|---|---|---|
| L1 | Instrumentation ms, épisodes (R14, A12), outil de mesure | `EventLog.swift`, `AutomationEvent.swift`, `AutomationEventCatalog.swift`, `scripts/measure-layout-reactivity`, tests EventLog | Sonnet |
| L2 | Cache de l'état (A7), migration explicite (A8) | `JSONPersistence.swift`, `StageStore.swift`, `LayoutIntentStore.swift`, `LayoutCommandActivity.swift`, `StatePersistenceTests`, `FileLockTests`, nouveau `StateMigrationTests` | Opus |
| L3 | Écriture AX, événements AX, registre, sonde de bureau (R8, A4, A5) | `SystemSnapshotProvider.swift`, `AXWindowEventObserver.swift`, `WrittenFrameRegistry.swift`, `SpaceProbe.swift`, `Tests/RoadieAXTests/*` | Opus |
| L4 | Moteur à arbre (R3, A2, A8, A9, R12 côté arbre), sans rien supprimer | `BSPTree.swift`, `SpatialBSPLayoutStrategy.swift`, `WindowManagementMode.swift` (`usesTreeEngine`), parsing du mode dans la config, `Tests/RoadieTilerTests/*`, `SpatialBSPConfigTests` | Opus |

Entre les deux vagues, l'orchestrateur pose les constantes de `LayoutTolerance` et les stubs (A10), vérifie le build et la suite complète, puis commite.

### Vague 2 (dépend de la vague 1)

| Lot | Objet | Fichiers exclusifs | Modèle |
|---|---|---|---|
| L6 | Ordonnanceur, sources d'événements, session de geste, glisser (R5, A1, A4, A11) | `main.swift`, `TickScheduler.swift`, `FocusFollowsMouseController.swift` (UserInputActivity), `WindowDragActivity.swift`, `TickSchedulerTests` | Opus |
| L7 | Cœur du maintainer, par étapes séquentielles (A1, A2, A4, A6, A5 côté garde, R9, durées absolues) | `LayoutMaintainer.swift`, `LayoutTolerance.swift`, `LayoutMaintainerTests.swift` | Opus |
| L8 | Arbre qui fait foi dans le snapshot (R2, A9, R11, A12), appel de la migration, `applyTreeScope` | `DaemonSnapshot.swift`, `SnapshotServiceTests.swift` | Opus |
| L9 | Commandes, bascules et restaurations sur l'arbre (R12, A11) | `WindowCommands.swift`, `LayoutCommandService.swift`, `WidthAdjustmentService.swift`, `CLICommandRouter.swift`, `DropPreviewController.swift`, `StageCommands.swift`, `DesktopCommands.swift`, `WindowBookmarkCommands.swift`, `RailController.swift`, `PowerUser*Tests`, `DropPreviewEngineTests` | Opus |

### Vague 3 (intégration, séquentielle)

- Suppression des symboles `mutableBsp` devenus inutilisés (stratégie, `LayoutStrategy.mutableBsp`, chaînes mortes), une fois tous les appelants portés.
- Build et suite complète.
- ADR 009 (arbre qui fait foi, passe unique) et ADR 010 (lecture privée du type de bureau).
- README et exemples.
- Mesure finale.
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
