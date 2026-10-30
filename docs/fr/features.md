# Fonctionnalites

## Sélecteur de fenêtres

Retrouve les fenêtres gérées par Roadie dans leur bureau, leur stage et leur écran.
Recherche, grille de miniatures à côté d'un grand aperçu, icônes ou liste, profils
indépendants et actions ciblées. Les outils de raccourcis appellent la CLI ;
les réglages se trouvent dans **Réglages Roadie > Sélecteur**.
[Guide et commandes](window-switcher.md).

## Vue d’ensemble

Montre tous les écrans, bureaux, stages et fenêtres sur une seule page, en Archipel
ou en Baies. Glissez la puce d'un bureau, la puce d'une stage ou la carte d'une
fenêtre pour réorganiser vos espaces, sur un écran ou d'un écran à l'autre : un
aperçu en direct montre le résultat avant le relâchement. Déposez une fenêtre ou une
stage dans le vide pour créer une stage ou un bureau.
[Guide de la vue d’ensemble](overview.md).

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

### Redimensionnement par les séparations

En mode `spatialBsp`, tire une poignée dans l'espace entre deux groupes de fenêtres
pour modifier leur proportion. Les autres séparations gardent leur position relative.
Le résultat est enregistré dans l'arbre. Le redimensionnement natif par les bords
des fenêtres reste disponible.

Le réglage **Tuilage > Poignées de redimensionnement** masque ou affiche ces prises
sans retuiler les fenêtres (`tiling.resize_handles`, activé par défaut). Les poignées
n'apparaissent que dans un espace libre entre fenêtres, sur une stage active compatible.
Le repère est un petit trait contrasté au milieu de la séparation. Les bordures
décoratives JankyBorders ne le masquent pas ; une vraie fenêtre qui recouvre cet
espace reste protégée.
Sans espace entre les fenêtres, utilise leurs bords ou la commande `resize`.
Un changement de stage ou d'écran interrompt le geste sans appliquer sa cible en attente.

Les retours macOS de placements récents sont reconnus même lorsqu'ils arrivent dans
le désordre. Les refus de taille et les minimums appris restent liés à leur génération
et au contexte de la fenêtre, pour préserver les gestes plus récents.

## Runtime modulaire

Roadie peut tourner comme daemon monolithique classique ou comme ensemble de
composants runtime separes :

- `tiler` : applique les layouts et garde les stages tilees coherentes;
- `rail` : affiche le navrail et les thumbnails;
- `border` : dessine la bordure de focus;
- `focus-mouse` : gere le focus-follows-mouse;
- `titlebar-menu` : affiche le menu contextuel de clic droit sur la barre de titre (le glisser-deposer vers le navrail est gere par `rail`);
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

Un nom de stage est unique dans tout Roadie, tous écrans et bureaux confondus :
`stage rename` refuse un nom déjà porté par une autre stage, et `roadie state heal`
corrige les doublons hérités. La vue d'ensemble déplace aussi une stage ou une
fenêtre par glisser-déposer.

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

Le plein écran Roadie (`roadie toggle fullscreen`) masque entièrement le rail
sur l'écran concerné, même au survol. Il ne crée pas de Space plein écran macOS.
Répéter restaure la disposition et le comportement du rail. La maximisation
`roadie toggle maximize` conserve son accès au rail.

Le masquage automatique (`fx.rail.auto_hide`) est indépendant : hors plein écran,
le rail se replie comme le Dock et revient au survol du bord gauche. La largeur
du bord et le délai de repli sont réglables dans Réglages Roadie > Rail. Un rail épinglé
reste ouvert ; `roadie rail unpin` réactive le repli si auto_hide est activé.

