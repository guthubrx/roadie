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
roadie desktop label 1 Dev
roadie stage rename 1 Dev
roadie stage create docs
roadie stage create comms
roadie mode masterStack
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
roadie display list
roadie stage move-to-display 2
roadie desktop summon 2
```

Concrete scenario:

- display 1: active incident;
- display 2: logs, dashboards, documentation;
- `stage move-to-display` moves the context without recreating windows.

## 3. Research/Documentation Workflow

Goal: group several documentation windows and expose them through queries.

```bash
roadie windows list
roadie group create research 12345 67890
roadie group focus research 67890
roadie query groups
```

Possible integration:

```bash
roadie query groups | jq '.data'
```

## 4. Local Status Bar

Goal: display the active window, stage, and important events.

```bash
roadie events subscribe --from-now --initial-state --scope window --scope stage
```

The consumer should:

- ignore unknown fields;
- use `type`, `scope`, `subject`, and `payload`;
- tolerate new event types.

## 5. Validate Before Changing Config

Goal: avoid a broken TOML rule disrupting the session.

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

Recommended workflow:

1. edit `roadies.toml`;
2. run `rules validate`;
3. test a representative window with `rules explain`;
4. restart Roadie if needed.

## 6. Recover From State Inconsistency

Goal: repair local state without deleting all configuration.

```bash
roadie state audit
roadie state heal
roadie daemon heal
roadie daemon health
```

Use this sequence after:

- display disconnect/reconnect;
- abrupt app shutdown;
- branch switch or rebuild.

## 7. Before A Risky Operation

Goal: keep an explicit fallback and inspect the same snapshot used by the crash watcher.

```bash
roadie config reload --json
roadie restore snapshot --json
roadie restore status
```

If frames must be restored explicitly:

```bash
roadie restore apply --yes
```

This restore matches windows by current window ID. The crash watcher uses the same mechanism only when the daemon disappears without a clean exit; it does not run in the focus/border path.

## 8. Reasonable Local Administration

Goal: avoid accumulating logs and backups.

```bash
roadie cleanup --dry-run
roadie cleanup --apply
```

Start with `--dry-run` to inspect candidate files before deletion or rotation.

## 9. Keyboard-First Navigation With Labels

Goal: jump to a window, stage, display, desktop, or bookmark without remembering
internal IDs.

```bash
roadie targets interactive --source all
roadie targets pick work --action switch
roadie targets inspect A --json
```

Use this when:

- the nav rail is visible but the target is easier to type than click;
- a script or agent needs a structured list of possible destinations;
- you want ambiguous searches to fail safely instead of moving windows.

## 10. Spatial Targeting When Accessibility Cannot See A Control

Goal: target a visual area even when the application does not expose a useful
Accessibility element.

```bash
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
```

Use **Display Grid** for full-screen or cross-display targeting. Use **Window
Grid** when the interaction belongs inside the focused window, such as a video
player, canvas, webview, or dense application pane.

## 11. Short Macro Capture

Goal: record a short mouse manipulation with both coordinates and semantic
target context.

```bash
roadie record start demo --duration 10
roadie record inspect demo --json
roadie record replay demo
```

Recordings keep a best-effort Roadie or Accessibility target and a grid fallback,
so replay can prefer stable targets and use coordinates only when needed.
