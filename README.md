<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Roadie logo" width="128" height="128">

# Roadie

**A macOS window manager combining automatic tiling, named stages, and virtual desktops.**

English | [Français](README.fr.md)

</div>

Roadie is written in Swift. It groups windows into stages and tiles the active stage on each display. A native side panel, the **nav rail**, lets you switch stages and move windows with thumbnails.

**Status:** active development. Commands and configuration can still change. This README describes the current project, including the latest fixes to reactive tiling, cross-display drag and drop, the nav rail, display recovery, signing, and restart. Build from `main` to use this code.

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="Roadie desktop with tiling, nav rail, and CLI" width="100%">
</p>

## Why Roadie Exists

Roadie brings three ideas into one workflow:

- Automatic tiling inspired by [yabai](https://github.com/koekeishiya/yabai).
- Virtual desktops inspired by [AeroSpace](https://github.com/nikitabobko/AeroSpace).
- Named window groups inspired by Stage Manager.

Roadie desktops and stages belong to Roadie. They do not create or control native macOS Spaces. SIP stays enabled. Window movement uses Accessibility. A private read-only system probe helps identify native fullscreen transitions; Roadie does not use private APIs to write or switch Spaces.

## What Roadie Does Today

| Area | Current behavior |
|---|---|
| Tiling | Persistent `spatialBsp` tree, automatic `bsp`, `masterStack`, and `float` modes |
| Stages | Named window groups, hide/restore, reorder, summon, and move to another display |
| Desktops | Roadie virtual desktops with independent current desktop and active stage per display |
| Multiple displays | Independent layouts, parking on disconnect, and recovery on reconnect |
| Nav rail | Stage cards, live thumbnails or app icons, drag and drop, and window presentation state |
| Window tools | Focus border, focus follows mouse, title-bar context menu, window pins, bookmarks, and groups |
| Automation | CLI, JSON queries, JSONL events, TOML rules, and configuration reload |
| Safety | State backups, atomic persistence, hidden-window recovery, instance locks, and health checks |
| Optional modes | Keyboard Targets, application-zone discovery, display/window grids, and short macros |
| Runtime | One daemon for daily use, or separate modular components |

### Reactive Tiling And Drag And Drop

`spatialBsp` stores the layout as a persistent binary tree. The tree keeps the splits and their ratios. A new window splits the focused window along its longest side. Closing a window gives its space to its sibling. Temporarily absent windows keep their place in the stored tree without receiving placements.

Accessibility and application events trigger layout updates. Roadie groups bursts of events and ignores echoes of its own placements. It also keeps a periodic safety check. It holds layout writes while you drag a window, then applies the drop.

- On the same display, within the same stage, a drop on a window center swaps the two positions. A drop on an edge inserts on that side.
- Between displays, the preview follows the pointer. A center drop inserts to the right of the target; an edge drop inserts on that edge. An empty tiled stage can also receive the window.
- A swapped window takes the destination cell. If an application refuses a small size, Roadie adjusts the affected splits to respect its minimum size. A wide minimum can make the result look balanced instead of giving the other window the full original width.
- Reconnecting a display preserves the last useful visible positions. Old saved members alone do not create visible window cards in the rail.

`mutableBsp` and `yabai` remain aliases of `spatialBsp`. Existing `mutableBsp` stages migrate once. Roadie saves the previous state as `stages.json.pre-017` in its local state directory.

Use `move`, `warp`, `resize`, `window swap`, `layout split`, and `layout toggle-split` to edit the tree. In this mode, `layout insert` and `layout join-with` are rejected: use `warp`. `layout width` is also rejected: use `resize`. `layout flatten` balances the existing tree; it does not rebuild it from window positions.

### Stages, Desktops, And The Nav Rail

Only the active stage of the current Roadie desktop is shown on each display. Other stages stay hidden and remain accessible through the nav rail. You can drag a thumbnail between stages, summon it into the active workspace, or move a whole stage to another display.

The rail distinguishes normal, maximized, and native fullscreen windows. It hides over native fullscreen by default. Hiding over maximized windows is configurable. Screen Recording enables live thumbnails; without it, app icons remain available.

When a display disconnects, Roadie parks its non-empty stages on a remaining display. It keeps their origin so they can return when the display is recognized safely. Pins keep selected windows visible across stage changes. Bookmarks let you return to a selected window. Persistent groups provide a narrower stack-like workflow.

### Stabilization And Recovery

The daemon caches shared window snapshots and keeps state mutations under a single file lock. Changed state is written atomically. Invalid files are preserved for diagnosis. Configuration reload keeps the last valid configuration if the replacement is invalid.

Commands normally reach the daemon through a local Unix socket. The daemon uses its own macOS permissions. Health queries, event logs, state audits, and read-only performance summaries help diagnose problems.

`make restart` now stops an instance opened directly as an app as well as the installed service. Installation preserves the exact existing signing certificate when available, which helps retain Accessibility permission. Shutdown and the crash watcher restore hidden windows.

### Optional And Experimental Features

Keyboard Targets provide labels, search, inspection, activation, and JSON output. Application-zone discovery, recursive Display Grid and Window Grid, and short mouse macro recording are experimental. Each has a separate configuration gate.

The modular runtime splits `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, and `target-mode` into separate processes. The standard modular launcher starts the full set. Using Roadie as a stage-only or overlay-only companion to another window manager still needs dedicated startup profiles.

Native Spaces management, built-in global shortcut bindings, and a notarized public installer remain outside the current scope. Some listed CLI commands, such as `window close` and `toggle floating`, explicitly report that they are not implemented. The abandoned pin-popover redesign is not part of the delivered features.

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

Historical notes: [v0.3.0 archive](docs/releases/v0.3.0.md). These notes describe an earlier version of the project.

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

`make restart` stops Roadie, then reloads the installed service through launchd. It also stops an instance opened directly as an application. Startup checks that launchd and the daemon PID file identify the same live process. It does not build anything. Reloading the service applies changes to the LaunchAgent too.

After an update, run `make install`, then `make restart`, then `roadie query health`. If a development tmux session is running, use `make stop` first.

### Code signing and permissions

Grant Accessibility to **Roadie** in System Settings > Privacy & Security > Accessibility. macOS ties this permission to the code signature of the app. `make install` reuses the exact certificate of the installed app when its fingerprint is available. If that certificate is missing from the keychain, installation stops before replacing the app. A certificate with the same name is not enough. An explicit `ROADIE_CODESIGN_IDENTITY` overrides this choice. For a first install, it uses `roadied-cert` if that identity is available. Otherwise, it uses an ad hoc signature and prints a warning: macOS may forget the permission after a new build.

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
./scripts/roadie query health
```

Logs are kept in `~/.roadies/`. At each start, the previous log is kept as `roadied.stdout.log.1` and `roadied.stderr.log.1`, so a crash stays readable after a restart.

## Uninstall

```bash
make uninstall
```

The script does these steps in order:

1. runs `roadie restore unhide-all` so that no window stays hidden or off screen;
2. stops the LaunchAgent (`launchctl bootout`);
3. deletes the LaunchAgent file, `~/Applications/Roadie.app`, and the binaries in `~/.local/bin`;
4. asks whether to keep Roadie state (`~/.roadies`, `~/.local/state/roadies`). Without a terminal, it keeps it.

The script never deletes your configuration in `~/.config/roadies`. Delete it by hand if you want. To finish, remove Roadie from System Settings > Privacy & Security > Accessibility and Screen Recording.

## Modular Runtime

The classic path (`make install`, or `make dev-start` while developing) runs Roadie as one daemon. The modular path starts
the same capabilities as separate processes:

```bash
./scripts/start-modular
roadie query components
roadie query health
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

After `make install`, grant permissions to **Roadie**, the installed app in `~/Applications/Roadie.app`. The `~/.local/bin/roadied` command links to its daemon. In the file picker, use Cmd+Shift+G to open the app location. Then restart and check the daemon:

```bash
make restart
roadie query health
```

### The `roadie` command needs no permission

When the daemon runs, the `roadie` command sends your request to it through a local socket (`~/.roadies/roadied.sock`). The daemon does the work with its own permissions. So BetterTouchTool, Karabiner, skhd, or a shell script that calls `roadie` does not need Accessibility permission. It also does not scan all windows for each key press, which makes shortcuts faster.

If the daemon is stopped, `roadie` runs the command itself. In that case, the program that started it (terminal, BetterTouchTool) needs Accessibility permission. Some commands always run locally: `daemon start|stop|restart|health`, `doctor`, `permissions`, and `config validate`.

Use `roadie query health` to check the running daemon with its own permissions. `roadie doctor` also reads the daemon status and checks configuration. Local `doctor` and `daemon health` checks can scan windows with the terminal’s permissions. A local empty scan does not mean the daemon sees no windows. The daemon publishes this state in `~/.roadies/daemon-status.json` (process id, version, permissions, configuration validity, update time), and `roadie doctor` reads that file. Doctor treats the daemon as stopped when its process is gone or when the file is more than 90 seconds old.

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
roadie query health
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
roadie layout toggle-split
roadie warp right
roadie layout flatten
roadie layout zoom-parent
```

In `spatialBsp`, these commands modify the stored tree or its zoom state. Use `warp` for insertion and `resize` for size changes. The legacy `layout insert`, `layout join-with`, and `layout width` commands are unavailable in tree mode. They remain available where supported by the other layout modes.

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
roadie query health
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

If windows stop moving after a new install, check that Roadie is still enabled in Accessibility (see [Code signing and permissions](#code-signing-and-permissions)), then restart:

```bash
make restart
```

The daemon restores hidden windows when it receives a stop signal (SIGTERM, SIGINT, SIGHUP) and a small watcher process does the same if the daemon crashes. To run the daemon without this safety, start it with `roadied run --yes --no-restore-safety`.

The previous run logs are in `~/.roadies/roadied.stderr.log.1` and `~/.roadies/roadied.stdout.log.1`.

## Privacy

Roadie runs locally. The current application sources have no telemetry or remote upload service. CLI commands communicate with the daemon through a local Unix socket. Screen Recording is optional and is used for window thumbnails.

Local state and diagnostic output can contain window titles, application names, display identifiers, window positions, and event history. Recorded macros can include target context. Treat configuration, state backups, logs, query exports, macros, and desktop screenshots as private. Review and redact them before sharing an issue or committing files.

The repository contains source code and example/test data. Local runtime folders, environment files, signing keys, and machine-specific SpecKit metadata are excluded from Git. Review screenshots before publication. Repository checks cannot remove data from older commits or copies already downloaded.

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
