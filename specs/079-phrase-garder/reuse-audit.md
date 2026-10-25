# Audit de réutilisation 079

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Analyse de phrase | appariement `LauncherMatch`, destinations 074 | RÉUTILISER ; CRÉER `LauncherPhrase` (aucun analyseur) |
| Alias | historique du mode commande (autre usage) ; lot 3 F10 prévu | CRÉER `LauncherAliases` (fichier local, `JSONPersistence`) |
| Position | `WindowCommandService.warp`, `toggleMaximize`, `WindowContextActions.toggleFloating` | RÉUTILISER |
| Commande | `roadie launch` (077) | RÉUTILISER, option `--position` |
| Étape « Garder » | étapes verbes/destinations 074 | RÉUTILISER le même mécanisme |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
