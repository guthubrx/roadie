# Fonctionnalites

## Tiling

Roadie tile les fenetres visibles d'une stage active.

Modes disponibles :

- `bsp` : repartition en arbre binaire, adaptee aux workflows terminal/code/navigateur.
- `spatialBsp` : arbre binaire persistant. Les séparations et proportions enregistrées définissent la disposition. `mutableBsp` et `yabai` restent des alias.
- `masterStack` : une fenetre principale et une pile secondaire.
- `float` : Roadie garde les fenetres dans l'etat de stage mais ne les retile pas.

Exemples :

```bash
roadie mode bsp
roadie mode spatialBsp
roadie mode masterStack
roadie mode float
roadie balance
```

Cas d'usage :

- developpement avec editeur en master et terminaux en stack;
- arbre BSP persistant modifié avec `move`, `warp`, `resize` et glisser-déposer;
- operations multi-ecran avec chaque ecran dans un mode different;
- pause temporaire du tiling sur une stage en `float`.

## Runtime modulaire

Roadie peut tourner comme daemon monolithique classique ou comme ensemble de
composants runtime separes :

- `tiler` : applique les layouts et garde les stages tilees coherentes;
- `rail` : affiche le navrail et les thumbnails;
- `border` : dessine la bordure de focus;
- `focus-mouse` : gere le focus-follows-mouse;
- `titlebar-menu` : gere drag/drop et actions de barre de titre;
- `target-mode` : expose les cibles clavier, grilles et activations de cible.

La sécurité de restauration n'est pas un composant séparé : elle tourne dans `roadied run` et `roadied tiler`. L'ancienne commande `roadied restore-safety` existe encore, mais elle affiche seulement un message et sort avec le code 0.

`roadied run` et `roadied tiler` partagent un seul verrou d'instance (`~/.roadies/roadied.lock`) : un seul des deux peut tourner. Une deuxième instance sort avec le code 1. Utilise un seul lanceur à la fois : le LaunchAgent, `make dev-start` ou `./scripts/start-modular`. Le tiler écrit `~/.roadies/roadied.pid` ; les autres composants écrivent `<nom>.pid`.

Lancer le profil modulaire complet :

```bash
./scripts/start-modular
roadie query components
roadie daemon health
```

C'est utile aujourd'hui pour l'observabilite et le debug cible : chaque
composant a son propre processus, son lock file et ses logs stdout/stderr sous
`~/.roadies`.

Cela pose aussi les bases du mode compagnon. Dans ce modele, Roadie pourra
fournir stages, rail, bordures, aides de focus, mode cibles ou restore safety a
cote d'un autre window manager comme yabai ou AeroSpace, au lieu de posseder
systematiquement toute la boucle de tiling. Le script modulaire standard lance
encore le tiler : les profils explicites stage-only ou overlay-only restent donc
un travail experimental futur, pas encore un contrat public stable.

## Stages

Une stage est un groupe nomme de fenetres dans un desktop Roadie. Seule la stage active est visible; les autres sont masquees et restent recuperables.

```bash
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
roadie stage move-to-display right --no-follow
```

Les variantes `*-position` suivent l'ordre visible du navrail ; elles sont faites
pour les raccourcis utilisateur de type Alt-1, Alt-2, Alt-3.
`stage switch-visible prev|next` parcourt les stages non vides dans l'ordre du
navrail. `stage assign-empty` envoie la fenetre active vers la prochaine stage
vide non nommee, ou en cree une si necessaire.

Une stage peut aussi etre envoyee vers un autre ecran depuis le menu contextuel
du navrail. Le comportement de focus est controle par `[focus].stage_move_follows_focus`
et peut etre force ponctuellement avec `--follow` ou `--no-follow`.

Cas d'usage :

- isoler une stage `Focus`, une stage `Comms`, une stage `Docs`;
- masquer rapidement un contexte sans fermer les apps;
- ramener une fenetre precise dans la stage active avec `stage summon`.

