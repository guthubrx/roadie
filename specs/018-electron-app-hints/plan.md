# Implementation Plan: Lettres d'accès dans les applications Electron

**Branch**: `018-electron-app-hints` | **Date**: 2026-10-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/018-electron-app-hints/spec.md`

## Summary

Le mode lettres lit l'arbre d'accessibilité de la fenêtre au premier plan. Electron ne publie cet arbre que si un outil le demande avec l'attribut `AXManualAccessibility`. Roadie ne le demande pas, donc il ne voit que la fenêtre vide.

Le correctif reste dans `LiveAppTargetProvider` (`Sources/RoadieDaemon/AppTargetQueryService.swift`) :

1. Avant chaque parcours d'une application Electron, quand le boost AX est actif, poser `AXManualAccessibility` (sans lecture préalable, voir research.md).
2. Si le parcours est complet et ne contient aucune zone web (`AXWebArea`), attendre 150 ms et relancer, deux fois au plus, dans une échéance commune `timeout_ms` + 300 ms.
3. Rogner chaque cadre à la partie visible dans la fenêtre ; écarter les éléments entièrement dehors.
4. Rendre les statistiques du parcours dans le rapport, et les journaliser dans `TargetHintService.list`.

Le réglage de `max_depth` et `timeout_ms` dans la configuration de l'utilisateur se fera ensuite, avec les mesures.

## Technical Context

**Language/Version**: Swift 6 (Swift Package Manager), macOS 14+
**Primary Dependencies**: ApplicationServices (API d'accessibilité), AppKit. Aucune nouvelle dépendance.
**Storage**: aucun. Journal existant `~/.roadies/events.jsonl` (`EventLog`).
**Testing**: Swift Testing (`./scripts/test`, `make test`)
**Target Platform**: macOS, daemon `roadied`
**Project Type**: CLI + daemon
**Performance Goals**: aucune attente pour les applications natives ou déjà publiées. Durée totale bornée à `timeout_ms` + 300 ms, à un appel AX près.
**Constraints**: aucun relayout depuis le parcours (FR-007). Aucune nouvelle clé de configuration (FR-008).
**Scale/Scope**: 2 fichiers de production, 2 fichiers de tests.

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| III SpecKit | spec, plan, tâches avant code | OK |
| XV Test-before-next | tests unitaires de la partie pure, build, test manuel dans T3 Code | OK |
| XVI Worktree | `.worktrees/018-electron-app-hints` | OK |
| XVIII Complexité | parcours O(n), n = éléments lus, borné par `max_targets`, `max_depth` et `timeout_ms`. La relance multiplie au plus par 3 un parcours qui n'a trouvé qu'un élément | OK |
| XIX Minimalisme | aucune nouvelle clé, aucune abstraction ; les statistiques passent par le rapport existant | OK |
| XX Responsabilité | la cause est prouvée par le journal réel (`app:60116/0`, `partial=false`) ; la mesure de la User Story 3 sert au réglage | OK |
| XXII Optimisation | aucune optimisation de vitesse dans cette feature ; la mesure vient d'abord | OK |

## Project Structure

### Documentation (this feature)

```text
specs/018-electron-app-hints/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/app-scan-event.md
├── reuse-audit.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/RoadieDaemon/
├── AppTargetQueryService.swift   # activation, relance, filtre visible, statistiques
└── TargetHintService.swift       # journalisation de l'événement targets.app_scan

Tests/RoadieDaemonTests/
├── AppTargetQueryServiceTests.swift   # filtre visible, politique de relance
└── TargetHintServiceTests.swift       # événement targets.app_scan
```

**Structure Decision**: tout reste dans le service existant de cibles applicatives. Les décisions testables (cadre visible, relance) sont des fonctions statiques pures de `AppTargetQueryService`, comme `targets(from:config:)` aujourd'hui.

## Complexity Tracking

Aucune violation à justifier.
