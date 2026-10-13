# Commandes CLI

Toutes les commandes ci-dessous utilisent le binaire `roadie`. `make install` le place dans `~/.local/bin` ; ajoute ce dossier à ton `PATH`. Depuis les sources, `./scripts/roadie` lance les mêmes commandes avec `swift run`.

Quand le daemon tourne, `roadie` lui envoie chaque commande par le socket `~/.roadies/roadied.sock`. La commande n'a pas besoin de sa propre permission Accessibilité. Si le daemon est arrêté, `roadie` exécute la commande lui-même et a alors besoin de la permission. `daemon start|stop|restart|health`, `doctor`, `permissions` et `config validate` tournent toujours en local.

## Etat et diagnostic

```bash
roadie daemon health
roadie daemon heal
roadie state dump --json
roadie state audit
roadie state heal
roadie metrics --json
roadie doctor
roadie self-test
roadie performance summary
roadie performance recent --limit 20
roadie performance thresholds --json
```

Utilisation typique :

- `daemon health` : verifier que le daemon et l'etat sont coherents.
- `doctor` : rapport complet sur le daemon (en marche ou non), les permissions Accessibilité et Enregistrement d'écran, et la validité de la configuration. Il lit `~/.roadies/daemon-status.json`, que le daemon met à jour régulièrement.
- `--version` : affiche la version. `roadied --version` fait de même pour le binaire du daemon.
- `state audit` : detecter doublons, references obsoletes ou scopes casses.
- `state heal` : reparer les incoherences conservatrices.
- `metrics --json` : alimenter un script ou un dashboard.
- `performance ...` : lire les interactions recentes depuis le journal, sans instrumentation active du daemon.

## Fenetres et focus

```bash
roadie windows list
roadie windows list --json
roadie focus left|right|up|down
roadie focus back-and-forth
roadie move left|right|up|down
roadie warp left|right|up|down
roadie resize left|right|up|down
roadie window display 2
roadie window desktop 2 --follow
roadie window reset
roadie toggle maximize
roadie toggle fullscreen
roadie toggle native-fullscreen
```

`roadie toggle maximize` agrandit la fenêtre active en gardant la bande du navrail visible libre. Relance la commande pour restaurer la disposition. Les voisines de la même stage sont cachées pendant la maximisation. Activer une autre fenêtre de cette stage restaure directement la disposition. Changer de stage conserve le zoom sauvegardé. Avec le masquage automatique, le rail masqué laisse toute la zone utile, comme le plein écran Roadie. Quand il revient au survol ou avec `roadie rail pin`, la fenêtre se redimensionne pour lui laisser la place, sans quitter la maximisation. Le menu de titre propose aussi « Fenêtre → Maximiser / restaurer (garder le navrail) » lorsqu'il est activé.

`roadie toggle fullscreen` utilise toute la zone utile, avec le rail au-dessus. `roadie toggle native-fullscreen` utilise le plein écran macOS. Les deux modes Roadie peuvent se remplacer directement ; répéter le mode actif restaure la disposition précédente.

Cas d'usage :

- naviguer au clavier entre les fenetres tilees;
- revenir au dernier focus avec `focus back-and-forth`;
- envoyer une fenetre vers un autre ecran ou desktop Roadie;
- reset une fenetre recalcitrante avant de relancer le layout.

## Layout

```bash
roadie mode bsp
roadie mode spatialBsp
roadie mode masterStack
roadie mode float
roadie layout plan --json
roadie layout apply --yes
roadie layout split horizontal
roadie layout split vertical
roadie layout join-with left|right|up|down
roadie layout insert left|right|up|down
roadie layout toggle-split [left|right|up|down]
roadie layout flatten
roadie layout zoom-parent
roadie layout width next
roadie layout width prev
roadie layout width nudge 0.05
roadie layout width ratio 0.67
roadie balance
```

Cas d'usage :

- inspecter le plan avant application avec `layout plan`;
- modifier l’arbre enregistré avec `warp`, `resize` ou `layout split`;
- inverser l'orientation locale de deux voisines en `spatialBsp` avec `toggle-split`;
- ajuster manuellement la largeur de la fenetre active avec `layout width`;
- équilibrer l’arbre existant avec `flatten` en `spatialBsp`.

Dans `spatialBsp`, `layout insert` et `layout join-with` sont refusés : utilise `warp`. `layout width` est refusé : utilise `resize`. `layout flatten` équilibre l’arbre existant. Les anciennes commandes restent disponibles dans les autres modes compatibles.

## Navrail

```bash
roadie rail status
roadie rail pin
roadie rail unpin
roadie rail toggle
```

Le navrail accepte aussi les interactions souris :

- drag d'une miniature vers une stage;
- drag d'une miniature vers l'espace actif;
- drag d'une fenetre d'application par sa barre de titre vers une stage ou une zone vide.

## Securite et fichiers generes

```bash
roadie config validate --json
roadie config reload --json
roadie restore snapshot --json
roadie restore status --json
roadie restore apply --yes --json
roadie restore unhide-all
roadie cleanup --dry-run --json
roadie cleanup --apply
```

Notes :

- `config reload` valide avant d'appliquer et conserve l'ancienne config si la nouvelle est invalide.
- `restore unhide-all` ramène à l'écran toutes les fenêtres masquées ou parquées par Roadie. Utilise-la après un crash, ou avant de désinstaller Roadie (`make uninstall` la lance pour toi).
- `restore snapshot` et `restore apply` restent disponibles manuellement; le daemon ecrit aussi un snapshot au demarrage/arret propre.
- le daemon remet les fenêtres masquées quand il s'arrête, et un watcher le fait après un crash; `roadied run --yes --no-restore-safety` désactive les deux.
- `cleanup --dry-run` affiche ce qui serait supprime ou rotate avant toute action.