## Parking d'ecran

Roadie traite un ecran debranche comme un changement temporaire de topologie,
pas comme une raison de detruire ou de fusionner l'etat des stages.

Quand un ecran disparait :

- les stages non vides de cet ecran sont rapatriees comme stages distinctes sur un ecran restant;
- leurs noms, modes, membres, groupes, focus et ordre relatif sont conserves;
- les stages vides restent en metadata cachee pour restauration;
- la stage active de l'ecran hote n'est pas remplacee par les stages rapatriees.

Quand l'ecran revient, Roadie restaure les stages parkées courantes vers cet
ecran s'il peut le reconnaitre sans ambiguite. La reconnaissance utilise d'abord
l'ancien identifiant d'ecran, puis une empreinte conservative basee sur le nom,
la taille, la taille visible, la position et l'indice d'ecran principal. Si
plusieurs ecrans matchent aussi bien, Roadie refuse la restauration automatique
et laisse les stages parkées visibles.

Cas d'usage :

- debrancher un portable d'un moniteur sans perdre les stages du moniteur;
- continuer a travailler sur les stages rapatriees pendant l'absence du moniteur;
- rebrancher le moniteur et retrouver ces stages sans les avoir fusionnees.

## Navrail

Le navrail est le panneau lateral par ecran qui represente les stages non vides.
Une stage vide n'y est pas affichee, meme si elle a ete renommee.

Les vignettes de fenetres peuvent aussi exposer leur etat de presentation. Une
fenetre `maximized` reste dans sa stage normale et est marquee par une bordure a
quatre coins. Une fenetre `nativeFullscreen` est marquee par une bordure continue
pour signaler que la semantique fullscreen native de macOS peut s'appliquer.

Interactions principales :

