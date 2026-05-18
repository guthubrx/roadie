# Commandes CLI

Toutes les commandes ci-dessous peuvent etre appelees directement avec `./bin/roadie` ou via `./scripts/roadie`.

## Etat et diagnostic

```bash
./bin/roadie daemon health
./bin/roadie daemon heal
./bin/roadie state dump --json
./bin/roadie state audit
./bin/roadie state heal
./bin/roadie metrics --json
./bin/roadie doctor
./bin/roadie self-test
./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie performance thresholds --json
```

Utilisation typique :

- `daemon health` : verifier que le daemon et l'etat sont coherents.
- `state audit` : detecter doublons, references obsoletes ou scopes casses.
- `state heal` : reparer les incoherences conservatrices.
- `metrics --json` : alimenter un script ou un dashboard.
- `performance ...` : lire les interactions recentes depuis le journal, sans instrumentation active du daemon.

## Fenetres et focus

```bash
./bin/roadie windows list
./bin/roadie windows list --json
./bin/roadie focus left|right|up|down
./bin/roadie focus back-and-forth
./bin/roadie move left|right|up|down
./bin/roadie warp left|right|up|down
./bin/roadie resize left|right|up|down
./bin/roadie window display 2
./bin/roadie window desktop 2 --follow
./bin/roadie window reset
```

Cas d'usage :

- naviguer au clavier entre les fenetres tilees;
- revenir au dernier focus avec `focus back-and-forth`;
- envoyer une fenetre vers un autre ecran ou desktop Roadie;
- reset une fenetre recalcitrante avant de relancer le layout.

## Layout

```bash
./bin/roadie mode bsp
./bin/roadie mode mutableBsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie layout plan --json
./bin/roadie layout apply --yes
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout join-with left|right|up|down
./bin/roadie layout insert left|right|up|down
./bin/roadie layout toggle-split [left|right|up|down]
./bin/roadie layout flatten
./bin/roadie layout zoom-parent
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67
./bin/roadie balance
```

Cas d'usage :

- inspecter le plan avant application avec `layout plan`;
- persister une intention manuelle avec `insert` ou `zoom-parent`;
- inverser l'orientation locale de deux voisines en `mutableBsp` avec `toggle-split`;
- ajuster manuellement la largeur de la fenetre active avec `layout width`;
- revenir a un layout lineaire avec `flatten`.

## Navrail

```bash
./bin/roadie rail status
./bin/roadie rail pin
./bin/roadie rail unpin
./bin/roadie rail toggle
```

Le navrail accepte aussi les interactions souris :

- drag d'une miniature vers une stage;
- drag d'une miniature vers l'espace actif;
- drag d'une fenetre d'application par sa barre de titre vers une stage ou une zone vide.

## Securite et fichiers generes

```bash
./bin/roadie config validate --json
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --yes --json
./bin/roadie cleanup --dry-run --json
./bin/roadie cleanup --apply
```

Notes :

- `config reload` valide avant d'appliquer et conserve l'ancienne config si la nouvelle est invalide.
- `restore snapshot` et `restore apply` restent disponibles manuellement; le daemon ecrit aussi un snapshot au demarrage/arret propre.
- le crash watcher restaure uniquement si `roadied` disparait sans marker de sortie propre; `roadied run --yes --no-restore-safety` le desactive.
- `cleanup --dry-run` affiche ce qui serait supprime ou rotate avant toute action.

## Ecrans, desktops et stages

```bash
./bin/roadie display list
./bin/roadie display current
./bin/roadie display focus 2

./bin/roadie desktop list
./bin/roadie desktop current
./bin/roadie desktop focus 2
./bin/roadie desktop prev
./bin/roadie desktop next
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork

./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage switch-position 2
./bin/roadie stage assign-position 2
./bin/roadie stage switch-visible next
./bin/roadie stage switch-visible prev
./bin/roadie stage assign-empty
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage move-to-display right
./bin/roadie stage move-to-display right --no-follow
./bin/roadie stage prev
./bin/roadie stage next
```

`stage switch` et `stage assign` ciblent les IDs stables. `stage switch-position`
et `stage assign-position` ciblent l'ordre visible du navrail : la position 1 est
la premiere stage visible, meme si son ID interne est different.
`stage switch-visible prev|next` parcourt uniquement les stages non vides, dans
l'ordre affiche par le navrail. `stage assign-empty` envoie la fenetre active
vers la prochaine stage vide non nommee, ou en cree une si necessaire.

`stage move-to-display` accepte un index d'ecran ou une direction
`left|right|up|down`. Sans flag, Roadie utilise la preference TOML :

```toml
[focus]
stage_move_follows_focus = false
```

`--follow` et `--no-follow` forcent ponctuellement le comportement. Le navrail
propose aussi cette action par clic droit sur une carte de stage, en listant les
autres ecrans disponibles.

## Rules

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

## Groupes de fenetres

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

