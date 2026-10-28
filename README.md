<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Roadie logo" width="128" height="128">

# Roadie

**A macOS window manager combining automatic tiling, named stages, and virtual desktops.**

English | [Français](README.fr.md)

</div>

Roadie organizes your windows around your activities. Bring a project's apps
together, find them in the side rail and switch workspaces on each display.

**[Download Roadie 0.10.0](https://github.com/guthubrx/roadie/releases/tag/v0.10.0)** ·
[What's new](docs/releases/v0.10.0.en.md) · [Installation guide](#manual-installation)

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="Roadie workspaces across multiple displays" width="100%">
</p>

## A workspace for every activity

An editor, a terminal and a browser for development. Documents for writing.
A meeting window to keep close at hand. Roadie brings these windows into
**stages**: named groups you can reach from the rail.

The project combines tiling inspired by [yabai](https://github.com/koekeishiya/yabai),
virtual desktops inspired by [AeroSpace](https://github.com/nikitabobko/AeroSpace)
and Stage Manager's window groups.

## What you can do with Roadie

| Your goal | Feature |
|---|---|
| Arrange windows | Automatic tiling, multiple layouts and divider handles in persistent tree layouts |
| Switch projects | Named stages, previews and workspace switching from the rail |
| Use multiple displays | Independent desktops, new windows on the active display by default, window and stage transfers |
| Keep a window within reach | Pins, bookmarks and window groups |
| Work from the keyboard | Labels, grids and the search and command bar |
| Personalize the interface | Live settings, independent sizes and font choices |
| Automate routine actions | Placement rules, short macros, commands and a JSON API |

### A layout that follows your work

Roadie arranges windows and adjusts their space as you open or close them.
Choose a balanced layout, a main window beside its neighbors, or free placement.

Rearrange windows by dragging: drop in the center to swap positions, or on an
edge to insert on that side. You can also adjust proportions from the keyboard
or drag divider handles between window groups. Control their visibility in Tiling settings.
Maximization keeps the rail within reach and lets you return to the previous layout.

[Explore layouts and gestures](docs/en/features.md)

### Keep your projects in view

The rail shows each display's stages with thumbnails or app icons. Switch
stages, bring a window into the active workspace or move an entire stage to
another display. Keep your chosen order and preview stage positions as you
rearrange them. [Arrange stages and drop windows](#nav-rail).

Floating mode takes a window out of tiling within its stage. Pins keep a window
visible as you change stages. Bookmarks let you return to a chosen window.
Your stages and settings are saved between sessions.

When a display reconnects, its stages return to their places. A stage explicitly
moved to another display stays there. Named empty stages keep an outline and name;
destination menus follow the rail order.

### One bar to search and act

Open the **search and command bar** with your chosen shortcut. Type a few letters
to find a visible window, stage or element. Tab completes the selection; a leading `/` opens
Roadie's commands.

For example, `/stage dev` switches activities and `/settings` opens settings.
Suggestions and history help you enter commands. Set the shortcut in the
**Recherche** (Search) settings category; `roadie targets search` also opens the bar.

### Make it your own

The **window switcher** opens a selected window in its own Roadie desktop and
stage. In Réglages Roadie > Sélecteur, create profiles for a display, desktop, stage or
application. Record a shortcut directly, let BetterTouchTool manage it, or use an
external CLI binding. Choose whether releasing the keys activates the selection,
keeps the switcher open or starts search. Navigate with the four arrow keys or
the mouse, and give each profile its own appearance. Organize windows into stage
columns, desktop tabs, a hierarchy, grouped sections or desktop overviews.
The classic grid remains available.
[Window switcher guide](docs/en/window-switcher.md).

The **global overview** shows every window on a single page, by display and
desktop, in Archipelago or Bays layout, over your blurred wallpaper. The
magnifier enlarges the hovered desktop by 100–250%. Open it with
`roadie overview show`, a BTT gesture (a four-finger upward swipe, for example)
or an optional shortcut. Drag a chip to reorder desktops or move a stage, and
drag a card to send a window to another stage, with a live preview of the result. [Overview guide](docs/en/overview.md).


Settings are grouped by purpose, with aligned controls and scrollable help.
Expand individual rules as needed; switcher tabs span the full available width.
Adjust spacing, stage names, rules and overrides
in the settings window.
Valid values apply as you type. Choose separate sizes for the rail, labels
and settings, and font families for the search field and its suggestions.

Keyboard labels let you select an element by typing its letters. Display and window
grids let you choose a precise area. Short macros record mouse actions to repeat.
Enable the tools that suit the way you work.

[See the features](docs/en/features.md) · [Everyday examples](docs/en/use-cases.md)

## Documentation

Full documentation is available in English and French:

- [English documentation](docs/en/README.md)
- [Documentation française](docs/fr/README.md)

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
2. stops the LaunchAgent, modular components, and standalone instances; if a process refuses to stop, it keeps the installed files;
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

The standard modular launcher starts all components, including the tiler.
Each component has its own logs and health status. Use this mode when you want
to observe the services separately.

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
unnamed empty stage, creating one if needed. A stage name is unique across Roadie:
`stage rename` refuses a name already used by another stage, and
`roadie state heal` fixes inherited duplicates. `stage delete` removes an inactive
stage without windows, named or not; the closed windows it still remembered go with it.

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
roadie desktop move 2 1
```

`desktop move` places a desktop at another position and renumbers desktops, as in
Mission Control. The overview does the same by drag and drop, including to another
display.

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

Roadie fullscreen (`roadie toggle fullscreen`) fills the visible area and hides
the rail, including on hover, without entering native macOS fullscreen. Repeat
the command to restore the layout. Maximization (`roadie toggle maximize`) keeps
the rail accessible. Outside fullscreen, `[fx.rail]` with `auto_hide = true` gives
the rail Dock-like behavior: hover over the left edge to reveal it.

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
- Drag a stage with the right mouse button to reorder stages. A translucent preview shows its destination, while neighboring cards show the new order. Release to apply it, or move outside the rail before releasing to cancel.
- Right-click a stage without dragging to open its menu: rename the stage, send the stage to another display, send a window to another stage, or delete the stage once it has no window.
- Clicks in macOS-reserved areas such as the menu bar are ignored by rail empty-click handling.

Adjust the strength in **Réglages Roadie > Rail > Aimantation du réordonnancement (%)**. At 0, snapping is disabled; higher values keep the preview at its destination through small pointer movements.

Rail rendering is configured in `~/.config/roadies/roadies.toml`.

By default, the rail hides in front of a window in native macOS fullscreen. To hide it in front of a maximized window too, set `hide_on_maximized = true` in `[fx.rail]`.

## Keyboard Targets, Display Grid, And Window Grid

Roadie exposes **Keyboard Targets**: short labels for windows, stages,
displays, desktops, bookmarks, and optional Accessibility application zones.
Targets can be searched, inspected, activated, and exported as JSON for scripts
or agents.

**Search mode** (`Cmd+Ctrl+Option+F` by default, configured by `search_hotkey`) opens an input bar: type a
few letters of any element in any visible window, then press Return to click it
(Shift-Return right-click, Cmd-Return Cmd-click, Return twice double-click).

`Tab` completes the selected result's title without clicking it. Arrow keys and
Ctrl-N/Ctrl-P change results. The bar keeps its position and width on the opening display, with a count
chip on the right, a thin border, and a proportional font.

### Command box and settings window

A leading `/` switches the bar to **command mode**. Suggestions complete commands,
directions, stages, bookmarks, and settings. `Tab` inserts the selected suggestion;
subsequent Tab presses cycle through alternatives. Arrow
keys navigate history. `Return` runs a command; `Esc` closes the
bar. System shortcuts remain intercepted while entering a command.

| Action | Example |
|---|---|
| Move the window | `/move left` |
| Swap windows | `/swap right` |
| Switch stage | `/stage 2` or `/stage Work` |
| Switch display | `/screen right` |
| Send the window to a display | `/send 2` |
| Open settings | `/settings` |
| Read or change a setting | `/set target_mode.label_font_size 20` |
| Restore its default | `/set target_mode.label_font_size default` |
| Diagnose or reload | `/doctor`, `/heal`, `/reload` |

The settings window provides categories, search, and changes as soon as a typed
value is valid. Margins trigger a new layout, including one-point changes. Lists,
stages, rules and per-display overrides have built-in editors. Incomplete input
stays in the field without replacing the last valid value.
The interface is in French. TOML comments are preserved.
A backup precedes the first change of the session. Invalid writes are
rejected. Font sizes are independent and apply immediately through sliders,
steppers, or valid typed values. Open sessions retain their input when fonts change.

| Surface | Setting IDs |
|---|---|
| Settings: text, help, titles | `interface.settings_text_font_size`, `interface.settings_help_font_size`, `interface.settings_title_font_size` |
| Letter labels | `target_mode.label_font_size` |
| Grid labels | `target_grid.label_font_size` |
| Search labels, input, command suggestions | `target_mode.search_label_font_size`, `target_mode.search_text_font_size`, `target_mode.command_text_font_size` |
| Rail display, desktop, stage text | `rail.header.display.font_size`, `rail.header.desktop.font_size`, `rail.stage_labels.font_size` |

For example, `/set interface.settings_text_font_size 20` updates the settings window.
The settings text, help and title defaults are 16, 14 and 22 points. Letters,
grid and search labels default to 13 points. Rail cards adapt their size to the font.
Native macOS tooltips and system dialog messages keep their system font.

Search input and command suggestions have independent font families:
`target_mode.search_font_family` and `target_mode.command_font_family`. Changes
appear in the open bar. `system` selects the macOS font; missing families fall
back to it. Rare complex fragments use a built-in advanced editor with validation
and explicit saving. `signals.hooks` can be stored but are not currently executed
by Roadie. An invalid file can be repaired inside the settings window.
Rule actions `layout` and `gap_override` are stored but do not yet change tiling.
Their editors display this limitation.

The bar and settings require a running daemon and `overlay_enabled = true`.
In the existing configuration table, enable at least:

```toml
[experimental.target_mode]
overlay_enabled = true
search_hotkey = "command+control+alt+f"
```

To discover and click application elements, also enable
`[experimental.app_targets].enabled = true` and
`[experimental.target_mode].app_mouse_actions_enabled = true`. Commands and
settings work without enabling application clicks.

See [the command catalog and limits](docs/en/features.md#command-mode--and-settings-window).

### Display and window grids

Roadie also provides two spatial grid modes:

- **Display Grid** targets a whole display.
- **Window Grid** targets the currently focused window.

Both grids use the same spatial language: type a cell label to zoom into that
cell, use `Space` to validate, arrows to move, and `Esc` to cancel. Short macro
recording can store the best target context plus a grid fallback.

```bash
roadie targets interactive --source all --include-app-targets
roadie targets search
roadie grid interactive --scope display
roadie grid interactive --scope focused_window
roadie record start demo --duration 10
```

These tools can be enabled independently through
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

Development continues on `main`. Follow the [release notes](https://github.com/guthubrx/roadie/releases) for new features and update instructions.
