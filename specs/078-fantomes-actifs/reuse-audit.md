# Audit de réutilisation 078

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Disposition future | `layoutPlan`, `reconciledTree`, `BSPTree.inserting`, `LayoutPlanner.plan` | RÉUTILISER ; CRÉER une méthode qui les combine avec un identifiant fantôme |
| Suspension | pause Mission Control interne à `LayoutMaintainer` (non partageable) | CRÉER `LayoutPreviewHold`, même sortie tôt |
| Écriture | `SnapshotService.apply` (registre des cadres écrits) | RÉUTILISER |
| Bascule de stage | `StageCommandService.switchTo(_:displayID:)` | RÉUTILISER |
| Fantôme | fantômes de la vue d'ensemble (dessin d'aperçu de vignettes) | CRÉER un dessin simple dans l'overlay de la barre (autre vue, autre repère) |
| Fenêtre fantôme gérée | — | ÉCARTÉ (research R1) |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
