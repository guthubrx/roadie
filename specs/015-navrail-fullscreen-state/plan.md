# Implementation Plan: Etat fullscreen dans le navrail

**Branch**: `015-navrail-fullscreen-state` | **Date**: 2026-05-25 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/015-navrail-fullscreen-state/spec.md`

## Summary

Roadie doit représenter dans le navrail les fenêtres `maximized` et `nativeFullscreen` sans changer le modèle de stage et sans déclencher de relayout. La solution retenue ajoute un état de présentation de fenêtre calculé dans le chemin snapshot partagé, exposé dans l'automation JSON et consommé par le renderer du navrail. Le navrail dessine une bordure à quatre coins pour `maximized` et une bordure continue pour `nativeFullscreen`.

## Technical Context

**Language/Version**: Swift 6.0  
**Primary Dependencies**: AppKit, CoreGraphics, ApplicationServices Accessibility, RoadieAX, RoadieCore, RoadieDaemon, RoadieStages  
**Storage**: Aucun nouveau stockage persistant ; l'état est calculé depuis le snapshot runtime et exposé dans les surfaces existantes  
**Testing**: `./scripts/test`, tests unitaires Swift sous `Tests/RoadieDaemonTests/` et `Tests/RoadieCoreTests/` si nécessaire  
**Target Platform**: macOS 14+  
**Project Type**: Desktop app + daemon + CLI SwiftPM  
**Performance Goals**: Calcul O(n_windows) par snapshot, sans appel AX supplémentaire par fenêtre hors collecte existante ; refresh navrail sans dépassement notable du budget actuel  
**Constraints**: Parité monolithique/modulaire ; pas de relayout induit ; JSON automation rétrocompatible ; indicateurs lisibles à taille navrail ; pas de stage fullscreen dédiée  
**Scale/Scope**: Fenêtres gérées Roadie sur plusieurs displays/desktops/stages ; tous les modes visuels du navrail (`stacked`, `mosaic`, `parallax`, `icons`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Langue française : PASS, artefacts en français.
- Workflow SpecKit complet : PASS, specify → plan → tasks → analyze → implement.
- Observabilité : PASS, l'état sera exposé dans le snapshot automation et pourra être diagnostiqué.
- Tests : PASS attendu, tests unitaires pour détection, JSON automation et absence de commandes layout.
- Parité runtime : PASS, le calcul est partagé avant rendu par les composants.
- Anti-scope-creep : PASS, pas de commande toggle fullscreen nouvelle, pas de stage dédiée.
- Dérogation worktree : ACCEPTÉE pour ce tour, car l'arbre courant contient des correctifs runtime non commités que la nouvelle implémentation doit préserver.

## Project Structure

### Documentation (this feature)

```text
specs/015-navrail-fullscreen-state/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── automation-window-presentation.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/
│   └── AutomationSnapshot.swift
├── RoadieAX/
│   └── SystemSnapshotProvider.swift
└── RoadieDaemon/
    ├── WindowPresentationStateResolver.swift
    ├── AutomationSnapshotService.swift
    └── RailController.swift

Tests/
└── RoadieDaemonTests/
    ├── WindowPresentationStateResolverTests.swift
    ├── AutomationSnapshotTests.swift
    └── PowerUserFocusCommandTests.swift
```

**Structure Decision**: Placer le type exposé dans `RoadieCore` pour qu'il soit sérialisable dans les snapshots automation. Placer la détection dans `RoadieDaemon`, car elle dépend du `DaemonSnapshot`, des displays et des fenêtres AX. Le navrail consomme une table `WindowID -> WindowPresentationState` et ne réimplémente aucune heuristique.

## Phase 0: Research

Voir [research.md](./research.md).

## Phase 1: Design & Contracts

Voir [data-model.md](./data-model.md), [contracts/automation-window-presentation.md](./contracts/automation-window-presentation.md) et [quickstart.md](./quickstart.md).

## Constitution Check Post-Design

- Le modèle de stage reste inchangé : PASS.
- Les chemins monolithique et modulaire consomment le même snapshot : PASS.
- Le navrail ne devient pas source de vérité de layout : PASS.
- Le contrat JSON est rétrocompatible si les anciens snapshots décodent `presentationState` manquant comme `normal` : PASS.
- Les indicateurs de bordure respectent une distinction non uniquement chromatique : PASS.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Dérogation au worktree isolé | Les correctifs runtime non commités du tour précédent doivent rester dans le même arbre pour éviter une implémentation sur base obsolète | Créer un worktree propre aurait perdu le contexte exact du tiler/navrail actuellement en cours de stabilisation |
