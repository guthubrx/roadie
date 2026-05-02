# Contract — CLI & IPC `signals` (US3 / FR-A2-*)

**Status**: Done
**Last updated**: 2026-05-02

## 1. Format TOML `[[signals]]`

```toml
[[signals]]
event = "string"           # parmi la liste fermée (cf. §2)
action = "string"          # commande shell brute, exécutée via /bin/sh -c

# Filtres optionnels
app = "string"             # exact ou regex sur bundleID/localizedName
title = "string"           # regex sur title (window events seulement)
```

### Section globale `[signals]` (≠ `[[signals]]`)

```toml
[signals]
timeout_ms = 5000          # default — timeout par action
queue_cap = 1000           # default — drop FIFO si saturé
```

### Exemples

```toml
# Log chaque fenêtre focused
[[signals]]
event = "window_focused"
action = "echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log"

# Notifier quand Slack se lance
[[signals]]
event = "application_launched"
app = "Slack"
action = "osascript -e 'display notification \"Slack started\" with title \"roadie\"'"

# Backup state à chaque change de desktop
[[signals]]
event = "space_changed"
action = "/Users/me/.scripts/backup-roadie-state.sh"

# Auto-tile une nouvelle fenêtre Terminal
[[signals]]
event = "window_created"
app = "com.apple.Terminal"
action = "roadie window swap left"

# Trigger script custom à un drop drag-drop sur autre display
[[signals]]
event = "mouse_dropped"
action = "/Users/me/.scripts/on-drop.sh"
```

## 2. Events supportés

Liste **fermée** (validation au parsing). Tout autre `event` → rule skip + log warn.

### Window events

| Event | Quand | Env vars (fournies en plus de `ROADIE_INSIDE_SIGNAL=1`) |
|---|---|---|
| `window_created` | Fenêtre détectée par `WindowRegistry` | `ROADIE_WINDOW_ID`, `ROADIE_WINDOW_PID`, `ROADIE_WINDOW_BUNDLE`, `ROADIE_WINDOW_TITLE`, `ROADIE_WINDOW_FRAME` |
| `window_destroyed` | Fenêtre fermée ou disparue | idem (snapshot dernier état connu) |
| `window_focused` | Focus change | idem |
| `window_moved` | Position change ≥ 1 px | idem |
| `window_resized` | Taille change ≥ 1 px | idem |
| `window_title_changed` | Title change | idem + `ROADIE_WINDOW_TITLE_OLD` |

### Application events

| Event | Quand | Env vars |
|---|---|---|
| `application_launched` | App nouvelle dans `NSWorkspace` | `ROADIE_APP_BUNDLE`, `ROADIE_APP_PID`, `ROADIE_APP_NAME` |
| `application_terminated` | App quittée | idem |
| `application_front_switched` | App frontmost change | idem |
| `application_visible` | App devient visible (unhidden) | idem |
| `application_hidden` | App hidden (`Cmd+H`) | idem |

### Space (desktop virtuel) events

| Event | Quand | Env vars |
|---|---|---|
| `space_changed` | `desktop focus N` | `ROADIE_SPACE_FROM`, `ROADIE_SPACE_TO`, `ROADIE_SPACE_LABEL?` |
| `space_created` | `desktop create N` (futur, hors SPEC-016) | `ROADIE_SPACE_ID`, `ROADIE_SPACE_LABEL?` |
| `space_destroyed` | idem | idem |

### Display events

| Event | Quand | Env vars |
|---|---|---|
| `display_added` | Hot-plug d'un nouvel écran | `ROADIE_DISPLAY_ID`, `ROADIE_DISPLAY_UUID`, `ROADIE_DISPLAY_NAME?`, `ROADIE_DISPLAY_FRAME` |
| `display_removed` | Débranchement | idem (dernier état) |
| `display_changed` | Résolution / DPI change | idem |

### Mouse events

| Event | Quand | Env vars |
|---|---|---|
| `mouse_dropped` | Fin de drag SPEC-015 (drop sur autre fenêtre/display) | `ROADIE_DROP_X`, `ROADIE_DROP_Y`, `ROADIE_DROP_DISPLAY`, `ROADIE_DROP_FRAME` (frame source post-drop) |

### Stage events (spécifique roadie)

| Event | Quand | Env vars |
|---|---|---|
| `stage_switched` | `stage <id>` | `ROADIE_STAGE_FROM`, `ROADIE_STAGE_TO`, `ROADIE_STAGE_NAME?` |
| `stage_created` | `stage create` | `ROADIE_STAGE_ID`, `ROADIE_STAGE_NAME?` |
| `stage_destroyed` | `stage delete` | idem |

## 3. Sémantique exec

### Pipeline

1. EventBus publie un `DesktopEvent`.
2. `SignalDispatcher` reçoit (subscribe AsyncStream).
3. Si `event.payload["_inside_signal"] == "1"` → **skip silencieux** (re-entrancy guard).
4. Enqueue. Si queue saturée (≥ `queue_cap`) → drop oldest + log warn.
5. Worker async pop → match contre tous les `SignalDef` chargés (event name + filters app/title).
6. Pour chaque match : exec async via `/bin/sh -c <action>`.

