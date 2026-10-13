# Features

## Tiling

Roadie tiles the visible windows in the active stage.

Available modes:

- `bsp`: binary tree layout for terminal/code/browser workflows.
- `spatialBsp`: persistent binary tree; stored splits and ratios define the layout. `mutableBsp` and `yabai` remain aliases.
- `masterStack`: one main window and a secondary stack.
- `float`: Roadie keeps stage state but does not retile windows.

Examples:

```bash
roadie mode bsp
roadie mode spatialBsp
roadie mode masterStack
roadie mode float
roadie balance
```

Use cases:

- development with an editor as master and terminals in the stack;
- persistent BSP layouts edited with `move`, `warp`, `resize`, and drag and drop;
- multi-display operations with different modes per display/stage;
- temporary tiling pause on a `float` stage.

## Modular Runtime

Roadie can run as a classic monolithic daemon or as a set of separate runtime
components:

- `tiler`: applies layouts and keeps tiled stages consistent;
- `rail`: renders the stage rail and thumbnails;
- `border`: draws the focus border overlay;
- `focus-mouse`: handles focus-follows-mouse;
- `titlebar-menu`: handles title-bar drag/drop and context actions;
- `target-mode`: exposes keyboard targets, grids, and target activation.

Restore safety is not a separate component: it runs inside `roadied run` and `roadied tiler`. The old `roadied restore-safety` command still exists, but it only prints a message and exits with code 0.

`roadied run` and `roadied tiler` share one instance lock (`~/.roadies/roadied.lock`), so only one of them can run. A second instance exits with code 1. Use one launcher at a time: the LaunchAgent, `make dev-start`, or `./scripts/start-modular`. The tiler writes `~/.roadies/roadied.pid`; the other components write `<name>.pid`.

Start the full modular profile:

```bash
./scripts/start-modular
roadie query components
roadie daemon health
```

This is useful today for observability and targeted debugging: each component
has its own process, lock file, and stdout/stderr logs under `~/.roadies`.

It also creates the foundation for companion-mode usage. In that model, Roadie
can eventually provide stages, rail, borders, focus helpers, target mode, or
restore safety beside another window manager such as yabai or AeroSpace instead
of always owning the full tiling loop. The standard modular script still starts
the tiler, so explicit stage-only or overlay-only profiles remain experimental
future work rather than a stable public contract.

## Stages

A stage is a named group of windows inside a Roadie desktop. Only the active stage is visible; inactive stages are hidden but restorable.

```bash
roadie stage list
roadie stage create 4
roadie stage rename 4 Comms
roadie stage switch 2
roadie stage assign 2
roadie stage switch-position 2
roadie stage assign-position 2
roadie stage switch-visible next
roadie stage switch-visible prev
roadie stage assign-empty
roadie stage summon WINDOW_ID
roadie stage move-to-display 2
roadie stage move-to-display right --no-follow
```

The `*-position` variants follow the visible nav rail order. They are intended
for user shortcuts such as Alt-1, Alt-2, Alt-3.
`stage switch-visible prev|next` cycles through non-empty stages in nav rail
order. `stage assign-empty` sends the active window to the next unnamed empty
stage, creating one if needed.

A stage can also be sent to another display from the nav rail context menu. The
focus behavior is controlled by `[focus].stage_move_follows_focus` and can be
overridden per command with `--follow` or `--no-follow`.

Use cases:

- keep separate `Focus`, `Comms`, and `Docs` stages;
- hide a context without closing apps;
- bring a specific window back to the active stage with `stage summon`.

## Display Parking

Roadie treats a disconnected display as a temporary topology change, not as a
reason to destroy or merge stage state.

When a display disappears:

- non-empty stages from that display are parked as distinct stages on a remaining display;
- their names, mode, members, groups, focus metadata, and relative order are kept;
- empty stages stay as hidden restoration metadata;
- the active stage on the host display is not replaced by the parked stages.

When the display comes back, Roadie restores the current parked stages to that
display if it can recognize the display safely. Recognition first uses the
previous display ID, then a conservative fingerprint based on name, size,
visible size, position, and main-display hint. If several displays match equally,
Roadie refuses the automatic restore and leaves the parked stages visible.

Use cases:

- unplug a laptop from a monitor without losing the monitor's stages;
- keep working on the parked stages while the monitor is absent;
- replug the monitor and have those stages return without collapsing into one stage.

## Nav Rail

The nav rail is the per-display side panel that represents non-empty stages.
An empty stage is not shown there, even when it has been renamed.

Window thumbnails can also expose their presentation state. A `maximized`
window stays in its normal stage and is marked with a four-corner border. A
`nativeFullscreen` window is marked with a continuous border to show that macOS
fullscreen semantics may apply.

Main interactions:

- click a stage to activate it;
- keep empty rail clicks inert by default, with an opt-in `empty_click_hide_active` setting for switching to an empty stage;
- drag a thumbnail to another stage to move that window there;
- drag a thumbnail into the active workspace to summon it;
- drag an application window by its title bar onto a stage to move it there;
- drag an application window by its title bar onto empty rail space to create or use an empty stage.