## Ecrans, desktops et stages

```bash
roadie display list
roadie display current
roadie display focus 2

roadie desktop list
roadie desktop current
roadie desktop focus 2
roadie desktop prev
roadie desktop next
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork

roadie stage list
roadie stage create 4
roadie stage rename 4 Comms
roadie stage switch 2
roadie stage assign 2
roadie stage switch-position 2
roadie stage assign-position 2
roadie stage switch-visible next
roadie stage switch-visible prev
roadie stage assign-empty
roadie stage summon WINDOW_ID
roadie stage move-to-display 2
roadie stage move-to-display right
roadie stage move-to-display right --no-follow
roadie stage prev
roadie stage next
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
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

## Groupes de fenetres

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

## Evenements et queries

```bash
roadie events tail 50
roadie events subscribe --from-now --initial-state
roadie events subscribe --from-now --type window.focused --scope window

roadie query state
roadie query windows
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
roadie query event_catalog
roadie query performance
roadie query restore
roadie query targets
```

Chaque `query` retourne un JSON stable :

```json
{
  "kind": "windows",
  "data": []
}
```

## Mode Cibles

```bash
roadie targets list
roadie targets list --json
roadie targets list --source roadie|app|all
roadie targets list --filter TEXT --max 40
roadie targets pick QUERY_OR_LABEL
roadie targets pick QUERY_OR_LABEL --action focus|switch|send-active|click|double-click|right-click
roadie targets inspect TARGET_ID_OR_LABEL
roadie targets inspect TARGET_ID_OR_LABEL --json
roadie targets activate TARGET_ID_OR_LABEL --action focus
roadie targets activate TARGET_ID_OR_LABEL --action switch
roadie targets activate TARGET_ID_OR_LABEL --action send-active
roadie targets activate TARGET_ID_OR_LABEL --action click
roadie targets activate TARGET_ID_OR_LABEL --action double-click
roadie targets activate TARGET_ID_OR_LABEL --action right-click
roadie targets activate TARGET_ID_OR_LABEL --action command-click
roadie targets search
roadie targets show --json --labels-only
roadie targets hide
```

`--source app` et `--source all` lisent les zones applicatives uniquement si
`[experimental.app_targets].enabled = true`, ou si la commande ajoute
`--include-app-targets`. Les clics applicatifs restent coupes par defaut :
`click`, `double-click` et `right-click` exigent aussi
`[experimental.target_mode].app_mouse_actions_enabled = true`. Les actions
impossibles renvoient une erreur structuree au lieu de tenter un fallback
implicite.

La section `[experimental.target_mode]` permet aussi de couper tout le Mode
Cibles (`enabled = false`) ou seulement le picker (`picker_enabled = false`).

`targets search` ouvre le mode recherche (barre de saisie, toutes les fenetres
visibles), comme le raccourci `search_hotkey` (Hyper+F par defaut). Voir
`docs/fr/features.md`, section Mode recherche.

Dans cette barre, un `/` en premier caractère ouvre le mode commande. Ses
commandes (`/move`, `/stage`, `/screen`, `/bm`, `/grid`, `/doctor`, `/set`,
`/settings`...) appellent les mêmes services que les commandes `roadie`
ci-dessus, sans passer par le socket. Elles exigent que le daemon tourne. Voir
`docs/fr/features.md`, section Mode commande (`/`) et fenêtre de réglages.

`targets pick` applique l'action seulement si la requete pointe vers une cible
unique. En cas d'ambiguite, la commande affiche les candidates et ne change pas
le layout.

## Grille Ecran, Grille Fenetre Et Macros

```bash
roadie grid show --json
roadie grid show A --visual --duration 2
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
roadie grid click A
roadie grid double-click A
roadie grid right-click A
roadie grid move A
roadie grid scroll-up A
roadie grid scroll-down A
roadie grid drag A L

roadie record start demo --duration 10
roadie record list
roadie record inspect demo --json
roadie record replay demo
roadie record delete demo
```

Les deux grilles sont configurees par `[experimental.target_grid]`.
`--scope display` correspond a la **Grille Ecran** et utilise l'ecran cible
complet. `--scope focused_window` correspond a la **Grille Fenetre** et utilise
la fenetre focussee comme racine, avec la meme recursion. Par defaut, les
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

## Raccourcis

Roadie n'a pas de moteur de raccourcis clavier. Utilise un outil qui lance une commande à l'appui d'une touche. Le dossier `examples/` contient des fichiers prêts à l'emploi :

- `examples/skhd/skhdrc` : raccourcis pour [skhd](https://github.com/koekeishiya/skhd). Copie-le vers `~/.config/skhd/skhdrc`, puis lance `skhd --reload`.
- `examples/karabiner/roadie.json` : règles pour Karabiner-Elements. Copie-le vers `~/.config/karabiner/assets/complex_modifications/`, puis active les règles dans Karabiner-Elements > Complex Modifications > Add predefined rule.

Les deux fichiers appellent `~/.local/bin/roadie`. Ils couvrent le focus, le déplacement de fenêtre, le changement de stage et de desktop, le mode de layout et le rééquilibrage. Avec BetterTouchTool, crée un déclencheur de type « Execute Terminal Command » avec les mêmes commandes.

Comme le daemon exécute les commandes, ces outils n'ont pas besoin de la permission Accessibilité pour `roadie` (voir [Permissions](../../README.fr.md#permissions)).
