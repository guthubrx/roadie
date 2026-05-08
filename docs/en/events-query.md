# Events And Query API

Roadie exposes two complementary surfaces:

- `events subscribe`: JSON Lines stream for changes.
- `query`: point-in-time reads of current state.

## Events

```bash
./bin/roadie events subscribe --from-now --initial-state
```

Example line:

```json
{
  "schemaVersion": 1,
  "id": "evt_001",
  "timestamp": "2026-05-08T14:07:01Z",
  "type": "window.focused",
  "scope": "window",
  "subject": { "kind": "window", "id": "12345" },
  "cause": "ax",
  "payload": {
    "windowID": "12345",
    "app": "Terminal"
  }
}
```

Options:

```bash
./bin/roadie events subscribe --from-now
./bin/roadie events subscribe --initial-state
./bin/roadie events subscribe --type window.focused
./bin/roadie events subscribe --scope rule
```

Semantics:

- without `--from-now`, Roadie replays the journal and then follows new lines;
- with `--from-now`, Roadie starts at the end of the current journal;
- with `--initial-state`, Roadie first emits `state.snapshot`;
- consumers must ignore unknown fields.

## Useful Catalog

Window:

- `window.created`
- `window.destroyed`
- `window.focused`
- `window.moved`
- `window.resized`
- `window.grouped`
- `window.ungrouped`

Layout:

- `layout.mode_changed`
- `layout.rebalanced`
- `layout.flattened`
- `layout.insert_target_changed`
- `layout.zoom_changed`

Rules:

- `rule.matched`
- `rule.applied`
- `rule.skipped`
- `rule.failed`

Commands:

- `command.received`
- `command.applied`
- `command.failed`

Control and safety:

- `config.reload_requested`
- `config.reload_applied`
- `config.reload_failed`
- `config.active_preserved`
- `restore.snapshot_written`
- `restore.crash_detected`
- `restore.crash_completed`
- `transient.detected`
- `transient.cleared`
- `transient.recovery_attempted`
- `layout_identity.restore_started`
- `layout_identity.restore_applied`
- `layout_identity.conflict_detected`
- `layout.width_adjust_requested`
- `layout.width_adjust_applied`
- `layout.width_adjust_rejected`

## Query API

```bash
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

Stable format:

```json
{
  "kind": "state",
  "data": {}
}
```

Use cases:

- `query windows`: display tileable windows in a status bar.
- `query groups`: display tabbed/stacked groups.
- `query rules`: verify what was loaded from TOML.
- `query health`: integrate Roadie into a local health check.
- `query events`: debug recent events without following the live stream.
- `query restore`: inspect the last restore safety snapshot.
- `query transient`: inspect active transient-window pause state.
- `query identity_restore`: inspect layout persistence v2 dry-run matches.

## SketchyBar Or Script Example

```bash
./bin/roadie events subscribe --from-now --type window.focused |
while read -r line; do
  app=$(printf '%s' "$line" | jq -r '.payload.app // "-"')
  echo "Focused app: $app"
done
```
