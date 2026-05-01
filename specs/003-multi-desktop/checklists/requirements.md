# Specification Quality Checklist: Multi-desktop awareness (V2)

**Purpose** : Validate specification completeness and quality before proceeding to planning
**Created** : 2026-05-01
**Feature** : [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs) — *exception assumée : 2 références à SkyLight/CGSGetActiveSpace nécessaires pour cadrer la contrainte technique vs SIP, justifiable comme "constraint" et non "implementation"*
- [X] Focused on user value and business needs
- [X] Written for non-technical stakeholders — *vocabulaire macOS standard (desktop, stage), terminologie expliquée en intro*
- [X] All mandatory sections completed (User Scenarios, Requirements, Success Criteria)

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain — *1 marqueur restant en FR-024 sur la faisabilité du window-pinning sans SIP off, marqué intentionnellement comme "à investiguer en plan"*
- [X] Requirements are testable and unambiguous
- [X] Success criteria are measurable (SC-001 à SC-009 tous chiffrés)
- [X] Success criteria are technology-agnostic (formulés côté utilisateur : "switch en moins de 200 ms", "100 % de restauration", etc.)
- [X] All acceptance scenarios are defined (3-4 scénarios par user story)
- [X] Edge cases are identified (8 cas listés)
- [X] Scope is clearly bounded (Out of Scope V2 listé exhaustivement)
- [X] Dependencies and assumptions identified (5 assumptions explicites)
- [X] **Dependencies declared in spec.md header (OBLIGATOIRE)** : SPEC-002-tiler-stage déclaré

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria (24 FR avec scenarios)
- [X] User scenarios cover primary flows (4 user stories P1+P2)
- [X] Feature meets measurable outcomes defined in Success Criteria
- [X] No implementation details leak into specification (sauf l'exception cadrée plus haut sur SkyLight)

## Notes

- Le marqueur `[NEEDS CLARIFICATION]` en FR-024 est **intentionnel** : la faisabilité du window-pinning macOS sans SIP désactivé est une question technique qui se résout en Phase Plan/Research, pas en Phase Spec. Un fallback "best-effort" est documenté dans le FR lui-même, donc le scope feature reste bien bounded même si l'investigation technique conclut "infaisable".
- La référence à SkyLight et `CGSGetActiveSpace` dans les FR est une **contrainte** (non-utilisation de SIP off) plutôt qu'un détail d'implémentation. Acceptable selon les guidelines SpecKit : `Avoid HOW to implement (no tech stack, APIs, code structure)` — ici on précise *quelle* API privée *ne pas* utiliser (SIP off), pas *comment* coder.
- Bon-à-savoir : la migration FR-023 de V1→V2 est zéro régression utilisateur — c'est une exigence forte qui sera retestée à chaque commit V2.
- 4 user stories : 2 × P1 (fondation + CLI), 2 × P2 (events stream + per-desktop config). Aucune P3 puisque tout ce qui est ambitieux mais non-MVP est explicitement out-of-scope V2.