- cliquer une stage pour l'activer;
- garder les clics vides du navrail inertes par défaut, avec `empty_click_hide_active` en option pour basculer vers une stage vide;
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
roadie desktop list
roadie desktop focus 2
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
```

Cas d'usage :

- garder un desktop `DeepWork`, un desktop `Ops`, un desktop `Admin`;
- basculer entre deux contextes avec `desktop back-and-forth`;
- rappeler un desktop sur l'ecran courant avec `desktop summon`.

## Mode Cibles

Le Mode Cibles donne une liste stable de destinations activables au clavier ou
par un agent externe. Il ne remplace pas le navrail : il expose les memes objets
sous forme de cibles nommees, inspectables et actionnables.

```bash
roadie targets list
roadie targets list --json
roadie targets list --filter gray
roadie targets inspect A
roadie targets pick gray
roadie targets activate A --action switch
roadie targets activate S --action focus
roadie targets activate D --action send-active
roadie targets show --json --labels-only
roadie query targets
```

Les cibles Roadie couvrent les fenetres, stages, ecrans, desktops et bookmarks.
Chaque cible a un label court (`A`, `S`, `D`, puis `AA`, etc.), un ID stable et
une liste d'actions possibles. Les labels sont faits pour l'humain; les IDs sont
faits pour les scripts.

Les zones applicatives sensibles peuvent etre listees en mode experimental via
Accessibility. Ce mode est desactive par defaut pour eviter de scanner les apps
pendant les chemins chauds du window manager.

Les applications Electron (T3 Code, Slack, Discord...) ne publient leur contenu
Accessibility qu'a la demande. Quand le boost AX est actif (`ax_boost_enabled` ou
`additional_boost_bundle_ids`), Roadie pose `AXManualAccessibility` sur
l'application Electron au premier plan a chaque session. L'application construit
son arbre en arriere-plan : juste apres son lancement, la premiere session peut ne
montrer que la fenetre (Roadie reessaie au plus 300 ms) ; les suivantes sont
completes. Une arborescence web est profonde : prevoir `max_depth = 30` et
`timeout_ms = 250`. Seuls les elements visibles
dans la fenetre recoivent un label. Couper le boost coupe aussi cette demande.

Chaque parcours ecrit un evenement `targets.app_scan` (elements lus, profondeur
atteinte, duree, raison d'arret) dans `~/.roadies/events.jsonl`. Il sert a regler
`max_depth` et `timeout_ms` :

```bash
grep '"targets.app_scan"' ~/.roadies/events.jsonl | tail -3
```

Certaines interfaces web (SolidJS, React) rendent leurs elements cliquables par du
JavaScript : Chromium ne leur donne aucune action Accessibility. Dans une zone web,
Roadie pose donc aussi un label sur chaque element focalisable qui ne contient aucun
autre element focalisable (entrees de menu, cartes). Ces labels passent apres les
cibles classiques. `focusableAdded` et `rejectedRoles` dans `targets.app_scan`
mesurent cette regle.

Dans une zone web, Roadie lit seulement `AXChildren` : les attributs du boost AX
y coutent cher sans rien apporter. Une page web lourde (Bluejay : environ 3 300
elements) demande `timeout_ms = 700`.

Les applications CEF (Grayjay, Bluejay) ne repondent a aucune demande externe :
leur arbre n'existe que si l'application lance CEF avec
`--force-renderer-accessibility` (option integree a Bluejay sur macOS).

### Mode recherche (Hyper+F)

Le mode recherche reprend l'idee de Homerow : on tape un texte au lieu de lire
des etiquettes. Un raccourci global ouvre une barre de saisie en bas de l'ecran
du pointeur. Chaque lettre filtre les cibles ; Retour clique la cible en vert.

- **Raccourci** : `search_hotkey` dans `[experimental.target_mode]`, par defaut
  `command+control+alt+f` (Hyper+F quand Caps Lock est une hyper key Karabiner).
  Alias acceptes : `hyper` (= `command+control+alt`) et `ctrl`. Une chaine vide
  desactive le raccourci. Un changement prend effet sans redemarrage, y compris
  apres un changement de disposition clavier. `roadie targets search` ouvre la
  meme session.
- **Toutes les fenetres visibles** : la barre s'ouvre tout de suite avec les
  cibles Roadie. Les fenetres de l'espace courant sont lues en parallele en
  arriere-plan (2 s par fenetre au moins) et chacune s'ajoute des qu'elle est
  lue ; la barre affiche `lecture…` en attendant. Un element cache par une
  fenetre placee devant n'a pas de label. Les cibles de l'ecran du pointeur
  passent en premier.
- **Correspondance** : casse, accents et espaces ignores (`watchlater` trouve
  `Watch Later`). Elle porte sur le titre, la valeur, le role et, pour les
  cibles web, le texte de leurs enfants (ligne de fil T3 Code, carte video).
- **Affichage** : aucune etiquette tant que la barre est vide. Les etiquettes
  des resultats sont vertes ; la cible choisie a un cadre epais. A 9 resultats
  ou moins, les etiquettes deviennent `A`, `S`, `D`... et chaque resultat est
  encadre.
- **Valider sur une autre fenetre** : Roadie focalise la fenetre, attend que
  son application soit active (0,5 s au plus), puis clique.

| Touche | Effet |
|--------|-------|
| lettres, chiffres, espace | filtrer |
| Tab, Fleche bas, Ctrl-N | resultat suivant |
| Maj-Tab, Fleche haut, Ctrl-P | resultat precedent |
| Maj + etiquette | choisir ce resultat (`Maj+S` avec peu de resultats) |
| Retour | clic |
| Retour deux fois (moins de 0,35 s) | double-clic |
| Maj-Retour | clic droit |
| Cmd-Retour | Cmd-clic (nouvel onglet) |
| `*` ou `;` | afficher toutes les cibles |
| `?` | fiche de la cible en vert (role, titre, texte, id) |
| Echap | fermer sans action |

La recherche se ferme seule apres 60 s sans frappe. Les clics exigent
`app_mouse_actions_enabled = true` et la barre `overlay_enabled = true`.

Une feuille web sans action (regle des elements focalisables) est cliquee au
centre de sa premiere image ou de son premier texte visible, pas au centre de
l'element : le centre d'une ligne de l'Historique de Bluejay ne reagit pas,
seuls la vignette, le titre et l'auteur ont un gestionnaire de clic.

Le mode lettres classique reste limite a la fenetre active. Pour l'etendre a
toutes les fenetres visibles : `scope = "visible_windows"` dans
`[experimental.app_targets]`.

Les briques du Mode Cibles sont configurables separement. Le socle CLI et le picker
restent actifs par defaut, tandis que l'overlay graphique futur, les clics dans
les apps et le scroll-mode applicatif restent coupes tant que l'utilisateur ne
les demande pas.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = false
overlay_labels_only = true
overlay_duration_seconds = 3
app_mouse_actions_enabled = false
scroll_mode_enabled = false
search_hotkey = "command+control+alt+f"
```

