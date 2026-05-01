# Specification Quality Checklist: SPEC-004 fx-framework

**Purpose** : Validation completude avant Phase 2 plan (déjà rédigé)
**Created** : 2026-05-01
**Feature** : [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (langages, frameworks) dans `spec.md` (les détails sont dans `plan.md`)
- [x] Focus sur la valeur utilisateur (Alice vanilla, Bob power, Charlie hybride, Diane désinstall)
- [x] Lisible par non-tech (les sections "User Scenarios" sont en français clair)
- [x] Toutes les sections obligatoires complétées

## Requirement Completeness

- [x] Aucun marqueur `[NEEDS CLARIFICATION]` restant
- [x] Requirements testables et non-ambigus (chaque FR a une condition de pass mesurable)
- [x] Success criteria mesurables (SC-001 à SC-009 quantifiés)
- [x] Success criteria technologie-agnostiques (parlent de comportement, pas d'implémentation)
- [x] Acceptance scenarios définis pour chaque user story
- [x] Edge cases identifiés (SIP fully on, osax disparue, crash module, UID mismatch, etc.)
- [x] Scope clairement borné (Out of Scope explicite)

## Architecture Quality

- [x] Compartimentation totale documentée (P1)
- [x] Daemon dealbreaker sans SIP documenté et testable (US1 + SC-007 + T055)
- [x] Plafond LOC strict 800 (cible 600) — accepté par utilisateur
- [x] Pas de feature qui ne soit pas justifiée par un user scenario concret
- [x] Insistance minimalisme rappelée à chaque tâche (tasks.md "Garde-fou minimalisme")

## Constitution Compliance

- [x] Amendement constitution-002 explicitement requis (T010 dans tasks.md)
- [x] ADR-004 prévu pour tracer l'amendement (T011 dans tasks.md)
- [x] Conditions de garde explicites (6 points dans research.md décision 7)
- [x] Plafond LOC déclaré et mesurable (T123 dans tasks.md)
- [x] Gate `nm | grep CGSSetWindow*` automatisé (T052 + T123 dans tasks.md)

## Dependencies & Coordination

- [x] SPEC-002 et SPEC-003 listés en dépendances (parallélisable via worktrees)
- [x] Famille SPEC-005 à SPEC-010 listée comme suite (out of scope strict pour 004)
- [x] Modules `.dynamicLibrary` séparés du daemon par construction
