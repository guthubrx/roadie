# Use Cases

## 1. Daily Development Workstation

Goal: keep code, terminals, and documentation organized without moving windows by mouse.

Suggested setup:

- Desktop `1`: development.
- Stage `dev`: editor + main terminal.
- Stage `docs`: browser/documentation.
- Stage `comms`: messaging.

Commands:

```bash
./bin/roadie desktop label 1 Dev
./bin/roadie stage rename 1 Dev
./bin/roadie stage create docs
./bin/roadie stage create comms
./bin/roadie mode masterStack
```

Typical rule:

```toml
[[rules]]
id = "docs-browser"
priority = 10

[rules.match]
app_regex = "Safari|Firefox|Chrome"
title_regex = "Docs|Documentation|README"

[rules.action]
assign_stage = "docs"
scratchpad = "research"
emit_event = true
```

## 2. Multi-Display Operations

Goal: keep the main display for active work and move a full stage to a secondary display.

```bash
./bin/roadie display list
./bin/roadie stage move-to-display 2
./bin/roadie desktop summon 2
```

Concrete scenario:

- display 1: active incident;
- display 2: logs, dashboards, documentation;
- `stage move-to-display` moves the context without recreating windows.

## 3. Research/Documentation Workflow

Goal: group several documentation windows and expose them through queries.

```bash
./bin/roadie windows list
./bin/roadie group create research 12345 67890
./bin/roadie group focus research 67890
./bin/roadie query groups
```

Possible integration:

```bash
./bin/roadie query groups | jq '.data'
```

## 4. Local Status Bar

Goal: display the active window, stage, and important events.

```bash
./bin/roadie events subscribe --from-now --initial-state --scope window --scope stage
```

The consumer should:

- ignore unknown fields;
- use `type`, `scope`, `subject`, and `payload`;
- tolerate new event types.

## 5. Validate Before Changing Config

Goal: avoid a broken TOML rule disrupting the session.

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

Recommended workflow:

1. edit `roadies.toml`;
2. run `rules validate`;
3. test a representative window with `rules explain`;
4. restart Roadie if needed.

## 6. Recover From State Inconsistency

Goal: repair local state without deleting all configuration.

```bash
./bin/roadie state audit
./bin/roadie state heal
./bin/roadie daemon heal
./bin/roadie daemon health
```

Use this sequence after:

- display disconnect/reconnect;
- abrupt app shutdown;
- branch switch or rebuild.

## 7. Before A Risky Operation

Goal: keep an explicit fallback and inspect the same snapshot used by the crash watcher.

```bash
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status
```

If frames must be restored explicitly:

```bash
./bin/roadie restore apply --yes
```

This restore matches windows by current window ID. The crash watcher uses the same mechanism only when the daemon disappears without a clean exit; it does not run in the focus/border path.

## 8. Reasonable Local Administration

Goal: avoid accumulating logs and backups.

```bash
./bin/roadie cleanup --dry-run
./bin/roadie cleanup --apply
```

Start with `--dry-run` to inspect candidate files before deletion or rotation.