Le rail conserve l'ordre choisi pour les stages, même lorsqu'elles reçoivent ou
perdent une fenêtre. Fais défiler le rail lorsque les cartes dépassent l'écran.
Dépose une fenêtre sur une carte pour rejoindre cette stage. Dans un espace libre,
le repère « Nouvelle stage » indique sa création en haut, entre deux cartes ou en
bas, à l'endroit choisi. Les menus et les aperçus suivent le même ordre.
Les stages nommées vides gardent un contour discret, leur nom et la mention « Vide »,
même lorsque les libellés temporaires sont masqués. Les stages vides sans nom
restent accessibles par « Prochaine stage vide ».

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
- tirer une fenetre d'application par sa barre de titre vers une zone vide du navrail pour creer ou utiliser une stage vide;
- tirer une stage avec le bouton droit : son aperçu translucide et les cartes voisines montrent le futur ordre ; relâcher pour appliquer, ou relâcher hors du rail pour annuler ;
- faire un clic droit sur une stage, sans tirer, pour ouvrir son menu : renommer la stage, l'envoyer vers un autre ecran, envoyer une fenetre vers une autre stage ou supprimer la stage si elle n'a plus de fenetre (la stage active et une stage d'un ecran absent restent).

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

Quand `visibility_seconds` est superieur a `0`, les noms des stages occupées sont caches
par defaut. La commande `roadie rail labels show` les affiche pendant cette duree,
puis ils disparaissent en fondu pendant `fade_seconds`.

Si `enabled = false`, le menu de barre de titre n'affiche plus les stages vides
anonymes une par une. Il garde les stages qui contiennent des fenetres et ajoute
une seule destination `Prochaine stage vide`.

## Menu contextuel de barre de titre

Roadie peut afficher un menu contextuel lors d'un clic droit dans la zone haute d'une fenêtre gérée. Le clic droit dans le contenu de l'application reste laissé à l'application.

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
double_click_maximize = false
```

### Double-clic sur la barre de titre

Un double-clic dans la même zone haute affiche la fenêtre seule, avec la maximisation Roadie
qui garde le rail libre. Un second double-clic rend la disposition, comme
`roadie toggle maximize`. Ce réglage (`double_click_maximize`, désactivé par défaut) ne dépend
pas du menu par clic droit.

macOS agit déjà sur ce double-clic et Roadie ne peut pas l'en empêcher. Roadie n'agit donc
que si le réglage macOS « Double-cliquer sur la barre de titre d'une fenêtre pour » vaut
« Ne rien faire » (Réglages Système > Bureau et Dock). Sinon, `roadie daemon health` le
signale dans le contrôle `macos-window-settings`.

## Placement des nouvelles fenêtres

Par défaut, une nouvelle fenêtre rejoint le stage courant de l'écran actif.
Ainsi, ⌘N depuis un terminal garde la nouvelle fenêtre dans ton espace de travail,
même si la souris est restée sur un autre écran. Roadie l'intègre au tuilage dès
qu'elle est disponible. Les popups, dialogues et fenêtres non tuilables ne sont
pas concernés.

Ce choix se règle dans **Réglages Roadie > Tuilage > Écran des nouvelles fenêtres**.
Les choix déjà enregistrés restent conservés ; « Rétablir » sélectionne l'écran actif.

Choisir l'écran actif peut aussi améliorer la réactivité perçue en limitant les
déplacements et les réorganisations entre écrans. L'effet dépend du placement
initial de l'application et des écrans utilisés.

```toml
[window_placement]
new_apps_target = "focused_display" # défaut ; mouse | focused_display | macos
```

- **Écran actif (recommandé)** (`focused_display`, défaut) : stage courant de l'écran actif dans Roadie.
- **Écran de la souris** (`mouse`) : stage courant de l'écran sous le pointeur.
- **Choix de macOS** (`macos`) : écran choisi initialement par l'application et macOS.

Dans le fichier de configuration, ces valeurs s'écrivent exactement comme ci-dessus,
en minuscules et sans espace ajouté. Une valeur invalide reprend le défaut `focused_display`.

Actions disponibles :

- faire flotter la fenetre dans sa stage, hors du tuilage;
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

### Fenêtre flottante

`roadie toggle floating` fait flotter la fenêtre active dans sa stage. Elle sort
du tuilage : les autres fenêtres reprennent sa place, et vous la placez à la main.
Elle reste rattachée à sa stage : masquée quand vous changez de stage, au même
endroit au retour. Relancez la commande pour la remettre dans le tuilage.

Le menu « Fenêtre » de la barre de titre propose aussi « Flotter dans cette stage »
et « Revenir au tuilage ». Sur une fenêtre déjà pinnée sur un desktop, la commande
retire le pin et rend la fenêtre au tuilage. Aucun raccourci n'est posé par défaut :
associez la commande à une touche dans BetterTouchTool ou Karabiner.

L'état survit au redémarrage de Roadie. Une version antérieure de Roadie lit
encore le fichier d'état : elle traite une fenêtre flottante comme un pin sur ce
desktop, visible sur toutes ses stages.

## Desktops Roadie

Les desktops Roadie sont virtuels. Ils ne creent pas et ne pilotent pas les Spaces macOS natifs.

```bash
roadie desktop list
roadie desktop focus 2
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
roadie desktop move 2 1
```

`desktop move` déplace un bureau à une autre place et renumérote les bureaux, comme
Mission Control ; ses stages, fenêtres et nom le suivent. La vue d'ensemble fait de
même par glisser-déposer, y compris vers un autre écran.

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

Les contrôles d'une application peuvent être listés via Accessibility.
Active cette découverte lorsque tu souhaites les utiliser ; elle est désactivée
par défaut pour garder la lecture des applications facultative.

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

### Mode recherche

Le mode recherche reprend l'idee de Homerow : on tape un texte au lieu de lire
des etiquettes. Un raccourci global ouvre une barre de saisie en bas de l'ecran
du pointeur. Chaque lettre filtre les cibles ; Retour clique la cible en vert.

- **Raccourci** : `search_hotkey` dans `[experimental.target_mode]`, par defaut
  `command+control+alt+f`. Ce raccourci est personnalisable.
  Alias acceptes : `hyper` (= `command+control+alt`) et `ctrl`. Une chaine vide
  desactive le raccourci. Un changement prend effet sans redemarrage, y compris
  apres un changement de disposition clavier. `roadie targets search` ouvre la
  meme session.
- **Toutes les fenetres visibles** : la barre s'ouvre tout de suite avec les
  cibles Roadie. Les fenetres de l'espace courant sont lues en parallele en
  arriere-plan (2 s par fenetre au moins) et chacune s'ajoute des qu'elle est
  lue ; le compteur se met a jour dans la pastille a droite. Un element cache par une
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

**Lanceur** : au-dessus de la barre, une liste groupe les résultats en sections :
**Applications** (toutes les applications installées), **Fenêtres**, **Stages et
bureaux**, puis **À l'écran** (les cibles étiquetées). La correspondance tolère les
initiales (`vsc` pour Visual Studio Code). Roadie retient vos choix : la ligne
choisie après une même saisie remonte en tête la fois suivante (classement local,
`~/.roadies/launcher-ranking.json`, effaçable sans dommage). Retour sur une
application déjà ouverte va à sa fenêtre, dans sa stage et son bureau ; sur une
application fermée, l'ouvre dans la stage active de l'écran actif, sauf règle
`assign_stage`. Les flèches parcourent la liste ; un clic sur une ligne l'active.
Le classement retient aussi la stage active au moment du choix : dans « Com », `o`
propose d'abord ce que vous y choisissez d'habitude, dans « Dev » autre chose. Une
stage nommée est reconnue par son nom, même déplacée ; six stages au plus par objet.
**Documents et onglets** : la barre trouve aussi ce qui est ouvert, même dans une stage
cachée ou sur un autre bureau : le document de chaque fenêtre (TextEdit, Aperçu, Pages…)
et les onglets de Chrome, Brave, Edge et Safari (titre et adresse). Retour affiche la
stage, met la fenêtre devant et sélectionne l'onglet. macOS demande une fois
l'autorisation d'automatisation pour chaque navigateur. Firefox n'expose pas ses
onglets : non couvert. Rien n'est écrit ni journalisé. Diagnostic :
`roadie launch --open-items [--tabs]` (nombre d'éléments par application).

**Fichiers** : dès 3 lettres, Spotlight cherche dans le dossier personnel (hors
`~/Library`, éléments cachés et `node_modules`) les dossiers, documents, textes, images,
PDF, tableurs et présentations ; section « Fichiers » avec icône et dossier. Une espace
ou une apostrophe en tête ne cherche que des fichiers (dès 2 lettres). Retour va à la
fenêtre qui affiche déjà le fichier (applications qui exposent leur document : TextEdit,
Aperçu, Pages…), sinon l'ouvre dans la stage où vous ouvrez d'habitude les fichiers de
ce dossier, ou dans la stage active. Verbes : ouvrir dans…, amener ici, montrer dans le
Finder, aperçu, copier le chemin. ⌘C sans texte sélectionné copie la ligne choisie
(chemin, titre) ; ⌘Y montre l'aperçu Quick Look.
Les fenêtres montrent leur vignette réelle (déjà capturée par le rail, le sélecteur ou
la vue d'ensemble) avec l'icône de leur application en pastille ; sans vignette,
l'icône seule.

**Web** : une adresse tapée (`github.com/x`, `www.lemonde.fr`, `localhost:3000`, `https://…`) donne
en tête « Ouvrir … » ; Retour l'ouvre dans le navigateur par défaut, Tab propose Ouvrir dans… (une
nouvelle fenêtre du navigateur rejoint la stage choisie ; Firefox : un onglet vide peut rester),
Amener ici, Copier. Un nom de fichier (`fichier.txt`, `readme.md`) n'est pas une adresse, sauf avec
`/`, un port ou `www.`. `yt chat` cherche « chat » sur YouTube ; défauts : `g` Google, `yt`
YouTube, `wp` Wikipédia, `ddg` DuckDuckGo, `maps` Plans ; une table
`[[experimental.target_mode.web_searches]]` (`keyword`, `title`, `url` avec `{query}`) les
remplace. Toute saisie finit par une section « Web » (recherche de `web_search_url`, puis les
mots-clés de `fallback_searches`), choisie seulement s'il n'y a rien d'autre.
**Historique** : les 20 dernières saisies qui ont mené à une action sont gardées
(`~/.roadies/launcher-history.json`, sur ce Mac seulement). Rouverte dans les 5 minutes, la barre
reprend la dernière, sélectionnée : la frappe la remplace. La barre vide propose les 3 recherches
récentes. `roadie launcher history [--clear]` les montre ou les efface.