## Evenements et queries

```bash
./bin/roadie events tail 50
./bin/roadie events subscribe --from-now --initial-state
./bin/roadie events subscribe --from-now --type window.focused --scope window

./bin/roadie query state
./bin/roadie query windows
./bin/roadie query displays
./bin/roadie query desktops
./bin/roadie query stages
./bin/roadie query groups
./bin/roadie query rules
./bin/roadie query health
./bin/roadie query events
./bin/roadie query event_catalog
./bin/roadie query performance
./bin/roadie query restore
./bin/roadie query targets
```

Chaque `query` retourne un JSON stable :

```json
{
  "kind": "windows",
  "data": []
}
```

## Target mode

```bash
./bin/roadie targets list
./bin/roadie targets list --json
./bin/roadie targets list --source roadie|app|all
./bin/roadie targets list --filter TEXT --max 40
./bin/roadie targets pick QUERY_OR_LABEL
./bin/roadie targets pick QUERY_OR_LABEL --action focus|switch|send-active|click|double-click|right-click
./bin/roadie targets inspect TARGET_ID_OR_LABEL
./bin/roadie targets inspect TARGET_ID_OR_LABEL --json
./bin/roadie targets activate TARGET_ID_OR_LABEL --action focus
./bin/roadie targets activate TARGET_ID_OR_LABEL --action switch
./bin/roadie targets activate TARGET_ID_OR_LABEL --action send-active
./bin/roadie targets activate TARGET_ID_OR_LABEL --action click
./bin/roadie targets activate TARGET_ID_OR_LABEL --action double-click
./bin/roadie targets activate TARGET_ID_OR_LABEL --action right-click
./bin/roadie targets show --json --labels-only
./bin/roadie targets hide
```

`--source app` et `--source all` lisent les zones applicatives uniquement si
`[experimental.app_targets].enabled = true`, ou si la commande ajoute
`--include-app-targets`. Les clics applicatifs restent coupes par defaut :
`click`, `double-click` et `right-click` exigent aussi
`[experimental.target_mode].app_mouse_actions_enabled = true`. Les actions
impossibles renvoient une erreur structuree au lieu de tenter un fallback
implicite.

La section `[experimental.target_mode]` permet aussi de couper tout le Target
Mode (`enabled = false`) ou seulement le picker (`picker_enabled = false`).

`targets pick` applique l'action seulement si la requete pointe vers une cible
unique. En cas d'ambiguite, la commande affiche les candidates et ne change pas
le layout.

## Grille et macros

```bash
./bin/roadie grid show --json
./bin/roadie grid show A --visual --duration 2
./bin/roadie grid interactive --duration 10
./bin/roadie grid click A
./bin/roadie grid double-click A
./bin/roadie grid right-click A
./bin/roadie grid move A
./bin/roadie grid scroll-up A
./bin/roadie grid scroll-down A
./bin/roadie grid drag A L

./bin/roadie record start demo --duration 10
./bin/roadie record list
./bin/roadie record inspect demo --json
./bin/roadie record replay demo
./bin/roadie record delete demo
```

La grille est configuree par `[experimental.target_grid]`. Par defaut, les
labels suivent un pavé 3x3 naturel sur clavier Mac AZERTY français :
`A Z E / Q S D / W X C`, soit `hint_characters = "azeqsdwxc"`. Le mode
`interactive` zoome recursivement dans la cellule tapee. `Espace` clique la
zone courante, les fleches deplacent la selection au meme niveau, `Backspace`
remonte, `R` revient a la grille racine et `Esc` annule. Au niveau racine, les
fleches changent l'ecran cible dans la direction demandee. Le comportement au
bord de la grille est configure par `arrow_edge_behavior = "clamp"` ou `"wrap"`.
`wake_mouse_pixels` provoque un micro aller-retour du curseur a chaque changement
de grille pour reveiller les controles hover; `0` le desactive. Si
`mouse_follow_grid = true`, le curseur suit plutot le centre de la cellule
courante, utile pour reveiller les controles d'une video sur un autre ecran.
Si `focus_follow_grid = true`, la fenetre sous la cellule courante prend aussi
le focus.
`label_placement = "callout"` garde les bulles externes; `"center"` place les
labels au milieu des cellules. `overlay_label_background_opacity` regle
l'opacite du fond des labels de grille, de `0.0` transparent a `1.0` opaque.
Le timeout interactif est rearme a chaque mouvement de grille.
Les macros sont configurees par
`[experimental.target_record]`. Les recordings conservent les coordonnees, la
meilleure cible Roadie/AX si disponible, et un chemin de grille de secours. Le
texte saisi n'est pas enregistre par defaut. L'indicateur d'enregistrement se
regle avec `indicator = "notification"`, `"navrail"`, `"both"` ou `"none"`.
Quand il est affiche dans le navrail, `navrail_bottom_offset` controle sa
distance au bas du rail en pixels.
