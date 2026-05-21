# Implementation Plan: Roadie Target Mode

**Branch**: `009-roadie-target-mode` | **Date**: 2026-05-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-roadie-target-mode/spec.md`

## Summary

Roadie ajoute une couche "Target Mode" inspirée des concepts de Vimac, Homerow et Neru, sans reprise de code : un inventaire de cibles actionnables, des labels courts déterministes, une recherche textuelle, un inspecteur, des actions Roadie, une extension expérimentale vers les zones sensibles applicatives via Accessibility, une grille récursive et un record/replay agent-friendly.

## Technical Context

**Language/Version**: Swift 6.0  
**Primary Dependencies**: AppKit, CoreGraphics, RoadieAX, RoadieCore, RoadieDaemon, RoadieStages, RoadieTiler, TOMLKit existant  
**Storage**: Fichiers d'état Roadie existants (`StageStore`, bookmarks, events) + recordings JSON sous `~/.local/state/roadies/records`  
**Testing**: `swift test`, tests unitaires Swift sous `Tests/RoadieDaemonTests/`  
**Target Platform**: macOS 14+  
**Project Type**: Desktop app + daemon + CLI SwiftPM  
**Performance Goals**: Cibles Roadie listées en <100 ms p95 pour 50 fenêtres/20 stages ; picker unique sans relayout en <150 ms p95 ; app targets bornées par timeout et limite de résultats ; grille 3x3 générée en <20 ms  
**Constraints**: Ne pas copier de code GPL Vimac/Homerow/Neru ; pas de relayout déclenché par découverte AX applicative, grille ou record ; JSON stable pour agents ; commandes non destructrices par défaut ; overlay visuel découplé du navrail  
**Scale/Scope**: Roadie targets complets pour stages/fenêtres/displays/desktops/bookmarks ; picker CLI ; overlay-state labels-only ; app targets expérimentaux limités à la fenêtre active ; grille récursive ; record/replay JSON ; scroll-mode applicatif complet reste borné

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Langue française : PASS, artefacts en français.
- Workflow SpecKit complet : PASS, specify → plan → tasks → analyze → implement.
- Observabilité : PASS attendu, events structurés pour listing/inspection/action.
- Tests : PASS attendu, tests unitaires pour génération labels, filtering, listing, inspection et stale target.
- Sécurité/licence : PASS, concepts Vimac/Homerow seulement, pas de code repris.
- Anti-scope-creep : PASS, le clicker applicatif complet reste expérimental et isolé.

## Project Structure

### Documentation (this feature)

```text
specs/009-roadie-target-mode/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── target-mode-cli.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/
│   └── Config.swift
├── RoadieDaemon/
│   ├── TargetHintService.swift
│   ├── TargetInspectionService.swift
│   ├── AppTargetQueryService.swift
│   ├── TargetGridService.swift
│   ├── TargetMacroService.swift
│   ├── TargetModeRuntimeController.swift
│   ├── TargetOverlayPresenter.swift
│   ├── RoadieScreenCoordinate.swift
│   ├── Formatters.swift
│   └── AutomationQueryService.swift
└── roadie/
    └── main.swift

Tests/
└── RoadieDaemonTests/
    ├── TargetHintServiceTests.swift
    ├── TargetInspectionServiceTests.swift
    ├── AppTargetQueryServiceTests.swift
    ├── TargetGridServiceTests.swift
    ├── TargetModeRuntimeControllerTests.swift
    └── TargetMacroServiceTests.swift
```

**Structure Decision**: Implémenter dans `RoadieDaemon` pour réutiliser `SnapshotService`, `StageStore`, `WindowCommandService`, `StageCommandService`, `WindowBookmarkCommandService` et les formatters CLI existants. Ajouter seulement les options de configuration nécessaires dans `RoadieCore`. Les raccourcis BTT/Karabiner restent des consommateurs externes de la CLI, pas des dépendances du daemon.

## Phase 0: Research

Voir [research.md](./research.md).

## Phase 1: Design & Contracts

Voir [data-model.md](./data-model.md), [contracts/target-mode-cli.md](./contracts/target-mode-cli.md) et [quickstart.md](./quickstart.md).

## Constitution Check Post-Design

- La surface CLI/JSON rend la feature testable sans capture écran : PASS.
- Les cibles applicatives AX sont isolées et désactivées par défaut : PASS.
- Aucun choix n'exige de modifier le moteur de layout pour les app targets : PASS.
- Les commandes destructrices nécessitent une action explicite : PASS.
- Le picker et l'overlay-state ne modifient pas le layout tant qu'aucune action explicite n'est demandée : PASS.
- Grille, record/replay et AX boost sont derrière configuration expérimentale et isolés du tiler : PASS.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Overlay graphique complet différé | Réduire le risque sur navrail/focus/bordures | Dessiner directement un overlay AppKit avant d'avoir un contrat stable aurait rendu les tests fragiles |