```toml
[experimental.app_targets]
enabled = false
scope = "frontmost_window"   # ou "visible_windows"
max_targets = 150
timeout_ms = 120
hint_characters = "asdfghjkl"
include_roles = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow"]
```

```toml
[experimental.target_grid]
enabled = true
overlay_enabled = true
overlay_draw_grid = true
overlay_fill_color = "#4DABF7"
overlay_fill_opacity = 0.10
overlay_border_color = "#4DABF7"
overlay_border_opacity = 0.55
overlay_label_color = "#FFFFFF"
rows = 3
columns = 3
max_depth = 3
hint_characters = "azeqsdwxc"
```

Cas d'usage :

- sauter vers une fenetre bookmarkee ou une stage sans memoriser son ID;
- chercher une cible par texte avec `targets pick` et refuser proprement les ambiguities;
- taper quelques lettres (Hyper+F) pour cliquer un element de n'importe quelle fenetre visible;
- envoyer la fenetre active vers une cible affichee par label;
- fournir a un agent une API JSON plus robuste qu'une capture d'ecran;
- inspecter pourquoi une cible est stale, pinnee, flottante ou hors tiling.

Meme si `experimental.app_targets.enabled = true`, les actions `click`,
`double-click`, `right-click` et `command-click` sur les zones applicatives sont refusees tant que
`experimental.target_mode.app_mouse_actions_enabled = false`.

Ce qui reste volontairement borne : le controle applicatif profond. Les app
targets restent experimentales, limitees par timeout et desactivees par defaut.

## Commandes power-user

Roadie expose des primitives de layout inspirees des window managers power-user.

```bash
roadie focus back-and-forth
roadie layout split horizontal
roadie layout split vertical
roadie layout flatten
roadie warp right
roadie resize right
roadie layout zoom-parent
roadie layout toggle-split
```

Cas d'usage :

- revenir au dernier focus;
- forcer une restructuration locale du layout;
- insérer la fenêtre active du côté voulu avec `warp`;
- inverser localement deux fenetres voisines en `spatialBsp` avec `toggle-split`;
- agrandir temporairement une fenetre sans perdre le contexte.

Dans `spatialBsp`, `layout insert` et `layout join-with` sont refusés : utilise `warp`. `layout width` est refusé : utilise `resize`. `layout flatten` équilibre l’arbre existant. Les anciennes commandes restent disponibles dans les autres modes compatibles.

## Rules

Les rules automatisent le traitement des fenetres selon app, titre, role, stage ou regex.
Elles peuvent aussi placer une nouvelle vraie fenetre d'application sur une
stage, un desktop Roadie et un ecran cible, sans suivre le focus par defaut.

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

Cas d'usage :

