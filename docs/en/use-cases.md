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

## 12. Work In Tabbed Or Scrolling Ribbon Mode

Goal: switch a reading or writing stage to full-frame tabs (`tabbed`) or a centered horizontal ribbon (`scrolling`) without changing other `spatialBsp` stages.

```bash
roadie mode tabbed       # clickable floating tab bar (auto-hidden for a single window)
roadie focus right       # next tab
roadie move left         # reorder tab left

roadie mode scrolling    # centered horizontal columns (65% width by default)
roadie focus right       # scroll to the next column
roadie layout width next # adjust column width

# Or stack tabs inside individual tiles while staying in spatialBsp:
roadie tab stack right   # stack active window into the right BSP tile
roadie tab next          # switch to the next tab inside the tile
roadie tab move left     # reorder active tab left
roadie tab unstack       # detach active tab back into its own BSP tile
```

Layout modes are also available from the NavRail stage context menu and from the launcher. Inside `spatialBsp`, you can also hold `⌥ Option` while dropping on a tile center (or drop directly onto an existing tile's tab bar) to stack, and drag any tab out of its bar to detach it into a BSP tile.

## 13. Floating Scratchpad, Dim Inactive, And Workspace Scenes

Goal: keep a scratchpad window one shortcut away above any stage, softly dim unfocused tiled windows to stay focused, and save a complete project scene.

```bash
roadie scratchpad assign notes
roadie scratchpad toggle notes

roadie project save Sprint --url https://example.org/board --app com.apple.Terminal --note "Weekly review"
roadie project info Sprint
roadie project open Sprint
```

Enable `[fx.dim_inactive].enabled = true` in **Settings > Effects** to apply a lightweight click-through dimming veil over unfocused tiled windows in the active stage.

## 14. Secure Clipboard History And Daily Snippets

Goal: recall an earlier copy without exposing passwords and expand reusable templates (`{date}`, `{clipboard}`, `{cursor}`).

- In the launcher: type `cb` (or `clipboard`) to search and copy an entry, or `snip` (or `snippet`) to expand a snippet.
- In CLI:

```bash
roadie clipboard list
roadie clipboard search "roadmap"
roadie clipboard pin ID
roadie snippet list
roadie snippet expand !sig --copy
```

Sensitive types (`ConcealedType`, `TransientType`, `AutoGeneratedType`) and password managers are automatically skipped; history stays local in `~/.roadies/clipboard.json` (`0o600`).

## 15. Instant Launcher Tools And Fast Switcher Triage

Goal: convert units, start a Pomodoro, sample a screen color, or triage open windows without launching dedicated apps.

- In the launcher: `100 km in mi`, `0xff in dec`, `14:00 NYC in Paris`, `timer 25m focus`, `pomodoro`, `color picker`, `:rocket`.
- In the window switcher (`Cmd+Tab`, outside search): `W` closes the window, `Q` quits the app, `M` minimizes/restores, `H` hides the app, `S` summons into the active stage, `A` filters by current app, `D` filters by current display.

## 16. Run Roadie 100% Standalone (No BetterTouchTool Or Karabiner Required)

Goal: set up Roadie on a fresh Mac or simplify an existing stack by letting Roadie natively handle keyboard shortcuts, `⌘ Tab` switching, trackpad gestures (`scrolling` ribbon and Overview), and scratchpad reboot persistence — while keeping BetterTouchTool or Karabiner optional.

```bash
# Bootstrap a clean config with a collision-free preset (AZERTY/QWERTY hardware-key aware)
roadie config init --preset standard    # or: vim | minimal
roadie shortcuts list
roadie shortcuts check
```

- **Native `⌘ Tab` / `⌘ Shift Tab` switcher**: in **Settings > Switcher** (or `[[switcher.shortcuts]]`), set `hotkey = "command+tab"` and `trigger_source = "roadie"`. Roadie intercepts both directions natively through `CGEventTap`.
- **Native trackpad gestures**: swipe horizontally with 3 fingers (or `⌥ Option + scrollWheel`) to smoothly glide the `scrolling` ribbon at up to 120 Hz ProMotion; swipe up with 4 fingers to open Overview and down to close (`overview.trackpad_gesture = true`).
- **One-click scratchpad from the title bar**: right-click any window title bar → **Fenêtre → Transformer en scratchpad** (or **Retirer du scratchpad**). After a reboot, `tiling.scratchpad_reboot_policy = "reattach_or_relaunch"` (default) reattaches or relaunches the app on the next `toggle` (configurable to `reattach` or `ephemeral`).
- **Optional BetterTouchTool import**: in **Settings > Shortcuts**, click **Importer depuis BetterTouchTool** to import your existing Roadie bindings without altering your BTT profile.
