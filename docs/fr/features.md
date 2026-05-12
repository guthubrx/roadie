# Fonctionnalites

## Tiling

Roadie tile les fenetres visibles d'une stage active.

Modes disponibles :

- `bsp` : repartition en arbre binaire, adaptee aux workflows terminal/code/navigateur.
- `mutableBsp` : repartition en arbre binaire qui conserve les ratios observes quand les fenetres sont deplacees ou redimensionnees.
- `masterStack` : une fenetre principale et une pile secondaire.
- `float` : Roadie garde les fenetres dans l'etat de stage mais ne les retile pas.

Exemples :

```bash
./bin/roadie mode bsp
./bin/roadie mode mutableBsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie balance
```

Cas d'usage :

- developpement avec editeur en master et terminaux en stack;
- experimentations BSP proches de yabai ou les mouvements manuels doivent influencer le prochain tiling;
- operations multi-ecran avec chaque ecran dans un mode different;
- pause temporaire du tiling sur une stage en `float`.

## Stages

Une stage est un groupe nomme de fenetres dans un desktop Roadie. Seule la stage active est visible; les autres sont masquees et restent recuperables.

```bash
./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage switch-position 2
./bin/roadie stage assign-position 2
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage move-to-display right --no-follow
```

Les variantes `*-position` suivent l'ordre visible du navrail ; elles sont faites
pour les raccourcis utilisateur de type Alt-1, Alt-2, Alt-3.

Une stage peut aussi etre envoyee vers un autre ecran depuis le menu contextuel
du navrail. Le comportement de focus est controle par `[focus].stage_move_follows_focus`
et peut etre force ponctuellement avec `--follow` ou `--no-follow`.

Cas d'usage :

- isoler une stage `Focus`, une stage `Comms`, une stage `Docs`;
- masquer rapidement un contexte sans fermer les apps;
- ramener une fenetre precise dans la stage active avec `stage summon`.

## Navrail

Le navrail est le panneau lateral par ecran qui represente les stages non vides.
Une stage vide n'y est pas affichee, meme si elle a ete renommee.

Interactions principales :

- cliquer une stage pour l'activer;
- cliquer une zone vide pour basculer vers une stage vide, si `empty_click_hide_active` est active;
- tirer une miniature vers une autre stage pour y deplacer la fenetre;
- tirer une miniature vers l'espace de travail actif pour y rappeler la fenetre;
- tirer une fenetre d'application par sa barre de titre vers une stage pour l'y deplacer;
- tirer une fenetre d'application par sa barre de titre vers une zone vide du navrail pour creer ou utiliser une stage vide.

Les zones reservees par macOS, comme la barre de menu, sont ignorees par les actions de clic vide du navrail.

Les noms de stages du navrail sont configurables. Par defaut, ils sont dessines
sous les vignettes, dans la couleur d'accent de la stage, avec une position qui
laisse voir environ les deux tiers du libelle.

```toml
[fx.rail.stage_labels]
enabled = true
color = "stage"      # ou une couleur hex, ex. "#6BE675"
font_size = 11
font_family = "system"
weight = "semibold"
alignment = "center" # left | center | right
opacity = 0.72
offset_x = 0
offset_y = 0
placement = "below" # above | below
z_order = "below"   # below | above
visibility_seconds = 0 # 0 = toujours visible, sinon duree apres reveal
fade_seconds = 0.35
```

Quand `visibility_seconds` est superieur a `0`, les noms de stages sont caches
par defaut. La commande `roadie rail labels show` les affiche pendant cette duree,
puis ils disparaissent en fondu pendant `fade_seconds`.

Si `enabled = false`, le menu de barre de titre n'affiche plus les stages vides
anonymes une par une. Il garde les stages qui contiennent des fenetres et ajoute
une seule destination `Prochaine stage vide`.

## Menu contextuel de barre de titre

Roadie peut afficher un menu experimental lors d'un clic droit dans la zone haute d'une fenetre geree. Le clic droit dans le contenu de l'application reste laisse a l'application.

Activation TOML :

```toml
[experimental.titlebar_context_menu]
enabled = true
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
```

## Menu Pin et repliage

Roadie peut afficher un petit bouton circulaire bleu sur les fenetres gerees
par Roadie. Ce bouton ouvre un menu compact qui reprend les actions du menu de
barre de titre : changer le scope du pin, retirer le pin, envoyer la fenetre
vers une stage, un desktop ou un ecran.

Activation TOML :

```toml
[experimental.pin_popover]
enabled = true
show_on_unpinned = true
button_size = 12.5
button_color = "#0A84FF"
titlebar_height = 36
leading_exclusion = 64
trailing_exclusion = 16
collapse_enabled = true
proxy_height = 28
proxy_min_width = 160
```

Quand `collapse_enabled = true`, une fenetre pinnee peut etre repliee. Roadie
memorise sa position, cache la vraie fenetre hors de l'espace visible et affiche
un proxy compact avec son titre. Le proxy permet de rouvrir le menu et de
deplier la fenetre.

Cas d'usage :

- garder une fenetre de reference pinnee sans masquer durablement ce qui est dessous;
- retirer ou changer un pin sans utiliser le clic droit de barre de titre;
- ranger une fenetre pinnee vers une autre stage ou un autre desktop depuis un point d'entree visible.

