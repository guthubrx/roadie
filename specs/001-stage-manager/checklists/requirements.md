# Specification Quality Checklist: Stage Manager Suckless

**Purpose** : Valider la complétude et la qualité de la spec avant passage en planification
**Créé** : 2026-05-01
**Feature** : [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — *les détails techniques (Swift, AX API, CGWindowID) sont confinés à la section Assumptions et Research Findings, pas dans les requirements ni les user stories*
- [x] Focused on user value and business needs — *user stories formulées en termes de contextes de travail et bascule, pas en termes techniques*
- [x] Written for non-technical stakeholders — *les FR utilisent un vocabulaire système accessible (fenêtre, stage, identifiant), évite les noms d'API*
- [x] All mandatory sections completed — *User Scenarios, Requirements, Success Criteria tous remplis*

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain — *aucun marqueur dans le document*
- [x] Requirements are testable and unambiguous — *chaque FR exprime une condition vérifiable (ex. FR-006 sur l'auto-GC, FR-008 sur le code de sortie)*
- [x] Success criteria are measurable — *latences, taille binaire, taux de plantage tous chiffrés (SC-001 à SC-007)*
- [x] Success criteria are technology-agnostic — *pas de mention Swift/swiftc/AX dans les SC ; "binaire compilé" reste neutre*
- [x] All acceptance scenarios are defined — *3 user stories avec 2-3 scénarios chacune*
- [x] Edge cases are identified — *6 edge cases listés (permission, argument invalide, fichier corrompu, manuelle, multi-fenêtre, multi-app)*
- [x] Scope is clearly bounded — *section "Out of Scope (V1)" explicite avec 8 exclusions*
- [x] Dependencies and assumptions identified — *section Assumptions avec 7 hypothèses, Out of Scope avec 8 exclusions*
- [x] Dependencies declared in spec.md header (OBLIGATOIRE) — *ligne `**Dependencies**: None` présente, première spec du projet, aucune dépendance amont*

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria — *chaque FR est tracée à un edge case ou un scenario de user story*
- [x] User scenarios cover primary flows — *bascule (US1), assignation (US2), tolérance aux disparitions (US3) couvrent l'intégralité du cycle de vie*
- [x] Feature meets measurable outcomes defined in Success Criteria — *les SC chiffrés couvrent perf (SC-001/002), empreinte (SC-003/004), robustesse (SC-005/006), UX (SC-007)*
- [x] No implementation details leak into specification — *toute mention de Swift, AX, CGWindowID est cantonnée aux sections Assumptions et Research Findings, jamais dans les requirements ni les success criteria*

## Notes

- Spec validée en autonomie complète (mode `/my.specify-all`).
- Tous les items passent à la première itération.
- Constitution projet locale (`.specify/memory/constitution.md`) déjà alignée avec les principes suckless / mono-fichier / 0 dépendance / CGWindowID stable / fail loud.
- Dépendance `None` confirmée : c'est la première spec du projet 39.roadies. Aucune feature amont à attendre.
- Aucun red flag bloquant identifié dans la phase de recherche préalable (cf. section Research Findings du spec.md).
