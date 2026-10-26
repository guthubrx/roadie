# Audit de réutilisation 090

Statut : `OK`. Repli manuel (`rg`), 26 octobre 2026.

| Élément | Existant | Issue |
|---|---|---|
| Recherche web | `LauncherWeb.searchURL`, `web_search_url` (075) | RÉUTILISER, étendre `LauncherWeb` |
| Reconnaissance d'adresse | aucune | CRÉER dans `LauncherWeb` |
| Nouvelle fenêtre placée | `placeNewWindow` (074/080), `LauncherBrowsers` (082) | RÉUTILISER |
| Historique | aucun `launcher-history` ; motif de magasin JSON (`LauncherMemoryStore`, `LauncherAliasStore`) | CRÉER `LauncherHistoryStore` sur le même motif |
| Barre vide | `idleRows` (081) | RÉUTILISER, section ajoutée |
| Réglages | `TargetModeConfig` | RÉUTILISER |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
