# Audit de réutilisation 082

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Document des fenêtres | `axDocumentRead`, `LauncherDocuments` (077) | RÉUTILISER |
| Onglets | aucun appel AppleScript de navigateur | CRÉER `LauncherOpenItems` (scripts, lecture) |
| Aller à la fenêtre | `WindowSwitcherService.activate` | RÉUTILISER |
| Chargement en fond | `refreshApps` du contexte (073) | RÉUTILISER le même modèle de rappel |
| Section | `LauncherList.Section` | RÉUTILISER |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
