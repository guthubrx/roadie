# CLI Commands

All commands below can be called directly with `./bin/roadie` or through `./scripts/roadie`.

## State And Diagnostics

```bash
./bin/roadie daemon health
./bin/roadie daemon heal
./bin/roadie state dump --json
./bin/roadie state audit
./bin/roadie state heal
./bin/roadie metrics --json
./bin/roadie doctor
./bin/roadie self-test
./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie performance thresholds --json
```

Typical use:

- `daemon health`: check daemon and state health.
- `state audit`: detect duplicates, stale references, or broken scopes.
- `state heal`: repair conservative state inconsistencies.
- `metrics --json`: feed a script or dashboard.
- `performance ...`: read recent interactions from the event log without active daemon instrumentation.

## Windows And Focus

```bash
./bin/roadie windows list
./bin/roadie windows list --json
./bin/roadie focus left|right|up|down
./bin/roadie focus back-and-forth
./bin/roadie move left|right|up|down
./bin/roadie warp left|right|up|down
./bin/roadie resize left|right|up|down
./bin/roadie window display 2
./bin/roadie window desktop 2 --follow
./bin/roadie window reset
```

Use cases:

- keyboard navigation between tiled windows;
- return to the previous focus with `focus back-and-forth`;
- send a window to another display or Roadie desktop;
- reset a stubborn window before recalculating layout.

## Layout

```bash
./bin/roadie mode bsp
./bin/roadie mode mutableBsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie layout plan --json
./bin/roadie layout apply --yes
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout join-with left|right|up|down
./bin/roadie layout insert left|right|up|down
./bin/roadie layout toggle-split [left|right|up|down]
./bin/roadie layout flatten
./bin/roadie layout zoom-parent
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67
./bin/roadie balance
```

Use cases:

- inspect the plan before applying it with `layout plan`;
- persist a manual layout intent with `insert` or `zoom-parent`;
- flip the local orientation of two neighboring windows in `mutableBsp` with `toggle-split`;
- manually adjust the active window width with `layout width`;
- return to a linear layout with `flatten`.

## Nav Rail

```bash
./bin/roadie rail status
./bin/roadie rail pin
./bin/roadie rail unpin
./bin/roadie rail toggle
```

The nav rail also supports mouse interactions:

- drag a thumbnail to a stage;
- drag a thumbnail into the active workspace;
- drag an application window by its title bar onto a stage or empty rail space.

## Safety And Generated Files

```bash
./bin/roadie config validate --json
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --yes --json
./bin/roadie cleanup --dry-run --json
./bin/roadie cleanup --apply
```

Notes:

- `config reload` validates before applying and keeps the previous config when the new one is invalid.
- `restore snapshot` and `restore apply` remain available manually; the daemon also writes a snapshot on startup/clean exit.
- the crash watcher restores only when `roadied` disappears without a clean-exit marker; `roadied run --yes --no-restore-safety` disables it.
- `cleanup --dry-run` shows what would be deleted or rotated before doing anything.

## Displays, Desktops, And Stages

```bash
./bin/roadie display list
./bin/roadie display current
./bin/roadie display focus 2

./bin/roadie desktop list
./bin/roadie desktop current
./bin/roadie desktop focus 2
./bin/roadie desktop prev
./bin/roadie desktop next
./bin/roadie desktop back-and-forth
./bin/roadie desktop summon 3
./bin/roadie desktop label 2 DeepWork

./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage switch-position 2
./bin/roadie stage assign-position 2
./bin/roadie stage switch-visible next
./bin/roadie stage switch-visible prev
./bin/roadie stage assign-empty
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage move-to-display right
./bin/roadie stage move-to-display right --no-follow
./bin/roadie stage prev
./bin/roadie stage next
```

`stage switch` and `stage assign` target stable IDs. `stage switch-position`
and `stage assign-position` target the visible nav rail order: position 1 is the
first visible stage, even when its internal ID is different.
`stage switch-visible prev|next` cycles through non-empty stages only, matching
the nav rail order. `stage assign-empty` sends the active window to the next
unnamed empty stage, creating one if needed.

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
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules list --json
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

## Window Groups

```bash
./bin/roadie group create terminals 12345 67890
./bin/roadie group add terminals 11111
./bin/roadie group focus terminals 67890
./bin/roadie group remove terminals 12345
./bin/roadie group dissolve terminals
./bin/roadie group list
```

## Events And Queries

```bash
./bin/roadie events tail 50
./bin/roadie events subscribe --from-now --initial-state
./bin/roadie events subscribe --from-now --type window.focused --scope window

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

Every `query` returns stable JSON:

```json
{
  "kind": "windows",
  "data": []
}
```
