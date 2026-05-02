# Specification Quality Checklist: SPEC-014 Stage Rail UI

**Purpose**: Valider la complétude et la qualité de la spec avant de passer à la planification et à l'implémentation.
**Created**: 2026-05-02
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
  - *Note* : `spec.md` mentionne SwiftUI macOS 14+, ScreenCaptureKit, NSPanel — ces choix ont été **explicitement validés par l'utilisateur** dans la session interactive du 2026-05-02 et constituent des décisions de scope, pas des fuites d'implémentation. Documentés en tant que tels en section "Principes architecturaux non-négociables" et "Assumptions".
- [X] Focused on user value and business needs
  - 7 user stories centrées sur l'expérience utilisateur (révéler le rail, basculer, drag-drop, click wallpaper, etc.).
- [X] Written for non-technical stakeholders
  - Vocabulaire technique encadré (ScreenCaptureKit, NSPanel) toujours accompagné d'une justification fonctionnelle.
- [X] All mandatory sections completed
  - Vision, User Scenarios, Functional Requirements, Success Criteria, Key Entities, Out of Scope, Assumptions, Risks, Constitution Check, Open Questions.

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
  - Toutes les ambiguïtés ont été résolues lors des deux passes de questions interactives (8 questions au total). Section "Open Questions" déclare explicitement "aucune".
- [X] Requirements are testable and unambiguous
  - 32 FR rédigés impératifs, chacun mesurable par un test fonctionnel ou d'acceptance.
- [X] Success criteria are measurable
  - 10 SC quantifiés : SC-001 (300 ms), SC-002 (200 ms), SC-003 (300 ms), SC-004 (30 MB / 1 % CPU), SC-006 (1 frame @ 60 Hz), SC-010 (400 ms), etc.
- [X] Success criteria are technology-agnostic (no implementation details)
  - SC-001 à SC-010 énoncent des métriques observables (latence, CPU, RSS), pas des choix d'API.
- [X] All acceptance scenarios are defined
  - Chaque user story a 3-5 acceptance scenarios numérotés.
- [X] Edge cases are identified
  - Section "Edge cases & invariants" dans `data-model.md` couvre 8 cas (daemon down, écran débranché, drag même stage, etc.).
- [X] Scope is clearly bounded
  - "Out of Scope (V1)" liste 7 exclusions explicites (animations entre stages, thèmes utilisateur, stages cross-desktop, edge custom, drag depuis bureau, vignettes live-streaming, mode sans daemon).

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
  - Mapping FR → tests d'acceptance documenté dans `plan.md` Section "Stratégie de tests".
- [X] User scenarios cover primary flows
  - US1-US4 = MVP flow complet (révéler → switch → drag → wallpaper-click).
- [X] Feature meets measurable outcomes defined in Success Criteria
  - Performance budget tabulé dans `plan.md` Phase 2.
- [X] No implementation details leak into specification
  - Les rares mentions techniques sont encadrées et justifiées (cf premier item).

## Constitution Compliance

- [X] Article A — pas de mono-fichier > 200 LOC effectives
  - Plan.md prévoit ~20 fichiers Swift répartis, chacun cible 50-150 LOC.
- [X] Article B — zéro dépendance externe non justifiée
  - Aucune nouvelle dépendance Swift Package. Réutilise TOMLKit déjà présent.
- [X] Article C' — SkyLight write privé interdit hors modules opt-in
  - Le rail = lecture seule via daemon. Le daemon utilise ScreenCaptureKit (API publique macOS 14+).
- [X] Article D — pas de `try!`, pas de `print()`, logger structuré
  - Convention déjà en place dans le projet, à respecter dans l'implémentation.
- [X] Article G — plafond LOC déclaré
  - Cible 1500 / plafond 2000 LOC pour SPEC-014 (cf spec.md "Constitution Check").

## Dependencies & Pre-requisites

- [X] Dependencies on prior specs explicitly declared
  - SPEC-002 (dur), SPEC-011 (dur), SPEC-012 (souple), SPEC-013 (souple) — listés dans spec.md header.
- [X] Pre-requisites for user (permissions, manual steps) documented
  - `quickstart.md` détaille permission Screen Recording (recommandée), config TOML, lancement manuel ou LaunchAgent.

## Verdict

**PASS** — la spec est prête pour le passage en plan + tasks. Toutes les sections obligatoires sont complètes, aucune ambiguïté résiduelle, success criteria mesurables, scope clairement borné.

Cette checklist a été validée le 2026-05-02 dans le cadre du pipeline `/my.specify-all` — Phase 4 Analyze a appliqué 4 fixes (1 MEDIUM + 3 LOW) sur la spec et les tasks pour résoudre les findings de couverture détectés (cf scoring audit cycle 1).
