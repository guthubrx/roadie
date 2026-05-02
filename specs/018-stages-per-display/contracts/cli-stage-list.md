# Contract — `roadie stage list` (V2 scope)

**Status**: Draft
**Spec**: SPEC-018 stages-per-display
**Type**: Extension d'une commande IPC existante (SPEC-002)

## Synopsis

```
roadie stage list [--display <selector>] [--desktop <id>] [--json]
```

Retourne la liste des stages **du scope courant** (mode `per_display`) ou la liste flat (mode `global`).

## Arguments

| Arg | Type | Description |
|---|---|---|
| `--display <selector>` (optionnel) | String | Index 1-N (ordre `roadie display list`) ou UUID natif. Override la résolution implicite (curseur). |
| `--desktop <id>` (optionnel) | Int | ID desktop 1-N (range défini par `[desktops] count`). Override la résolution implicite (current desktop du display ciblé). |
| `--json` (optionnel) | Flag | Force la sortie JSON brute |

Si aucun override n'est passé, le scope est résolu côté daemon dans cet ordre :
1. Position du curseur (`NSEvent.mouseLocation`)
2. Frontmost window
3. Primary display + desktop default = 1

## Pré-conditions

- Daemon `roadied` démarré (SPEC-002)
- En mode `per_display` : SPEC-013 multi-desktop activé (`[desktops] enabled = true`)
- En mode `global` : aucune pré-condition supplémentaire

## Réponse

### Mode `per_display`

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "current": "1",
    "mode": "per_display",
    "scope": {
      "display_uuid": "37D8832A-2D66-4A47-9B5E-39DA5CF2D85F",
      "display_index": 1,
      "desktop_id": 1,
      "inferred_from": "cursor"
    },
    "stages": [
      {
        "id": "1",
        "display_name": "Default",
        "is_active": true,
        "window_ids": [12345, 67890],
        "window_count": 2
      },
      {
        "id": "2",
        "display_name": "Code",
        "is_active": false,
        "window_ids": [11111],
        "window_count": 1
      }
    ]
  }
}
```

### Mode `global`

```json
{
  "status": "success",
  "version": "roadie/1",
  "payload": {
    "current": "1",
    "mode": "global",
    "scope": null,
    "stages": [
      {"id": "1", "display_name": "Default", "is_active": true, ...},
      {"id": "2", "display_name": "Code", "is_active": false, ...}
    ]
  }
}
```

### Erreurs

#### `unknown_display` (override `--display` invalide)

```json
{
  "status": "error",
  "error_code": "unknown_display",
  "error_message": "no display matching selector \"42\" or UUID"
}
```

#### `desktop_out_of_range` (override `--desktop` hors range)

```json
{
  "status": "error",
  "error_code": "desktop_out_of_range",
  "error_message": "desktop 42 not in range 1..N"
}
```

#### `multi_desktop_disabled` (déjà SPEC-011, en mode per_display)

```json
{
  "status": "error",
  "error_code": "multi_desktop_disabled",
  "error_message": "multi_desktop disabled, set [desktops] enabled = true in roadies.toml"
}
```

## Garanties

- **Latence** : < 5 ms p95 (résolution scope + lookup hash O(1))
- **Idempotence** : N appels successifs identiques retournent le même résultat tant que le scope ne change pas
- **Cohérence** : la réponse reflète l'état du daemon à l'instant T (pas de cache stale)

## CLI examples

```bash
# Stages du scope courant (curseur ou frontmost)
roadie stage list

# Stages explicites du display 2 desktop 1
roadie stage list --display 2 --desktop 1

# Par UUID (utile pour scripts qui veulent stabilité cross-reboot)
roadie stage list --display 9F22B3D1-8A4E-4B3D-A1F0-2E7C5D9B8A6F --desktop 1

# JSON brut pour parsing
roadie stage list --json | jq '.payload.stages[].display_name'

# Comparaison cross-display avec un script
for d in 1 2; do
  echo "Display $d:"
  roadie stage list --display $d --desktop 1
done
```

## Test acceptance (bash)

`tests/18-stage-list-scope.sh` :
1. Mode `per_display` activé
2. Position curseur sur Display 1, créer "Stage 2" via assign
3. `roadie stage list` curseur sur D1 → contient "Stage 2"
4. Bouger souris sur Display 2 → `roadie stage list` ne contient PAS "Stage 2"
5. `roadie stage list --display 1 --desktop 1` → contient "Stage 2" (override)
6. `roadie stage list --display 99 --desktop 1` → erreur `unknown_display`
