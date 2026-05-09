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
