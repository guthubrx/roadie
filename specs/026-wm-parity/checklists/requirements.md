# Specification Quality Checklist: WM-Parity Hyprland/Yabai

**Purpose**: Valider la complétude et qualité de spec.md avant `/speckit.plan`
**Created**: 2026-05-05
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — la spec mentionne quelques noms de structures internes (FocusManager, MouseDragHandler, BSPTiler) parce que la feature étend du code existant ; c'est volontaire et acceptable pour une spec interne d'extension d'un projet déjà spécifié.
- [x] Focused on user value and business needs — chaque US explique le pourquoi et le scénario utilisateur.
- [x] Written for non-technical stakeholders — sections US et acceptance lisibles ; la section FR contient nécessairement du jargon technique car ce sont des exigences précises.
- [x] All mandatory sections completed — User Scenarios, Requirements, Success Criteria, Edge Cases, Assumptions tous remplis.

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain — aucun, l'utilisateur a tout confirmé en amont.
- [x] Requirements are testable and unambiguous — chaque FR est formulé avec MUST + critère vérifiable.
- [x] Success criteria are measurable — SC-001 à SC-007 ont tous des seuils numériques/booléens.
- [x] Success criteria are technology-agnostic — sauf SC-007 qui cite la commande de mesure LOC (justifié par la nature constitution G du projet, ce critère EST technique par construction).
- [x] All acceptance scenarios are defined — 6 US chacune avec 3-4 scénarios Given/When/Then.
- [x] Edge cases are identified — section dédiée couvrant tree vide, scratchpad timeout, feedback loop, sécurité shell, etc.
- [x] Scope is clearly bounded — 9 features énumérées explicitement, aucune ouverture vers fonctionnalités hors-périmètre.
- [x] Dependencies and assumptions identified — header `**Dependencies**` rempli, section Assumptions présente.
- [x] **Dependencies declared in spec.md header (OBLIGATOIRE)** — `**Dependencies**: SPEC-016, SPEC-022, SPEC-025`.

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria — chaque FR est mappé à au moins une AC dans une US.
- [x] User scenarios cover primary flows — 6 US couvrant les 9 features (US1 groupe les 3 commandes tree, US2 smart_gaps, US3 scratchpad, US4 sticky, US5 follow focus bidirectionnel = 2 features, US6 signals).
- [x] Feature meets measurable outcomes defined in Success Criteria — SC numériques permettent vérification post-merge.
- [x] No implementation details leak into specification — exception assumée pour les hooks/structures réutilisés (FocusManager, MouseDragHandler, etc.) qui sont des points d'extension nommés, pas des choix d'implémentation.

## Notes

- Cette spec est un **lot consolidé** : 9 features livrées en 1 SPEC, comme demandé explicitement par l'utilisateur. Le découpage initial proposé (5 SPECs distinctes) a été rejeté.
- Tous les toggles TOML ont été décidés en amont, aucune ambiguïté sur les défauts (smart_gaps_solo=false, focus_follows_mouse=false, mouse_follows_focus=false, signals.enabled=true).
- Le sticky_scope par défaut "stage" a été confirmé comme la portée la plus utile pour macOS Stage Manager en mode per_display.
- Pas de `[NEEDS CLARIFICATION]` car toutes les questions ont été tranchées dans la conversation préliminaire (table de décision toggle TOML + clarification sticky scope).
