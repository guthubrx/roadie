<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Logo Roadie" width="128" height="128">
</div>

<div align="center">

# Roadie

**Projet en cours. Il faut s’attendre à des aspérités, des changements cassants et du polish manquant.**

[English](README.md) | Français

</div>

Roadie est un petit gestionnaire de fenêtres tiling pour macOS, écrit en Swift, construit autour d’une idée simple : le tiling automatique et un workflow de type Stage Manager devraient pouvoir cohabiter.

Release courante : [v0.3.0](docs/releases/v0.3.0.md).

## Pourquoi Ce Projet Existe

À l’origine, je ne voulais pas écrire un window manager. Pendant des années, [yabai](https://github.com/koekeishiya/yabai) a été la base de mon poste macOS : puissant, précis, et profondément structurant pour tous ceux qui font du tiling sur macOS. Roadie doit beaucoup à yabai, fonctionnellement et culturellement.

Le déclencheur a été personnel : je n’ai jamais réussi à faire cohabiter proprement yabai avec le workflow Stage Manager que je voulais. Je voulais des groupes de fenêtres nommés, masquables, restaurables, tout en gardant le tiling automatique pour les fenêtres visibles.

Roadie se concentre donc sur cette combinaison précise :

- Tiling `bsp`, `mutableBsp` et `masterStack` pour les fenêtres visibles.
- Stages Roadie : groupes de fenêtres nommés, masquables, restaurables, réordonnables et représentés visuellement.
- Desktops virtuels Roadie sans contrôle des Spaces macOS natifs.
- Support multi-écran où chaque écran garde son desktop courant, sa stage active et son layout.
- Parking d’écran : quand un écran disparaît, Roadie rapatrie ses stages non vides sur un écran restant au lieu de les fusionner dans la stage active.
- Runtime modulaire : tiler, rail, bordures, focus-follows-mouse, mode cibles,
  actions de barre de titre et restore safety peuvent tourner dans des
  composants séparés.

Roadie n’essaie pas de remplacer yabai. yabai est plus large, plus ancien et beaucoup plus mature. Roadie est volontairement plus petit, et très orienté autour de mon workflow.

## L’Influence AeroSpace

La deuxième grande influence est [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Au lieu d’essayer de manipuler les Spaces natifs de macOS, Roadie suit la même grande direction : garder SIP activé, éviter les APIs privées d’écriture, et gérer des workspaces virtuels côté Roadie. Changer de desktop Roadie signifie masquer les fenêtres du desktop sortant et restaurer celles du desktop entrant.

Le résultat est un petit hybride :

- Un modèle de tiling inspiré de l’ergonomie concrète de yabai sur macOS.
- Un modèle de desktops virtuels inspiré du refus d’AeroSpace de se battre contre les Spaces natifs.
- Une couche de stages pour les personnes qui veulent un workflow de type Stage Manager au-dessus du tiling.

Si tu veux un window manager macOS généraliste et mature, regarde d’abord yabai ou AeroSpace. Roadie existe pour le cas plus étroit où tiling, desktops virtuels et groupes de stages doivent former un seul workflow.

## Positionnement Fonctionnel

Ce n’est pas un tableau de supériorité. Il sert seulement à clarifier le périmètre de Roadie.

Légende : ✅ supporté, ◐ partiel ou plus étroit, ❌ non supporté,
🧪 expérimental, ⚙️ nécessite un setup supplémentaire ou un outil externe.

### Layout Et Contrôle Des Fenêtres

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Tiling BSP | ✅ | ✅ | ✅ |
| Arbre de tiling modifiable par l'utilisateur | ✅ | ✅ | ◐ |
| Layout master-stack | ◐ | ✅ | ✅ |
| Mode float | ✅ | ✅ | ✅ |
| Placement de fenêtre sur grille | ✅ | ❌ | ❌ |
| Point d'insertion de fenêtre | ✅ | ❌ | ◐ |
| Layout stack/tab/accordion | ✅ stack | ✅ accordion | ◐ groupes seulement |
| Fenêtres scratchpad | ✅ | ❌ | ◐ |
| Commandes power-user sur l'arbre | ✅ | ✅ | ◐ |

### Runtime Et Mode Compagnon

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Daemon window-manager complet unique | ✅ | ✅ | ✅ |
| Composants modulaires | ❌ | ❌ | ✅ |
| Lancer seulement overlays/stages avec un autre WM | ⚙️ | ⚙️ | 🧪 base prête |
| Santé par composant | ◐ | ◐ | ✅ |
| Logs par composant | ◐ | ◐ | ✅ |

### Desktops, Stages Et Écrans

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Contrôle des Spaces macOS natifs | ✅ ⚙️ | ❌ | ❌ |
| Création/destruction/déplacement des Spaces macOS natifs | ✅ ⚙️ | ❌ | ❌ |
| Desktops virtuels sans Spaces natifs | ❌ | ✅ | ✅ |
| Stages nommées dans un desktop | ❌ | ❌ | ✅ |
| Nav rail avec thumbnails | ❌ | ❌ | ✅ |
| Navigation et réordonnancement visibles des stages | ❌ | ❌ | ✅ |
| Parking d'écran et restauration au rebranchement | ❌ | ◐ | ✅ |
| Tiling multi-écran | ✅ | ✅ | ✅ |
| Déplacement de workspace/stage vers un autre écran | ✅ | ✅ | ✅ |
| Awareness Mission Control | ✅ | ◐ | ◐ |

### Rules, Automatisation Et Configuration

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Rules de fenêtres et placement automatique | ✅ | ✅ callbacks | ✅ |
| Effets riches dans les rules | ✅ | ◐ | ◐ |
| Hotkeys intégrées | ❌ ⚙️ `skhd` | ✅ | ❌ ⚙️ BTT/Karabiner |
| Binding modes | ❌ | ✅ | ❌ |
| Callbacks de configuration | ✅ signals | ✅ | ◐ |
| Reload déclaratif de configuration | ◐ shell | ✅ | ✅ |
| Query API JSON stable | ✅ | ✅ | ✅ |
| Flux d'événements automation | ✅ signals | ✅ subscribe | ✅ JSONL |
| Usage CLI-first | ✅ | ✅ | ✅ |

### Focus Et Comportement Visuel

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Focus follows mouse | ✅ | ✅ | ✅ |
| Bordure de focus overlay | ❌ | ❌ | ✅ |
| Toggles opacity/layers/PiP/shadow | ✅ ⚙️ | ❌ | ❌ |
| Aides fullscreen natif | ✅ | ✅ | ◐ |
| Actions contextuelles sur barre de titre | ❌ | ❌ | ✅ |

### Cibles Clavier Et Grilles

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Labels clavier de cibles | ❌ | ❌ | ✅ |
| Découverte des zones applicatives | ❌ | ❌ | 🧪 |
| Grille récursive écran | ❌ | ❌ | 🧪 |
| Grille récursive fenêtre focusée | ❌ | ❌ | 🧪 |
| Record/replay de macros courtes | ❌ | ❌ | 🧪 |

`◐` signifie que Roadie a une version plus étroite ou moins mature de la
fonctionnalité, pas une parité complète avec yabai ou AeroSpace.

Roadie ne nécessite pas de désactiver SIP. Il utilise Accessibilité pour découvrir et déplacer les fenêtres, et Enregistrement d’écran uniquement pour les thumbnails du rail.

## Ce Que Fait Roadie Aujourd’hui

- Tile les fenêtres visibles avec les modes `bsp`, `mutableBsp`, `masterStack` ou `float`.
- Tourne soit en daemon monolithique, soit en composants modulaires separes :
  `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu` et `target-mode`.
  La sécurité de restauration vit dans les processus `run` et `tiler`.
- Gère des groupes de fenêtres par stage, écran et desktop Roadie.
- Fournit des desktops virtuels Roadie sans contrôler les Spaces macOS natifs.
- Supporte plusieurs écrans indépendamment.
- Rapatrie les stages d’un écran débranché sur un écran restant, puis les restaure quand le même écran revient et peut être reconnu sans ambiguïté.
- Affiche un nav rail natif avec les thumbnails des stages.
- Permet de déplacer des thumbnails entre stages ou vers la scène active.
- Permet optionnellement de faire un clic droit sur la barre de titre d'une fenêtre gérée pour l'envoyer vers une autre stage, un autre desktop ou un autre écran.
- Affiche une bordure autour de la fenêtre active.
- Fournit des commandes CLI faciles à brancher dans BetterTouchTool, Karabiner, des scripts shell ou un launcher.
- Persiste les stages et l’état du layout entre les redémarrages du daemon.
- Expose des commandes d’état, santé, métriques, événements et audit pour diagnostiquer.
- Publie des événements automation JSONL et des projections JSON stables via `roadie query ...`.
- Supporte des rules TOML avec validation, explain, événements runtime `rule.*` et placement automatique stage/écran.
- Supporte des commandes power-user comme `focus back-and-forth`, `layout insert`, `layout flatten` et `layout zoom-parent`.
- Supporte un arbre BSP persistant et des operations BSP mutables plus proches
  de yabai : move, warp, resize, insert, swap et preservation des ratios observes.
- Persiste et expose des groupes de fenêtres pour des workflows stack/tab-like.
- Expose le Mode Cibles pour labels clavier, picker par recherche, automatisation JSON, inspection de cibles et decouverte experimentale des zones applicatives.
- Fournit deux grilles spatiales configurables : Grille Ecran pour cibler recursivement un ecran complet, et Grille Fenetre pour cibler recursivement la fenetre focussee.
- Enregistre de courtes macros souris avec contexte de cible et fallback grille.
- Fournit des outils de sûreté : reload config atomique, restore snapshot manuel, restore-on-exit/crash watcher limité, cleanup des fichiers générés.
- Expose des diagnostics performance read-only, sans instrumentation du chemin focus/bordure.

## Documentation

La documentation complete existe en francais et en anglais :

- [Documentation francaise](docs/fr/README.md)
- [English documentation](docs/en/README.md)

Guides principaux :

- [Vue d'ensemble des fonctionnalites](docs/fr/features.md)
- [Commandes CLI](docs/fr/cli.md)
- [Configuration et rules](docs/fr/configuration-rules.md)
- [Evenements et Query API](docs/fr/events-query.md)
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
- installe le daemon comme application Roadie, avec son nom et son icône dans les réglages de confidentialité ;
- installe la commande et un lien vers le daemon hors du dépôt : le service continue de marcher si tu déplaces ou supprimes le dossier source ;
- signe l’application et la commande (voir plus bas) ;
- crée le LaunchAgent, qui lance le daemon depuis l’application ;
- démarre le LaunchAgent s’il n’est pas déjà chargé.

Ajoute `~/.local/bin` à ton `PATH` pour pouvoir taper `roadie` dans un terminal.

Si Roadie tourne déjà, `make install` ne l’arrête pas. Lance ceci quand tu veux que le daemon recharge les nouveaux binaires installés :

```bash
make restart
```

`make restart` arrête Roadie, puis recharge le service installé avec launchd. Il arrête aussi une instance ouverte directement comme application. Il ne compile rien. Le rechargement applique aussi les changements du LaunchAgent.

### Signature du code et permissions

macOS lie la permission Accessibilité à la signature de Roadie. `make install` reprend l’identité de signature de l’application installée. À la première installation, il utilise `roadied-cert` si cette identité existe dans le trousseau. Sinon, il utilise une signature ad hoc et affiche un avertissement : macOS peut oublier la permission après une nouvelle compilation.

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
./scripts/roadie daemon health
```

Les logs sont dans `~/.roadies/`. À chaque démarrage, le log précédent est conservé sous `roadied.stdout.log.1` et `roadied.stderr.log.1`. Un crash reste donc lisible après un redémarrage.

## Désinstallation

```bash
make uninstall
```

Le script fait ces étapes dans l’ordre :

1. lance `roadie restore unhide-all` pour qu’aucune fenêtre ne reste masquée ou hors écran ;
2. arrête le LaunchAgent (`launchctl bootout`) ;
3. supprime le fichier LaunchAgent et les binaires de `~/.local/bin` ;
4. demande s’il faut garder l’état de Roadie (`~/.roadies`, `~/.local/state/roadies`). Sans terminal, il le garde.

Le script ne supprime jamais ta configuration dans `~/.config/roadies`. Supprime-la à la main si tu le souhaites. Pour finir, retire `roadied` de Réglages Système > Confidentialité et sécurité > Accessibilité et Enregistrement d’écran.

## Runtime Modulaire

Le chemin classique (`make install`, ou `make dev-start` en développement) lance Roadie comme un daemon unique. Le chemin
modulaire lance les memes capacites sous forme de processus separes :

```bash
./scripts/start-modular
roadie query components
roadie daemon health
```

Le script modulaire standard lance aujourd'hui tout le set de composants, y
compris le tiler. L'interet architectural est plus large : permettre a Roadie de
devenir non seulement un window manager complet, mais aussi un ensemble de
composants utilisables comme couche compagnon avec yabai, AeroSpace ou un autre
gestionnaire de fenetres.

Cet usage "companion mode" reste volontairement note comme experimental : les
frontieres runtime, les locks de composants, la sante par composant et les logs
separes sont en place, mais les profils explicites "stage-only" ou
"overlay-only" restent a formaliser.

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

Après `make install`, ajoute ce binaire dans Réglages Système > Confidentialité et sécurité > Accessibilité, et dans Enregistrement d’écran si tu veux les thumbnails :

```text
~/.local/bin/roadied
```

Dans le sélecteur de fichier, appuie sur Cmd+Maj+G et tape le chemin, car `.local` est un dossier caché. Puis redémarre le daemon :

```bash
make restart
```

### La commande `roadie` n’a besoin d’aucune permission

Quand le daemon tourne, la commande `roadie` lui envoie ta demande par un socket local (`~/.roadies/roadied.sock`). Le daemon fait le travail avec ses propres permissions. BetterTouchTool, Karabiner, skhd ou un script shell qui appelle `roadie` n’ont donc pas besoin de la permission Accessibilité. La commande ne scanne pas non plus toutes les fenêtres à chaque appui de touche, ce qui accélère les raccourcis.

Si le daemon est arrêté, `roadie` exécute la commande lui-même. Dans ce cas, le programme qui l’a lancé (terminal, BetterTouchTool) a besoin de la permission Accessibilité. Certaines commandes tournent toujours en local : `daemon start|stop|restart|health`, `doctor`, `permissions` et `config validate`.

Lance `roadie doctor` pour voir l’état réel du daemon, des deux permissions et de la validité de ta configuration. Le daemon publie cet état dans `~/.roadies/daemon-status.json` (identifiant du processus, version, permissions, validité de la configuration, heure de mise à jour), et `roadie doctor` lit ce fichier. Doctor considère le daemon arrêté quand son processus a disparu ou quand le fichier a plus de 90 secondes.

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
roadie daemon health
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
roadie mode bsp
roadie mode mutableBsp
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
roadie stage reorder 2 1
roadie stage delete 4
roadie stage prev
roadie stage next
```

Ramener dans la stage active une fenêtre d’une stage inactive :

```bash
roadie stage summon WINDOW_ID
roadie stage move-to-display 2
```

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
roadie layout insert right
roadie layout join-with left
roadie layout flatten
roadie layout zoom-parent
```

Ces commandes persistent l'intention de layout quand c'est pertinent, pour eviter que le maintainer annule immediatement une structure manuelle volontaire.

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

Le nav rail est un panneau latéral natif par écran.

Il affiche les stages non vides, les thumbnails live quand elles sont disponibles, des icônes d’app fallback quand la capture n’est pas disponible, et un halo autour de la stage active.

Interactions supportées :

- Cliquer sur une pile de thumbnails pour changer de stage.
- Un clic dans une zone vide du rail ne fait rien par défaut, pour qu’un clic raté ne masque pas la stage active. Mets `empty_click_hide_active = true` seulement si tu veux qu’une zone vide bascule vers une stage vide.
- Drag une thumbnail vers une autre stage pour y déplacer la fenêtre.
- Drag une thumbnail vers la scène active pour la ramener.
- Drag une thumbnail vers une zone vide du rail pour la placer dans une stage vide ou nouvellement créée.
- Utiliser les chevrons au-dessus et au-dessous d’une stage pour réordonner les stages.

Le rendu du rail se configure dans `~/.config/roadies/roadies.toml`.

Par défaut, le rail se masque devant une fenêtre en plein écran natif macOS. Pour le masquer aussi devant une fenêtre agrandie, mets `hide_on_maximized = true` dans `[fx.rail]`.

## Mode Cibles, Grille Ecran Et Grille Fenetre

Roadie expose un **Mode Cibles** : des labels courts pour les fenetres, stages,
ecrans, desktops, bookmarks et, en option, les zones applicatives Accessibility.
Ces cibles peuvent etre cherchees, inspectees, activees et exportees en JSON
pour des scripts ou des agents.

Roadie fournit aussi deux grilles recursives :

- **Grille Ecran** pour cibler un ecran complet.
- **Grille Fenetre** pour cibler la fenetre actuellement focussee.

Les deux grilles utilisent le meme langage spatial : taper le label d'une
cellule zoome dedans, `Espace` valide, les fleches deplacent la selection et
`Esc` annule. Les macros courtes peuvent stocker le meilleur contexte de cible
plus un fallback grille.

```bash
roadie targets interactive --source all --include-app-targets
roadie grid interactive --scope display
roadie grid interactive --scope focused_window
roadie record start demo --duration 10
```

Les surfaces risquées sont expérimentales et activables séparément dans
`[experimental.target_mode]`, `[experimental.app_targets]`,
`[experimental.target_grid]` et `[experimental.target_record]`.

## Dépannage

Lancer les vérifications rapides :

```bash
roadie daemon health
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

Si les fenêtres ne bougent plus après une nouvelle installation, vérifie que `~/.local/bin/roadied` est toujours activé dans Accessibilité (voir [Signature du code et permissions](#signature-du-code-et-permissions)), puis redémarre :

```bash
make restart
```

Le daemon remet les fenêtres masquées quand il reçoit un signal d’arrêt (SIGTERM, SIGINT, SIGHUP), et un petit processus de surveillance fait de même si le daemon plante. Pour lancer le daemon sans cette sécurité, démarre-le avec `roadied run --yes --no-restore-safety`.

Les logs du lancement précédent sont dans `~/.roadies/roadied.stderr.log.1` et `~/.roadies/roadied.stdout.log.1`.

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

Roadie est d’abord construit pour un usage quotidien personnel. Les commandes, les clés de configuration et le comportement du rail peuvent encore changer pendant la stabilisation.
