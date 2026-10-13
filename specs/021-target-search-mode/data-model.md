# Data Model: Mode recherche

## TargetSearchModel (valeur)

| Champ | Type | Règle |
|---|---|---|
| `targets` | [RoadieTarget] | cibles de la session (labels déjà attribués) |
| `query` | String | texte tapé |
| `matches` | [RoadieTarget] | correspondances : `*`/`;` ou requête vide = toutes ; sinon « contient » sur texte compact (normalisé, sans espaces) ; titres qui commencent par la requête d'abord |
| `highlightedIndex` | Int? | index dans `matches` ; 0 après chaque frappe ; nil si aucune |
| `showsProperties` | Bool | vrai après `?` jusqu'à la frappe suivante |

Opérations : `type(_:)`, `deleteBackward()`, `next()`, `previous()` (en boucle), `typeLabel(_:)`, `pressReturn(shift:command:at:)` et `pendingReturn(at:)` → `TargetActionVerb?` (Maj = clic droit ; Cmd = Cmd-clic ; Retour seul différé de 0,35 s ; un second Retour dans ce délai = double-clic sur la **même cible figée**).

## SearchHotkey (valeur)

`"cmd+alt+ctrl+f"` → modificateurs Carbon (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`) + touche (caractère ou nom : `space`, `return`, `tab`, `escape`, `f1`-`f12`). Alias acceptés : `command`/`cmd`, `option`/`alt`, `control`/`ctrl`, `shift`, `hyper` (= cmd+alt+ctrl). Chaîne vide = désactivé. Au moins un modificateur requis.

## Config

`[experimental.target_mode] search_hotkey = "cmd+alt+ctrl+f"` (défaut).

## RoadieTarget (inchangé) ; AppElementCandidate

`AppElementCandidate.searchText` : texte des `AXStaticText` descendants d'un candidat web qui ne contient aucun autre candidat (500 caractères max), ajouté au `matchText` ; `title` inchangé.
