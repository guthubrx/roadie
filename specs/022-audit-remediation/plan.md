# Plan : Corrections de l'audit v14 complet

## Approche

11 lots à fichiers exclusifs, exécutés par des agents en parallèle (méthode SPEC-016) :
un agent = un lot = des fichiers dont il est seul propriétaire. Brief commun : `agent-brief.md`.
Chaque agent compile avec son propre `--scratch-path /tmp/roadie-build-022-<lot>`. Les agents ne
commitent pas ; l'orchestrateur vérifie (build + tests complets) et commite par lot.

Deux vagues pour ne pas saturer la machine : vague 1 = lots A à F (tous les HIGH), vague 2 = G à K.
Contre-revue adverse Codex sur le diff complet, puis nouvel audit v14.

## Lots

| Lot | Modèle | Fichiers propriétaires | Constats |
|-----|--------|------------------------|----------|
| A | Opus | DaemonSnapshot.swift, AutomationSnapshotService.swift | PERF-001, REL-005, REL-006, MIN-002, REL-013 |
| B | Opus | LayoutMaintainer.swift | PERF-004, REL-007, REL-008, REL-009 |
| C | Opus | RoadieTiler/SpatialBSPLayoutStrategy.swift, LayoutTypes.swift, MasterStackLayoutStrategy.swift | PERF-002, REL-030, REL-031 |
| D | Sonnet | StageStore.swift, StageCommands.swift | REL-001, PERF-005, REL-023 |
| E | Opus | StateAudit.swift | REL-002 |
| F | Opus | TargetModeRuntimeController.swift, AppTargetQueryService.swift, TargetMacroService.swift, TargetModeRuntimeControllerTests.swift | REL-003, REL-004, REL-012, REL-024, REL-025, TEST-002 |
| G | Sonnet | DesktopCommands.swift, DisplayParkingService.swift, HiddenWindowPlacement.swift, WidthAdjustmentService.swift | REL-016, MIN-004, REL-017, REL-020, REL-026, REL-027 |
| H | Opus | DropPreviewController.swift, RailPanel.swift, RailController.swift, TitlebarContextMenuController.swift, FocusFollowsMouseController.swift | PERF-003, MIN-001, REL-022, DUP-001, PERF-006, REL-019 |
| I | Sonnet | CommandSocketServer.swift, EventSubscriptionService.swift, FileAdministration.swift, JSONPersistence.swift, CLICommandRouter.swift, scripts/uninstall | REL-015, PERF-007, REL-018, OBS-001, REL-021, REL-014, REL-032 |
| J | Sonnet | RoadieCore/Config.swift, RoadieAX/SystemSnapshotProvider.swift, WindowBookmarkCommands.swift, WindowRuleAffinityService.swift | REL-011, MIN-003, REL-010, REL-028, REL-029 |
| K | Sonnet | QueryCommandTests.swift, WindowGroupCommandTests.swift, WindowGroupIndicatorTests.swift, README.fr.md, README.md, docs/ | TEST-001, TEST-003, TEST-004, QUAL-001 |

## Risques

- Un correctif qui exige un fichier d'un autre lot : l'agent s'arrête sur ce point et le signale ;
  l'orchestrateur arbitre (pas d'édition concurrente).
- Charge machine : 6 compilations en parallèle au plus.