**Calcul** : un calcul tapé (`12*4,5`, `2^10`, `-(3+4)*2`) donne son résultat en tête,
sous « Calcul » ; Retour le copie et ferme la barre, ⌘C le copie. Opérateurs `+ - * / ^ %`, `×`,
`÷`, parenthèses, `,` ou `.` décimal ; après `=` : `pi`, `e`, `sqrt`, `abs`, `round`, `floor`,
`ceil`, `exp`, `ln`, `log`, `log2`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan` (`=sqrt(2)`).
12 chiffres significatifs, virgule décimale en français. Un nombre seul ou un calcul inachevé
(`12*`, `1/0`) ne donne aucune ligne. Avec `calc_opens_calculator = true` (Paramètres > Recherche,
« Calcul : ouvrir aussi Calculette »), Retour copie le résultat et ouvre aussi Calculette, ou va à sa
fenêtre déjà ouverte ; ⌘V y colle le résultat. ⌘C copie toujours sans ouvrir.

**Chemin** : une saisie qui commence par `~`, ou par `/` suivi d'un dossier de la racine (`/Us`,
`/Applications/`), liste ce dossier filtré par la suite tapée ; rien d'autre n'est cherché. Tab
complète le nom choisi (`~/Doc` → `~/Documents/`), → ouvre ses verbes, Retour l'ouvre comme un
fichier (un dossier dans le Finder). Les éléments cachés n'apparaissent que si la suite commence
par `.`. Le mode commande garde la priorité : `/s`, `/set`, `/d`… restent des commandes ; dès le
second `/` (`/sbin/`), c'est un chemin.

**Workflows** : la barre fait tourner les workflows au format d'Alfred, ceux installés dans
Alfred (lus sans les modifier, dossier synchronisé suivi) et ceux de `~/.config/roadies/workflows`.
Taper leur mot-clé (`emoji heart`) montre seulement leurs lignes, sous leur nom ; dès 2 lettres,
les mots-clés possibles apparaissent dans une section « Workflows » (Tab ou Retour complète).
Le script d'un filtre tourne en fond (100 ms après la dernière frappe, arrêté à la suivante, 10 s au plus) ;
les actions (Run Script, Run NSAppleScript, tâches d'automatisation, raccourcis) vont à leur terme, comme dans Alfred.
Retour suit le schéma du workflow : scripts, conditions, découpes, remplacements, adresse,
fichier, Finder, copie (collage automatique compris), notification, son, parole, fichier écrit.
Tenir ⌘, ⌥ ou ⌃ montre ce que la ligne fera ; Tab complète, ⌘C copie, ⌘Y montre l'aperçu.
Un workflow tourne avec les droits de Roadie, comme dans Alfred : n'installez que ceux que vous
connaissez. Réglages : `workflows_enabled`, `alfred_workflows` (Paramètres > Recherche).
`roadie workflow list` donne l'état de chacun (complet, partiel, inutilisable) et ce qui manque ;
`roadie workflow check DOSSIER` fait le même relevé ; `roadie workflow install X.alfredworkflow`
et `roadie workflow remove ID` gèrent le dossier de Roadie. Les filtres de liste et de fichiers
(Spotlight, → ouvre les verbes du fichier), les recherches de repli et les actions universelles
sur texte (section « Repli » en bas) marchent aussi ; les actions sur fichier deviennent des verbes
« Workflow : … » (Tab sur un fichier). `roadie workflow run ID OBJET [ARGUMENT]` lance n'importe
quel objet, `roadie workflow trigger ID DÉCLENCHEUR [ARGUMENT] [--var nom=valeur]` un déclencheur
externe ; `roadie workflow list --hotkeys` liste les raccourcis avec la commande à lier dans
BetterTouchTool (Roadie ne capture pas ces touches ; argument « sélection » lu par l'accessibilité,
sinon par ⌘C). Les tâches d'automatisation officielles d'Alfred (dépôt public
`alfredapp/automation-tasks`, licence BSD-3) s'installent par `roadie workflow tasks update` dans
`~/.roadies/alfred-tasks`. Autres briques : touches simulées, grand texte, Terminal, Raccourcis
Apple, dialogue, type de fichier, barre rouverte sur un chemin. **Présentations** : les résultats d'un workflow (par exemple `emoji`), d'un dossier exploré (`~/Pictures/`) ou
les fichiers d'une recherche s'affichent en liste, en grille ou en grandes tuiles. ⌘G (réglable : Paramètres >
Recherche > « Touche des présentations ») ou un clic sur le chip à droite de la saisie (☰ ▦ ▣) passe à la
présentation suivante ; Roadie la retient par workflow, par dossier et pour les fichiers. En grille, les images
montrent leur contenu, ← → ↑ ↓ changent de tuile. **Grille** : une brique Grille
ouvre la barre en tuiles (grande image, titre, sous-titre sur la tuile ou en pied), au nombre de
colonnes du workflow ; ← → ↑ ↓ changent de tuile, la frappe filtre, Tab garde les verbes, Retour
envoie la tuile à la suite du workflow. Un déclencheur externe peut viser n'importe quelle brique
qui le déclare (Alfred 5.5). **Ordres à Alfred** : quand un script de workflow s'adresse à Alfred
(`tell application id "com.runningwithcrayons.Alfred" to …`, `Application("com.runningwithcrayons.Alfred")`),
Roadie fait lui-même ce qui est demandé, sans ouvrir Alfred : `search` ouvre la barre, `run trigger`
lance le déclencheur, `set configuration` / `remove configuration` gardent le réglage dans
`~/.roadies/workflows-settings/` (jamais dans le dossier d'Alfred), `reveal workflow` montre le dossier,
`version` rend la version. `roadie workflow list` liste ces « ordres à Alfred » et ceux « non traduits ».
Vues Texte, Image et PDF et boutons d'Alfred Remote : voir plus bas. Jamais : snippets, tampon d'Alfred, scripts AppleScript compilés. Un script lancé par un workflow obtient
l'autorisation Accessibilité de Roadie (mesuré). Le journal ne garde ni saisie ni résultat.

**Verbes et destinations** : Tab sur la ligne choisie ouvre ses verbes. Application :
ouvrir ou aller à sa fenêtre, ouvrir dans…, nouvelle fenêtre ici, réunir ses fenêtres
dans…, amener ici, masquer, quitter. Fenêtre : aller à, envoyer vers…, amener ici,
faire flotter cette fenêtre ou toujours toute l'application (et l'inverse : remettre au
tuilage, toujours tuiler, retirer la règle), plein écran, réduire, fermer. Stage : afficher, déplacer vers un bureau ou un écran.
Bureau : afficher, déplacer vers un écran. Cible à l'écran : clic, double-clic, clic
droit, Cmd-clic. Un verbe suivi de « … » demande une destination : stage, bureau,
écran, ou « Nouvelle stage » (nommée d'après la saisie si ce nom est libre). Dès
qu'on tape un nom à l'étape des verbes, les destinations correspondantes
apparaissent : `fire`, Tab, `perso`, Retour ouvre une fenêtre Firefox dans la stage
Perso et y va. Échap, ou l'effacement dans un champ vide, revient d'une étape.

**Sélection multiple** : ⌥↑ ajoute ou retire la ligne choisie, ⌥↓ l'ajoute et descend, ⌥← retire la
dernière ajoutée, ⌥→ ouvre les verbes de la sélection, ⌥⌫ la vide (applications, fenêtres et
fichiers ; « ✓ » devant les lignes, « N choisis » dans la capsule). La sélection reste quand la
saisie change : `fire` ⌥↓, `term` ⌥↓, `code` ⌥↓. Retour avec une sélection ouvre ses verbes, avec le
nombre d'objets concernés : Envoyer vers… (fenêtres envoyées ; applications et fichiers ouverts
dans la stage), Amener ici, Fermer, Réduire, Quitter, Masquer, Copier les chemins, Montrer dans le
Finder. Une nouvelle stage est créée une seule fois puis reçoit tout ; Roadie y va à la fin.
« Annuler » de la barre vide remet tout le lot. Échap vide d'abord la sélection. Dans ce champ, ⌥ +
flèches ne déplace plus le curseur par mot (⌃A, ⌃E restent).

**Barre vide** : avant de taper, la barre propose ce qui sert maintenant : une règle
proposée, Revenir (fenêtre précédente), Annuler (remettre la fenêtre du dernier
déplacement, 10 minutes au plus ; aussi `roadie undo`), Fermées récemment (rouvrir dans
sa stage une fenêtre fermée depuis moins de 12 h), Souvent ici (applications choisies le
plus souvent dans cette stage), Recherches récentes. Paramètres > Recherche active ou retire
Souvent ici et Recherches récentes, et règle leur nombre de lignes (3 par défaut) :
`idle_frequent_enabled`, `idle_frequent_count`, `idle_recent_searches_enabled`,
`idle_recent_searches_count`. **Règles proposées** : trois déplacements au moins d'une
application vers une même stage en une semaine font proposer « Créer la règle »
(affinité d'ouverture), « Plus tard » ou « Jamais ». Pendant une recherche, la capsule du
compteur affiche « 💡 1 » ; ⌘R montre la proposition. Déplacements notés :
`~/.roadies/launcher-moves.json` (200 au plus).

**Projets** : une stage nommée se garde comme projet (verbe « Enregistrer comme projet »
d'une stage, ou `roadie project save NOM`) : ses fenêtres dans l'ordre, le document ou
l'adresse de chacune quand l'application les expose (TextEdit, Aperçu, Pages, Chrome…), et
la forme de sa disposition. Rouvrir le projet (section « Projets » de la barre, ou
`roadie project open NOM`) montre la stage si elle vit encore ; sinon la recrée sur le
bureau affiché, rouvre chaque fenêtre à son tour et remet la disposition, même après un
redémarrage. Une application qui n'expose pas son document (Firefox, iTerm2) revient en
nouvelle fenêtre vide. Projets : `~/.roadies/projects.json`.

**Phrase** : plusieurs mots dont les derniers désignent une destination et une position,
en français ou en anglais : `fire perso gauche` ou `fire perso left` ouvre Firefox dans la
stage Perso, à gauche. Mots reconnus : un nom de stage (exact, ou début unique de 3 lettres),
`ici`/`here`, `nouvelle`/`new`, `bureau N`/`desktop N`, `écran N`/`screen N`, et
`gauche`/`left`, `droite`/`right`, `plein`/`full`, `flotte`/`float`. La ligne « Phrase »
annonce l'action avant Retour.

**Garder une action** : ⌘S sur une application, un fichier, une phrase ou un verbe composé
ouvre l'étape « Garder » : tapez une abréviation (12 caractères au plus), Retour
l'enregistre ; ⌘C copie la commande `roadie launch` équivalente, à coller dans
BetterTouchTool. Taper ensuite l'abréviation met l'action en tête. Les fenêtres et les
stages ne se gardent pas (elles disparaissent) ; une stage visée doit être nommée.
Abréviations : `~/.roadies/launcher-aliases.json`.

**Aperçu actif** : quand la ligne choisie se pose sur une stage de destination (Ouvrir
dans…, Envoyer vers…, Amener ici), les vraies fenêtres de cette stage prennent leur future
place ; la fenêtre envoyée y va aussi, et une fenêtre à ouvrir est marquée par un fantôme
translucide avec l'icône de son application. Une stage cachée du bureau affiché s'affiche
pendant le choix. Échap, une autre ligne ou la fermeture remettent tout comme avant ;
Retour garde la disposition. Pas d'aperçu vers un autre bureau ou une nouvelle stage.

**Variantes de Retour** : tenir ⌘, ⌥ ou ⌃ change ce que fait Retour, et le détail de
la ligne choisie l'annonce. ⌘ Retour ouvre l'application dans une nouvelle stage du
bureau affiché, ou y envoie la fenêtre, puis Roadie y va. ⌥ Retour amène la fenêtre
(ou celle de l'application) dans la stage active, sans changer la stage affichée.
⌃ Retour cherche le texte tapé sur le web (`web_search_url`, Google par défaut).
Les neuf premières lignes montrées portent ⌘1 à ⌘9 : la touche fait leur action, à
toutes les étapes. La touche se règle dans `pick_modifier` (`command` par défaut,
`shift`, `alt` ou `control`) ; avec `shift`, les chiffres de la rangée du haut ne
s'écrivent dans la recherche en AZERTY que dans une saisie vide ou un calcul. → avec le curseur en fin de saisie ouvre les verbes, comme Tab.

**Verbes de la fenêtre active** : Capslock + Maj + F (`actions_hotkey`, Hyper + Maj + F)
ou `roadie targets actions` ouvre la barre directement sur les verbes de la fenêtre au
premier plan. « Toujours faire flotter <App> » et « Toujours tuiler <App> » sont aussi
dans le menu Fenêtre de la barre de titre ; le choix est écrit dans
`roadies.generated.toml`, sur la même règle que « Toujours ouvrir cette app ici », et
vaut pour toutes les fenêtres de l'application, présentes et futures.

**Fenêtres d'appoint** : un rappel, une boîte de dialogue ou une palette ressemble souvent, pour macOS,
à une fenêtre ordinaire (le rappel de Thunderbird a les mêmes boutons que sa boîte de réception) ; seul
son titre la distingue. La liste « Fenêtres toujours flottantes » (Paramètres > Règles,
`[[exclusions.floating_windows]]`) garde hors du tuilage les fenêtres d'une application selon leur titre :
`app` (nom ou identifiant) et `title`, où `#` remplace un nombre et `*` n'importe quel texte, sans tenir
compte des majuscules (« # Reminder » couvre « 1 Reminder » et « 3 Reminders »). Chacun y ajoute, modifie
ou retire ses propres lignes. Le menu Fenêtre de la barre de titre propose « Toujours faire flotter les
fenêtres « # Reminder » » pour la fenêtre choisie, ou « Ne plus faire flotter… » si elle est déjà dans la
liste. Une ligne passe avant la règle de l'application (priorité 9 100). Les critères de taille (panneau
court, petite fenêtre de réglages) jugent la fenêtre à sa naissance, et non après son tuilage.
`roadie window explain [ID]` montre ce que l'accessibilité dit d'une fenêtre (sous-rôle, boutons, premier
cadre) et la raison de la décision.