macOS-reserved areas such as the menu bar are ignored by empty rail click handling.

Stage labels in the nav rail are configurable. By default, they are drawn below
the thumbnails, in the stage accent color, positioned so roughly two thirds of
the label remains visible.

```toml
[fx.rail.stage_labels]
enabled = true
color = "stage"      # or a hex color, e.g. "#6BE675"
font_size = 11
font_family = "system"
weight = "semibold"
alignment = "center" # left | center | right
opacity = 0.72
offset_x = 0
offset_y = 0
placement = "below" # above | below
z_order = "below"   # below | above
visibility_seconds = 0 # 0 = always visible, otherwise duration after reveal
fade_seconds = 0.35
```

When `visibility_seconds` is greater than `0`, stage names are hidden by default.
The `roadie rail labels show` command shows them for that duration, then fades
them out over `fade_seconds`.

If `enabled = false`, the title bar context menu no longer lists anonymous empty
stages one by one. It keeps stages that contain windows and adds one `Next empty
stage` destination.

## Title Bar Context Menu

Roadie can show an experimental menu when you right-click the top band of a managed window. Right-clicks inside application content are left to the application.

TOML activation:

```toml
[experimental.titlebar_context_menu]
enabled = true
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
```

## New App Placement

Roadie can choose the landing display for a new real application window when it
is discovered. Popups, dialogs, and non-tileable windows are not affected.

```toml
[window_placement]
new_apps_target = "mouse" # mouse | focused_display | macos
```

- `mouse`: assigns the new window to the active stage on the display under the pointer.
- `focused_display`: assigns the new window to the active stage on Roadie's focused display.
- `macos`: keeps the display initially chosen by macOS.

Available actions:

- pin the window across all stages on the current desktop;
- pin the window across all Roadie desktops on the same display;
- remove a window pin;
- send the window to another stage;
- send the window to another Roadie desktop;
- send the window to another display.

Use cases:

- keep a video, reference document, or terminal visible while switching stages;
- keep a window visible across all desktops on one display without duplicating or retiling it;
- move a window without looking up its ID;
- keep current focus while filing a window elsewhere;
- avoid popups and dialogs by limiting the menu to managed tileable windows.

Window pins do not copy a window into multiple stages. The window keeps one
home context, but Roadie does not hide it while the pinned desktop or display is
active. A pinned window is excluded from automatic layout to avoid moving other
windows unexpectedly.

## Roadie Desktops

Roadie desktops are virtual. They do not create or control native macOS Spaces.

```bash
roadie desktop list
roadie desktop focus 2
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
```

Use cases:

- keep `DeepWork`, `Ops`, and `Admin` desktops;
- switch between two contexts with `desktop back-and-forth`;
- bring a desktop to the current display with `desktop summon`.

## Keyboard Targets

Keyboard Targets provide a stable list of keyboard-addressable destinations for
humans and external agents. It does not replace the nav rail: it exposes the
same concepts as named, inspectable, actionable targets.

```bash
roadie targets list
roadie targets list --json
roadie targets list --filter gray
roadie targets inspect A
roadie targets pick gray
roadie targets activate A --action switch
roadie targets activate S --action focus
roadie targets activate D --action send-active
roadie targets show --json --labels-only
roadie query targets
```

Roadie targets cover windows, stages, displays, desktops, and bookmarks. Each
target has a short label (`A`, `S`, `D`, then `AA`, etc.), a stable ID, and a
list of supported actions. Labels are for humans; IDs are for scripts.

Application-sensitive zones can be listed experimentally through Accessibility.
This mode is disabled by default so app scanning does not run on window-manager
hot paths.

Electron apps (T3 Code, Slack, Discord...) only publish their Accessibility
content on request. When the AX boost is active (`ax_boost_enabled` or
`additional_boost_bundle_ids`), Roadie sets `AXManualAccessibility` on the
frontmost Electron app on each session. The app builds its tree in the
background: right after launch, the first session may only show the window
(Roadie retries for at most 300 ms); later sessions are complete. Web trees are
deep: use `max_depth = 30` and `timeout_ms = 250`. Only
elements visible inside the window get a label. Turning the boost off also turns
this request off.

Each scan writes a `targets.app_scan` event (elements read, depth reached,
duration, stop reason) to `~/.roadies/events.jsonl`. Use it to tune `max_depth`
and `timeout_ms`:

```bash
grep '"targets.app_scan"' ~/.roadies/events.jsonl | tail -3
```

