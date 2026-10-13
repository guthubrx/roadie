# Contrat : commandes de la boîte

La boîte lit la saisie. Le premier caractère `/` ouvre le mode commande. Les arguments sont séparés par des espaces. Les directions acceptent le français et l'anglais.

Notation : `DIR` = `gauche|droite|haut|bas` (ou `left|right|up|down`), traduit en `left|right|up|down`. `N` = nombre entier ≥ 1.

| Commande | Alias | Forme | Appel du routeur (`CLICommandRouter.run`) | Remarque |
|---|---|---|---|---|
| `/move` | | `/move DIR` | `["move", dir]` | |
| `/swap` | | `/swap DIR` | `["window","swap", dir]` | alias de `move` dans le routeur |
| `/resize` | | `/resize DIR` | `["resize", dir]` | |
| `/full` | | `/full` | `["toggle","native-fullscreen"]` | |
| `/max` | | `/max` | `["toggle","maximize"]` | |
| `/stage` | `/s` | `/stage N` | `["stage","switch", id]` | |
| | | `/stage NOM` | `["stage","switch", id]` | le nom est résolu en identifiant par l'état des stages ; nom inconnu = erreur ; nom ambigu = erreur avec la liste |
| | | `/stage new [NOM]` | `["stage","create", id, nom?]` | `id` = plus petit identifiant numérique libre |
| | | `/stage rename NOM` | `["stage","rename", idCourant, nom]` | stage du focus |
| | | `/stage send N` | `["stage","assign", id]` | |
| `/screen` | | `/screen DIR\|N` | `["display","focus", dir\|N]` | |
| `/send` | | `/send N` | `["window","display", N]` | numéro d'écran |
| `/desktop` | `/d` | `/desktop N` | `["desktop","focus", N]` | |
| `/layout` | | `/layout bsp\|spatial\|master\|float` | `["mode", bsp\|spatialBsp\|masterStack\|float]` | |
| `/balance` | | `/balance` | `["balance"]` | |
| `/split` | | `/split h\|v` | `["layout","split", horizontal\|vertical]` | |
| `/bm` | `/b` | `/bm NOM` | `["bookmark","jump", nom]` | |
| | | `/bm set NOM` | `["bookmark","set", nom]` | |
| `/grid` | | `/grid` | `["grid","interactive","--scope","display"]` | différée |
| | | `/grid fenêtre` | `["grid","interactive","--scope","focused_window"]` | différée |
| `/letters` | | `/letters` | `["targets","interactive","--source","all","--include-app-targets"]` | différée |
| `/doctor` | | `/doctor` | `["doctor"]` | résultat affiché dans la boîte |
| `/heal` | | `/heal` | `["daemon","heal"]` | |
| `/reload` | | `/reload` | `["config","reload"]` | |
| `/restart` | | `/restart` | `["daemon","restart"]` | différée, sans message |
| `/settings` | | `/settings [catégorie]` | (aucun) | ouvre la fenêtre |
| `/set` | | `/set nom [valeur\|défaut]` | (aucun) | voir contracts/settings.md |

## Résultat

- Succès (`exitCode == 0`) : la boîte se ferme, sauf `/doctor`, `/set nom` et `/settings` sans fenêtre disponible, qui affichent leur résultat.
- Échec (`exitCode != 0`, argument invalide, commande inconnue) : la boîte reste ouverte. Le message contient la cause courte et la forme attendue (`usage`). Aucun état de Roadie ne change quand l'analyse échoue.
- Une commande inconnue propose la commande la plus proche (distance d'édition ≤ 2).
- Journal : une commande refusée émet `command.rejected` {commande, raison}.

## Cas particuliers

- Aucune fenêtre active : le routeur répond « no active window » ; la boîte l'affiche en français : « Aucune fenêtre active ».
- Un seul écran ou un seul bureau : `/screen` et `/desktop` affichent « Il n'y a pas d'autre écran » / « Il n'y a pas d'autre bureau ».
- Action différée : le lanceur appelle `finish` de la session, puis exécute l'action au tour suivant de la boucle principale.

## Complétion

- Avant le premier espace : noms et alias des commandes.
- Après `/stage` : numéros et noms de stage. Après `/bm` : noms de bookmark. Après `/set` : noms de réglage. Après `/settings` : catégories. Après `/layout`, `/screen`, `/move`… : valeurs permises.
- Tab complète sur l'unique correspondance, ou avance dans la liste.

## Historique

50 commandes, fichier `~/.local/state/roadies/command-history.json`. Flèche haut = commande précédente, Flèche bas = suivante.
