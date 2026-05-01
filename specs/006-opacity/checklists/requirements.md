# Specification Quality Checklist: SPEC-006 opacity

**Created** : 2026-05-01

## Content Quality
- [x] No implementation details dans `spec.md` (détails dans `plan.md`)
- [x] Focus utilisateur (Bob power user)
- [x] Toutes sections complétées

## Requirement Completeness
- [x] Aucun `[NEEDS CLARIFICATION]`
- [x] FR-001..FR-008 testables
- [x] SC-001..SC-007 mesurables
- [x] Edge cases identifiés
- [x] Out of Scope explicite

## Architecture Quality
- [x] Plafond 220 LOC strict (cible 150)
- [x] Logique pure (`targetAlpha`) séparée du module wrapper → testable unitairement
- [x] Compat avec ou sans SPEC-007 chargé (`animate_dim` no-op si absent)
- [x] Extension SPEC-002 minimale et bornée (+10 LOC `StageHideOverride`)

## Constitution Compliance
- [x] G' minimalisme respecté
- [x] I' pluggable respecté
- [x] C' (amendée 1.3.0) : SPEC-006 fait partie famille SIP-off déclarée

## Dependencies
- [x] SPEC-004 listée bloqueur dur (T010)
- [x] SPEC-002 extension localisée (T015)
- [x] SPEC-007 listée optionnelle (animate_dim graceful fallback)