Keyboard Target building blocks are independently configurable. The CLI foundation
and picker stay enabled by default, while the future visual overlay, app mouse
actions, and app scroll mode stay off until the user opts in.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = false
overlay_labels_only = true
overlay_duration_seconds = 3
app_mouse_actions_enabled = false
scroll_mode_enabled = false
```

```toml
[experimental.app_targets]
enabled = false
scope = "frontmost_window"
max_targets = 150
timeout_ms = 120
hint_characters = "asdfghjkl"
include_roles = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow"]
```

```toml
[experimental.target_grid]
enabled = true
overlay_enabled = true
overlay_draw_grid = true
overlay_fill_color = "#4DABF7"
overlay_fill_opacity = 0.10
overlay_border_color = "#4DABF7"
overlay_border_opacity = 0.55
overlay_label_color = "#FFFFFF"
rows = 3
columns = 3
max_depth = 3
hint_characters = "azeqsdwxc"
```

Use cases:

- jump to a bookmarked window or stage without remembering its ID;
- search for a target with `targets pick` and fail cleanly on ambiguity;
- send the active window to a target selected by label;
- give an agent a JSON API that is more robust than screenshots;
- inspect why a target is stale, pinned, floating, or excluded from tiling.

Even when `experimental.app_targets.enabled = true`, `click`, `double-click`,
and `right-click` on application targets are refused until
`experimental.target_mode.app_mouse_actions_enabled = true`.

Still intentionally bounded: deep application control remains experimental,
timeout-limited, and disabled by default.

## Power-User Commands

Roadie exposes layout primitives inspired by power-user window managers.

```bash
roadie focus back-and-forth
roadie layout split horizontal
roadie layout split vertical
roadie layout flatten
roadie warp right
roadie resize right
roadie layout zoom-parent
roadie layout toggle-split
```

Use cases:

- return to the previous focus;
- force a local layout restructuring;
- insert the active window on a chosen side with `warp`;
- locally flip two neighboring windows in `spatialBsp` with `toggle-split`;
- temporarily enlarge a window without losing context.

In `spatialBsp`, `layout insert` and `layout join-with` are rejected; use `warp`. `layout width` is rejected; use `resize`. `layout flatten` balances the existing tree. In other modes, legacy commands remain available where supported.

## Rules

Rules automate window handling by app, title, role, stage, or regex. They can
also place a new real application window on a target stage, Roadie desktop, and
display without following focus by default.

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

Use cases:

- send project terminals to a `shell` stage;
- always open Firefox on the `web` stage of the external display;
- create that affinity directly from the title bar right-click menu;
- tag documentation windows as `research` scratchpad candidates;
- catch invalid regexes before restarting the daemon.

## Window Groups

Window groups associate multiple windows with the same user intent.

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

Use cases:

- group several terminals for the same project;
- group multiple browser documentation windows;
- expose grouped state to scripts via `roadie query groups`.

## Events And Query API

Roadie publishes JSONL events and exposes stable JSON queries.

```bash
roadie events subscribe --from-now --initial-state
roadie query state
roadie query windows
roadie query groups
roadie query events
```

Use cases:

- feed a status bar;
- watch focus changes;
- debug a rule or a group;
- build a local dashboard.

## Restore Safety And Administration

The daemon (`roadied run` or `roadied tiler`) writes a restore snapshot at startup, at each stage change, and every 30 seconds. On SIGTERM, SIGINT, or SIGHUP, it brings hidden windows back before it exits. A small watcher process (`restore-watch`) follows the daemon and does the same if the daemon disappears without a clean exit. None of this runs in the focus/border path. To disable it, start the daemon with `roadied run --yes --no-restore-safety`. To bring every hidden window back by hand, run `roadie restore unhide-all`.

```bash
roadie config reload --json
roadie restore snapshot --json
roadie restore status --json
roadie restore apply --yes --json
roadie cleanup --dry-run --json
roadie cleanup --apply
```

Use cases:

- reload config only when validation succeeds;
- take a manual frame snapshot before a risky operation;
- explicitly restore frames by window ID when requested, or after an unclean crash;
- keep logs, backups, and legacy archives under control.

## Width Presets And Performance Diagnostics

Width presets apply to `bsp` and `masterStack`. In `spatialBsp`, use `resize` instead of `layout width`. Performance diagnostics read the event log; they do not time the focus/border path in real time.

```bash
roadie layout width next
roadie layout width prev
roadie layout width nudge 0.05
roadie layout width ratio 0.67

roadie performance summary
roadie performance recent --limit 20
roadie performance thresholds --json
```

Use cases:

- quickly widen the active window without changing the whole layout mode;
- inspect recent interaction event types in `events.jsonl`;
- keep target thresholds documented without touching the daemon.

## Keyboard Targets, Display Grid, Window Grid, And Macros

Keyboard Targets expose actionable stages, windows, displays, desktops,
bookmarks, and Accessibility application zones.

The **Display Grid** adds a recursive spatial language over a full display when
Accessibility cannot see everything. The **Window Grid** uses the same recursive
language but scopes it to the focused window, which is useful for video players,
webviews, canvases, and dense application panes.

Record/replay captures short manipulations with target context and grid
fallback. A `record` indicator can appear in the navrail while capture is
running.

```bash
roadie targets interactive --source all --include-app-targets
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
roadie record start demo --duration 10
roadie record replay demo
```

Use cases:

- switch to a stage or window by label instead of ID;
- click an application button exposed by Accessibility;
- target a non-accessible zone through Display Grid;
- target a control inside the focused window through Window Grid;
- show a manipulation to an agent, then replay or analyze it.
