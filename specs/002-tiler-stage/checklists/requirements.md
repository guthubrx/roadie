# Specification Quality Checklist: Tiler + Stage Manager modulaire (roadies)

**Purpose** : valider la complétude de la spec avant passage en planification
**Créé** : 2026-05-01
**Feature** : [spec.md](../spec.md)

## Content Quality

- [x] No implementation details in user stories — *les stories décrivent les comportements observables, les détails Swift/AX sont confinés aux Functional Requirements et Research*
- [x] Focused on user value — *click-to-focus fiable, tiling automatique, stages opt-in : tous formulés en termes de bénéfice utilisateur*
- [x] Written for technical stakeholders — *l'audience reste technique mais les FR évitent le jargon Swift inutile*
- [x] All mandatory sections completed — *User Scenarios (4 stories), Requirements (23 FR), Success Criteria (10 SC), Edge Cases (10), Assumptions, Out of Scope*

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers — *aucune ambiguïté résiduelle*
- [x] Requirements testable — *chaque FR exprime une condition vérifiable (ex. FR-001 listing exact des notifications, FR-003 timing 100 ms)*
- [x] Success criteria measurable — *SC chiffrés en ms, MB, %*
- [x] Success criteria technology-agnostic — *acceptable d'avoir Swift mentionné dans Architecture Research, mais SC restent en termes utilisateur (latence, taille, taux de succès)*
- [x] All acceptance scenarios defined — *4 stories avec 2-4 scénarios chacune*
- [x] Edge cases identified — *10 cas couverts (permission, popups, plein écran, multi-monitor, race start, etc.)*
- [x] Scope clearly bounded — *Out of Scope explicite (V2 multi-monitor, plugins tiers, etc.)*
- [x] Dependencies declared — *Dependencies: SPEC-001*

## Feature Readiness

- [x] All FR have clear acceptance criteria — *traçables vers user stories ou edge cases*
- [x] User scenarios cover primary flows — *tiling auto + click-to-focus + stages couvrent les 3 valeurs clés du produit*
- [x] Feature meets measurable outcomes — *SC chiffrés couvrent perf (SC-001/002/003), empreinte (SC-004), qualité (SC-005/006), robustesse (SC-007/008/009), UX (SC-010)*
- [x] No implementation details leak into spec — *Architecture Research et FR techniques séparés des user stories*

## Architectural Soundness

- [x] Modularité respectée — *Tiler et StageManager séparés architecturalement (FR-007 protocole + FR-012 module séparé)*
- [x] Click-to-focus traité comme objectif différenciateur — *FR-003 timing strict + SC-002 + SC-009*
- [x] Sans SIP désactivé — *FR-005 interdiction explicite des SkyLight, scripting addition*
- [x] Plusieurs stratégies de tiling supportées dès V1 — *FR-008 BSP + FR-009 Master-Stack + FR-010 changement runtime*
- [x] Stage manager opt-in — *FR-013 enabled flag*

## Notes

- Spec validée en autonomie. Tous les items passent à la première itération.
- Recherche préalable (yabai + AeroSpace) intégrée en synthèse, détails dans `research.md`.
- 23 FR + 10 SC + 4 user stories + 10 edge cases — couvre largement la complexité du projet.
- LOC totale visée 4 000 lignes Swift effectives — réaliste pour V1 single-monitor.
