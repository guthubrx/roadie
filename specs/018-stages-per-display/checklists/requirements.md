# Specification Quality Checklist: SPEC-018 Stages-per-display

**Purpose**: Valider la complétude et la qualité de la spec avant de passer à la planification.
**Created**: 2026-05-02
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
  - *Note* : la spec mentionne `CGDisplayCreateUUIDFromDisplayID`, `NSEvent.mouseLocation`, TOMLKit — choix techniques alignés sur SPEC-002/012/013, documentés en "Principes architecturaux non-négociables" et "Constitution Check"
- [X] Focused on user value and business needs
  - 5 user stories centrées sur l'isolation par écran, la migration, la compat global mode, le power-user override, la cohérence avec le rail
- [X] Written for non-technical stakeholders
  - Vocabulaire technique encadré, justifications fonctionnelles partout
- [X] All mandatory sections completed
  - Vision, User Scenarios, Functional Requirements, Success Criteria, Key Entities, Out of Scope, Assumptions, Risks, Constitution Check, Open Questions

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
  - La description utilisateur est exhaustive, aucune ambiguïté résiduelle
- [X] Requirements are testable and unambiguous
  - 21 FR rédigés impératifs, chacun mesurable
- [X] Success criteria are measurable
  - 8 SC quantifiés : SC-002 (500 ms / 50 stages), SC-004 (5 ms p95), SC-005 (RSS ±10%), SC-007 (test manuel + screenshot)
- [X] Success criteria are technology-agnostic
  - SC énoncent latence/perf/comportement observable, pas API
- [X] All acceptance scenarios are defined
  - Chaque user story a 2-3 acceptance scenarios numérotés
- [X] Edge cases are identified
  - Risques tabulés : migration corrompue, curseur hors écran, hot-switch mode, displayUUID conflict
- [X] Scope is clearly bounded
  - "Out of Scope V1" liste 5 exclusions explicites (drag cross-display, stages partagées, UI rail, sync cloud, multi-machine)
- [X] Dependencies and assumptions identified
  - Dependencies header : SPEC-002, SPEC-011, SPEC-012, SPEC-013. Section "Assumptions" : 4 hypothèses
- [X] **Dependencies declared in spec.md header (OBLIGATOIRE)**
  - `**Dependencies**: SPEC-002, SPEC-011, SPEC-012, SPEC-013`
  - `**Blocks**: SPEC-014` (information ascendante)

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
  - Mapping FR → user story / SC documenté
- [X] User scenarios cover primary flows
  - US1-US5 = MVP complet (isolation + migration + global compat + override + rail coherence)
- [X] Feature meets measurable outcomes defined in Success Criteria
  - 8 SC couvrent les 5 user stories + perf + observabilité
- [X] No implementation details leak into specification
  - Les rares mentions techniques sont justifiées (cohérence SPEC-012/013, types Apple stables)

## Constitution Compliance

- [X] Article A — pas de mono-fichier > 200 LOC effectives
  - Découpage prévu : StageManagerV2.swift, StageScope.swift, StagePersistenceV2.swift, MigrationV1V2.swift
- [X] Article B — zéro dépendance externe non justifiée
  - Aucune nouvelle dépendance Swift Package
- [X] Article C' — pas de SkyLight write privé
  - Lecture seule via CGDisplayCreateUUIDFromDisplayID (API publique CoreGraphics)
- [X] Article D — pas de `try!`, pas de `print()`
  - Convention du projet, à respecter dans l'implémentation
- [X] Article G — plafond LOC déclaré
  - Cible 600 / plafond 900 LOC

## Verdict

**PASS** — la spec est prête pour le passage en plan + tasks. Toutes les sections obligatoires sont complètes, aucune ambiguïté résiduelle, success criteria mesurables, scope clairement borné, dépendances déclarées, compat ascendante explicite.
