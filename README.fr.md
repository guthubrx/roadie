<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Logo Roadie" width="128" height="128">

# Roadie

**Un gestionnaire de fenêtres macOS qui combine disposition automatique, stages nommés et bureaux virtuels.**

[English](README.md) | Français

</div>

Roadie organise tes fenêtres autour de tes activités. Regroupe les applications
d'un projet, retrouve-les dans le rail latéral et passe d'un espace de travail à
l'autre sur chaque écran.

**[Télécharger Roadie 0.7.0](https://github.com/guthubrx/roadie/releases/tag/v0.7.0)** ·
[Découvrir les nouveautés](docs/releases/v0.7.0.md) · [Guide d'installation](#installation-manuelle)

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="Espaces de travail Roadie sur plusieurs écrans" width="100%">
</p>

## Un espace pour chaque activité

Un éditeur, un terminal et un navigateur pour développer. Des documents pour
écrire. Une fenêtre de réunion à garder sous la main. Roadie permet de réunir
ces fenêtres dans des **stages**, des groupes nommés que tu retrouves dans le rail.

Le projet réunit le tuilage inspiré de [yabai](https://github.com/koekeishiya/yabai),
les bureaux virtuels inspirés d'[AeroSpace](https://github.com/nikitabobko/AeroSpace)
et les groupes de fenêtres de Stage Manager.

## Ce que tu peux faire avec Roadie

| Besoin | Fonction |
|---|---|
| Organiser les fenêtres | Tuilage automatique, plusieurs dispositions et poignées de séparation en arbre persistant |
| Passer d'un projet à l'autre | Stages nommés, aperçus et changement d'espace depuis le rail |
| Travailler sur plusieurs écrans | Bureaux indépendants, nouvelles fenêtres sur l'écran actif par défaut, transfert des fenêtres et des stages |
| Garder une fenêtre accessible | Épinglages, signets et groupes de fenêtres |
| Agir au clavier | Étiquettes, grilles et barre de recherche et de commandes |
| Adapter l'interface | Réglages immédiats, tailles indépendantes et choix de polices |
| Automatiser les habitudes | Règles de placement, macros courtes, commandes et API JSON |

### Une disposition qui suit ton travail

Roadie répartit les fenêtres et ajuste leur place quand tu en ouvres ou en fermes
une. Choisis une disposition équilibrée, une fenêtre principale avec ses voisines,
ou un placement libre.

Réorganise les fenêtres par glisser-déposer : un dépôt au centre échange les
positions, un dépôt sur un bord insère la fenêtre de ce côté. Tu peux aussi
modifier les proportions au clavier ou tirer les poignées entre les groupes de
fenêtres. Leur affichage se règle dans Tuilage. La maximisation laisse le rail
accessible et permet de revenir à la disposition précédente.

[Explorer les dispositions et les gestes](docs/fr/features.md)

### Tes projets, à portée de vue

Le rail affiche les stages de chaque écran avec leurs vignettes ou leurs icônes.
Passe à un autre stage, ramène une fenêtre dans l'espace actif ou déplace un
stage entier vers un autre écran. Conserve ton ordre et prévisualise la place des
stages pendant leur réorganisation. [Organiser les stages et déposer les fenêtres](#nav-rail).

Le mode flottant sort une fenêtre du tuilage dans sa stage. Les épinglages la
gardent visible pendant les changements de stage.
Les signets permettent de retrouver une fenêtre choisie. Tes stages et tes
réglages sont conservés entre les sessions.

Quand un écran est reconnecté, ses stages retrouvent leur place. Un stage déplacé
explicitement vers un autre écran y reste. Les stages nommés restent accessibles
même lorsqu'ils sont vides, avec un contour et leur nom ; les menus de destination
suivent l'ordre du rail.

### Une barre pour chercher et agir

Ouvre la **barre de recherche et de commandes** avec le raccourci de ton choix.
Tape quelques lettres pour trouver une fenêtre, un stage ou un élément visible. Tab complète la sélection ;
un `/` initial donne accès aux commandes de Roadie.

Par exemple, `/stage dev` change d'activité et `/settings` ouvre les paramètres.
Les suggestions et l'historique accompagnent la saisie. Le raccourci se règle
dans la catégorie Recherche ; `roadie targets search` ouvre aussi la barre.

### Une interface à ta mesure

Le **sélecteur de fenêtres** ouvre la fenêtre choisie dans son bureau et sa
stage Roadie. Dans Réglages Roadie > Sélecteur, crée des profils pour un écran, un
bureau, une stage ou une application. Enregistre directement une combinaison,
confie-la à BetterTouchTool ou utilise une commande externe. Au relâchement,
choisis entre activer la fenêtre, garder le sélecteur ouvert et passer en recherche.
Navigue avec les quatre flèches ou la souris. Chaque profil peut avoir sa propre
apparence.
[Guide du sélecteur](docs/fr/window-switcher.md).

Les paramètres sont regroupés par usage, avec des champs alignés et des aides
défilables. Les règles se déplient une par une ; les onglets du sélecteur occupent
toute la largeur. Ajuste les espacements, les noms de stages, les règles et les exceptions depuis
la fenêtre de paramètres. Les valeurs valides s'appliquent pendant la saisie.
Choisis séparément les tailles du rail, des étiquettes et des paramètres, ainsi
que les polices du champ de recherche et de ses suggestions.

Les étiquettes clavier permettent de sélectionner un élément en tapant ses lettres.
Les grilles écran et fenêtre permettent de viser une zone précise. Les macros
courtes enregistrent des actions de souris à répéter. Active les outils qui
conviennent à ta façon de travailler.

[Voir les fonctionnalités](docs/fr/features.md) ·
[Exemples d'utilisation](docs/fr/use-cases.md)

## Documentation

La documentation complète existe en français et en anglais :

- [Documentation française](docs/fr/README.md)
- [English documentation](docs/en/README.md)

Guides principaux :

- [Vue d'ensemble des fonctionnalités](docs/fr/features.md)
- [Commandes CLI](docs/fr/cli.md)
- [Configuration et rules](docs/fr/configuration-rules.md)
- [Événements et API de requêtes](docs/fr/events-query.md)
- [Cas d'usage](docs/fr/use-cases.md)

## Prérequis

- macOS 14 ou plus récent.
- Xcode Command Line Tools. Xcode complet n’est pas nécessaire.
- Permission Accessibilité pour `roadied`.
- Permission Enregistrement d’écran pour `roadied`, seulement si tu veux les vraies thumbnails dans le rail.
- Outils facultatifs : `tmux` pour le runtime modulaire, `create-dmg` pour construire le DMG.

Installer Xcode Command Line Tools si besoin :

```bash
xcode-select --install
```

Les scripts du projet utilisent `/Applications/Xcode.app` s’il existe. Sinon, ils utilisent les Command Line Tools indiquées par `xcode-select -p`. Ils nettoient aussi l’environnement shell des variables qui peuvent injecter des flags linker incompatibles. Si aucune toolchain Swift n’est trouvée, le script s’arrête et te demande d’installer les Command Line Tools.

## Build Et Lancement De Développement

Depuis la racine du dépôt :

```bash
make test
make dev-start
```

`make dev-start` sert au développement. Il compile en mode debug, copie les binaires dans `./bin` seulement, décharge le LaunchAgent installé et lance le daemon dans une session `tmux`. Il ne touche pas aux binaires installés par `make install`. Dans ce mode, utilise `./bin/roadie` et donne l’Accessibilité à `bin/roadied` de ce dossier. Pour l’usage quotidien, installe Roadie avec `make install`.

**Un seul lanceur à la fois.** `roadied run` et `roadied tiler` prennent un verrou d’instance (`~/.roadies/roadied.lock`). Une deuxième instance sort avec le code 1. Le LaunchAgent relance un processus qui échoue (`KeepAlive`) : il réessaierait en boucle si une session `tmux` fait déjà tourner le daemon. Pour cette raison :

- `make dev-start` et `./scripts/start-modular` déchargent d’abord le LaunchAgent ;
- `make restart` ne lance jamais `tmux`, et il refuse de s’exécuter tant qu’une session de développement existe. Lance d’abord `make stop` ;
- pour revenir au service installé, lance `make stop`, puis `make restart`.

## Installation Manuelle

Pour une installation locale manuelle depuis les sources :

```bash
make install
```

Cette cible masque la mise en place macOS habituelle :

- build `roadie` et `roadied` en mode release ;
- installe le daemon comme application `~/Applications/Roadie.app`, avec son nom et son icône dans les réglages de confidentialité ;
- installe la commande dans `/Users/moi/.local/bin`, avec un lien `roadied` vers le daemon de l'application : le service reste indépendant du dossier source ;
- signe l’application et la commande (voir plus bas) ;
- crée `/Users/moi/Library/LaunchAgents/com.roadie.roadied.plist`, qui lance le daemon depuis l'application ;
- démarre le LaunchAgent s’il n’est pas déjà chargé.

Ajoute `~/.local/bin` à ton `PATH` pour pouvoir taper `roadie` dans un terminal.

Si Roadie tourne déjà, `make install` ne l’arrête pas. Lance ceci quand tu veux que le daemon recharge les nouveaux binaires installés :

```bash
make restart
```

`make restart` arrête Roadie, puis recharge le service installé avec launchd. Il arrête aussi une instance ouverte directement comme application. Le démarrage vérifie que launchd et le fichier PID désignent le même processus vivant. Il ne compile rien. Le rechargement applique aussi les changements du LaunchAgent.

Après une mise à jour, lance `make install`, puis `make restart`, puis `roadie query health`. Si une session de développement tmux tourne, lance d’abord `make stop`.

### Signature du code et permissions

Donne l'accès à **Roadie** dans Réglages Système > Confidentialité et sécurité > Accessibilité.

macOS lie la permission Accessibilité à la signature de Roadie. `make install` reprend le certificat exact de l’application installée quand son empreinte est disponible. Si ce certificat manque dans le trousseau, l’installation s’arrête avant de remplacer l’application. Un certificat du même nom ne suffit pas. Un choix explicite avec `ROADIE_CODESIGN_IDENTITY` reste prioritaire. À la première installation, il utilise `roadied-cert` si cette identité existe dans le trousseau. Sinon, il utilise une signature ad hoc et affiche un avertissement : macOS peut oublier la permission après une nouvelle compilation.

Pour choisir une identité stable explicitement :

```bash
security find-identity -v -p codesigning
ROADIE_CODESIGN_IDENTITY="Apple Development: Ton Nom (TEAMID)" make install
```

Si tu veux seulement installer les fichiers sans démarrer le LaunchAgent :

```bash
ROADIE_INSTALL_NO_START=1 make install
```

Commandes utiles :

```bash
make test
make build
make install
make uninstall
make dev-start
make stop
make restart
make status
make logs
make doctor
make dmg
```

Équivalents directs :

```bash
./scripts/test
./scripts/start        # make dev-start
./scripts/stop
./scripts/status
./scripts/logs
./scripts/roadie query health
```

Les logs sont dans `~/.roadies/`. À chaque démarrage, le log précédent est conservé sous `roadied.stdout.log.1` et `roadied.stderr.log.1`. Un crash reste donc lisible après un redémarrage.

## Désinstallation

```bash
make uninstall
```

Le script fait ces étapes dans l’ordre :

1. lance `roadie restore unhide-all` pour qu’aucune fenêtre ne reste masquée ou hors écran ;
2. arrête le LaunchAgent, les composants modulaires et les instances autonomes ; si un processus refuse de s’arrêter, il conserve les fichiers installés ;
3. supprime le fichier LaunchAgent, `~/Applications/Roadie.app` et les binaires de `~/.local/bin` ;
4. demande s’il faut garder l’état de Roadie (`~/.roadies`, `~/.local/state/roadies`). Sans terminal, il le garde.

Le script ne supprime jamais ta configuration dans `~/.config/roadies`. Supprime-la à la main si tu le souhaites. Pour finir, retire Roadie de Réglages Système > Confidentialité et sécurité > Accessibilité et Enregistrement d’écran.

## Runtime Modulaire

Le chemin classique (`make install`, ou `make dev-start` en développement) lance Roadie comme un daemon unique. Le chemin
modulaire lance les mêmes capacités sous forme de processus séparés :

```bash
./scripts/start-modular
roadie query components
roadie query health
```

Le lanceur modulaire standard démarre tous les composants, y compris le tuilage.
Chaque composant dispose de ses journaux et de son état de santé. Ce mode permet
d'observer les services séparément.

## Build DMG Et Installation Non Signée Apple

Roadie peut être packagé dans un DMG macOS classique :

```bash
make dmg
```

Le résultat est :

```text
dist/Roadie.dmg
```

Le DMG contient `Roadie.app` et un raccourci `/Applications`, donc l’installation se fait par drag-and-drop classique.

Important : ce build est signé ad-hoc, pas signé avec un certificat Apple Developer ID, et pas notarized par Apple. macOS Gatekeeper ne le considérera donc pas comme une app publique entièrement approuvée.

Pour les utilisateurs, le premier lancement attendu est :

1. Glisser `Roadie.app` dans `/Applications`.
2. L’ouvrir une première fois avec clic droit > Ouvrir, puis confirmer. Roadie démarre comme une app de fond sans menu ni fenêtre.
3. Si macOS bloque encore l’app, lancer :

```bash
xattr -dr com.apple.quarantine /Applications/Roadie.app
```

4. Donner les permissions à `/Applications/Roadie.app` dans Réglages Système > Confidentialité et sécurité :

- Accessibilité.
- Enregistrement d’écran, si les thumbnails live du nav rail sont souhaitées.

Cette limite est normale tant que l’app n’est pas signée avec un certificat Apple Developer ID et notarized par Apple.

Le DMG demande `create-dmg` (`brew install create-dmg`). Le script vérifie ses outils d’abord et s’arrête avec un message clair s’il en manque un.

L’app n’a ni icône dans la barre des menus, ni icône dans le Dock. Pour la quitter, quitte `roadied` dans le Moniteur d’activité. Pour la désinstaller, quitte `roadied`, puis glisse `Roadie.app` dans la corbeille.

L’app packagée démarre aujourd’hui Roadie pour la session utilisateur courante. Un futur installateur signé pourra ajouter automatiquement un login item ou un LaunchAgent ; pour l’instant, le démarrage au login reste volontairement explicite.

## Permissions

Roadie demande deux permissions. Les deux vont au daemon `roadied`.

| Permission | Sert à | Obligatoire |
|---|---|---|
| Accessibilité | Lire et déplacer les fenêtres | Oui |
| Enregistrement d’écran | Thumbnails live des fenêtres dans le rail | Non. Sans elle, le rail affiche des icônes d’app. |

Après `make install`, donne les permissions à **Roadie**, l’application installée dans `~/Applications/Roadie.app`. La commande `~/.local/bin/roadied` pointe vers son daemon. Dans le sélecteur de fichier, utilise Cmd+Maj+G pour ouvrir le dossier de l’application. Puis redémarre et contrôle le daemon :

```bash
make restart
roadie query health
```

### La commande `roadie` n’a besoin d’aucune permission

Quand le daemon tourne, la commande `roadie` lui envoie ta demande par un socket local (`~/.roadies/roadied.sock`). Le daemon fait le travail avec ses propres permissions. BetterTouchTool, Karabiner, skhd ou un script shell qui appelle `roadie` n’ont donc pas besoin de la permission Accessibilité. La commande ne scanne pas non plus toutes les fenêtres à chaque appui de touche, ce qui accélère les raccourcis.

Si le daemon est arrêté, `roadie` exécute la commande lui-même. Dans ce cas, le programme qui l’a lancé (terminal, BetterTouchTool) a besoin de la permission Accessibilité. Certaines commandes tournent toujours en local : `daemon start|stop|restart|health`, `doctor`, `permissions` et `config validate`.

Utilise `roadie query health` pour contrôler le daemon avec ses propres permissions. `roadie doctor` lit aussi son statut et vérifie la configuration. Les contrôles locaux de `doctor` et `daemon health` peuvent relever les fenêtres avec les permissions du terminal. Un relevé local vide ne signifie pas que le daemon ne voit aucune fenêtre. Le daemon publie cet état dans `~/.roadies/daemon-status.json` (identifiant du processus, version, permissions, validité de la configuration, heure de mise à jour), et `roadie doctor` lit ce fichier. Doctor considère le daemon arrêté quand son processus a disparu ou quand le fichier a plus de 90 secondes.

## Configuration

Le fichier de configuration utilisateur est :

```text
~/.config/roadies/roadies.toml
```

Un exemple commenté est dans [`examples/roadies.toml`](examples/roadies.toml). Copie-le comme point de départ :

```bash
mkdir -p ~/.config/roadies
cp examples/roadies.toml ~/.config/roadies/roadies.toml
```

Valider la configuration :

```bash
roadie config validate
```

La validation signale chaque problème avec le nom complet de la clé :

- `error  focus.stage_follows_focus  attendu booléen, reçu texte` : une valeur a le mauvais type ;
- `warning  tiling.gaps_inr  clé inconnue, ignorée ; vouliez-vous dire « gaps_inner » ?` : une faute de frappe, avec la clé valide la plus proche ;
- `warning  desktops.count  clé sans effet` : Roadie lit la clé dans le fichier mais ne l’utilise pas. C’est le cas de toute la table `[desktops]` et de `enabled` et `hide_strategy` dans `[stage_manager]`.

Des exemples de raccourcis pour skhd et Karabiner-Elements sont dans `examples/skhd/skhdrc` et `examples/karabiner/roadie.json`. Voir [Raccourcis](docs/fr/cli.md#raccourcis).

Afficher la configuration chargée :

```bash
roadie config show
```

Valider et inspecter les rules :

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

## Usage Quotidien

Démarrer ou redémarrer le daemon :

```bash
make restart
```

Vérifier l’état runtime :

```bash
roadie query health
roadie state audit
roadie metrics
roadie tree dump
```

Lister les fenêtres et les écrans :

```bash
roadie windows list
roadie display list
```

Changer le mode de layout de la stage courante :

```bash
roadie mode spatialBsp   # alias : mutableBsp, yabai
roadie mode bsp
roadie mode masterStack
roadie mode float
```

Déplacer le focus ou les fenêtres :

```bash
roadie focus left
roadie focus right
roadie focus back-and-forth
roadie move left
roadie warp right
roadie resize left
roadie display focus right
```

Envoyer la fenêtre active vers un autre écran :

```bash
roadie window display 2
```

## Stages

Les stages sont des groupes de fenêtres. Seule la stage active est visible ; les stages inactives sont masquées et représentées dans le nav rail.

Commandes courantes :

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
roadie stage reorder 2 1
roadie stage delete 4
roadie stage prev
roadie stage next
```

`stage switch` et `stage assign` ciblent les identifiants stables. `stage switch-position` et `stage assign-position` ciblent l’ordre visible du nav rail. `stage switch-visible prev|next` parcourt uniquement les stages non vides. `stage assign-empty` envoie la fenêtre active vers le prochain stage vide sans nom et le crée si nécessaire.

Ramener dans la stage active une fenêtre d’une stage inactive :

```bash
roadie stage summon WINDOW_ID
```

Déplacer le stage actif vers un autre écran :

```bash
roadie stage move-to-display 2
roadie stage move-to-display right
roadie stage move-to-display right --no-follow
```

Sans option, Roadie suit `[focus].stage_move_follows_focus`. `--follow` et `--no-follow` remplacent ce réglage pour une commande. Le menu d’une carte du nav rail propose la même action.

## Desktops Roadie

Les desktops Roadie sont des desktops virtuels gérés par Roadie. Ils ne créent, ne switchent et ne contrôlent pas les Spaces macOS natifs.

```bash
roadie desktop list
roadie desktop current
roadie desktop focus 2
roadie desktop focus next
roadie desktop focus prev
roadie desktop focus back
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
```

## Commandes Layout Power-User

```bash
roadie layout split horizontal
roadie layout split vertical
roadie layout toggle-split
roadie warp right
roadie layout flatten
roadie layout zoom-parent
```

Dans `spatialBsp`, ces commandes modifient l’arbre enregistré ou son état de zoom. Utilise `warp` pour une insertion et `resize` pour un changement de taille. Les anciennes commandes `layout insert`, `layout join-with` et `layout width` sont refusées dans ce mode. Elles restent disponibles dans les autres modes compatibles.

## Groupes De Fenetres

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

Les groupes sont persistés dans l'état des stages Roadie et exposes via `roadie query groups`.

## Automation

Suivre les evenements live :

```bash
roadie events subscribe --from-now --initial-state
```

Lire les projections JSON stables :

```bash
roadie query state
roadie query windows
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
```

Envoyer la fenêtre active vers un autre desktop Roadie :

```bash
roadie window desktop 2
roadie window desktop 2 --follow
```

## Nav Rail

Le plein écran Roadie (`roadie toggle fullscreen`) remplit la zone utile et cache
le rail, même au survol, sans passer au plein écran natif macOS. Répète la commande
pour restaurer la disposition. La maximisation (`roadie toggle maximize`) garde
le rail accessible. Hors plein écran, `auto_hide = true` dans `[fx.rail]` replie
le rail comme le Dock : le survol du bord gauche le révèle.

Le nav rail est un panneau latéral natif par écran.

Il affiche les stages non vides, les thumbnails live quand elles sont disponibles, des icônes d’app fallback quand la capture n’est pas disponible, et un halo autour de la stage active.

Interactions supportées :

- Cliquer sur une pile de thumbnails pour changer de stage.
- Un clic dans une zone vide du rail ne fait rien par défaut, pour qu’un clic raté ne masque pas la stage active. Mets `empty_click_hide_active = true` seulement si tu veux qu’une zone vide bascule vers une stage vide.
- Drag une thumbnail vers une autre stage pour y déplacer la fenêtre.
- Drag une thumbnail vers la scène active pour la ramener.
- Drag une thumbnail vers une zone vide du rail pour la placer dans une stage vide ou nouvellement créée.
- Glisser une fenêtre d’application par sa barre de titre vers une stage pour l’y déplacer.
- Glisser une fenêtre d’application par sa barre de titre vers une zone vide du rail pour la placer dans une stage vide ou nouvellement créée.
- Glisser une stage avec le bouton droit de la souris pour réordonner les stages. Un aperçu translucide montre sa future place ; les cartes voisines montrent le nouvel ordre. Relâcher pour l’appliquer, ou sortir du rail avant de relâcher pour annuler.
- Faire un clic droit sur une stage, sans glisser, pour ouvrir son menu : renommer la stage, l’envoyer vers un autre écran ou envoyer une fenêtre vers une autre stage.

L’intensité de l’aimantation se règle dans **Réglages Roadie > Rail > Aimantation du réordonnancement (%)**. À 0, elle est désactivée ; une valeur plus élevée stabilise davantage la destination malgré les petits mouvements de souris.

Le rendu du rail se configure dans `~/.config/roadies/roadies.toml`.

Le rail se masque en plein écran Roadie et devant une fenêtre en plein écran natif macOS. Pour le masquer aussi devant une fenêtre agrandie, mets `hide_on_maximized = true` dans `[fx.rail]`.

## Mode Cibles, Grille Ecran Et Grille Fenetre

Roadie expose un **Mode Cibles** : des labels courts pour les fenetres, stages,
ecrans, desktops, bookmarks et, en option, les zones applicatives Accessibility.
Ces cibles peuvent etre cherchees, inspectees, activees et exportees en JSON
pour des scripts ou des agents.

Le **mode recherche** (`Cmd+Ctrl+Option+F` par défaut, clé `search_hotkey`) ouvre une barre de
saisie : tape quelques lettres d'un element de n'importe quelle fenetre visible,
puis Retour pour le cliquer (Maj-Retour clic droit, Cmd-Retour Cmd-clic, deux
Retour double-clic).

`Tab` complète le titre du résultat sélectionné sans le cliquer. Les flèches et
Ctrl-N/Ctrl-P changent de résultat. La barre garde sa position et sa largeur sur l'écran d'ouverture,
avec un compteur dans une pastille à droite, une bordure fine et une police proportionnelle.

### Boîte de commandes et fenêtre de réglages

Un `/` en premier caractère passe la barre en **mode commande**. Les suggestions
complètent les commandes, les directions, les stages, les signets et les réglages.
`Tab` insère la suggestion sélectionnée ; les Tab suivants parcourent les alternatives.
Les flèches haut et bas parcourent l'historique.
`Retour` exécute la commande ; `Échap` ferme la barre. Les raccourcis système restent
interceptés pendant la saisie de commande.

| Action | Exemple |
|---|---|
| Déplacer la fenêtre | `/move gauche` |
| Échanger deux fenêtres | `/swap droite` |
| Changer de stage | `/stage 2` ou `/stage Travail` |
| Changer d'écran | `/screen droite` |
| Envoyer la fenêtre vers un écran | `/send 2` |
| Ouvrir les réglages | `/settings` |
| Lire ou écrire un réglage | `/set target_mode.label_font_size 20` |
| Rétablir la valeur par défaut | `/set target_mode.label_font_size défaut` |
| Contrôler ou recharger | `/doctor`, `/heal`, `/reload` |

La fenêtre de réglages propose des catégories, une recherche et des changements
appliqués dès la saisie d'une valeur valide. Les marges déclenchent une nouvelle
disposition, même pour un changement d'un point. Les listes, les stages, les règles
et les surcharges par écran ont leurs éditeurs intégrés. Un brouillon incomplet
reste dans le champ sans remplacer la dernière valeur valide.
L'interface est en français. Les commentaires du fichier TOML sont conservés.
Une sauvegarde précède la première modification de la session. Une écriture invalide
est refusée. Les tailles de police sont indépendantes. Les curseurs, le pas à pas
et la saisie d'une taille valide les appliquent immédiatement. Les sessions ouvertes
gardent leur saisie lors du changement.

| Zone | Identifiants des réglages |
|---|---|
| Paramètres : textes, aides, titres | `interface.settings_text_font_size`, `interface.settings_help_font_size`, `interface.settings_title_font_size` |
| Étiquettes du mode lettres | `target_mode.label_font_size` |
| Étiquettes de la grille | `target_grid.label_font_size` |
| Recherche : étiquettes, saisie, suggestions | `target_mode.search_label_font_size`, `target_mode.search_text_font_size`, `target_mode.command_text_font_size` |
| Rail : écran, bureau, textes de stage | `rail.header.display.font_size`, `rail.header.desktop.font_size`, `rail.stage_labels.font_size` |

Par exemple, `/set interface.settings_text_font_size 20` modifie la fenêtre des paramètres.
Ses textes, aides et titres ont des défauts de 16, 14 et 22 points. Les étiquettes des
lettres, de la grille et de la recherche ont un défaut de 13 points. Les cartes du rail
adaptent leur taille à la police. Les infobulles et messages de dialogue natifs de macOS
gardent la police du système.

Dans Recherche, les familles de police de la saisie et des suggestions sont
indépendantes : `target_mode.search_font_family` et `target_mode.command_font_family`.
Le changement apparaît dans la barre ouverte. `system` choisit la police macOS ;
une famille absente utilise aussi cette police.
Les rares fragments complexes ont un éditeur avancé intégré avec validation et
enregistrement explicite. Les `signals.hooks` peuvent être enregistrés, mais Roadie
ne les exécute pas actuellement. Un fichier invalide peut être réparé dans la fenêtre.
Les actions de règle `layout` et `gap_override` sont enregistrées, mais ne modifient
pas encore le tuilage. Les éditeurs signalent cette limite.

La barre et les réglages exigent un daemon démarré et `overlay_enabled = true`.
Dans la table existante du fichier de configuration, active au minimum :

```toml
[experimental.target_mode]
overlay_enabled = true
search_hotkey = "command+control+alt+f"
```

Pour découvrir et cliquer les éléments des applications, active aussi
`[experimental.app_targets].enabled = true` et
`[experimental.target_mode].app_mouse_actions_enabled = true`. Les commandes
et les réglages fonctionnent sans activer les clics dans les applications.

Voir [le catalogue et les limites du mode commande](docs/fr/features.md#mode-commande--et-fenêtre-de-réglages).

### Grilles écran et fenêtre

Roadie fournit aussi deux grilles recursives :

- **Grille Ecran** pour cibler un ecran complet.
- **Grille Fenetre** pour cibler la fenetre actuellement focussee.

Les deux grilles utilisent le meme langage spatial : taper le label d'une
cellule zoome dedans, `Espace` valide, les fleches deplacent la selection et
`Esc` annule. Les macros courtes peuvent stocker le meilleur contexte de cible
plus un fallback grille.

```bash
roadie targets interactive --source all --include-app-targets
roadie targets search
roadie grid interactive --scope display
roadie grid interactive --scope focused_window
roadie record start demo --duration 10
```

Ces outils peuvent être activés séparément dans
`[experimental.target_mode]`, `[experimental.app_targets]`,
`[experimental.target_grid]` et `[experimental.target_record]`.

## Dépannage

Lancer les vérifications rapides :

```bash
roadie query health
roadie state audit
roadie self-test
```

Réparer les problèmes d’état conservateurs :

```bash
roadie state heal
roadie daemon heal
```

Inspecter logs et événements :

```bash
make logs
roadie events tail 50
```

Obtenir un rapport complet sur le daemon, les deux permissions et la configuration :

```bash
roadie doctor
roadied --version
```

`roadied --version` (et `roadie --version`) affiche la version, utile pour comparer le binaire installé avec le daemon en marche.

Si des fenêtres restent masquées ou hors écran (par exemple après un crash), ramène-les toutes :

```bash
roadie restore unhide-all
```

Si les fenêtres ne bougent plus après une nouvelle installation, vérifie que Roadie est toujours activé dans Accessibilité (voir [Signature du code et permissions](#signature-du-code-et-permissions)), puis redémarre :

```bash
make restart
```

Le daemon remet les fenêtres masquées quand il reçoit un signal d’arrêt (SIGTERM, SIGINT, SIGHUP), et un petit processus de surveillance fait de même si le daemon plante. Pour lancer le daemon sans cette sécurité, démarre-le avec `roadied run --yes --no-restore-safety`.

Les logs du lancement précédent sont dans `~/.roadies/roadied.stderr.log.1` et `~/.roadies/roadied.stdout.log.1`.

## Confidentialité

Roadie fonctionne localement. Les sources actuelles de l’application ne contiennent aucun service de télémétrie ou d’envoi distant. Les commandes CLI passent par un socket Unix local. Enregistrement d’écran reste facultatif et sert aux vignettes des fenêtres.

L’état local et les diagnostics peuvent contenir des titres de fenêtres, des noms d’applications, des identifiants d’écrans, des positions et l’historique des événements. Les macros peuvent garder un contexte de cible. Considère la configuration, les sauvegardes, les logs, les exports, les macros et les captures du bureau comme privés. Relis et anonymise ces fichiers avant de les partager ou de les ajouter à Git.

Le dépôt contient les sources et des données d’exemple ou de test. Les dossiers d’exécution locaux, les fichiers d’environnement, les clés de signature et les métadonnées SpecKit propres à la machine sont exclus de Git. Vérifie le contenu des captures avant publication. Ces contrôles ne retirent pas les données des anciens commits ni des copies déjà téléchargées.

## Organisation Du Dépôt

```text
Sources/RoadieAX       Snapshots système et Accessibilité
Sources/RoadieCore     Types partagés, géométrie, configuration
Sources/RoadieTiler    Stratégies de layout pures
Sources/RoadieStages   État persistant desktops et stages Roadie
Sources/RoadieDaemon   Services daemon, rail, bordure, commandes
Sources/roadie         CLI
Sources/roadied        Point d’entrée daemon
Tests                  Tests unitaires
scripts                Helpers build et runtime
examples               Config d’exemple, raccourcis skhd et Karabiner
```

## Statut

Le développement se poursuit sur `main`. Les [notes de release](https://github.com/guthubrx/roadie/releases) présentent les nouveautés et les consignes de mise à jour.
