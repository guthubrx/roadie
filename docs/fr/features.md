# Fonctionnalites

## Tiling

Roadie tile les fenetres visibles d'une stage active.

Modes disponibles :

- `bsp` : repartition en arbre binaire, adaptee aux workflows terminal/code/navigateur.
- `masterStack` : une fenetre principale et une pile secondaire.
- `float` : Roadie garde les fenetres dans l'etat de stage mais ne les retile pas.

Exemples :

```bash
./bin/roadie mode bsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie balance
```

Cas d'usage :

- developpement avec editeur en master et terminaux en stack;
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
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
```

`stage switch N` cible la position visible dans la liste des stages. Avec des ids `1`, `3`, `4`, le raccourci `Alt-2` peut donc appeler `stage switch 2` et activer la deuxieme stage, celle dont l'id interne est `3`.

Cas d'usage :

- isoler une stage `Focus`, une stage `Comms`, une stage `Docs`;
- masquer rapidement un contexte sans fermer les apps;
- ramener une fenetre precise dans la stage active avec `stage summon`.

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
```

Cas d'usage :

- revenir au dernier focus;
- forcer une restructuration locale du layout;
- placer la prochaine fenetre du cote voulu;
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

## Performance ressentie

Roadie mesure les interactions critiques pour expliquer les lenteurs ressenties sans lire les logs bruts.

```bash
./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie performance thresholds
./bin/roadie query performance
```

Les interactions suivies incluent les changements de stage, desktop, ecran, focus directionnel, AltTab vers une fenetre geree et actions du rail. Roadie conserve un historique local borne aux 100 dernieres interactions dans `~/.local/state/roadies/performance.json`.

Cas d'usage :

- comparer une baseline avant/apres optimisation;
- voir si une lenteur vient du masquage, de la restauration, du layout, du focus ou du travail secondaire;
- verifier que le rail et les diagnostics restent hors du chemin critique;
- detecter les interactions qui depassent les seuils de confort.

## Control Center

Le Control Center est la surface macOS de Roadie dans la barre de menus.
Il est desactive par defaut tant qu'on le durcit. Lance-le seulement quand tu veux tester explicitement l'UI de barre de menus.

```bash
./bin/roadie control status --json
./scripts/start --no-control-center
```

Le Control Center en barre de menu est actuellement desactive. La commande sous-jacente `roadie control status --json` reste disponible pour les scripts et le diagnostic.

## Securite et recuperation

Roadie conserve un snapshot de restauration pour remettre les fenetres gerees dans des frames visibles apres un arret normal ou via un crash watcher.

```bash
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --json
./bin/roadied crash-watcher --pid DAEMON_PID
```

Cas d'usage :

- recuperer les fenetres apres une session daemon interrompue;
- inspecter le dernier snapshot de securite avant de redemarrer Roadie;
- garder la restauration scriptable pour LaunchAgent ou les workflows manuels.

## Fenetres systeme transitoires

Roadie detecte les sheets, dialogues, popovers, menus et panneaux open/save macOS via les roles Accessibility.

```bash
./bin/roadie transient status --json
./bin/roadie query transient
```

Quand une fenetre transitoire est active, Roadie suspend les mutations de layout non essentielles et peut tenter une recuperation conservative si elle est hors ecran.

## Layout persistence v2 et ajustements de largeur

La persistance de layout v2 rapproche les fenetres avec une identite stable au lieu de dependre seulement des IDs volatils.

```bash
./bin/roadie state restore-v2 --dry-run --json
./bin/roadie state restore-v2 --json
./bin/roadie query identity_restore
```

Les presets et nudges de largeur ajustent les layouts compatibles `bsp` et `masterStack` tout en preservant l'intention utilisateur.

```bash
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67 --all
```
