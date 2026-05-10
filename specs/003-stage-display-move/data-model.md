# Data Model: Stage Display Move

## StageMoveRequest

Represente une demande de deplacement d'une stage vers un autre ecran.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `stageID` | `StageID` | oui | Stage a deplacer. Pour la CLI active, derivee de la stage active. Pour le rail, fournie par la carte cliquee. |
| `sourceDisplayID` | `DisplayID` | oui | Ecran qui possede actuellement la stage. |
| `target` | `DisplayTarget` | oui | Cible par index visible, ID d'ecran resolu, ou direction. |
| `followFocus` | `Bool?` | non | Override ponctuel. Si absent, utiliser la configuration. |
| `source` | enum | oui | `cli`, `railContextMenu`, `test`. Utile pour les evenements et diagnostics. |

## DisplayTarget

| Variant | Data | Resolution |
|---------|------|------------|
| `index` | `Int` | Selectionne l'ecran visible par ordre Roadie courant. |
| `direction` | `left/right/up/down` | Utilise `DisplayTopology.neighbor` depuis `sourceDisplayID`. |
| `id` | `DisplayID` | Utilise par les appels internes du rail apres resolution UI. |

## StageMoveResult

| Field | Type | Description |
|-------|------|-------------|
| `changed` | `Bool` | `true` si le state a change et qu'une application layout a ete tentee. |
| `status` | enum | `moved`, `noopCurrentDisplay`, `invalidTarget`, `ambiguousTarget`, `partialFailure`, `failed`. |
| `stageID` | `StageID` | ID final de la stage deplacee. Peut differer si collision non vide sur cible. |
| `sourceDisplayID` | `DisplayID` | Ecran source. |
| `targetDisplayID` | `DisplayID?` | Ecran cible resolu si disponible. |
| `movedWindowCount` | `Int` | Nombre de fenetres membres traitees. |
| `failedWindowCount` | `Int` | Nombre de fenetres impossibles a deplacer ou redimensionner. |
| `followFocus` | `Bool` | Politique effective appliquee. |
| `message` | `String` | Message utilisateur CLI/log. |

## FocusStageMoveConfig

Nouvelle configuration partagee par CLI et daemon.

```toml
[focus]
stage_move_follows_focus = true
```

Regles :

- valeur absente : `true` ;
- `--follow` force `true` pour l'action courante ;
- `--no-follow` force `false` pour l'action courante ;
- en mode no-follow, l'ecran source garde son contexte actif si possible.

## Stage Ownership Invariants

- Une fenetre ne doit appartenir qu'a une seule stage apres le deplacement.
- Une stage deplacee ne doit plus rester dans la liste de stages du scope source.
- L'ecran source doit conserver une stage active valide.
- L'ecran cible doit conserver ses stages existantes.
- Une collision d'ID ne doit jamais supprimer une stage cible non vide.
- Les layout intents de la stage source et cible doivent etre invalidees pour eviter de rejouer un layout obsolete.

## Event

Le deplacement reussi ou echoue doit produire un evenement `stage_move_display`.

Payload minimal :

```json
{
  "event": "stage_move_display",
  "status": "moved",
  "stageID": "3",
  "requestedStageID": "3",
  "sourceDisplayID": "built-in",
  "targetDisplayID": "lg-hdr-4k",
  "targetDisplayIndex": "2",
  "followFocus": "false",
  "movedWindowCount": "3",
  "failedWindowCount": "0"
}
```
