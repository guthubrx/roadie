# CLI Commands

All commands below use the `roadie` binary. `make install` puts it in `~/.local/bin`; add that folder to your `PATH`. From the source tree, `./scripts/roadie` runs the same commands with `swift run`.

When the daemon runs, `roadie` sends each command to it through the socket `~/.roadies/roadied.sock`. The command needs no Accessibility permission of its own. If the daemon is stopped, `roadie` runs the command itself and then needs the permission. `daemon start|stop|restart|health`, `doctor`, `permissions`, and `config validate` always run locally.

## State And Diagnostics

```bash
roadie daemon health
roadie daemon heal
roadie state dump --json
roadie state audit
roadie state heal
roadie metrics --json
roadie doctor
roadie self-test
roadie performance summary
roadie performance recent --limit 20
roadie performance thresholds --json
```

Typical use:

- `daemon health`: check daemon and state health. The `macos-window-settings` check warns about macOS settings that move windows instead of Roadie: Stage Manager, tiling by dragging a window to a screen edge or to the menu bar, and clicking the wallpaper to reveal the desktop. The message says where to turn them off in System Settings. Roadie never changes these settings.
- `doctor`: full report on the daemon (running or not), the Accessibility and Screen Recording permissions, and the validity of the configuration. It reads `~/.roadies/daemon-status.json`, which the daemon updates regularly.
- `--version`: prints the version. `roadied --version` does the same for the daemon binary.
- `state audit`: detect duplicates, stale references, or broken scopes.
- `state heal`: repair conservative state inconsistencies, including duplicate stage names.
- `metrics --json`: feed a script or dashboard.
- `performance ...`: read recent interactions from the event log without active daemon instrumentation.

## Windows And Focus

```bash
roadie windows list
roadie windows list --json
roadie focus left|right|up|down
roadie focus back-and-forth
roadie move left|right|up|down
roadie warp left|right|up|down
roadie resize left|right|up|down
roadie window display 2
roadie window desktop 2 --follow
roadie window reset
roadie toggle maximize
roadie toggle fullscreen
roadie toggle native-fullscreen
roadie toggle floating
```

`roadie toggle floating` floats the active window in its stage, outside tiling. Run it again to put it back into tiling. See "Floating Window" in the features guide.

`roadie toggle maximize` enlarges the active window while keeping the visible nav rail strip clear. Run it again to restore the layout. Siblings in the same stage are hidden while maximized. Activating another window in that stage restores the layout directly. Switching stages preserves the saved zoom. With auto-hide enabled, a hidden rail frees the entire visible area, just like Roadie fullscreen. When the rail returns on hover or with `roadie rail pin`, the window resizes to make room without leaving maximized mode. The enabled title-bar menu also offers “Fenêtre → Maximiser / restaurer (garder le navrail)”.

`roadie toggle fullscreen` uses the entire visible area and hides the rail, including on hover, without entering macOS fullscreen. `roadie toggle native-fullscreen` uses macOS fullscreen. Switching between the two Roadie zoom modes preserves the original layout; repeating the active mode restores it.

Use cases:

- keyboard navigation between tiled windows;
- return to the previous focus with `focus back-and-forth`;
- send a window to another display or Roadie desktop;
- reset a stubborn window before recalculating layout.

## Layout

```bash
roadie mode bsp
roadie mode spatialBsp
roadie mode masterStack
roadie mode float
roadie layout plan --json
roadie layout apply --yes
roadie layout split horizontal
roadie layout split vertical
roadie layout join-with left|right|up|down
roadie layout insert left|right|up|down
roadie layout toggle-split [left|right|up|down]
roadie layout flatten
roadie layout zoom-parent
roadie layout width next
roadie layout width prev
roadie layout width nudge 0.05
roadie layout width ratio 0.67
roadie balance
```

Use cases:

- inspect the plan before applying it with `layout plan`;
- edit the stored tree with `warp`, `resize`, or `layout split`;
- flip the local orientation of two neighboring windows in `spatialBsp` with `toggle-split`;
- manually adjust the active window width with `layout width`;
- balance the existing tree with `flatten` in `spatialBsp`.

In `spatialBsp`, `layout insert` and `layout join-with` are rejected; use `warp`. `layout width` is rejected; use `resize`. `layout flatten` balances the existing tree. In other modes, legacy commands remain available where supported.

