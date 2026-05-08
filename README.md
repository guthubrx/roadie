<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="Roadie logo" width="128" height="128">
</div>

<div align="center">

# Roadie

**Work in progress. Expect rough edges, breaking changes, and missing polish.**

English | [Français](README.fr.md)

</div>

Roadie is a small macOS tiling window manager written in Swift, built around one idea: automatic tiling and a Stage Manager-like workflow should be able to live together.

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="Roadie multi-display screenshot" width="100%">
</p>

## Why This Project Exists

I never set out to write a window manager. For years, [yabai](https://github.com/koekeishiya/yabai) has been the foundation of my macOS workstation: sharp, powerful, and deeply influential for anyone who cares about tiling on macOS. Roadie owes a lot to yabai, both functionally and culturally.

The trigger was personal: I never managed to make yabai coexist cleanly with the Stage Manager workflow I wanted. I wanted named, hideable, restorable groups of windows, while still keeping automatic tiling for the visible windows.

So Roadie focuses on that specific combination:

- `bsp` and `masterStack` tiling for the visible windows.
- Roadie stages: named groups of windows that can be hidden, restored, reordered, and represented visually.
- Roadie virtual desktops managed without controlling native macOS Spaces.
- Multi-display support where each display keeps its own current desktop, active stage, and layout.

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

| Feature | yabai | AeroSpace | Roadie |
|---|---:|---:|---:|
| BSP tiling | yes | yes | yes |
| Master-stack layout | partial | yes | yes |
| Native macOS Spaces control | yes, with extra system setup | no | no |
| Virtual desktops without native Spaces | no | yes | yes |
| Named stages inside a desktop | no | no | yes |
| Stage rail with thumbnails | no | no | yes |
| Multi-display tiling | yes | yes | yes |
| Focus follows mouse | yes | yes | yes |
| Focus border overlay | no | no | yes |
| CLI-first operation | yes | yes | yes |

Roadie does not require disabling SIP. It uses Accessibility for window discovery and movement, and Screen Recording only for rail thumbnails.

## What Roadie Does Today

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
