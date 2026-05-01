# CLI ↔ Daemon Protocol

**Feature** : 002-tiler-stage | **Phase** : 1 | **Date** : 2026-05-01

---

## Transport

- Unix domain socket `~/.roadies/daemon.sock`
- Mode `0600` (lecture/écriture utilisateur uniquement)
- Encoding : **JSON-lines** (un message JSON par ligne, terminé par `\n`)
- Protocole simple : 1 requête → 1 réponse → fermeture connexion (pas de session persistante)
- Header de version dans chaque requête : `"version": "roadie/1"`

## Format requête

```json
{
  "version": "roadie/1",
  "command": "<command_type>",
  "args": { ... }
}
```

## Format réponse

```json
{
  "version": "roadie/1",
  "status": "success" | "error",
  "payload": { ... }   // si success
  "error_code": "...",  // si error
  "error_message": "..."  // si error
}
```

## Codes d'erreur

| Code | Signification | Exit CLI |
|---|---|---|
| `daemon_not_running` | Daemon absent (CLI ne se connecte pas) | 2 |
| `invalid_argument` | Argument mal formé | 64 |
| `unknown_stage` | Le stage demandé n'existe pas | 1 |
| `stage_manager_disabled` | Plugin désactivé dans config | 1 |
| `window_not_found` | Cible CGWindowID inexistante | 1 |
| `accessibility_denied` | Daemon n'a pas la permission | 2 |
| `internal_error` | Bug daemon, voir logs | 1 |

---

## Commandes

### `windows.list`

```json
{ "version": "roadie/1", "command": "windows.list", "args": {} }
```

Réponse :
```json
{
  "version": "roadie/1",
  "status": "success",
  "payload": {
    "windows": [
      { "id": 12345, "pid": 1234, "bundle": "com.apple.Terminal", "title": "~/code", 
        "frame": [22, 10, 800, 600], "subrole": "standard", "is_tiled": true,
        "stage": "dev", "is_focused": true }
    ]
  }
}
```

### `daemon.status`

```json
{ "command": "daemon.status", "args": {} }
```

Réponse :
```json
{
  "status": "success",
  "payload": {
    "version": "0.1.0",
    "uptime_seconds": 3600,
    "tiled_windows": 5,
    "tiler_strategy": "bsp",
    "stage_manager_enabled": true,
    "current_stage": "dev"
  }
}
```

### `daemon.reload`

Recharge la config TOML sans redémarrer.

```json
{ "command": "daemon.reload", "args": {} }
```

Réponse : success vide ou error si TOML invalide.

### `focus`

```json
{ "command": "focus", "args": { "direction": "left" | "right" | "up" | "down" } }
```

Logique : depuis la fenêtre focalisée actuelle, trouve le voisin dans la direction donnée selon l'arbre tiling et lui donne le focus AX.

### `move`

```json
{ "command": "move", "args": { "direction": "left" | "right" | "up" | "down" } }
```

Déplace la fenêtre focalisée dans l'arbre (peut traverser plusieurs niveaux de containers, similaire à `move-node` AeroSpace).

### `resize`

```json
{ "command": "resize", "args": { "direction": "left", "delta": 50 } }
```

Ajuste les `adaptiveWeight` des frères pour grandir/rétrécir dans la direction donnée. Delta en pixels.

### `tiler.set`

```json
{ "command": "tiler.set", "args": { "strategy": "bsp" | "masterStack" } }
```

Change la stratégie du workspace courant. Recalcule immédiatement les frames.

### `stage.list`

```json
{ "command": "stage.list", "args": {} }
```

Réponse :
```json
{
  "status": "success",
  "payload": {
    "current": "dev",
    "stages": [
      { "id": "dev", "display_name": "Development", "window_count": 4 },
      { "id": "comm", "display_name": "Communication", "window_count": 2 }
    ]
  }
}
```

### `stage.switch`

```json
{ "command": "stage.switch", "args": { "stage_id": "comm" } }
```

Bascule l'écran sur le stage cible. Erreur `unknown_stage` si inexistant. Erreur `stage_manager_disabled` si plugin off.

### `stage.assign`

```json
{ "command": "stage.assign", "args": { "stage_id": "dev" } }
```

Assigne la fenêtre frontmost (récupérée via `NSWorkspace.frontmostApplication` + `kAXFocusedWindowAttribute`) au stage.

### `stage.create`

```json
{ "command": "stage.create", "args": { "stage_id": "creative", "display_name": "Creative" } }
```

Crée un nouveau stage vide. Erreur si déjà existant.

### `stage.delete`

```json
{ "command": "stage.delete", "args": { "stage_id": "creative" } }
```

Supprime le stage. Les fenêtres assignées redeviennent libres (assignées au stage par défaut ou unassigned).

---

## Exemples d'échanges complets

### Lister les fenêtres

```
$ echo '{"version":"roadie/1","command":"windows.list","args":{}}' | nc -U ~/.roadies/daemon.sock
{"version":"roadie/1","status":"success","payload":{"windows":[...]}}
```

### Erreur quand daemon absent (côté CLI)

```
$ roadie focus left
roadie: daemon not running. Start with `roadied` or check `launchctl list com.local.roadies`.
$ echo $?
2
```

### Erreur stage manager désactivé

```
$ roadie stage dev
roadie: stage manager is disabled in config (~/.config/roadies/roadies.toml).
        Set `stage_manager.enabled = true` then `roadie daemon reload`.
$ echo $?
1
```

---

## Versioning

- `roadie/1` : version actuelle (V1).
- Le daemon refuse les requêtes avec version inconnue (`error_code: invalid_argument`).
- Toute évolution non rétrocompatible incrémente la version (`roadie/2`).
- Le CLI envoie sa version, le daemon vérifie compatibilité.

## Sécurité

- Socket `0600` empêche les autres utilisateurs d'envoyer des commandes.
- Pas de network listener, jamais. Uniquement Unix socket local.
- Pas d'exécution de code arbitraire reçu (le daemon ne reçoit que des commandes typées avec un enum fini).

## Non-objectifs V1

- Streaming events (CLI `--subscribe`) → V2
- Compression / batch de commandes → pas nécessaire au scope V1
- Authentification → l'ownership user du socket suffit
