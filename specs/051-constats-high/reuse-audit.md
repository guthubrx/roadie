# Audit de reutilisation de l'existant - 051 constats HIGH

## Decision

Statut: PASS
Date: 2026-10-18
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/051-constats-high

Conclusion courte: chaque correction réutilise un mécanisme existant ; aucun nouveau type
persistant, service ou dépendance.

## Items du plan

| Item | Existant réutilisé | Décision |
|---|---|---|
| A-02 | `AXWindowIndexCache` (déjà lu par l'écrivain) | REUTILISER |
| A-03 | dictionnaire local au relevé, sur le modèle de `appWindows` | ETENDRE |
| A-04 | `ConfigReloadService.stamp` | ETENDRE |
| A-05 | minuterie existante, reprogrammée | ETENDRE |
| B-01 | schéma « pré-contrôle sans verrou » de `LayoutIntentStore.prune` | REUTILISER |
| C-05 | `managedWindowFrames` du rail, bande de `dragSourceWindow` | REUTILISER |
| C-06 | état replié de `RailPanel` | ETENDRE (accesseur) |
| D-03 | paramètre `using:` de `applyTreeScope` (déjà utilisé par les poignées) | REUTILISER |

## Gate avant tasks

- [x] Chaque item a une ligne de résultat.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan requis.
