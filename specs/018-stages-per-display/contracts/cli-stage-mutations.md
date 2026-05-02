# Contract — `roadie stage` mutations (V2 scope)

**Status**: Draft
**Spec**: SPEC-018 stages-per-display
**Type**: Extension de commandes IPC existantes (SPEC-002, SPEC-014)

## Commandes couvertes

- `roadie stage <id>` (= `stage.switch`)
- `roadie stage assign <id> [wid]` (= `stage.assign`)
- `roadie stage create <id> <name>` (= `stage.create`)
- `roadie stage delete <id>` (= `stage.delete`)
- `roadie stage rename <id> <new_name>` (= `stage.rename`)

Toutes ces commandes sont scopées au tuple `(displayUUID, desktopID)` résolu :
1. Implicitement : curseur → frontmost → primary
2. Explicitement via `--display <selector> --desktop <id>` (override)

## Synopsis

```
roadie stage <stage_id>                            [--display <s>] [--desktop <id>]
roadie stage assign <stage_id> [<wid>]             [--display <s>] [--desktop <id>]
roadie stage create <stage_id> <display_name>      [--display <s>] [--desktop <id>]
roadie stage delete <stage_id>                     [--display <s>] [--desktop <id>]
roadie stage rename <stage_id> <new_name>          [--display <s>] [--desktop <id>]
```

## Comportement scopage

- **Mode `per_display`** : la commande s'applique uniquement au scope `(display, desktop)` résolu. Une stage `2` créée dans `(D1, 1)` n'existe pas pour `(D2, 1)`.
- **Mode `global`** : les overrides `--display`/`--desktop` sont silencieusement ignorés (warning log côté daemon, succès renvoyé). Le scope sentinelle `(emptyUUID, 0)` est utilisé.

## Réponses

### `stage.assign` succès

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "stage_id": "2",
    "wid": 12345,
    "scope": {
      "display_uuid": "37D8832A-...",
      "display_index": 1,
      "desktop_id": 1,
      "inferred_from": "cursor"
    },
    "created": true
  }
}
```

`created = true` si lazy-créé pendant cet appel, `false` si la stage existait déjà.

### `stage.create` succès

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "stage_id": "5",
    "display_name": "Code",
    "scope": {"display_uuid": "...", "desktop_id": 1, "inferred_from": "cursor"}
  }
}
```

### `stage.create` erreur (existe déjà dans ce scope)

```json
{
  "status": "error",
  "error_code": "stage_exists",
  "error_message": "stage 5 already exists in (Display 1, Desktop 1)"
}
```

### `stage.switch` succès

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "current": "2",
    "previous": "1",
    "scope": {"display_uuid": "...", "desktop_id": 1, "inferred_from": "cursor"}
  }
}
```

### `stage.delete` immortel stage 1

```json
{
  "status": "error",
  "error_code": "invalid_argument",
  "error_message": "cannot delete default stage 1 (immortal in scope)"
}
```

Comme V1 SPEC-002, la stage `1` est immortelle dans CHAQUE scope.

### `stage.rename` succès

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "stage_id": "2",
    "old_name": "Default",
    "new_name": "Code",
    "scope": {"display_uuid": "...", "desktop_id": 1, "inferred_from": "cursor"}
  }
}
```

## Garanties

- **Atomicité** : succès ou échec, jamais d'état partiel
- **Latence** : < 50 ms p95 (incluant écriture TOML disque)
- **Émission event** : chaque mutation déclenche son event correspondant (`stage_created`, `stage_renamed`, `stage_deleted`, `stage_changed`) avec `display_uuid` et `desktop_id` dans le payload (cf `events-stream-stages.md`)

## CLI examples

```bash
# Switch sur stage 2 du scope courant
roadie stage 2

# Assign frontmost à stage 3 sur Display 1 explicite
roadie stage assign 3 --display 1 --desktop 1

# Créer une stage "Comm" sur le scope du curseur
roadie stage create 4 "Comm"

# Renommer stage 2 du scope explicite
roadie stage rename 2 "Code" --display 1 --desktop 1

# Delete stage 5 du scope courant (skip si stage 1)
roadie stage delete 5
```

## Test acceptance (bash)

`tests/18-stage-mutations-scope.sh` :
1. Mode `per_display`, 2 écrans, curseur sur D1
2. `roadie stage create 7 "Test"` → créée dans `(D1, 1, 7)`
3. Bouger souris sur D2, `roadie stage list` → ne contient pas "Test"
4. `roadie stage rename 7 "Renamed" --display 1 --desktop 1` → success, le rename s'applique au tuple D1
5. Bouger souris sur D1, `roadie stage list` → "Renamed" visible
6. `roadie stage delete 7 --display 1 --desktop 1` → success
7. `roadie stage delete 1` → erreur `invalid_argument` (stage 1 immortel)
