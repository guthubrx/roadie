# Contract — `roadie rail status` & `roadie rail toggle`

**Status**: Draft
**Spec**: SPEC-014 stage-rail
**Type**: Nouvelles commandes CLI (helper debug / scripting)

## `roadie rail status`

### Synopsis

```
roadie rail status
```

Retourne l'état du binaire `roadie-rail` (s'il tourne ou pas) et un résumé de ses panels visibles.

### Réponse

```json
{
  "status": "ok",
  "data": {
    "running": true,
    "pid": 12345,
    "since": "2026-05-02T16:00:00Z",
    "panels_open": 2,
    "screens_visible": ["DUUID-37D8...", "DUUID-9F22..."],
    "current_desktop_id": 3,
    "stages_displayed": 4
  }
}
```

Si `roadie-rail` n'est pas lancé :

```json
{
  "status": "ok",
  "data": {
    "running": false,
    "pid": null,
    "panels_open": 0,
    "stages_displayed": 0
  }
}
```

### Logique

Le daemon lit `~/.roadies/rail.pid`. Si présent et PID vivant (`kill(pid, 0)`), `running = true` + détails. Sinon, `running = false`.

Les `panels_open` et `stages_displayed` sont remontés par le rail au daemon via un keep-alive périodique (toutes les 5 s). Si le rail est déconnecté du daemon depuis > 10 s, les détails sont marqués `null`.

## `roadie rail toggle`

### Synopsis

```
roadie rail toggle
```

Si `roadie-rail` ne tourne pas → le lance (en background, détaché). S'il tourne → lui envoie SIGTERM pour qu'il s'arrête proprement.

### Réponse

```json
{"status": "ok", "data": {"action": "started", "pid": 23456}}
```

ou

```json
{"status": "ok", "data": {"action": "stopped", "killed_pid": 12345}}
```

### Side-effects

- Démarrage : `nohup roadie-rail >/dev/null 2>&1 &` lancé depuis le daemon (chemin `~/.local/bin/roadie-rail` par défaut, configurable via `[fx.rail] binary_path`).
- Arrêt : `kill -TERM <pid>`.

### Use case

Permet d'inclure le rail dans des raccourcis BTT, scripts d'onboarding, ou un toggle clavier custom :

```bash
# BTT shortcut: cmd+shift+r → roadie rail toggle
roadie rail toggle
```

## Test acceptance (bash)

`tests/14-rail-toggle-cycle.sh` :
1. `roadie rail status` → `running: false`.
2. `roadie rail toggle` → `action: started`.
3. Sleep 1s. `roadie rail status` → `running: true, pid > 0`.
4. `roadie rail toggle` → `action: stopped`.
5. Sleep 0.5s. `roadie rail status` → `running: false`.