## Nav Rail

```bash
roadie rail status
roadie rail pin
roadie rail unpin
roadie rail toggle
```

The nav rail also supports mouse interactions:

- drag a thumbnail to a stage;
- drag a thumbnail into the active workspace;
- drag an application window by its title bar onto a stage or empty rail space;
- drag a stage with the right mouse button to preview its destination and the new card order; release to apply, or release outside the rail to cancel;
- right-click a stage to open its menu (rename, send to another display).

## Safety And Generated Files

```bash
roadie config validate --json
roadie config reload --json
roadie restore snapshot --json
roadie restore status --json
roadie restore apply --yes --json
roadie restore unhide-all
roadie cleanup --dry-run --json
roadie cleanup --apply
```

Notes:

- `config reload` validates before applying and keeps the previous config when the new one is invalid.
- `restore unhide-all` brings every window hidden or parked by Roadie back on screen. Use it after a crash, or before you uninstall Roadie (`make uninstall` runs it for you).
- `restore snapshot` and `restore apply` remain available manually; the daemon also writes a snapshot on startup/clean exit.
- the daemon restores hidden windows when it stops, and a watcher does it after a crash; `roadied run --yes --no-restore-safety` disables both.
- `cleanup --dry-run` shows what would be deleted or rotated before doing anything.

## Displays, Desktops, And Stages

```bash
roadie display list
roadie display current
roadie display focus 2

roadie desktop list
roadie desktop current
roadie desktop focus 2
roadie desktop prev
roadie desktop next
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
roadie desktop move 2 1

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
roadie stage move-to-display right
roadie stage move-to-display right --no-follow
roadie stage prev
roadie stage next
```

`stage switch` and `stage assign` target stable IDs. `stage switch-position`
and `stage assign-position` target the visible nav rail order: position 1 is the
first visible stage, even when its internal ID is different.
`stage switch-visible prev|next` cycles through non-empty stages only, matching
the nav rail order. `stage assign-empty` sends the active window to the next
unnamed empty stage, creating one if needed.

`desktop move N POSITION` places desktop N of the active display at POSITION and
renumbers desktops, like dragging in the overview; its stages, windows, name and
pins follow it. `stage rename` refuses a name already used by another stage: a stage
name is unique across Roadie.

`stage move-to-display` accepts a display index or a direction
`left|right|up|down`. Without a flag, Roadie uses this TOML preference:

```toml
[focus]
stage_move_follows_focus = false
```

`--follow` and `--no-follow` override the preference for one command. The nav
rail exposes the same action from a stage card context menu and lists the other
available displays.

## Rules

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

## Window Groups

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

## Events And Queries

```bash
roadie events tail 50
roadie events subscribe --from-now --initial-state
roadie events subscribe --from-now --type window.focused --scope window

roadie query state
roadie query windows
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
roadie query event_catalog
roadie query performance
roadie query restore
roadie query targets
```

Every `query` returns stable JSON:

```json
{
  "kind": "windows",
  "data": []
}
```

## Keyboard Targets

```bash
roadie targets list
roadie targets list --json
roadie targets list --source roadie|app|all
roadie targets list --filter TEXT --max 40
roadie targets pick QUERY_OR_LABEL
roadie targets pick QUERY_OR_LABEL --action focus|switch|send-active|click|double-click|right-click
roadie targets inspect TARGET_ID_OR_LABEL
roadie targets inspect TARGET_ID_OR_LABEL --json
roadie targets activate TARGET_ID_OR_LABEL --action focus
roadie targets activate TARGET_ID_OR_LABEL --action switch
roadie targets activate TARGET_ID_OR_LABEL --action send-active
roadie targets activate TARGET_ID_OR_LABEL --action click
roadie targets activate TARGET_ID_OR_LABEL --action double-click
roadie targets activate TARGET_ID_OR_LABEL --action right-click
roadie targets activate TARGET_ID_OR_LABEL --action command-click
roadie targets search
roadie targets actions
roadie targets show --json --labels-only
roadie targets hide
```

`--source app` and `--source all` read application zones only when
`[experimental.app_targets].enabled = true`, or when the command includes
`--include-app-targets`. Application clicks stay disabled by default:
`click`, `double-click`, and `right-click` also require
`[experimental.target_mode].app_mouse_actions_enabled = true`. Unsupported
actions return structured errors instead of silently falling back.