**Place des fenêtres flottantes** : une fenêtre non tuilée qui s'ouvre sur le rail (les informations du
Finder s'ouvrent en haut à gauche) est décalée juste à sa droite, sans changer de taille ; Paramètres >
Règles > « Fenêtres flottantes hors du rail » (`[exclusions] floating_avoid_rail`, activé par défaut). Pour
qu'une fenêtre revienne là où vous l'avez laissée, position et taille, cochez « Retenir la place » sur sa
ligne de la liste ci-dessus ou sur sa règle (`remember_frame = true`). La place est retenue par ligne ou par
règle, et non par titre : toutes les fenêtres d'informations du Finder partagent la même. Seule l'ouverture
d'une fenêtre est traitée : ensuite, Roadie ne fait que noter vos déplacements ; au démarrage, les fenêtres
déjà ouvertes ne bougent pas. Une application peut imposer sa taille (le Finder fixe la largeur de ses
fenêtres d'informations).

| Touche | Effet |
|--------|-------|
| lettres, chiffres, espace | filtrer |
| Tab | verbes de la ligne choisie ; sur un verbe à « … », ses destinations |
| Fleche bas, Ctrl-N | resultat suivant |
| Maj-Tab, Fleche haut, Ctrl-P | resultat precedent |
| Maj + lettre de la pastille | ouvrir cette ligne (`⇧K` a droite d'une fenetre, stage ou bureau) |
| Retour | clic ; sur une application : aller à sa fenêtre ou l'ouvrir |
| ⌘ Retour | application, fenêtre : nouvelle stage ; cible à l'écran : Cmd-clic |
| ⌥ Retour | application, fenêtre : amener dans la stage active |
| ⌃ Retour | chercher le texte tapé sur le web |
| ⌘1 à ⌘9 | action de la ligne portant ce chiffre |
| → en fin de saisie | verbes de la ligne choisie |
| Retour deux fois (moins de 0,35 s) | double-clic |
| Maj-Retour | clic droit |
| `*` ou `;` | afficher toutes les cibles |
| `?` | fiche de la cible en vert (role, titre, texte, id) |
| Echap | fermer sans action |

Un clic hors de la barre et de son panneau la ferme. Le clic atteint normalement
l'application, même sur un autre écran. Les clics dans la barre ou le panneau
la gardent ouverte. La recherche se ferme aussi seule après 60 s sans frappe.
Les actions de clic sur une cible exigent
`app_mouse_actions_enabled = true` et la barre `overlay_enabled = true`.

La barre reste centree en bas sur l'ecran d'ouverture, avec une largeur de 640 points reduite si l'ecran
est plus etroit. Le texte long est tronque sans deplacer la barre ni recouvrir
le compteur. Elle utilise une police systeme proportionnelle et un contour fin.
Les tailles de saisie et de suggestions restent reglables independamment.

Une feuille web sans action (regle des elements focalisables) est cliquee au
centre de sa premiere image ou de son premier texte visible, pas au centre de
l'element : le centre d'une ligne de l'Historique de Bluejay ne reagit pas,
seuls la vignette, le titre et l'auteur ont un gestionnaire de clic.

Le mode lettres classique reste limite a la fenetre active. Pour l'etendre a
toutes les fenetres visibles : `scope = "visible_windows"` dans
`[experimental.app_targets]`.

#### Thèmes, place de la barre, terminal, signets et commandes système (sessions 100 à 105)

- **Touches mortes** : `~` (⌥N sur un clavier français), `^` puis `e` et les autres compositions ne sont
  plus effacées par la barre pendant la frappe.
- **Thèmes** (`theme`, `theme_dark`) : Roadie, ou l'un des thèmes d'Alfred (Alfred, Alfred Dark, Alfred Modern,
  Alfred Modern Dark, Alfred macOS, Alfred macOS Dark, Frosty Teal, High Contrast Light, Large Avenir), avec
  couleurs, polices, tailles, arrondis, largeur et flou. Un thème exporté d'Alfred (`.alfredappearance`) dans
  `~/.config/roadies/themes`, ou un thème personnel créé dans Alfred, s'ajoute à la liste. `theme_dark` sert
  quand macOS est en mode sombre. `visible_results` limite le nombre de lignes montrées (0 : selon la place).
- **Place de la barre** : glissez-la par son bord ou par le fond de la liste ; elle garde cette place
  (`bar_save_position`). Un double-clic sur le bord la remet à sa place par défaut (`bar_position` : en bas,
  au centre ou en haut comme Alfred, la liste s'ouvrant du côté libre). `bar_screen` : écran de la souris, de
  la fenêtre active ou principal.
- **Terminal** : `> commande` puis Retour lance la commande dans une nouvelle fenêtre du terminal choisi
  (`terminal_app` : Terminal, iTerm, Ghostty, Warp, kitty, WezTerm, Alacritty).
- **Signets** (`bookmarks_enabled`, `bookmark_browsers`) : signets de Firefox (tous les profils, dossiers,
  étiquettes, icônes des sites), Safari (accès complet au disque requis) et Chrome, Brave ou Edge, dès deux
  lettres. Les mots-clés de Firefox fonctionnent : `w chat` avec un signet de mot-clé `w` et `%s`. Les
  onglets ouverts de Firefox sont aussi trouvés ; Retour choisit l'onglet.
- **Système** : verrouiller, suspendre les écrans, tout quitter, vider la corbeille, son, redémarrer,
  éteindre… (second Retour pour les commandes lourdes) ; verbe « Forcer à quitter » d'une application.
- **Dossiers tapés** : ⌫ à la fin de `…/` remonte d'un dossier ; `path_sort` trie par nom ou par date.
- **Raccourcis** : Paramètres > Raccourcis réunit toutes les touches, réglées par appui : raccourcis globaux,
  touches de la barre (`large_type_key`, `copy_key`… dans `[experimental.target_mode]`), grille, sélecteur, et
  commandes `roadie …` de BetterTouchTool, chacune prise en charge par BTT, par Roadie (`[[shortcuts]]` :
  `keys`, `command`, `btt_uuid`) ou par personne. Une touche de la barre prise par BTT est signalée ;
  `btt_pause_keys` met ce raccourci BTT en pause tant que la barre est ouverte.
- **Verbes** : après Tab, les verbes les plus choisis pour un type d'objet (application, fichier, fenêtre,
  stage…) passent en tête ; `learn_verb_order = false` garde l'ordre fixe.
- **Forme des tuiles** : une grille de workflow suit son réglage d'images d'Alfred (`imageaspect` : carré,
  portrait ou paysage) ; la largeur des tuiles ne change pas.
- **Contenu et étiquettes** : `in facture mars` cherche les fichiers dont le texte contient ces mots (début de
  mot), `tags rouge` ceux qui portent une étiquette du Finder (couleurs en français ou en anglais). Mots-clés
  réglables (`content_search_keyword`, `tag_search_keyword`, vide : désactivé). OneDrive, Dropbox, Google Drive
  et iCloud Drive (`~/Library/CloudStorage`, `~/Library/Mobile Documents`) sont aussi cherchés.
- **Historique web** (`web_history_days`, 90 par défaut, 0 : désactivé) : pages déjà vues dans les navigateurs
  des signets (Firefox, tous les profils ; Safari avec l'accès complet au disque ; Chrome, Brave, Edge), sous
  « Historique » dès deux lettres, hors pages déjà en signet ; les plus visitées d'abord.
- **Réglages** (`settings_in_search`) : pages et réglages des Paramètres de Roadie (`rail`, `thème`) et panneaux
  des Réglages Système dans votre langue (`clavier`, `wi-fi`) sous « Réglages » ; Retour ouvre la page, le réglage
  (recherche des Paramètres déjà remplie) ou le panneau. ⌘, (`settings_key`) ouvre les Paramètres de Roadie.
- **Documents récents** : sur une application, Tab puis « Documents récents… » liste ses 20 derniers documents
  encore présents (menu Fichier > Ouvrir récent de macOS ; pour Word, Excel et PowerPoint, la liste propre à Office).
  La saisie filtre, Retour ouvre le document avec cette application. La première lecture d'une liste d'Office peut
  faire demander par macOS l'accès aux données de cette application.
- **Vue Texte des workflows** : la brique Texte d'Alfred 5.5 ouvre une fenêtre (texte à lire, à modifier ou Markdown
  rendu avec ses images), remplie par l'argument, un fichier ou un script relancé par un champ de saisie (réponses
  JSON `append`, `replacelast`, `rerun`… comme dans Alfred). Retour envoie le texte à la suite du workflow,
  avec les touches tenues ; Échap ferme.
- **Vues Image et PDF des workflows** : le fichier reçu s'ouvre dans une fenêtre d'aperçu (image réduite, ajustée ou
  à ses pixels réels ; PDF en une ou deux pages, continues ou non, selon la brique). Retour envoie son chemin à la
  suite du workflow ; Échap ferme.
- **Petites reprises d'Alfred** : `open nom` ne montre que des fichiers, `find nom` aussi et Retour les montre dans
  le Finder (`open_keyword`, `find_keyword`) ; `file_types` ajoute des types de fichiers (archives, AppleScripts…),
  `file_excluded_folders` écarte des dossiers ; `calc_decimal` (macOS, point, virgule) et `calc_grouping` règlent
  le résultat d'un calcul ; `show_scrollbar` montre une barre de défilement ; 17 recherches web fournies (`gi`,
  `tr`, `amazon`, `gh`, `wa`…) ; commandes « Recharger les applications » et « Reconstruire l'index Spotlight ».
