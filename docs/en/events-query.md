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

Manual restore:

- `restore.snapshot_written`
- `restore.apply_started`
- `restore.apply_completed`
- `restore.apply_failed`

Read-only performance:

- `performance.summary_requested`
- `performance.recent_requested`
- `performance.thresholds_requested`

Administration:

- `config.reloaded`
- `config.reload_failed`
- `layout.width_adjust_requested`
- `layout.width_adjust_applied`
- `layout.width_adjust_rejected`

The public catalog is also available through the CLI:

```bash
./bin/roadie query event_catalog
```

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
./bin/roadie query event_catalog
./bin/roadie query performance
./bin/roadie query restore
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
- `query event_catalog`: list public event types.
- `query performance`: read a read-only summary built from `events.jsonl`.
- `query restore`: inspect the last manual restore snapshot.

## SketchyBar Or Script Example

```bash
./bin/roadie events subscribe --from-now --type window.focused |
while read -r line; do
  app=$(printf '%s' "$line" | jq -r '.payload.app // "-"')
  echo "Focused app: $app"
done
```
