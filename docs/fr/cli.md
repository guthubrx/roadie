# Commandes CLI

Toutes les commandes ci-dessous peuvent etre appelees directement avec `./bin/roadie` ou via `./scripts/roadie`.

## Etat et diagnostic

```bash
./bin/roadie daemon health
./bin/roadie daemon heal
./bin/roadie state dump --json
./bin/roadie state audit
./bin/roadie state heal
./bin/roadie metrics --json
./bin/roadie doctor
./bin/roadie self-test
```

Utilisation typique :

- `daemon health` : verifier que le daemon et l'etat sont coherents.
- `state audit` : detecter doublons, references obsoletes ou scopes casses.
- `state heal` : reparer les incoherences conservatrices.
- `metrics --json` : alimenter un script ou un dashboard.

## Fenetres et focus

```bash
./bin/roadie windows list
./bin/roadie windows list --json
./bin/roadie focus left|right|up|down
./bin/roadie focus back-and-forth
./bin/roadie move left|right|up|down
./bin/roadie warp left|right|up|down
./bin/roadie resize left|right|up|down
./bin/roadie window display 2
./bin/roadie window desktop 2 --follow
./bin/roadie window reset
```

Cas d'usage :

- naviguer au clavier entre les fenetres tilees;
- revenir au dernier focus avec `focus back-and-forth`;
- envoyer une fenetre vers un autre ecran ou desktop Roadie;
- reset une fenetre recalcitrante avant de relancer le layout.

## Layout

```bash
./bin/roadie mode bsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie layout plan --json
./bin/roadie layout apply --yes
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout join-with left|right|up|down
./bin/roadie layout insert left|right|up|down
./bin/roadie layout flatten
./bin/roadie layout zoom-parent
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67 --all
./bin/roadie balance
```

Cas d'usage :

- inspecter le plan avant application avec `layout plan`;
- persister une intention manuelle avec `insert` ou `zoom-parent`;
- revenir a un layout lineaire avec `flatten`.
- ajuster la largeur de la fenetre active ou de toutes les fenetres tilees avec `layout width`.

## Commandes de securite

```bash
./bin/roadie control status --json
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --json
./bin/roadie transient status --json
./bin/roadie state identity inspect --json
./bin/roadie state restore-v2 --dry-run --json
./bin/roadie state restore-v2 --json
```

Utilisation typique :

- `config reload` : valide et applique le TOML atomiquement, en gardant l'ancienne config en cas d'erreur.
- `restore snapshot` : ecrit un snapshot de securite des fenetres gerees.
- `restore apply` : restaure les frames visibles depuis le dernier snapshot.
- `transient status` : indique si une sheet/dialogue/open-save panel suspend le layout.
- `state restore-v2 --dry-run` : inspecte les matches d'identite stable avant application.

## Ecrans, desktops et stages

```bash
./bin/roadie display list
./bin/roadie display current
./bin/roadie display focus 2

./bin/roadie desktop list
./bin/roadie desktop current
./bin/roadie desktop focus 2
./bin/roadie desktop prev
./bin/roadie desktop next
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork

./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage prev
./bin/roadie stage next
```

`stage switch N` utilise la position visible dans `stage list`, pas l'id interne. Si les stages sont `1`, `3`, `4`, alors `stage switch 2` active la stage d'id `3`. Utilise `stage switch-id ID` seulement quand tu veux cibler l'id interne.

## Rules

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

## Groupes de fenetres

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

## Evenements et queries

```bash
./bin/roadie events tail 50
./bin/roadie events subscribe --from-now --initial-state
./bin/roadie events subscribe --from-now --type window.focused --scope window

./bin/roadie query state
./bin/roadie query windows
./bin/roadie query displays
./bin/roadie query desktops
./bin/roadie query stages
./bin/roadie query groups
./bin/roadie query rules
./bin/roadie query health
./bin/roadie query events
./bin/roadie query config_reload
./bin/roadie query restore
./bin/roadie query transient
./bin/roadie query identity_restore
```

Chaque `query` retourne un JSON stable :

```json
{
  "kind": "windows",
  "data": []
}
```