- **Workflows : boutons Remote et cache** : un bouton d'Alfred Remote devient un déclencheur appelé par
  `roadie workflow trigger ID TRIGGERID` (avec son texte fixe), listé par `roadie workflow list --hotkeys` pour
  BetterTouchTool ; un Script Filter qui demande un cache (`cache.seconds`) n'est pas relancé pour la même saisie
  pendant ce délai.
- **Divers** : ⌘L (réglable) montre la ligne choisie en grand texte ; ⌘⎋ ferme la barre ; `app_search_paths` ajoute des
  dossiers d'applications ; `learning_enabled` coupe l'apprentissage et `roadie launcher reset` l'efface ;
  la calculatrice connaît aussi sinh, cosh, tanh, trunc, dtor, rtod…

### Mode commande (`/`) et fenêtre de réglages

La barre du mode recherche sait aussi lancer des commandes, à la manière des
commandes `/` de Codex ou de Claude. Un `/` en **premier caractère** fait passer
la barre en mode commande. Sans `/` au début, la barre reste en mode recherche,
sans aucun changement. Pour chercher un texte qui commence par `/`, tape un
espace avant. Effacer le `/` ramène au mode recherche.

En mode commande :

- la barre liste les commandes avec une courte description ; la liste se filtre
  pendant la frappe (casse et accents ignorés) ;