### Environment des actions

L'action shell hérite de l'env du daemon (`PATH`, `HOME`, `USER`, etc.) **+** :

- `ROADIE_INSIDE_SIGNAL=1` (re-entrancy marker, toujours présent)
- `ROADIE_EVENT=<event_name>` (toujours)
- `ROADIE_TS=<ISO8601>` (timestamp event)
- env vars contextuelles selon table §2

**Variables shell** (notation `$ROADIE_XYZ`) expandées par `/bin/sh -c` standard.

### Timeout

- Default : 5 s (configurable `[signals] timeout_ms`).
- À l'expiration : `SIGTERM` au process. Si toujours running après +1 s → `SIGKILL`.
- Log warn avec stderr capturé (tronqué à 1 KB).
- `totalTimeouts` metric incrémenté.

### stdout/stderr

- Capturés en mémoire, cap 16 KB chacun.
- stdout : ignoré (pas loggé) sauf si exit code != 0.
- stderr : loggé en warn si exit code != 0 OU timeout, tronqué à 1 KB.

### Re-entrancy guard

Si l'action shell exécute `roadie window swap left`, le daemon reçoit la requête IPC avec un payload `_inside_signal: "1"` (propagé via env var → CLI → socket). Les events publiés pendant le traitement de cette requête sont flaggés `payload["_inside_signal"] = "1"` → SignalDispatcher skip.

→ **Aucune cascade infinie possible**.

## 4. CLI

### `roadie signals list`

Liste les signals chargés.

```bash
$ roadie signals list
INDEX  EVENT                   APP             ACTION (truncated)
0      window_focused          -               echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log
1      application_launched    Slack           osascript -e 'display notification "Slack started"...'
2      space_changed           -               /Users/me/.scripts/backup-roadie-state.sh
3      window_created          com.apple.Term  roadie window swap left
4      mouse_dropped           -               /Users/me/.scripts/on-drop.sh
```

Avec `--json` : structure complète (event, app, title, action full).

### Pas de `roadie signals add/remove` dynamique

Édition via TOML + `roadie daemon reload`.

## 5. IPC

### `signals.list`

**Requête** :
```json
{"cmd": "signals.list"}
```

**Réponse** :
```json
{
  "status": "ok",
  "data": {
    "signals": [
      {
        "index": 0,
        "event": "window_focused",
        "app": null,
        "title": null,
        "action": "echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log"
      }
    ],
    "rejected_at_parse": [],
    "metrics": {
      "queue_depth": 0,
      "dispatched_total": 1893,
      "dropped_total": 0,
      "timeouts_total": 2
    }
  }
}
```

## 6. Erreurs

| Code | Cas | Message |
|---|---|---|
| `signal_invalid_event` | Event hors liste fermée | `signal #N: event 'foo_bar' not in supported list (see contracts/cli-signals.md §2)` |
| `signal_empty_action` | `action = ""` | `signal #N: action cannot be empty` |
| `signal_invalid_filter` | Regex `app`/`title` cassé | `signal #N: regex invalid: <reason>` |
| `signal_queue_saturated` | (warn, pas error) | `signal queue saturated, dropping oldest event '<name>'` |
| `signal_action_timeout` | (warn, pas error) | `signal action timed out after Nms (event=<name>, signal=#N)` |

## 7. Sécurité & contre-patterns

### Ne **PAS** faire

```toml
# DANGEREUX — fork bomb potentielle
[[signals]]
event = "window_created"
action = "open -a Calculator"
# Calculator s'ouvre → window_created déclenché → ouvre Calculator → ...
# (mitigé par re-entrancy guard, mais user peut casser via nohup/setsid)

# DANGEREUX — long polling shell
[[signals]]
event = "window_focused"
action = "sleep 30 && do_something"
# 30s × N events = blocage virtuel (mitigé par timeout 5s, mais log spam)

# DANGEREUX — `nohup`/`setsid` qui contourne re-entrancy
[[signals]]
event = "window_created"
action = "nohup roadie window close > /dev/null 2>&1 &"
# Le child process ne propage pas ROADIE_INSIDE_SIGNAL → cascade possible
```

### À faire

- Actions courtes (< 100 ms) → log, notification, écriture fichier.
- Actions longues → écrire dans une queue/file, traiter par un cron/launchd séparé.
- Filtres précis (`app = "MyApp"`) plutôt que catch-all sur `event`.

## 8. Évolutions futures (hors scope V1)

- `[[signals]] enabled = false` pour désactiver
- `[[signals]] timeout_ms = N` per-signal override
- `[[signals]] one_shot = true` (désactive après 1 trigger)
- Filtres composés (`app_in = ["Slack", "Discord"]`)
- Action via `swift-script` au lieu de shell (V3 si demande forte)