La fonctionnalite est experimentale et desactivable. Avec
`show_on_unpinned = true`, les fenetres non pinnees recoivent aussi le bouton
pour pouvoir etre pinnees directement. Les popups/dialogues exclus du tiling ne
sont pas concernes.

## Placement des nouvelles applications

Roadie peut choisir l'ecran d'accueil d'une nouvelle vraie fenetre d'application
au moment ou elle est decouverte. Les popups, dialogues et fenetres non tileables
ne sont pas concernes.

```toml
[window_placement]
new_apps_target = "mouse" # mouse | focused_display | macos
```

- `mouse` : assigne la nouvelle fenetre a la stage active de l'ecran sous la souris.
- `focused_display` : assigne la nouvelle fenetre a la stage active de l'ecran focus par Roadie.
- `macos` : garde l'ecran choisi initialement par macOS.

Actions disponibles :

- pinner la fenetre sur toutes les stages du desktop courant;
- pinner la fenetre sur tous les desktops Roadie du meme ecran;
- retirer un pin de fenetre;
- envoyer la fenetre vers une autre stage;
- envoyer la fenetre vers un autre desktop Roadie;
- envoyer la fenetre vers un autre ecran.

Cas d'usage :

- garder une video, une doc ou un terminal de reference visible pendant qu'on change de stage;
- garder une fenetre visible sur tous les desktops d'un meme ecran sans la dupliquer ni la retiler;
- deplacer une fenetre sans memoriser son ID;
- garder le focus courant tout en rangeant une fenetre ailleurs;
- eviter les popups/dialogues en limitant l'action aux fenetres gerees et tileables.

Les pins de fenetres ne creent pas de copie dans les stages. La fenetre garde
un contexte d'origine unique, mais Roadie ne la cache pas tant que le desktop ou
l'ecran cible du pin est actif. Une fenetre pinnee est sortie du layout
automatique pour eviter les deplacements parasites des autres fenetres.

## Desktops Roadie

Les desktops Roadie sont virtuels. Ils ne creent pas et ne pilotent pas les Spaces macOS natifs.

```bash
./bin/roadie desktop list
./bin/roadie desktop focus 2
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork
```

Cas d'usage :

- garder un desktop `DeepWork`, un desktop `Ops`, un desktop `Admin`;
- basculer entre deux contextes avec `desktop back-and-forth`;
- rappeler un desktop sur l'ecran courant avec `desktop summon`.

## Commandes power-user

Roadie expose des primitives de layout inspirees des window managers power-user.

```bash
./bin/roadie focus back-and-forth
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout flatten
./bin/roadie layout insert right
./bin/roadie layout join-with left
./bin/roadie layout zoom-parent
./bin/roadie layout toggle-split
```

Cas d'usage :

- revenir au dernier focus;
- forcer une restructuration locale du layout;
- placer la prochaine fenetre du cote voulu;
- inverser localement deux fenetres voisines en `mutableBsp` avec `toggle-split`;
- agrandir temporairement une fenetre sans perdre le contexte.

## Rules

Les rules automatisent le traitement des fenetres selon app, titre, role, stage ou regex.

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

Cas d'usage :

- envoyer les terminaux de projet vers une stage `shell`;
- taguer les docs comme scratchpad `research`;
- detecter une mauvaise regex avant de relancer le daemon.

## Window groups

Les groupes de fenetres permettent d'associer plusieurs fenetres dans une meme intention utilisateur.

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

Cas d'usage :

- grouper plusieurs terminaux lies au meme projet;
- grouper plusieurs fenetres navigateur de documentation;
- exposer les groupes aux scripts via `roadie query groups`.

## Events et Query API

Roadie publie des evenements JSONL et expose des queries JSON stables.

```bash
./bin/roadie events subscribe --from-now --initial-state
./bin/roadie query state
./bin/roadie query windows
./bin/roadie query groups
./bin/roadie query events
```

Cas d'usage :

- alimenter une barre de statut;
- surveiller les changements de focus;
- debugger une rule ou un groupe;
- construire un dashboard local.

## Securite restore et administration

Roadie ecrit un snapshot restore au demarrage et a l'arret propre du daemon. Un watcher separe peut restaurer les frames uniquement si le process `roadied` disparait sans avoir marque une sortie propre. Il ne tourne pas dans le chemin focus/bordure et peut etre desactive avec `roadied run --yes --no-restore-safety`.

```bash
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --yes --json
./bin/roadie cleanup --dry-run --json
./bin/roadie cleanup --apply
```

Cas d'usage :

- recharger une config seulement si elle est valide;
- prendre un snapshot manuel des frames avant une operation risquee;
- restaurer explicitement les frames par ID de fenetre quand tu le demandes, ou apres crash non propre;
- garder les logs, backups et archives legacy sous controle.

## Width presets et diagnostics performance

Les ajustements de largeur sont des commandes manuelles. Les diagnostics performance lisent le journal d'evenements; ils ne mesurent pas le chemin focus/bordure en temps reel.

```bash
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67

./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie performance thresholds --json
```

Cas d'usage :

- elargir rapidement une fenetre active sans changer de layout global;
- voir les types d'interactions recentes dans `events.jsonl`;
- garder des seuils cibles documentes sans toucher au daemon.