- **Tab** complète la commande ou l'argument (commande, numéro ou nom de stage,
  nom de bookmark, nom de réglage, catégorie, direction) en insérant la suggestion
  sélectionnée. Les Tab suivants parcourent les alternatives. Maj-Tab remonte la sélection ;
- **Flèche haut** et **Flèche bas** parcourent l'historique des 50 dernières
  commandes. L'historique est conservé après un redémarrage, dans
  `~/.local/state/roadies/command-history.json` ;
- **Retour** exécute la commande sur la fenêtre, le stage, l'écran et le bureau
  actifs à cet instant. En cas de succès, la barre se ferme. En cas d'échec, elle
  reste ouverte et affiche une erreur courte avec la forme attendue ; une commande
  inconnue propose la plus proche ;
- **Échap** ferme la barre sans action.

Chaque commande a le même effet que la commande `roadie` correspondante : aucune
action nouvelle n'est créée. Les directions s'écrivent en français (`gauche`,
`droite`, `haut`, `bas`) ou en anglais (`left`, `right`, `up`, `down`). `N` est un
nombre entier supérieur ou égal à 1.

| Commande | Alias | Forme | Effet |
|----------|-------|-------|-------|
| `/move` | | `/move DIR` | déplace la fenêtre active |
| `/swap` | | `/swap DIR` | inverse la fenêtre active avec sa voisine |
| `/resize` | | `/resize DIR` | redimensionne la fenêtre active |
| `/full` | | `/full` | plein écran natif |
| `/max` | | `/max` | agrandit la fenêtre |
| `/stage` | `/s` | `/stage N` ou `/stage NOM` | affiche ce stage |
| | | `/stage new [NOM]` | crée un stage |
| | | `/stage rename NOM` | renomme le stage courant |
| | | `/stage send N` | envoie la fenêtre active dans le stage N |
| `/screen` | | `/screen DIR` ou `/screen N` | focus sur un autre écran |
| `/send` | | `/send N` | envoie la fenêtre active sur l'écran N |
| `/desktop` | `/d` | `/desktop N` | active le bureau N |
| `/layout` | | `/layout bsp\|spatial\|master\|float` | change la disposition du stage |
| `/balance` | | `/balance` | équilibre la disposition |
| `/split` | | `/split h\|v` | règle le sens de coupe |
| `/bm` | `/b` | `/bm NOM` | va au bookmark NOM |
| | | `/bm set NOM` | pose le bookmark NOM sur la fenêtre active |
| `/grid` | | `/grid` ou `/grid fenêtre` | ouvre la grille de l'écran ou de la fenêtre active |
| `/letters` | | `/letters` | ouvre le mode lettres |
| `/doctor` | | `/doctor` | diagnostic ; résultat affiché dans la barre |
| `/heal` | | `/heal` | répare l'état du daemon |
| `/reload` | | `/reload` | recharge la configuration |
| `/restart` | | `/restart` | redémarre le daemon (aucun résultat affiché) |
| `/settings` | | `/settings [catégorie]` | ouvre la fenêtre de réglages |
| `/set` | | `/set nom [valeur\|défaut]` | lit ou modifie un réglage |

