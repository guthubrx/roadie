# Roadie

English | [Français](README.fr.md)

Roadie is a small macOS tiling window manager written in Swift.

It combines automatic window tiling with a built-in stage manager: windows are grouped into stages, stages can be switched or hidden, and each display keeps its own current desktop, active stage, and layout.

Roadie is currently a work in progress. It is usable, but still evolving quickly.

## What It Does

- Tiles visible windows with `bsp`, `masterStack`, or `float` modes.
- Keeps stage groups per display and Roadie desktop.
- Provides Roadie virtual desktops without controlling native macOS Spaces.
- Supports multiple displays independently.
- Shows a native side rail with stage thumbnails.
- Lets you drag thumbnails between stages or into the active workspace.
- Shows a focus border around the active window.
- Provides keyboard-friendly CLI commands for BetterTouchTool, Karabiner, shell scripts, or any launcher.
- Persists stage membership and layout state across daemon restarts.
- Exposes state, health, metrics, events, and audit commands for debugging.

## Requirements

- macOS.
- Xcode Command Line Tools.
- Accessibility permission for `roadied`.
- Screen Recording permission if you want real window thumbnails in the rail.

Install Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

## Build

From the repository root:

```bash
make test
make start
```

The project scripts force the Xcode toolchain and avoid shell environments that may inject incompatible linker flags.

Useful commands:

```bash
make test
make start
make stop
make restart
make status
make logs
make doctor
```

Equivalent direct commands:

```bash
./scripts/test
./scripts/start
./scripts/stop
./scripts/status
./scripts/logs
./scripts/roadie daemon health
```

## Permissions

Roadie needs Accessibility permission to read and move windows.

After building and starting the daemon, add this binary in System Settings > Privacy & Security > Accessibility:

```text
/Users/moi/Nextcloud/10.Scripts/39.roadie/bin/roadied
```

Then restart the daemon:

```bash
make restart
```

Screen Recording is optional but recommended. Without it, the nav rail may show fallback app icons instead of live thumbnails.

## Configuration

The user configuration file is:

```text
~/.config/roadies/roadies.toml
```

Validate it with:

```bash
./bin/roadie config validate
```

Inspect the loaded configuration:

```bash
./bin/roadie config show
```

## Daily Use

Start or restart the daemon:

```bash
make restart
```

Check the runtime state:

```bash
./bin/roadie daemon health
./bin/roadie state audit
./bin/roadie metrics
./bin/roadie tree dump
```

List windows and displays:

```bash
./bin/roadie windows list
./bin/roadie display list
```

Switch layout mode for the current stage:

```bash
./bin/roadie mode bsp
./bin/roadie mode masterStack
./bin/roadie mode float
```

Move focus or windows:

```bash
./bin/roadie focus left
./bin/roadie focus right
./bin/roadie move left
./bin/roadie warp right
./bin/roadie resize left
```

Move the focused window to another display:

```bash
./bin/roadie window display 2
```

## Stages

Stages are groups of windows. Only the active stage is visible; inactive stages are hidden and represented in the nav rail.

Common commands:

```bash
./bin/roadie stage list
./bin/roadie stage create 4
./bin/roadie stage rename 4 Comms
./bin/roadie stage switch 2
./bin/roadie stage assign 2
./bin/roadie stage reorder 2 1
./bin/roadie stage delete 4
./bin/roadie stage prev
./bin/roadie stage next
```

Bring an inactive-stage window back into the active stage:

```bash
./bin/roadie stage summon WINDOW_ID
```

## Roadie Desktops

Roadie desktops are virtual desktops managed by Roadie. They do not create, switch, or control native macOS Spaces.

```bash
./bin/roadie desktop list
./bin/roadie desktop current
./bin/roadie desktop focus 2
./bin/roadie desktop focus next
./bin/roadie desktop focus prev
./bin/roadie desktop focus back
./bin/roadie desktop label 2 DeepWork
```

Move the focused window to another Roadie desktop:

```bash
./bin/roadie window desktop 2
./bin/roadie window desktop 2 --follow
```

## Nav Rail

The nav rail is a native per-display side panel.

It shows non-empty stages, live thumbnails when available, fallback app icons when capture is unavailable, and a halo around the active stage.

Supported interactions:

- Click a stage thumbnail stack to switch stage.
- Click empty rail space to hide the active stage and switch to an empty stage.
- Drag a thumbnail to another stage to move that window there.
- Drag a thumbnail into the active workspace to summon it.
- Drag a thumbnail to an empty rail area to place it in an empty or newly created stage.
- Use the chevrons above and below a stage to reorder stages.

Rail rendering is configured in `~/.config/roadies/roadies.toml`.

## Troubleshooting

Run the quick health checks:

```bash
./bin/roadie daemon health
./bin/roadie state audit
./bin/roadie self-test
```

Repair conservative state issues:

```bash
./bin/roadie state heal
./bin/roadie daemon heal
```

Inspect logs and events:

```bash
make logs
./bin/roadie events tail 50
```

If windows stop moving after a rebuild, re-check Accessibility for `bin/roadied`, then restart:

```bash
make restart
```

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
```

## Status

Roadie is built for personal daily use first. Expect changes in command shape, configuration keys, and rail behavior while the project stabilizes.
