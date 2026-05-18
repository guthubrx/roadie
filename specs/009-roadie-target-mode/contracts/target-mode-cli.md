# Contract: Roadie Target Mode CLI

## Commandes

```bash
roadie targets list [--json] [--source roadie|app|all] [--filter TEXT] [--max N]
roadie targets pick QUERY_OR_LABEL [--action focus|switch|send-active|click|double-click|right-click] [--json]
roadie targets inspect TARGET_ID_OR_LABEL [--json]
roadie targets activate TARGET_ID_OR_LABEL [--action focus|switch|send-active|click|double-click|right-click] [--json]
roadie targets show [--json] [--source roadie|app|all] [--filter TEXT] [--labels-only]
roadie targets hide [--json]
roadie query targets
```

## JSON `targets list`

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-05-17T12:00:00Z",
  "query": {
    "source": "roadie",
    "filter": "work",
    "maxResults": 100,
    "appTargetsEnabled": false
  },
  "targets": [
    {
      "id": "stage:display-1/1/work",
      "label": "A",
      "kind": "stage",
      "title": "Work",
      "subtitle": "Desktop 1 - 2 fenêtres",
      "source": "roadie",
      "scope": {
        "displayId": "display-1",
        "desktopId": 1,
        "stageId": "work",
        "windowId": null
      },
      "frame": null,
      "isActive": true,
      "actions": ["switch", "send-active", "inspect"],
      "diagnostics": ["visible", "non_empty"]
    }
  ],
  "partial": false,
  "error": null
}
```

## JSON `targets inspect`

```json
{
  "schemaVersion": 1,
  "target": {
    "id": "window:123",
    "label": "B",
    "kind": "window",
    "title": "iTerm2",
    "source": "roadie"
  },
  "summary": "Fenêtre iTerm2 sur stage Work",
  "identity": {
    "app": "iTerm2",
    "bundleId": "com.googlecode.iterm2",
    "title": "Default",
    "windowId": 123
  },
  "state": {
    "tileable": true,
    "floating": false,
    "pinned": false,
    "focused": true,
    "activeStage": true
  },
  "reasons": ["AXStandardWindow", "scope=display/1/work"],
  "recentEvents": []
}
```

## JSON `targets pick`

```json
{
  "schemaVersion": 1,
  "query": "gray",
  "action": "focus",
  "selected": {
    "id": "window:123",
    "label": "A",
    "kind": "window",
    "title": "Grayjay"
  },
  "candidates": [],
  "result": {
    "changed": true,
    "message": "focused 123",
    "error": null
  },
  "error": null
}
```

Si la requête est ambiguë, `selected` et `result` sont nuls, `candidates`
contient les cibles possibles, et `error` vaut `ambiguous_target`.

## JSON `targets show`

```json
{
  "schemaVersion": 1,
  "visible": true,
  "labelsOnly": true,
  "generatedAt": "2026-05-17T12:00:00Z",
  "expiresAt": null,
  "report": {
    "schemaVersion": 1,
    "targets": []
  }
}
```

## Erreurs

- `unknown_target`: label ou ID introuvable.
- `ambiguous_target`: filtre ou label incomplet.
- `stale_target`: cible disparue entre liste et activation.
- `app_targets_disabled`: app targets demandés mais désactivés.
- `target_mode_disabled`: Target Mode désactivé par `[experimental.target_mode].enabled = false`.
- `target_picker_disabled`: picker désactivé par `[experimental.target_mode].picker_enabled = false`.
- `app_mouse_actions_disabled`: clic applicatif désactivé par `[experimental.target_mode].app_mouse_actions_enabled = false`.
- `accessibility_denied`: Accessibility non autorisé.
- `unsupported_action`: action non supportée pour ce type.
- `no_frame`: action souris demandée sur une cible sans frame.
- `target_grid_disabled`: grille désactivée par `[experimental.target_grid].enabled = false`.
- `unknown_grid_path`: chemin de grille invalide.
- `target_record_disabled`: record désactivé par `[experimental.target_record].enabled = false`.
- `target_replay_disabled`: replay désactivé par `[experimental.target_record].replay_enabled = false`.
- `event_tap_failed`: macOS refuse la capture d'événements.

## Configuration

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = false
overlay_labels_only = true
overlay_duration_seconds = 3
app_mouse_actions_enabled = false
scroll_mode_enabled = false

[experimental.app_targets]
enabled = false
scope = "frontmost_window"
max_targets = 150
timeout_ms = 120
hint_characters = "asdfghjkl"
include_roles = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow"]
ax_boost_enabled = false
max_depth = 12
additional_boost_bundle_ids = []

[experimental.target_grid]
enabled = false
overlay_enabled = true
rows = 3
columns = 3
max_depth = 3
hint_characters = "asdfghjkl"
action_delay_ms = 30

[experimental.target_record]
enabled = false
replay_enabled = false
directory = "~/.local/state/roadies/records"
default_duration_seconds = 10
max_duration_seconds = 120
max_events = 2000
include_mouse_moves = false
include_key_events = true
include_ax_context = true
record_text_input = false
```

`experimental.target_mode` contrôle la surface Target Mode. `experimental.app_targets`
contrôle uniquement la découverte AX profonde. Même si les app targets sont activés,
les clics applicatifs restent refusés tant que `app_mouse_actions_enabled` vaut `false`.

## Commandes grille

```bash
roadie grid show [PATH] [--display N] [--scope display|focused_window] [--json]
roadie grid show [PATH] --visual --scope display|focused_window --duration 3
roadie grid click A
roadie grid double-click A
roadie grid right-click A
roadie grid move A
roadie grid scroll-up A
roadie grid scroll-down A
roadie grid drag A L
```

`PATH` est un chemin récursif de labels. Sans `PATH`, `grid show` retourne le
premier niveau. Avec `PATH`, il retourne le niveau sous cette cellule.
`--scope display` utilise tout l'ecran cible; `--scope focused_window` utilise
la fenetre focussee comme racine recursive.

## Commandes record/replay

```bash
roadie record start demo --duration 10
roadie record list
roadie record inspect demo --json
roadie record replay demo
roadie record delete demo
```

Un recording contient des événements horodatés, les coordonnées, la cible
Roadie/AX la plus spécifique si disponible, et un chemin de grille de secours.

## Compatibilité agents

- Tous les champs nécessaires à l'action doivent être disponibles sans screenshot.
- Les labels sont valables pour le résultat courant mais l'ID reste la référence robuste.
- Les actions modifiant Roadie doivent retourner `changed`, `message` et `error`.
