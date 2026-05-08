# Features

## Tiling

Roadie tiles the visible windows in the active stage.

Available modes:

- `bsp`: binary tree layout for terminal/code/browser workflows.
- `masterStack`: one main window and a secondary stack.
- `float`: Roadie keeps stage state but does not retile windows.

Examples:

```bash
./bin/roadie mode bsp
./bin/roadie mode masterStack
./bin/roadie mode float
./bin/roadie balance
```

Use cases:

- development with an editor as master and terminals in the stack;
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
./bin/roadie stage summon WINDOW_ID
./bin/roadie stage move-to-display 2
```

Use cases:

- keep separate `Focus`, `Comms`, and `Docs` stages;
- hide a context without closing apps;
- bring a specific window back to the active stage with `stage summon`.

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
```

Use cases:

- return to the previous focus;
- force a local layout restructuring;
- place the next window on a chosen side;
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