`targets search` opens search mode (input bar, every visible window), like the
configurable `search_hotkey` shortcut. `targets actions` opens it directly on the
verbs of the active window, like `actions_hotkey`. See `docs/en/features.md`,
Search mode section.

In this bar, a `/` as the first character opens command mode. Its commands
(`/move`, `/stage`, `/screen`, `/bm`, `/grid`, `/doctor`, `/set`,
`/settings`...) call the same services as the `roadie` commands above, without
going through the socket. They require the daemon to be running. See
`docs/en/features.md`, Command mode (`/`) and settings window section.

The `[experimental.target_mode]` section can also disable all Keyboard Target
commands (`enabled = false`) or only the picker (`picker_enabled = false`).

`targets pick` applies the action only when the query resolves to one target. If
the query is ambiguous, the command prints candidates and does not mutate the
layout.

## Display Grid, Window Grid, And Macros

```bash
roadie grid show --json
roadie grid show A --visual --duration 2
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
roadie grid click A
roadie grid double-click A
roadie grid right-click A
roadie grid move A
roadie grid scroll-up A
roadie grid scroll-down A
roadie grid drag A L

roadie record start demo --duration 10
roadie record list
roadie record inspect demo --json
roadie record replay demo
roadie record delete demo
```

Both grids are controlled by `[experimental.target_grid]`.
`--scope display` is the **Display Grid** and uses the whole target display.
`--scope focused_window` is the **Window Grid** and uses the focused window as
the recursive root. By default, labels use a
natural 3x3 block for a French Mac AZERTY keyboard: `A Z E / Q S D / W X C`,
encoded as `hint_characters = "azeqsdwxc"`. `interactive` recursively zooms
into the typed cell. `Space` clicks the current zone, arrow keys move the
selection at the same depth, `Backspace` goes up, `R` returns to the root grid,
and `Esc` cancels. At the root level, arrow keys switch the target display in
the requested direction. Edge behavior is controlled by
`arrow_edge_behavior = "clamp"` or `"wrap"`. `wake_mouse_pixels` performs a tiny
cursor round-trip on each grid change to wake hover controls; `0` disables it.
When `mouse_follow_grid = true`, the cursor follows the center of the current
cell instead, which is useful to wake video controls on another display. When
`focus_follow_grid = true`, the window under the current cell also receives
focus. The
`label_placement = "callout"` keeps external callouts; `"center"` places labels
inside cell centers. `overlay_label_background_opacity` controls the grid label
background opacity, from `0.0` transparent to `1.0` opaque. The interactive
timeout is reset on each grid movement.
Macros are controlled by
`[experimental.target_record]`. Recordings keep coordinates, the best Roadie/AX
target when available, and a grid-path fallback. Typed text is not recorded by
default. The recording indicator is configured with
`indicator = "notification"`, `"navrail"`, `"both"`, or `"none"`. When shown in
the navrail, `navrail_bottom_offset` controls its distance from the bottom of
the rail in pixels.

## Shortcuts

The switcher also accepts commands from gestures or external tools:

```sh
roadie switcher show --profile all
roadie switcher next
roadie switcher previous
roadie switcher accept
roadie switcher cancel
```

Without a profile, `show` chooses the first configured profile. `--json` reports
that the command was queued. The graphical component then executes it. See the
[switcher guide](window-switcher.md) for profiles and filters.

Roadie provides `search_hotkey` for search (see `[experimental.target_mode]`) and independent [window switcher profiles](window-switcher.md). For other commands, use a tool that runs a command on a key press. The folder `examples/` has ready-to-use files:

- `examples/skhd/skhdrc`: shortcuts for [skhd](https://github.com/koekeishiya/skhd). Copy it to `~/.config/skhd/skhdrc`, then run `skhd --reload`.
- `examples/karabiner/roadie.json`: rules for Karabiner-Elements. Copy it to `~/.config/karabiner/assets/complex_modifications/`, then enable the rules in Karabiner-Elements > Complex Modifications > Add predefined rule.

Both files call `~/.local/bin/roadie`. They cover focus, window move, stage and desktop switching, layout mode, and rebalance. With BetterTouchTool, create a trigger of type "Execute Terminal Command" with the same commands.

Because the daemon runs the commands, these tools need no Accessibility permission for `roadie` (see [Permissions](../../README.md#permissions)).
