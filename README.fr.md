<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Logo Roadie" width="128" height="128">
</div>

<div align="center">

# Roadie

**Projet en cours. Il faut s’attendre à des aspérités, des changements cassants et du polish manquant.**

[English](README.md) | Français

</div>

Roadie est un petit gestionnaire de fenêtres tiling pour macOS, écrit en Swift, construit autour d’une idée simple : le tiling automatique et un workflow de type Stage Manager devraient pouvoir cohabiter.

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="Capture Roadie multi-écran" width="100%">
</p>

## Pourquoi Ce Projet Existe

À l’origine, je ne voulais pas écrire un window manager. Pendant des années, [yabai](https://github.com/koekeishiya/yabai) a été la base de mon poste macOS : puissant, précis, et profondément structurant pour tous ceux qui font du tiling sur macOS. Roadie doit beaucoup à yabai, fonctionnellement et culturellement.

Le déclencheur a été personnel : je n’ai jamais réussi à faire cohabiter proprement yabai avec le workflow Stage Manager que je voulais. Je voulais des groupes de fenêtres nommés, masquables, restaurables, tout en gardant le tiling automatique pour les fenêtres visibles.

Roadie se concentre donc sur cette combinaison précise :

- Tiling `bsp` et `masterStack` pour les fenêtres visibles.
- Stages Roadie : groupes de fenêtres nommés, masquables, restaurables, réordonnables et représentés visuellement.
- Desktops virtuels Roadie sans contrôle des Spaces macOS natifs.
- Support multi-écran où chaque écran garde son desktop courant, sa stage active et son layout.

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

| Fonctionnalité | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Tiling BSP | oui | oui | oui |
| Layout master-stack | partiel | oui | oui |
| Contrôle des Spaces macOS natifs | oui, avec configuration système supplémentaire | non | non |
| Desktops virtuels sans Spaces natifs | non | oui | oui |
| Stages nommées dans un desktop | non | non | oui |
| Nav rail avec thumbnails | non | non | oui |
| Tiling multi-écran | oui | oui | oui |
| Focus follows mouse | oui | oui | oui |
| Bordure de focus overlay | non | non | oui |
| Usage CLI-first | oui | oui | oui |

Roadie ne nécessite pas de désactiver SIP. Il utilise Accessibilité pour découvrir et déplacer les fenêtres, et Enregistrement d’écran uniquement pour les thumbnails du rail.

## Ce Que Fait Roadie Aujourd’hui

- Tile les fenêtres visibles avec les modes `bsp`, `masterStack` ou `float`.
- Gère des groupes de fenêtres par stage, écran et desktop Roadie.
- Fournit des desktops virtuels Roadie sans contrôler les Spaces macOS natifs.
- Supporte plusieurs écrans indépendamment.
- Affiche un nav rail natif avec les thumbnails des stages.
- Permet de déplacer des thumbnails entre stages ou vers la scène active.
- Affiche une bordure autour de la fenêtre active.
- Fournit des commandes CLI faciles à brancher dans BetterTouchTool, Karabiner, des scripts shell ou un launcher.
- Persiste les stages et l’état du layout entre les redémarrages du daemon.
- Expose des commandes d’état, santé, métriques, événements et audit pour diagnostiquer.
- Publie des événements automation JSONL et des projections JSON stables via `roadie query ...`.
- Supporte des rules TOML avec validation, explain et événements runtime `rule.*`.
- Supporte des commandes power-user comme `focus back-and-forth`, `layout insert`, `layout flatten` et `layout zoom-parent`.
- Persiste et expose des groupes de fenêtres pour des workflows stack/tab-like.

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

- macOS.
- Xcode Command Line Tools.
- Permission Accessibilité pour `roadied`.
- Permission Enregistrement d’écran si tu veux les vraies thumbnails dans le rail.

Installer Xcode Command Line Tools si besoin :

```bash
xcode-select --install
```

## Build

Depuis la racine du dépôt :

```bash
make test
make start
```

Les scripts du projet forcent la toolchain Xcode et évitent les environnements shell qui peuvent injecter des flags linker incompatibles.

Commandes utiles :

```bash
make test
make start
make stop
make restart
make status
make logs
make doctor
```

Équivalents directs :

```bash
./scripts/test
./scripts/start
./scripts/stop
./scripts/status
./scripts/logs
./scripts/roadie daemon health
```

## Build DMG Et Installation Non Signée Apple

Roadie peut être packagé dans un DMG macOS classique :

```bash
make package-dmg
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

L’app packagée démarre aujourd’hui Roadie pour la session utilisateur courante. Un futur installateur signé pourra ajouter automatiquement un login item ou un LaunchAgent ; pour l’instant, le démarrage au login reste volontairement explicite.

## Permissions

Roadie a besoin de la permission Accessibilité pour lire et déplacer les fenêtres.

Après build et lancement du daemon, ajoute ce binaire dans Réglages Système > Confidentialité et sécurité > Accessibilité :

```text
/Users/moi/Nextcloud/10.Scripts/39.roadie/bin/roadied
```

Puis redémarre le daemon :

```bash
make restart
```

La permission Enregistrement d’écran est optionnelle mais recommandée. Sans elle, le nav rail peut afficher des icônes d’app fallback au lieu des thumbnails live.

## Configuration

Le fichier de configuration utilisateur est :

```text
~/.config/roadies/roadies.toml
```

Valider la configuration :

```bash
./bin/roadie config validate
```

Afficher la configuration chargée :

```bash
./bin/roadie config show
```

Valider et inspecter les rules :

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

## Usage Quotidien

Démarrer ou redémarrer le daemon :

```bash
make restart
```

Vérifier l’état runtime :

```bash
./bin/roadie daemon health
./bin/roadie state audit
./bin/roadie metrics
./bin/roadie tree dump
```

Lister les fenêtres et les écrans :

```bash
./bin/roadie windows list
./bin/roadie display list
```

Changer le mode de layout de la stage courante :

```bash
./bin/roadie mode bsp
./bin/roadie mode masterStack
./bin/roadie mode float
```

Déplacer le focus ou les fenêtres :

```bash
./bin/roadie focus left
./bin/roadie focus right
./bin/roadie focus back-and-forth
./bin/roadie move left
./bin/roadie warp right
./bin/roadie resize left
```

Envoyer la fenêtre active vers un autre écran :

```bash
./bin/roadie window display 2
```

## Stages

Les stages sont des groupes de fenêtres. Seule la stage active est visible ; les stages inactives sont masquées et représentées dans le nav rail.

Commandes courantes :

```bash
./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage reorder 2 1
./bin/roadie stage delete 4
./bin/roadie stage prev
./bin/roadie stage next
```

Ramener dans la stage active une fenêtre d’une stage inactive :

```bash
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
```

## Desktops Roadie

Les desktops Roadie sont des desktops virtuels gérés par Roadie. Ils ne créent, ne switchent et ne contrôlent pas les Spaces macOS natifs.

```bash
./bin/roadie desktop list
./bin/roadie desktop current
./bin/roadie desktop focus 2
./bin/roadie desktop focus next
./bin/roadie desktop focus prev
./bin/roadie desktop focus back
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork
```

## Commandes Layout Power-User

```bash
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout insert right
./bin/roadie layout join-with left
./bin/roadie layout flatten
./bin/roadie layout zoom-parent
```

Ces commandes persistent l'intention de layout quand c'est pertinent, pour eviter que le maintainer annule immediatement une structure manuelle volontaire.

## Groupes De Fenetres

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

Les groupes sont persistés dans l'état des stages Roadie et exposes via `roadie query groups`.

## Automation

Suivre les evenements live :

```bash
./bin/roadie events subscribe --from-now --initial-state
```

Lire les projections JSON stables :

```bash
./bin/roadie query state
./bin/roadie query windows
./bin/roadie query displays
./bin/roadie query desktops
./bin/roadie query stages
./bin/roadie query groups
./bin/roadie query rules
./bin/roadie query health
./bin/roadie query events
```

Envoyer la fenêtre active vers un autre desktop Roadie :

```bash
./bin/roadie window desktop 2
./bin/roadie window desktop 2 --follow
```

## Nav Rail

Le nav rail est un panneau latéral natif par écran.

Il affiche les stages non vides, les thumbnails live quand elles sont disponibles, des icônes d’app fallback quand la capture n’est pas disponible, et un halo autour de la stage active.

Interactions supportées :

- Cliquer sur une pile de thumbnails pour changer de stage.
- Cliquer dans une zone vide du rail pour masquer la stage active et passer sur une stage vide.
- Drag une thumbnail vers une autre stage pour y déplacer la fenêtre.
- Drag une thumbnail vers la scène active pour la ramener.
- Drag une thumbnail vers une zone vide du rail pour la placer dans une stage vide ou nouvellement créée.
- Utiliser les chevrons au-dessus et au-dessous d’une stage pour réordonner les stages.

Le rendu du rail se configure dans `~/.config/roadies/roadies.toml`.

## Dépannage

Lancer les vérifications rapides :

```bash
./bin/roadie daemon health
./bin/roadie state audit
./bin/roadie self-test
```

Réparer les problèmes d’état conservateurs :

```bash
./bin/roadie state heal
./bin/roadie daemon heal
```

Inspecter logs et événements :

```bash
make logs
./bin/roadie events tail 50
```

Si les fenêtres ne bougent plus après un rebuild, revérifie Accessibilité pour `bin/roadied`, puis redémarre :

```bash
make restart
```

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
```

## Statut

Roadie est d’abord construit pour un usage quotidien personnel. Les commandes, les clés de configuration et le comportement du rail peuvent encore changer pendant la stabilisation.
