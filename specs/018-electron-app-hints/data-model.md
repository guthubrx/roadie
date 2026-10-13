# Data Model: Lettres d'accès dans les applications Electron

## AppTargetScanStats (nouveau, valeur du rapport)

Statistiques d'un parcours applicatif. Champ optionnel `scan` de `AppTargetQueryReport` : absent quand aucun parcours n'a eu lieu (permission, pas de fenêtre).

| Champ | Type | Règle |
|---|---|---|
| `bundleID` | String | identifiant de l'application au premier plan, vide si inconnu |
| `isElectron` | Bool | `Contents/Frameworks/Electron Framework.framework` présent |
| `manualAccessibility` | String | `enabled`, `unsupported`, `skipped` |
| `visited` | Int | éléments lus, dernière passe |
| `candidates` | Int | éléments retenus avant filtrage des rôles |
| `offscreen` | Int | éléments écartés car hors du cadre de la fenêtre |
| `maxDepthReached` | Int | profondeur la plus grande lue |
| `atMaxDepth` | Int | éléments à `max_depth`, dont les enfants n'ont pas été lus |
| `sawWebArea` | Bool | un élément de rôle `AXWebArea` a été lu |
| `elapsedMs` | Int | durée totale, relances et attentes comprises |
| `stopReason` | String | `complete`, `timeout`, `limit` |
| `retries` | Int | 0 à 2 |

## Transitions de `manualAccessibility`

- boost inactif pour l'application : `skipped`, aucun appel.
- écriture réussie : `enabled`.
- écriture refusée : `unsupported`. Pour une application Electron, la relance reste permise (issue Electron #37465).
- Pas de lecture préalable : mesure du 2026-10-12, T3 Code répond « inactif » à la lecture même une fois actif.

## Politique de relance

`shouldRetryScan(isElectron, sawWebArea, exploredFully, retries)` = `isElectron && !sawWebArea && exploredFully && retries < 2`, avec `exploredFully` = `stopReason == complete && atMaxDepth == 0`.
