# Modèle 092

## AlfredGridView (nouveau)
| Champ | Type | Source |
|---|---|---|
| entry | AlfredEntry (`kind: .grid`, `objectUID` = uid de la grille) | workflow, objet |
| columns | Int (1 à 12, défaut 5) | `columncount`, surcharge JSON |
| showTitles, showSubtitles | Bool | `showtitles`, `showsubtitles` |
| titlesInFooter, subtitlesInFooter | Bool | `titlesinfooter`, `subtitlesinfooter` |
| filterable | Bool | `filterable` |
| items | [AlfredItem] | réponse JSON ou liste de chemins |
| preselect | String? | clé `preselect` du JSON |
| variables | [String: String] | schéma au moment de la grille + `variables` de la réponse |

Invariant : une tuile est choisissable au clavier si elle a un titre ou une icône (espaceurs exclus) ; `valid: false` empêche seulement Retour d'envoyer la tuile.

## AlfredObject (étendu)
`externalID: String?` : `inboundconfig.externalid`.

## AlfredEntry.Kind (étendu)
`.grid` : entrée créée par une vue, jamais indexée par mot-clé.

## TargetSearchBar (étendu)
`grid: SearchGrid?` avec `columns`, `showTitles`, `showSubtitles`, `footer: String?`.

## SearchKeyInput.Kind (étendu)
`.move(Int)` : ← (-1) et → (+1) dans une grille.
