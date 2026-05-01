# Specification Quality Checklist: SPEC-007 animations

**Created** : 2026-05-01

## Content Quality
- [x] No implementation details dans `spec.md`
- [x] Focus utilisateur (Bob power, demande Hyprland-style)
- [x] Toutes sections complétées

## Requirement Completeness
- [x] Aucun `[NEEDS CLARIFICATION]`
- [x] FR-001..FR-016 testables
- [x] SC-001..SC-008 mesurables
- [x] 5 user stories couvrent open/close, workspace_switch, stage_switch, resize, focus_pulse
- [x] Edge cases identifiés (runaway, wid détruite, reload, CVDisplayLink unavailable)
- [x] Out of Scope explicite (3D, spring, multi-display)

## Architecture Quality
- [x] Plafond 700 LOC strict (cible 500)
- [x] 5-6 fichiers, chacun < 200 LOC
- [x] Logique pure (BezierLib, AnimationQueue, AnimationFactory) testable unitairement
- [x] data-model.md détaillé (entités + diagramme + state transitions)

## Constitution Compliance
- [x] G' minimalisme respecté
- [x] I' pluggable (`.dynamicLibrary`)
- [x] H' tests unitaires couvrent ≥ 80 % logique pure

## Dependencies
- [x] SPEC-004 fxframework bloqueur dur (T010)
- [x] SPEC-006 / SPEC-008 listés comme consumers (API publique requestAnimation)