`/grid`, `/letters` et `/restart` s'exécutent après la fermeture de la barre.
Avec un seul écran ou un seul bureau, `/screen` et `/desktop` répondent qu'il n'y
a pas d'autre cible. Sans fenêtre active, les commandes qui en demandent une
répondent « Aucune fenêtre active ». Un refus est inscrit dans le journal
d'événements (`command.rejected`) avec le nom de la commande et un code de
raison, sans la saisie brute.

#### Fenêtre de réglages (`/settings`)

`/settings` ouvre la fenêtre « Réglages Roadie ». `/settings catégorie` l'ouvre
sur cette catégorie (identifiant sans accent ou libellé, casse ignorée). Sans
argument, elle s'ouvre sur la dernière catégorie vue (Général la première fois).
Une seconde demande ramène la même fenêtre au premier plan.

- **Colonne de gauche** : une zone de recherche, puis les catégories : Général,
  Tuilage, Stages et bureaux, Mode lettres, Grille, Recherche, Rail, Bordures,
  Focus et souris, Sélecteur, Règles, Avancé.
- **Zone de droite** : des groupes par usage, avec libellés et contrôles alignés.
  En fenêtre étroite, le contrôle passe sous son libellé. Le bouton d'information
  ouvre une aide défilable ; la flèche de réinitialisation rétablit le défaut.
  Les règles, leurs critères et leurs actions se déplient séparément.
  Les menus suivent la taille de texte choisie. Les onglets du sélecteur sont
  groupés sur toute la largeur, avec sélection visible. À grande police,
  ils passent sur deux rangées sans couper les mots.
- **Recherche** : filtre les réglages de toutes les catégories par nom et par
  description, casse et accents ignorés.
- **Sans bouton Enregistrer** : un changement est écrit dans le fichier de
  configuration dès la saisie d'une valeur valide, sans Retour ni perte du focus.
  Une valeur incomplète ou refusée reste en brouillon ; la dernière valeur valide
  reste active. Les marges déclenchent une nouvelle disposition, même pour un point.
  Pendant un déplacement à la souris, le tuilage attend le relâchement.
- **Suivi du fichier** : une modification faite ailleurs (à la main, par `/set`)
  apparaît dans la fenêtre sans la rouvrir.
