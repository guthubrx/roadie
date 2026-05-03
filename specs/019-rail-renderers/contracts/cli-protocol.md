# Contract — CLI `roadie rail renderer(s)`

**Modules**: `Sources/roadie/main.swift` (CLI client) + `Sources/roadied/CommandRouter.swift` (daemon handler)
**LOC budget combiné**: ≤ 100

## Sous-commandes

### `roadie rail renderers list`

Liste les renderers compilés dans le rail.

**Exit codes** : 0 si OK, 3 si daemon down.

**Output stdout (texte par défaut)** :
```
* stacked-previews   Stacked previews   (default, current)
  icons-only         Icons only
  hero-preview       Hero preview
  mosaic             Mosaic
  parallax-45        Parallax 45°
```

Le `*` marque le renderer actuellement actif. Le suffixe `(default, current)` ou `(default)` ou `(current)` selon le statut.

**Output JSON (option `--json`)** :
```json
{
  "default": "stacked-previews",
  "current": "icons-only",
  "renderers": [
    {"id": "stacked-previews", "display_name": "Stacked previews"},
    {"id": "icons-only", "display_name": "Icons only"}
  ]
}
```

### `roadie rail renderer <id>`

Sélectionne le renderer actif. Modifie la clé TOML `[fx.rail].renderer` et déclenche un `daemon reload` qui propage au rail.

**Arguments** :
- `<id>` (positionnel obligatoire) : identifiant du renderer (ex: `stacked-previews`, `icons-only`).

**Exit codes** :
- 0 : succès, le rail a basculé sur le nouveau renderer.
- 2 : `<id>` absent ou invalide (charset).
- 3 : daemon down.
- 5 : `<id>` inconnu du registre.

**Output stdout (succès)** :
```
renderer: stacked-previews → icons-only
reloaded
```

**Output stderr (erreur)** :
```
roadie: error [unknown_renderer] renderer 'parallax-99' not found. Available: stacked-previews, icons-only
```

## Protocole socket daemon ↔ client

### Commande `rail.renderer.list`

Request (no args) :
```json
{"command": "rail.renderer.list"}
```

Response success :
```json
{
  "status": "ok",
  "payload": {
    "default": "stacked-previews",
    "current": "icons-only",
    "renderers": [
      {"id": "stacked-previews", "display_name": "Stacked previews"},
      {"id": "icons-only", "display_name": "Icons only"}
    ]
  }
}
```

Note : le daemon connaît le `default` (constante du registry) et le `current` (lecture TOML). Le rail process est consulté indirectement via TOML pour rester découplé.

### Commande `rail.renderer.set`

Request :
```json
{"command": "rail.renderer.set", "args": {"id": "icons-only"}}
```

Response success :
```json
{
  "status": "ok",
  "payload": {"previous": "stacked-previews", "current": "icons-only"}
}
```

Response error (id inconnu) :
```json
{
  "status": "error",
  "error_code": "unknown_renderer",
  "message": "renderer 'parallax-99' not found",
  "payload": {"available": ["stacked-previews", "icons-only"]}
}
```

**Effets** :
1. Le daemon écrit `renderer = "<id>"` dans `[fx.rail]` du TOML utilisateur (création de la section et de la clé si absentes, préservation du reste).
2. Le daemon publie un event `config_reloaded` sur le bus.
3. Le rail consomme cet event, relit le TOML, instancie le nouveau renderer via `StageRendererRegistry.makeOrFallback(...)`, redessine ses cellules.

### Event `config_reloaded` (NEW)

Publié par le daemon après `daemon.reload` ou après un `rail.renderer.set` réussi.

Payload :
```json
{"name": "config_reloaded", "ts": "2026-05-03T10:00:00Z", "payload": {}}
```

Pas de champs additionnels — c'est un signal d'invalidation. Les consommateurs (rail, FX modules) re-lisent eux-mêmes le TOML.

## Tests acceptance bash

`tests/19-rail-renderer-cli.sh` :

```bash
#!/bin/bash
set -euo pipefail

# Précondition : daemon démarré, rail démarré

# T1 : list contient au moins le défaut
./build/debug/roadie rail renderers list | grep -q "stacked-previews"

# T2 : set vers icons-only réussit (US2 livré)
./build/debug/roadie rail renderer icons-only

# T3 : list montre maintenant icons-only comme current
./build/debug/roadie rail renderers list --json | jq -e '.current == "icons-only"'

# T4 : set vers id inconnu retourne exit 5
if ./build/debug/roadie rail renderer parallax-99; then
    echo "FAIL: should have exited 5"; exit 1
fi
[[ $? -eq 5 ]]

# T5 : set vers défaut explicit
./build/debug/roadie rail renderer stacked-previews

# T6 : config TOML mise à jour
grep 'renderer = "stacked-previews"' ~/.config/roadies/roadies.toml

echo "OK"
```
