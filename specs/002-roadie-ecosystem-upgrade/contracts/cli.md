# CLI Contract

## Events

```bash
roadie events tail [--json]
roadie events subscribe [--from-now] [--initial-state] [--type TYPE] [--scope SCOPE]
```

**Acceptance**:

- `subscribe --from-now` ne rejoue pas les événements anciens.
- `subscribe --initial-state` émet d'abord `state.snapshot`, puis les événements live.
- le format par défaut de `subscribe` est JSON Lines stable.

## State Queries

```bash
roadie query state --json
roadie query windows --json [--display ID] [--desktop ID] [--stage ID]
roadie query displays --json
roadie query desktops --json [--display ID]
roadie query stages --json [--desktop ID]
roadie query groups --json [--stage ID]
roadie query rules --json
```

**Compatibility**:

- Les commandes existantes `roadie state`, `roadie tree`, `roadie windows list --json` restent disponibles.
- Les nouvelles commandes privilégient un schéma stable plutôt qu'un dump de debug.

## Rules

```bash
roadie rules validate [--config PATH] [--json]
roadie rules list [--json]
roadie rules explain --window WINDOW_ID [--json]
```

**Acceptance**:

- `validate` retourne non-zéro si une règle est invalide.
- `explain` montre les règles matchées, ignorées et les raisons.

## Tree Commands

```bash
roadie layout split horizontal|vertical|opposite
roadie layout join-with north|east|south|west
roadie layout flatten
roadie layout insert north|east|south|west|stack|auto
roadie layout zoom-parent toggle
roadie focus back-and-forth
roadie desktop back-and-forth
roadie desktop summon DESKTOP_ID
```

**Acceptance**:

- chaque commande publie `command.received` puis `command.applied` ou `command.failed`.
- les erreurs utilisateur sont lisibles en texte et disponibles en JSON si demandé.

## Groups

```bash
roadie group create [--window WINDOW_ID ...]
roadie group add WINDOW_ID
roadie group remove WINDOW_ID
roadie group focus next|prev|WINDOW_ID
roadie group dissolve GROUP_ID
roadie group list --json
```

**Acceptance**:

- un groupe occupe un seul slot de layout.
- le membre actif est celui qui reçoit le focus.
- les changements publient `window.grouped`, `window.ungrouped` ou `group.*` si ajouté au catalogue.
