# Audit de réutilisation 081

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Déplacements | journal `stage_assign_window` (tournant, sans application) | CRÉER un journal dédié borné (R1) |
| Fenêtre précédente | `WindowSwitcherFocusHistory` | RÉUTILISER |
| Fermées | `confirmedClosedAt` (SPEC-029) | RÉUTILISER |
| Rouvrir | `openWindow(_:into:)` (074) | RÉUTILISER par « Ouvrir dans… » |
| Annuler | `WindowContextActions.assign` | RÉUTILISER par « Envoyer vers » |
| Règle | `WindowRuleAffinityService.saveAffinity` | RÉUTILISER |
| Habitudes | contextes du classement (076) | RÉUTILISER |
| Chip | capsule du compteur de la barre | RÉUTILISER, texte en plus |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