- envoyer les terminaux de projet vers une stage `shell`;
- ouvrir toujours Firefox sur la stage `web` de l'ecran externe;
- creer cette affinite directement depuis le clic droit de barre de titre;
- taguer les docs comme scratchpad `research`;
- detecter une mauvaise regex avant de relancer le daemon.

## Window groups

Les groupes de fenetres permettent d'associer plusieurs fenetres dans une meme intention utilisateur.

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

Cas d'usage :

- grouper plusieurs terminaux lies au meme projet;
- grouper plusieurs fenetres navigateur de documentation;
- exposer les groupes aux scripts via `roadie query groups`.

## Events et Query API

Roadie publie des evenements JSONL et expose des queries JSON stables.

```bash
roadie events subscribe --from-now --initial-state
roadie query state
roadie query windows
roadie query groups
roadie query events
```

Cas d'usage :

- alimenter une barre de statut;
- surveiller les changements de focus;
- debugger une rule ou un groupe;
- construire un dashboard local.

## Securite restore et administration

Le daemon (`roadied run` ou `roadied tiler`) écrit un snapshot de restauration au démarrage, à chaque changement de stage et toutes les 30 secondes. Sur SIGTERM, SIGINT ou SIGHUP, il remet les fenêtres masquées avant de sortir. Un petit processus de surveillance (`restore-watch`) suit le daemon et fait de même si le daemon disparaît sans sortie propre. Rien de cela ne tourne dans le chemin focus/bordure. Pour le désactiver, démarre le daemon avec `roadied run --yes --no-restore-safety`. Pour ramener toutes les fenêtres masquées à la main, lance `roadie restore unhide-all`.

```bash
roadie config reload --json
roadie restore snapshot --json
roadie restore status --json
roadie restore apply --yes --json
roadie cleanup --dry-run --json
roadie cleanup --apply
```

Cas d'usage :

- recharger une config seulement si elle est valide;
- prendre un snapshot manuel des frames avant une operation risquee;
- restaurer explicitement les frames par ID de fenetre quand tu le demandes, ou apres crash non propre;
- garder les logs, backups et archives legacy sous controle.

## Width presets et diagnostics performance

Les préréglages de largeur concernent `bsp` et `masterStack`. Dans `spatialBsp`, utilise `resize` à la place de `layout width`. Les diagnostics performance lisent le journal d'evenements; ils ne mesurent pas le chemin focus/bordure en temps reel.

```bash
roadie layout width next
roadie layout width prev
roadie layout width nudge 0.05
roadie layout width ratio 0.67

roadie performance summary
roadie performance recent --limit 20
roadie performance thresholds --json
```

Cas d'usage :

- elargir rapidement une fenetre active sans changer de layout global;
- voir les types d'interactions recentes dans `events.jsonl`;
- garder des seuils cibles documentes sans toucher au daemon.

## Mode Cibles, Grille Ecran, Grille Fenetre Et Macros

Le Mode Cibles donne un inventaire actionnable des stages, fenetres, displays,
desktops, bookmarks et zones applicatives Accessibility.

La **Grille Ecran** ajoute un langage spatial recursif sur un ecran complet
quand Accessibility ne voit pas tout. La **Grille Fenetre** utilise le meme
langage recursif, mais limite la racine a la fenetre focussee. Elle est utile
pour les lecteurs video, les webviews, les canvases et les panneaux applicatifs
denses.

Le record/replay permet de capturer une manipulation courte avec contexte de
cible et fallback grille. Un indicateur `record` peut apparaitre dans le navrail
pendant la capture.

```bash
roadie targets interactive --source all --include-app-targets
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
roadie record start demo --duration 10
roadie record replay demo
```

Cas d'usage :

- basculer vers une stage ou une fenetre par label plutot que par ID;
- cliquer un bouton d'app expose par Accessibility;
- cibler une zone non accessible via la Grille Ecran;
- cibler un controle dans la fenetre focussee via la Grille Fenetre;
- montrer une manipulation a un agent puis la rejouer ou l'analyser.
