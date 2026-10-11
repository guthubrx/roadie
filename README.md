<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Roadie logo" width="128" height="128">
</div>

<div align="center">

# Roadie

**Work in progress. Expect rough edges, breaking changes, and missing polish.**

English | [Français](README.fr.md)

</div>

Roadie is a small macOS tiling window manager written in Swift, built around one idea: automatic tiling and a Stage Manager-like workflow should be able to live together.

Current release: [v0.3.0](docs/releases/v0.3.0.md).

## Why This Project Exists

I never set out to write a window manager. For years, [yabai](https://github.com/koekeishiya/yabai) has been the foundation of my macOS workstation: sharp, powerful, and deeply influential for anyone who cares about tiling on macOS. Roadie owes a lot to yabai, both functionally and culturally.

The trigger was personal: I never managed to make yabai coexist cleanly with the Stage Manager workflow I wanted. I wanted named, hideable, restorable groups of windows, while still keeping automatic tiling for the visible windows.

So Roadie focuses on that specific combination:

- `spatialBsp` (yabai-like persistent tree), `bsp`, and `masterStack` tiling for the visible windows.
- Roadie stages: named groups of windows that can be hidden, restored, reordered, and represented visually.
- Roadie virtual desktops managed without controlling native macOS Spaces.
- Multi-display support where each display keeps its own current desktop, active stage, and layout.
- Display parking: when a monitor disappears, Roadie parks its non-empty stages on a remaining display instead of merging them into the active stage.
- A modular runtime where tiling, rail, borders, focus-follow-mouse, target mode,
  title-bar actions, and restore safety can run as separate components.

Roadie is not trying to replace yabai. yabai is broader, older, and much more mature. Roadie is intentionally smaller and opinionated around my workflow.

## The AeroSpace Influence

The second major influence is [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Instead of trying to manipulate native macOS Spaces, Roadie follows the same broad direction: keep SIP on, avoid private write APIs, and manage virtual workspaces on Roadie's side. Switching a Roadie desktop means hiding windows from the outgoing desktop and restoring windows from the incoming one.

The result is a small hybrid:

- A tiling model inspired by yabai's practical macOS window-manager ergonomics.
- A virtual desktop model inspired by AeroSpace's refusal to fight native Spaces.
- A stage layer built for people who want a Stage Manager-like workflow on top of tiling.

If you need a mature general-purpose macOS WM, look at yabai or AeroSpace first. Roadie exists for the narrower case where tiling, virtual desktops, and stage groups need to be one workflow.

## Feature Positioning

This is not a superiority table. It is only meant to make Roadie's scope clear.

Legend: ✅ supported, ◐ partial or narrower, ❌ not supported, 🧪 experimental,
⚙️ requires extra setup or an external companion tool.

### Layout And Window Control

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| BSP tiling | ✅ | ✅ | ✅ |
| User-mutable tiling tree | ✅ | ✅ | ◐ |
| Master-stack layout | ◐ | ✅ | ✅ |
| Float mode | ✅ | ✅ | ✅ |
| Window grid placement | ✅ | ❌ | ❌ |
| Window insert point | ✅ | ❌ | ◐ |
| Stack/tab/accordion layout | ✅ stack | ✅ accordion | ◐ groups only |
| Scratchpad windows | ✅ | ❌ | ◐ |
| Power-user tree commands | ✅ | ✅ | ◐ |

### Runtime And Companion Mode

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Single full window-manager daemon | ✅ | ✅ | ✅ |
| Modular components | ❌ | ❌ | ✅ |
| Run only overlays/stages beside another WM | ⚙️ | ⚙️ | 🧪 foundation |
| Component-level health checks | ◐ | ◐ | ✅ |
| Per-component logs | ◐ | ◐ | ✅ |

### Workspaces, Stages, And Displays

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Native macOS Spaces control | ✅ ⚙️ | ❌ | ❌ |
| Create/destroy/move native macOS Spaces | ✅ ⚙️ | ❌ | ❌ |
| Virtual desktops without native Spaces | ❌ | ✅ | ✅ |
| Named stages inside a desktop | ❌ | ❌ | ✅ |
| Stage rail with thumbnails | ❌ | ❌ | ✅ |
| Visible stage navigation and reorder | ❌ | ❌ | ✅ |
| Display parking and reconnect recovery | ❌ | ◐ | ✅ |
| Multi-display tiling | ✅ | ✅ | ✅ |
| Move workspace/stage to another display | ✅ | ✅ | ✅ |
| Mission Control awareness | ✅ | ◐ | ◐ |

### Rules, Automation, And Configuration

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Window rules and automatic placement | ✅ | ✅ callbacks | ✅ |
| Rich rule effects | ✅ | ◐ | ◐ |
| Integrated hotkeys | ❌ ⚙️ `skhd` | ✅ | ❌ ⚙️ BTT/Karabiner |
| Binding modes | ❌ | ✅ | ❌ |
| Config callbacks | ✅ signals | ✅ | ◐ |
| Declarative config reload | ◐ shell | ✅ | ✅ |
| Stable JSON query API | ✅ | ✅ | ✅ |
| Automation event stream | ✅ signals | ✅ subscribe | ✅ JSONL |
| CLI-first operation | ✅ | ✅ | ✅ |

### Focus And Visual Behavior

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Focus follows mouse | ✅ | ✅ | ✅ |
| Focus border overlay | ❌ | ❌ | ✅ |
| Window opacity/layers/PiP/shadow toggles | ✅ ⚙️ | ❌ | ❌ |
| Native fullscreen helpers | ✅ | ✅ | ◐ |
| Title-bar context actions | ❌ | ❌ | ✅ |

### Keyboard Targeting And Grids

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| Keyboard target labels | ❌ | ❌ | ✅ |
| App element target discovery | ❌ | ❌ | 🧪 |
| Recursive display grid | ❌ | ❌ | 🧪 |
| Recursive focused-window grid | ❌ | ❌ | 🧪 |
| Short macro record/replay | ❌ | ❌ | 🧪 |

`◐` means Roadie has a narrower or less mature version of the feature, not full
parity with yabai or AeroSpace.

Roadie does not require disabling SIP. It uses Accessibility for window discovery and movement, and Screen Recording only for rail thumbnails.

## What Roadie Does Today

- Tiles visible windows with `spatialBsp`, `bsp`, `masterStack`, or `float` modes. `spatialBsp` keeps a persistent BSP tree like yabai: a new window splits the focused one along its longest side, a closed window gives its space back to its sibling, and each event is applied in a single pass. `mutableBsp` and `yabai` are accepted as aliases of `spatialBsp`; existing `mutableBsp` stages are migrated once, with a backup in `~/.roadies/stages.json.pre-017`.
- Runs either as a monolithic daemon or as modular components with separate
  `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, and `target-mode`
  processes. Restore safety lives inside the `run` and `tiler` processes.
- Keeps stage groups per display and Roadie desktop.
- Provides Roadie virtual desktops without controlling native macOS Spaces.
- Supports multiple displays independently.
- Parks stages from a disconnected display on a remaining display, then restores them when the same display comes back and can be recognized safely.
- Shows a native side rail with stage thumbnails.
- Lets you drag thumbnails between stages or into the active workspace.
- Lets you optionally right-click a managed window title bar to send that window to another stage, desktop, or display.
- Shows a focus border around the active window.
- Provides keyboard-friendly CLI commands for BetterTouchTool, Karabiner, shell scripts, or any launcher.
- Persists stage membership and layout state across daemon restarts.
- Exposes state, health, metrics, events, and audit commands for debugging.
- Publishes JSONL automation events and stable `roadie query ...` JSON projections.
- Supports TOML window rules with validation, explain, runtime `rule.*` events, and automatic stage/display placement.
- Supports power-user layout commands such as `focus back-and-forth`, `layout insert`, `layout flatten`, and `layout zoom-parent`.
- Supports a persistent BSP tree and mutable BSP operations closer to yabai:
  move, warp, resize, insert, swap, and observed split-ratio preservation.
- Persists and exposes window groups for stack/tab-like workflows.
- Exposes Keyboard Targets for labels, search picking, JSON automation, target inspection, and experimental app-zone discovery.
- Provides two configurable spatial grids: Display Grid for full-screen recursive targeting, and Window Grid for recursive targeting inside the focused window.
- Records short mouse macros with target context and grid fallback.
- Provides safety tools: atomic config reload, manual restore snapshots, limited restore-on-exit/crash watcher, generated-file cleanup.
- Exposes read-only performance diagnostics without instrumenting focus/border hot paths.

## Documentation

Full documentation is available in English and French:

- [English documentation](docs/en/README.md)
- [Documentation francaise](docs/fr/README.md)

Main guides:

- [Feature overview](docs/en/features.md)
- [CLI commands](docs/en/cli.md)
- [Configuration and rules](docs/en/configuration-rules.md)
- [Events and Query API](docs/en/events-query.md)
- [Use cases](docs/en/use-cases.md)

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools. Full Xcode is not required.
- Accessibility permission for `roadied`.
- Screen Recording permission for `roadied`, only if you want real window thumbnails in the rail.
- Optional tools: `tmux` for the modular runtime, `create-dmg` to build the DMG.

Install Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

The project scripts use `/Applications/Xcode.app` when it exists. Otherwise they use the Command Line Tools reported by `xcode-select -p`. They also clean the shell environment of variables that may inject incompatible linker flags. If no Swift toolchain is found, the script stops and tells you to install the Command Line Tools.

## Build And Development Run

From the repository root:

```bash
make test
make dev-start
```

`make dev-start` is meant for development. It builds in debug mode, copies the binaries into `./bin` only, unloads the installed LaunchAgent, and runs the daemon in a `tmux` session. It does not touch the binaries installed by `make install`. In this mode, use `./bin/roadie` and grant Accessibility to `bin/roadied` in this folder. For daily use, install Roadie with `make install` instead.

**One launcher at a time.** `roadied run` and `roadied tiler` take an instance lock (`~/.roadies/roadied.lock`). A second instance exits with code 1. The LaunchAgent restarts a failed process (`KeepAlive`), so it would retry in a loop if a `tmux` session already runs the daemon. For this reason:

- `make dev-start` and `./scripts/start-modular` unload the LaunchAgent first;
- `make restart` never starts `tmux`, and it refuses to run while a development session exists. Run `make stop` first;
- to go back to the installed service, run `make stop`, then `make restart`.

## Manual Installation

For a local manual install from source, use:

```bash
make install
```

This hides the usual macOS service setup:

- builds `roadie` and `roadied` in release mode;
- installs the daemon as an app, `~/Applications/Roadie.app`, so macOS lists it as "Roadie" with its icon in the privacy settings;
- installs the `roadie` command in `~/.local/bin`, with a `~/.local/bin/roadied` link to the daemon inside the app. Both live outside the repository, so the service keeps working if you move or delete the source folder;
- signs the app and the command (see below);
- creates `~/Library/LaunchAgents/com.roadie.roadied.plist`, which starts the daemon from `Roadie.app`;
- starts the LaunchAgent when it is not already loaded.

Add `~/.local/bin` to your `PATH` so that you can type `roadie` in a terminal.

If Roadie is already running, `make install` does not stop it. Run this when you want the running daemon to reload the newly installed binaries:

```bash
make restart
```

`make restart` stops Roadie, then reloads the installed service through launchd. It also stops an instance opened directly as an application. It does not build anything. Reloading the service applies changes to the LaunchAgent too.

### Code signing and permissions

Grant Accessibility to **Roadie** in System Settings > Privacy & Security > Accessibility. macOS ties this permission to the code signature of the app. `make install` reuses the signing identity of the installed app. For a first install, it uses `roadied-cert` if that identity is available. Otherwise, it uses an ad hoc signature and prints a warning: macOS may forget the permission after a new build.

To choose a stable identity explicitly, use:

```bash
security find-identity -v -p codesigning
ROADIE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make install
```

If you only want to install files without starting the LaunchAgent:

```bash
ROADIE_INSTALL_NO_START=1 make install
```

Useful commands:

```bash
make test
make build
make install
make uninstall
make dev-start
make stop
make restart
make status
make logs
make doctor
make dmg
```

Equivalent direct commands:

```bash
./scripts/test
./scripts/start        # make dev-start
./scripts/stop
./scripts/status
./scripts/logs
./scripts/roadie daemon health
```

Logs are kept in `~/.roadies/`. At each start, the previous log is kept as `roadied.stdout.log.1` and `roadied.stderr.log.1`, so a crash stays readable after a restart.

## Uninstall

```bash
make uninstall
```

The script does these steps in order:

1. runs `roadie restore unhide-all` so that no window stays hidden or off screen;
2. stops the LaunchAgent (`launchctl bootout`);
3. deletes the LaunchAgent file and the binaries in `~/.local/bin`;
4. asks whether to keep Roadie state (`~/.roadies`, `~/.local/state/roadies`). Without a terminal, it keeps it.

The script never deletes your configuration in `~/.config/roadies`. Delete it by hand if you want. To finish, remove `roadied` from System Settings > Privacy & Security > Accessibility and Screen Recording.

## Modular Runtime

The classic path (`make install`, or `make dev-start` while developing) runs Roadie as one daemon. The modular path starts
the same capabilities as separate processes:

```bash
./scripts/start-modular
roadie query components
roadie daemon health
```

The standard modular script currently starts the full component set, including
the tiler. Its architectural purpose is broader: it lets Roadie evolve from a
single all-or-nothing window manager into a set of components that can also be
used as a companion layer beside yabai, AeroSpace, or another window manager.

Today, that companion-mode usage is intentionally described as experimental:
the runtime boundaries, component locks, health checks, and per-component logs
are in place, but explicit "stage-only" or "overlay-only" startup profiles are
still future work.

## DMG Build And Unsigned Installation

Roadie can be packaged as a classic macOS DMG:

```bash
make dmg
```

The output is:

```text
dist/Roadie.dmg
```

The DMG contains `Roadie.app` and an `/Applications` shortcut, so installation is the usual drag-and-drop flow.

Important: this build is ad hoc signed, not Developer ID signed, and not notarized. That means macOS Gatekeeper will not treat it like a fully trusted public app.

For users, the expected first-run flow is:

1. Drag `Roadie.app` to `/Applications`.
2. Open it once with right click > Open, then confirm. Roadie starts as a background menu-less app.
3. If macOS still blocks it, run:

```bash
xattr -dr com.apple.quarantine /Applications/Roadie.app
```

4. Grant permissions to `/Applications/Roadie.app` in System Settings > Privacy & Security:

- Accessibility.
- Screen Recording, if live nav rail thumbnails are wanted.

This limitation is normal until the app is signed with an Apple Developer ID certificate and notarized by Apple.

The DMG needs `create-dmg` (`brew install create-dmg`). The script checks its tools first and stops with a clear message if one is missing.

The app has no menu bar icon and no Dock icon. To quit it, quit `roadied` in Activity Monitor. To uninstall it, quit `roadied`, then drag `Roadie.app` to the Trash.

The packaged app currently starts Roadie for the current user session. A future signed installer can add a login item or LaunchAgent automatically; for now, startup-at-login is intentionally left explicit.

## Permissions

Roadie asks for two permissions. Both go to the `roadied` daemon.

| Permission | Used for | Required |
|---|---|---|
| Accessibility | Read and move windows | Yes |
| Screen Recording | Live window thumbnails in the rail | No. Without it, the rail shows app icons. |

After `make install`, add this binary in System Settings > Privacy & Security > Accessibility, and in Screen Recording if you want thumbnails:

```text
~/.local/bin/roadied
```

In the file picker, press Cmd+Shift+G and type the path, because `.local` is a hidden folder. Then restart the daemon:

```bash
make restart
```

### The `roadie` command needs no permission

When the daemon runs, the `roadie` command sends your request to it through a local socket (`~/.roadies/roadied.sock`). The daemon does the work with its own permissions. So BetterTouchTool, Karabiner, skhd, or a shell script that calls `roadie` does not need Accessibility permission. It also does not scan all windows for each key press, which makes shortcuts faster.

If the daemon is stopped, `roadie` runs the command itself. In that case, the program that started it (terminal, BetterTouchTool) needs Accessibility permission. Some commands always run locally: `daemon start|stop|restart|health`, `doctor`, `permissions`, and `config validate`.

Run `roadie doctor` to see the real state of the daemon, both permissions, and the validity of your configuration. The daemon publishes this state in `~/.roadies/daemon-status.json` (process id, version, permissions, configuration validity, update time), and `roadie doctor` reads that file. Doctor treats the daemon as stopped when its process is gone or when the file is more than 90 seconds old.

## Configuration

The user configuration file is:

```text
~/.config/roadies/roadies.toml
```

A commented example is in [`examples/roadies.toml`](examples/roadies.toml). Copy it as a starting point:

```bash
mkdir -p ~/.config/roadies
cp examples/roadies.toml ~/.config/roadies/roadies.toml
```

Validate it with:

```bash
roadie config validate
```

The validation reports each problem with its full key name. The messages are in French:

- `error  focus.stage_follows_focus  attendu booléen, reçu texte` means a value has the wrong type;
- `warning  tiling.gaps_inr  clé inconnue, ignorée ; vouliez-vous dire « gaps_inner » ?` means a typo, with the closest valid key;
- `warning  desktops.count  clé sans effet` means Roadie reads the key from the file but does not use it. This applies to the whole `[desktops]` table and to `enabled` and `hide_strategy` in `[stage_manager]`.

Shortcut examples for skhd and Karabiner-Elements are in `examples/skhd/skhdrc` and `examples/karabiner/roadie.json`. See [Shortcuts](docs/en/cli.md#shortcuts).

Inspect the loaded configuration:

```bash
roadie config show
```

Validate and inspect rules:

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

## Daily Use

Start or restart the daemon:

```bash
make restart
```

Check the runtime state:

```bash
roadie daemon health
roadie state audit
roadie metrics
roadie tree dump
```

List windows and displays:

```bash
roadie windows list
roadie display list
```

Switch layout mode for the current stage:

```bash
roadie mode spatialBsp   # alias: mutableBsp, yabai
roadie mode bsp
roadie mode masterStack
roadie mode float
```

Move focus or windows:

```bash
roadie focus left
roadie focus right
roadie focus back-and-forth
roadie move left
roadie warp right
roadie resize left
roadie display focus right
```

Move the focused window to another display:

```bash
roadie window display 2
```

## Stages

Stages are groups of windows. Only the active stage is visible; inactive stages are hidden and represented in the nav rail.

Common commands:

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
roadie stage reorder 2 1
roadie stage delete 4
roadie stage prev
roadie stage next
```

`stage switch` and `stage assign` target stable stage IDs. `stage switch-position`
and `stage assign-position` target the visible order in the nav rail, so position
1 is the first visible stage even if its internal ID is different.
`stage switch-visible prev|next` cycles through non-empty stages only, matching
the nav rail order. `stage assign-empty` sends the active window to the next
unnamed empty stage, creating one if needed.

Bring an inactive-stage window back into the active stage:

```bash
roadie stage summon WINDOW_ID
```

Move the active stage to another display:

```bash
roadie stage move-to-display 2
roadie stage move-to-display right
roadie stage move-to-display right --no-follow
```

Without a flag, Roadie uses `[focus].stage_move_follows_focus`. `--follow` and
`--no-follow` override that preference for one command. The nav rail also exposes
the same operation from a stage card context menu.

## Roadie Desktops

Roadie desktops are virtual desktops managed by Roadie. They do not create, switch, or control native macOS Spaces.

```bash
roadie desktop list
roadie desktop current
roadie desktop focus 2
roadie desktop focus next
roadie desktop focus prev
roadie desktop focus back
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
```

## Power-User Layout Commands

```bash
roadie layout split horizontal
roadie layout split vertical
roadie layout insert right
roadie layout join-with left
roadie layout flatten
roadie layout zoom-parent
```

These commands persist layout intent where applicable, so the maintainer does not immediately undo deliberate manual structure.

## Window Groups

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

Groups are persisted in Roadie's stage state and exposed through `roadie query groups`.

## Automation

Subscribe to live events:

```bash
roadie events subscribe --from-now --initial-state
```

Read stable JSON projections:

```bash
roadie query state
roadie query windows
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
```

Move the focused window to another Roadie desktop:

```bash
roadie window desktop 2
roadie window desktop 2 --follow
```

## Nav Rail

The nav rail is a native per-display side panel.

It shows non-empty stages, live thumbnails when available, fallback app icons when capture is unavailable, and a halo around the active stage.

Supported interactions:

- Click a stage thumbnail stack to switch stage.
- Empty rail clicks are inert by default, so a miss-click cannot hide the active stage. Set `empty_click_hide_active = true` only if you explicitly want empty rail space to switch to an empty stage.
- Drag a thumbnail to another stage to move that window there.
- Drag a thumbnail into the active workspace to summon it.
- Drag a thumbnail to an empty rail area to place it in an empty or newly created stage.
- Drag an application window by its title bar onto a stage to move it there.
- Drag an application window by its title bar onto empty rail space to place it in an empty or newly created stage.
- Use the chevrons above and below a stage to reorder stages.
- Clicks in macOS-reserved areas such as the menu bar are ignored by rail empty-click handling.

Rail rendering is configured in `~/.config/roadies/roadies.toml`.

By default, the rail hides in front of a window in native macOS fullscreen. To hide it in front of a maximized window too, set `hide_on_maximized = true` in `[fx.rail]`.

## Keyboard Targets, Display Grid, And Window Grid

Roadie exposes **Keyboard Targets**: short labels for windows, stages,
displays, desktops, bookmarks, and optional Accessibility application zones.
Targets can be searched, inspected, activated, and exported as JSON for scripts
or agents.

Roadie also provides two spatial grid modes:

- **Display Grid** targets a whole display.
- **Window Grid** targets the currently focused window.

Both grids use the same spatial language: type a cell label to zoom into that
cell, use `Space` to validate, arrows to move, and `Esc` to cancel. Short macro
recording can store the best target context plus a grid fallback.

```bash
roadie targets interactive --source all --include-app-targets
roadie grid interactive --scope display
roadie grid interactive --scope focused_window
roadie record start demo --duration 10
```

Risky surfaces are experimental and independently configurable through
`[experimental.target_mode]`, `[experimental.app_targets]`,
`[experimental.target_grid]`, and `[experimental.target_record]`.

## Troubleshooting

Run the quick health checks:

```bash
roadie daemon health
roadie state audit
roadie self-test
```

Repair conservative state issues:

```bash
roadie state heal
roadie daemon heal
```

Inspect logs and events:

```bash
make logs
roadie events tail 50
```

Get a full report on the daemon, the two permissions, and the configuration:

```bash
roadie doctor
roadied --version
```

`roadied --version` (and `roadie --version`) prints the version, which helps when you compare the installed binary with the running daemon.

If windows stay hidden or off screen (for example after a crash), bring them all back:

```bash
roadie restore unhide-all
```

If windows stop moving after a new install, check that `~/.local/bin/roadied` is still enabled in Accessibility (see [Code signing and permissions](#code-signing-and-permissions)), then restart:

```bash
make restart
```

The daemon restores hidden windows when it receives a stop signal (SIGTERM, SIGINT, SIGHUP) and a small watcher process does the same if the daemon crashes. To run the daemon without this safety, start it with `roadied run --yes --no-restore-safety`.

The previous run logs are in `~/.roadies/roadied.stderr.log.1` and `~/.roadies/roadied.stdout.log.1`.

## Repository Layout

```text
Sources/RoadieAX       Accessibility and system window snapshots
Sources/RoadieCore     Shared types, geometry, config
Sources/RoadieTiler    Pure layout strategies
Sources/RoadieStages   Persistent Roadie desktop and stage state
Sources/RoadieDaemon   Daemon services, rail, border, commands
Sources/roadie         CLI
Sources/roadied        Daemon entry point
Tests                  Unit tests
scripts                Build and runtime helpers
examples               Example config, skhd and Karabiner shortcuts
```

## Status

Roadie is built for personal daily use first. Expect changes in command shape, configuration keys, and rail behavior while the project stabilizes.
