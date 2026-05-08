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
```

Typical use:

- `daemon health`: check daemon and state health.
- `state audit`: detect duplicates, stale references, or broken scopes.
- `state heal`: repair conservative state inconsistencies.
- `metrics --json`: feed a script or dashboard.

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
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie layout plan --json
./bin/roadie layout apply --yes
./bin/roadie layout split horizontal
./bin/roadie layout split vertical
./bin/roadie layout join-with left|right|up|down
./bin/roadie layout insert left|right|up|down
./bin/roadie layout flatten
./bin/roadie layout zoom-parent
./bin/roadie layout width next
./bin/roadie layout width prev
./bin/roadie layout width nudge 0.05
./bin/roadie layout width ratio 0.67 --all
./bin/roadie balance
```

Use cases:

- inspect the plan before applying it with `layout plan`;
- persist a manual layout intent with `insert` or `zoom-parent`;
- return to a linear layout with `flatten`.
- adjust the active or all tiled window widths with `layout width`.

## Safety Commands

```bash
./bin/roadie control status --json
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status --json
./bin/roadie restore apply --json
./bin/roadie transient status --json
./bin/roadie state identity inspect --json
./bin/roadie state restore-v2 --dry-run --json
./bin/roadie state restore-v2 --json
```

Typical use:

- `config reload`: atomically validate and apply TOML, keeping the previous config on error.
- `restore snapshot`: write a safety snapshot for managed windows.
- `restore apply`: restore visible frames from the latest snapshot.
- `transient status`: check whether a sheet/dialog/open-save panel is pausing layout.
- `state restore-v2 --dry-run`: inspect stable-identity matches before applying.

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
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
./bin/roadie stage prev
./bin/roadie stage next
```

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
./bin/roadie query config_reload
./bin/roadie query restore
./bin/roadie query transient
./bin/roadie query identity_restore
```

Every `query` returns stable JSON:

```json
{
  "kind": "windows",
  "data": []
}
```
