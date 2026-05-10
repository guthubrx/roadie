# Features

## Tiling

Roadie tiles the visible windows in the active stage.

Available modes:

- `bsp`: binary tree layout for terminal/code/browser workflows.
- `mutableBsp`: binary tree layout that keeps observed split ratios when windows are moved or resized.
- `masterStack`: one main window and a secondary stack.
- `float`: Roadie keeps stage state but does not retile windows.

Examples:

```bash
./bin/roadie mode bsp
./bin/roadie mode mutableBsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie balance
```

Use cases:

- development with an editor as master and terminals in the stack;
- yabai-like BSP experiments where manual moves should influence the next tiling pass;
- multi-display operations with different modes per display/stage;
- temporary tiling pause on a `float` stage.

## Stages

A stage is a named group of windows inside a Roadie desktop. Only the active stage is visible; inactive stages are hidden but restorable.

```bash
./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage switch-position 2
./bin/roadie stage assign-position 2
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage move-to-display right --no-follow
```

The `*-position` variants follow the visible nav rail order. They are intended
for user shortcuts such as Alt-1, Alt-2, Alt-3.

A stage can also be sent to another display from the nav rail context menu. The
focus behavior is controlled by `[focus].stage_move_follows_focus` and can be
overridden per command with `--follow` or `--no-follow`.

Use cases:

- keep separate `Focus`, `Comms`, and `Docs` stages;
- hide a context without closing apps;
- bring a specific window back to the active stage with `stage summon`.

## Nav Rail

The nav rail is the per-display side panel that represents non-empty stages.

Main interactions:

- click a stage to activate it;
- click empty rail space to switch to an empty stage when `empty_click_hide_active` is enabled;
- drag a thumbnail to another stage to move that window there;
- drag a thumbnail into the active workspace to summon it;
- drag an application window by its title bar onto a stage to move it there;
- drag an application window by its title bar onto empty rail space to create or use an empty stage.

macOS-reserved areas such as the menu bar are ignored by empty rail click handling.

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

Available actions:

- send the window to another stage;
- send the window to another Roadie desktop;
- send the window to another display.

Use cases:

- move a window without looking up its ID;
- keep current focus while filing a window elsewhere;
- avoid popups and dialogs by limiting the menu to managed tileable windows.

## Roadie Desktops

Roadie desktops are virtual. They do not create or control native macOS Spaces.

```bash
./bin/roadie desktop list
./bin/roadie desktop focus 2
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork
```

Use cases:

- keep `DeepWork`, `Ops`, and `Admin` desktops;
- switch between two contexts with `desktop back-and-forth`;
- bring a desktop to the current display with `desktop summon`.

## Power-User Commands

Roadie exposes layout primitives inspired by power-user window managers.

```bash
./bin/roadie focus back-and-forth
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout flatten
./bin/roadie layout insert right
./bin/roadie layout join-with left
./bin/roadie layout zoom-parent
./bin/roadie layout toggle-split
```

Use cases:

- return to the previous focus;
- force a local layout restructuring;
- place the next window on a chosen side;
- locally flip two neighboring windows in `mutableBsp` with `toggle-split`;
- temporarily enlarge a window without losing context.

## Rules

Rules automate window handling by app, title, role, stage, or regex.

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

Use cases:

- send project terminals to a `shell` stage;
- tag documentation windows as `research` scratchpad candidates;
- catch invalid regexes before restarting the daemon.

## Window Groups

Window groups associate multiple windows with the same user intent.

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

Use cases:

- group several terminals for the same project;
- group multiple browser documentation windows;
- expose grouped state to scripts via `roadie query groups`.

## Events And Query API

Roadie publishes JSONL events and exposes stable JSON queries.

```bash
./bin/roadie events subscribe --from-now --initial-state
./bin/roadie query state
./bin/roadie query windows
./bin/roadie query groups
./bin/roadie query events
```

Use cases:

- feed a status bar;
- watch focus changes;
- debug a rule or a group;
- build a local dashboard.

## Restore Safety And Administration

Roadie writes a restore snapshot on daemon startup and clean exit. A separate watcher can restore frames only when the `roadied` process disappears without marking a clean exit. It does not run in the focus/border path and can be disabled with `roadied run --yes --no-restore-safety`.

```bash
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --yes --json
./bin/roadie cleanup --dry-run --json
./bin/roadie cleanup --apply
```

Use cases:

- reload config only when validation succeeds;
- take a manual frame snapshot before a risky operation;
- explicitly restore frames by window ID when requested, or after an unclean crash;
- keep logs, backups, and legacy archives under control.

## Width Presets And Performance Diagnostics

Width adjustments are manual commands. Performance diagnostics read the event log; they do not time the focus/border path in real time.

```bash
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67

./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie performance thresholds --json
```

Use cases:

- quickly widen the active window without changing the whole layout mode;
- inspect recent interaction event types in `events.jsonl`;
- keep target thresholds documented without touching the daemon.
