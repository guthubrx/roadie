# Specification Quality Checklist: Yabai-parity tier-1

**Purpose** : Valider la complétude et la qualité de la spec avant Phase 2 (plan).
**Created** : 2026-05-02
**Feature** : [spec.md](../spec.md)

## Content Quality

- [x] Pas de détails d'implémentation interdits (langages/frameworks/APIs spécifiques) dans les User Stories ou les Functional Requirements visibles user
  - Note : la mention `Swift Foundation/AppKit/CoreGraphics` dans FR-T-04 est une **contrainte de constitution** (Article 0), pas un détail d'implémentation prescriptif — elle EXCLUT des dépendances, donc reste légitime dans la spec.
  - Note : les noms `MouseFollowFocusWatcher`, `RoadieRules`, `SignalDispatcher` sont des **identifiants de concepts architecturaux** déjà en cours d'usage dans le projet (cf. SPEC-002, SPEC-015), nécessaires pour la traçabilité — acceptables.
- [x] Centré sur la valeur user et le besoin business (chaque US a un "Why this priority" explicite)
- [x] Lisible par un stakeholder non-dev (les sections US et SC sont en langage métier, les FR sont la zone technique)
- [x] Toutes les sections obligatoires complétées (User Scenarios, Requirements, Success Criteria, plus Edge Cases, Assumptions, Hors scope)

## Requirement Completeness

- [x] Aucun marqueur `[NEEDS CLARIFICATION]` restant (toutes les zones d'incertitude ont été résolues par défauts inférés et documentés en Assumptions)
- [x] Requirements testables et non-ambigus (chaque FR a un sujet `DOIT`/`MUST`, une condition vérifiable)
- [x] Success Criteria mesurables (SC-016-01 à SC-016-12 ont métriques chiffrées : %, ms, sessions, count)
- [x] Success Criteria technology-agnostic
  - Note : SC-016-09/10 mentionnent yabai par nom, c'est intentionnel (UX parity benchmarkée contre l'outil de référence cité dans la mission projet).
- [x] Tous les acceptance scenarios définis (5 US × 3-10 scénarios chacune)
- [x] Edge cases identifiés (section dédiée par catégorie A1/A2/A4/A5/A6 + génériques)
- [x] Scope clairement borné (section "Hors scope" explicite avec mapping ADR-006 catégories B/C/D)
- [x] Dépendances et assumptions identifiées (header `Dependencies:` + section `Assumptions`)
- [x] **Dependencies déclarées dans le header spec.md** : SPEC-002, SPEC-011, SPEC-012, SPEC-015 ✓

## Feature Readiness

- [x] Tous les FR ont des critères d'acceptance clairs (mapping FR ↔ acceptance scenarios via prefixes A1-A6)
- [x] User scenarios couvrent les flows primaires (MVP US1, P1 US2/US3, P2 US4/US5)
- [x] Feature atteint les outcomes mesurables définis dans Success Criteria (SC tracent vers les US)
- [x] Pas de fuite d'implémentation au-delà des concepts architecturaux nécessaires à la traçabilité

## Risques identifiés (à traiter en Phase 2 plan)

- **R1** — US5 stack mode est invasif (touche le model du LayoutEngine). Risque scope creep. Mitigation : SC-016-07 acte le scope-out vers SPEC-017 si > 8 sessions.
- **R2** — Le SignalDispatcher exec shell async ouvre une surface de bugs (timeouts, zombies, cascades). Mitigation : FR-A2-06/07/08 cadrent les protections.
- **R3** — Coexistence MouseFollowFocusWatcher + MouseModifier (SPEC-015 in flight) nécessite un `MouseInputCoordinator` partagé. Risque race conditions. Mitigation : à designer en Phase 2 avec attention.
- **R4** — Les rules avec `space=N` peuvent migrer une fenêtre **avant** que SPEC-011 ait fini son routing → race possible. Mitigation : tester explicitement la séquence `window_created → rule space=N → SPEC-011 desktop assign`.

## Notes

- Tous les items "incomplete" résolus en mode `/my.specify-all` autonome (zéro question utilisateur).
- Validation passée en 1 itération (pas de re-rédaction nécessaire).
- Spec prête pour `/speckit.plan` (Phase 2).
