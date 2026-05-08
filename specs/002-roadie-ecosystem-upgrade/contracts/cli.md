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

**Compatibility**:

- Les commandes existantes `roadie state`, `roadie tree`, `roadie windows list --json` restent disponibles.
- Les nouvelles commandes retournent toujours JSON avec `{ "kind": "...", "data": ... }`.
- Les commandes existantes restent disponibles pour compatibilité opérateur.

## Rules

```bash
roadie rules validate [--config PATH] [--json]
roadie rules list [--json]
roadie rules explain --app APP [--title TITLE] [--role ROLE] [--stage STAGE] [--json]
```

**Acceptance**:

- `validate` retourne non-zéro si une règle est invalide.
- `explain` montre les règles matchées, ignorées et les raisons.

## Tree Commands

```bash
roadie layout split horizontal|vertical
roadie layout join-with left|right|up|down
roadie layout flatten
roadie layout insert left|right|up|down
roadie layout zoom-parent
roadie focus back-and-forth
roadie desktop back-and-forth
roadie desktop summon DESKTOP_ID
roadie stage summon WINDOW_ID
roadie stage move-to-display DISPLAY_INDEX
```

**Acceptance**:

- chaque commande publie `command.received` puis `command.applied` ou `command.failed`.
- les erreurs utilisateur sont lisibles en texte et disponibles en JSON si demandé.
- les commandes stage échouent sans effet si le stage ou l'écran cible n'existe plus.

## Groups

```bash
roadie group create GROUP_ID [WINDOW_ID ...]
roadie group add GROUP_ID WINDOW_ID
roadie group remove GROUP_ID WINDOW_ID
roadie group focus GROUP_ID WINDOW_ID
roadie group dissolve GROUP_ID
roadie group list
```

**Acceptance**:

- un groupe est persisté dans l'état de stage et exposé aux snapshots/query.
- le membre actif est suivi dans l'état du groupe.
- les changements publient `window.grouped`, `window.ungrouped` ou `group.*` si ajouté au catalogue.
