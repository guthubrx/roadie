# Specification Quality Checklist: SPEC-008 borders

**Created** : 2026-05-01

## Content Quality
- [x] No implementation details dans `spec.md`
- [x] Focus utilisateur, 3 user stories
- [x] Toutes sections complétées

## Requirement Completeness
- [x] FR-001..FR-010 testables
- [x] SC-001..SC-006 mesurables
- [x] Edge cases identifiés
- [x] Out of Scope explicite (gradient animé droppé)

## Architecture Quality
- [x] Plafond 280 LOC strict (cible 200)
- [x] 3 fichiers Swift max
- [x] `ignoresMouseEvents = true` impératif
- [x] Compatible avec ou sans SPEC-007 (graceful fallback)

## Constitution Compliance
- [x] G' minimalisme respecté
- [x] I' pluggable

## Dependencies
- [x] SPEC-004 bloqueur dur
- [x] SPEC-007 optionnel pour pulse