- **Fermeture** : Échap, Cmd+W ou le bouton de fermeture. L'application qui était
  au premier plan reprend le focus.
- **Général** montre les tailles des textes, aides et titres de la fenêtre, ainsi
  que le chemin et l'état du fichier. Les outils avancés proposent Recharger,
  Diagnostic et l'ouverture facultative du fichier.
- **Listes et tableaux** : contrôles intégrés pour les côtés des marges, les rôles
  de fenêtres, les applications, les largeurs prédéfinies, les surcharges par écran,
  les stages nommés, les couleurs par stage et les règles. Chaque ligne complète et
  valide s'applique immédiatement. Un nom de stage modifié apparaît dans le rail.
  Retirer sa définition ne supprime ni le stage persistant ni ses fenêtres.
- **Éditeur avancé intégré** : les rares fragments complexes, dont `signals.hooks`,
  se modifient dans la fenêtre avec validation et enregistrement explicite.
  Roadie enregistre les hooks, mais ne les exécute pas actuellement.
  Si le fichier est invalide, les contrôles ordinaires sont désactivés ; l'éditeur
  complet permet de le réparer sans ouvrir une application externe.

#### Réglage en ligne (`/set`)

Un réglage se nomme `table.clé` : le chemin de la table du fichier, sans le
préfixe `experimental.` ni `fx.`, puis la clé. Exemples : `target_grid.overlay_fill_opacity`,
`app_targets.max_targets`, `rail.header.display.font_size`. La fenêtre, `/set` et
la complétion de la barre utilisent les mêmes noms.

| Saisie | Effet |
|--------|-------|
| `/set` | liste les catégories |
| `/set nom` | affiche la valeur actuelle, le défaut et la plage ou les choix permis (`target_grid.overlay_fill_opacity = 0.4 (défaut 0.1, de 0 à 1)`) |
| `/set nom valeur` | valide, écrit dans le fichier et applique |
| `/set nom défaut` | rétablit la valeur par défaut |

Conversions de la valeur :

- **Booléen** : `true`, `false`, `oui`, `non`, `on`, `off`, `1`, `0`.
- **Nombre** : point ou virgule décimale. Une valeur hors plage est refusée, tout
  comme un nombre non entier pour un entier.
- **Choix** : une valeur de la liste, sinon refus avec la liste.
- **Couleur** : `#RRGGBB` ou `#RRGGBBAA`.
- **Texte** : la fin de la saisie, sans les espaces de bord.
- **Liste ou tableau de tables** : utiliser l'éditeur intégré dans `/settings`.
  `/set nom défaut` peut rétablir une collection.

Un refus laisse le fichier intact et la barre donne la raison. Roadie journalise
chaque réglage modifié (`settings.changed`, nom du réglage et résultat), jamais sa
valeur.

#### Fichier de configuration

Le fichier est modifié **ligne à ligne** : seule la ligne de la clé change, avec
son indentation et son commentaire de fin de ligne. Les commentaires, l'ordre et
les réglages inconnus sont conservés. Une clé absente est ajoutée à la fin de sa
table ; une table absente, à la fin du fichier. Le texte résultat est validé avant
l'écriture, qui est atomique. À la première écriture de la session de Roadie, une
copie `roadies.toml.bak-<horodatage>` est créée dans le même dossier.

#### Taille des étiquettes

Les tailles sont indépendantes : `target_mode.label_font_size` pour les lettres,
`target_mode.search_label_font_size` pour la recherche et `target_grid.label_font_size`
pour la grille. Valeur en points, défaut 13, plage 8 à 48. La saisie de recherche
utilise `target_mode.search_text_font_size` et les suggestions
`target_mode.command_text_font_size`. Les cadres suivent la taille du texte.

La catégorie Recherche propose aussi les familles `target_mode.search_font_family`
et `target_mode.command_font_family`. Le menu liste les familles installées.
`system`, une valeur vide ou une famille absente utilise
la police macOS. Famille et taille changent dans la barre déjà ouverte sans perdre
la saisie. Les clés TOML se trouvent dans `[experimental.target_mode]`.

#### Limites

- Les fragments avancés exigent une validation et un enregistrement explicite.
  Les `signals.hooks` ne sont pas exécutés.
- Les actions de règle `layout` et `gap_override` sont enregistrées, mais ne
  modifient pas encore le tuilage. La fenêtre indique cette limite.
- `/float` et `/close` n'existent pas : Roadie n'a pas ces actions. `/layout float`
  règle la disposition du stage.
- Le mode commande et la fenêtre de réglages sont dessinés par le daemon : ils
  exigent que `roadied` tourne.
- Les clés sans effet (par exemple `desktops.*`, `stage_manager.enabled`) ne sont
  pas montrées. La fenêtre suit la langue de macOS (français ou anglais).

Les briques du Mode Cibles sont configurables separement. Le socle CLI et le picker
restent actifs par défaut. Les overlays graphiques existent ; leur activation
reste facultative. Les clics et le défilement dans les applications restent
désactivés par défaut.

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
label_font_size = 13   # taille des étiquettes en points (8 à 48)
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
label_font_size = 13   # taille des étiquettes en points (8 à 48)
```

Cas d'usage :

- sauter vers une fenetre bookmarkee ou une stage sans memoriser son ID;
- chercher une cible par texte avec `targets pick` et refuser proprement les ambiguities;
- ouvrir la barre avec le raccourci choisi, puis taper quelques lettres pour activer un élément visible;
- envoyer la fenetre active vers une cible affichee par label;
- fournir a un agent une API JSON plus robuste qu'une capture d'ecran;
- inspecter pourquoi une cible est stale, pinnee, flottante ou hors tiling.

Meme si `experimental.app_targets.enabled = true`, les actions `click`,
`double-click`, `right-click` et `command-click` sur les zones applicatives sont refusees tant que
`experimental.target_mode.app_mouse_actions_enabled = false`.

La découverte des contrôles dépend des informations exposées par chaque
application. Le temps de lecture est limité et la fonction s'active séparément.

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
roadie toggle floating
```

Cas d'usage :

- revenir au dernier focus;
- forcer une restructuration locale du layout;
- insérer la fenêtre active du côté voulu avec `warp`;
- inverser localement deux fenetres voisines en `spatialBsp` avec `toggle-split`;
- agrandir temporairement une fenetre sans perdre le contexte;
- sortir une fenetre du tuilage dans sa stage, puis l'y remettre.

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
