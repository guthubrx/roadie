# Analyse de cohérence - 023-command-box-settings

Date : 2026-10-13. Protocole : lecture croisée de `spec.md`, `plan.md`, `tasks.md`, constitution (primitive `speckit-analyze` exécutée en mode manuel : lecture seule, corrections appliquées ensuite).

## Constats et corrections

| ID | Catégorie | Sévérité | Constat | Correction |
|---|---|---|---|---|
| I1 | Incohérence | HIGH | La catégorie Général (ouverte à la première ouverture) n'était implémentée qu'en T022 (P3) alors que T018 (P1) ouvre la fenêtre | Général déplacée dans T018 |
| U1 | Sous-spécification | MEDIUM | Constitution XV (1 tâche = 1 commit, journal, build + tests avant de cocher) absente de `tasks.md` | règles ajoutées en tête de `tasks.md` |
| U2 | Sous-spécification | MEDIUM | Constitution VII (ADR pour une décision structurante : première fenêtre SwiftUI, éditeur TOML) sans tâche | T026 ajoutée |
| U3 | Sous-spécification | MEDIUM | `reset` retire la ligne de la clé, mais aucun test de `value == nil` | T003 et T007 complétées |
| T1 | Ordonnancement | MEDIUM | T008, T012, T014 modifient le même fichier `TargetOverlayPresenter.swift` sans ordre déclaré | note « fichier commun » dans les dépendances |
| T2 | Taille | MEDIUM | T014 mêlait aiguillage, exécution et dessin | scindée en T014 (aiguillage, exécution) et T014b (affichage) |
| A1 | Ambiguïté | LOW | T002 : formulation floue pour `editDistance` | `RoadieConfigLoader.editDistance(_:_:)` public, délègue à l'existant |
| XVIII | Constitution | LOW | Annotation de complexité non rappelée | règle ajoutée en tête de `tasks.md` |

## Couverture

| Exigence | Tâches |
|---|---|
| FR-001 à FR-003, FR-009 | T010, T011, T012, T013, T014, T014b |
| FR-004 | T013, T014 (contexte actif à l'exécution) |
| FR-005, FR-006 | T010, T013, T016 |
| FR-007, FR-008 | T011, T013, T021 |
| FR-010 | T012 (tests existants inchangés), T024 |
| FR-011, FR-012, FR-018, FR-019 | T017, T018 |
| FR-013, FR-014, FR-015, FR-016, FR-017 | T004, T005, T007, T018, T022 |
| FR-020, FR-021, FR-022 | T019, T020 |
| FR-023 | T004, T006 |
| FR-024 | T003, T007 |
| FR-025 à FR-027 | T001, T008, T009 |
| FR-028 | T023 |
| FR-029 | T007, T013 |
| SC-001, SC-002, SC-003 | T025 |
| SC-004 | T010 |
| SC-005 | T007 |
| SC-006 | T024 |
| SC-007 | T006 |
| SC-008 | T013 |

Aucun FR ni SC sans tâche. Aucune tâche sans exigence ou décision de plan. Aucun finding CRITICAL. Seconde lecture après corrections : aucun nouvel écart.
