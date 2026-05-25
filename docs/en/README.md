# Roadie Documentation

English documentation for daily Roadie usage, configuration, and scripting integrations.

## Guides

- [Feature overview](features.md)
- [CLI commands](cli.md)
- [Configuration and rules](configuration-rules.md)
- [Events and Query API](events-query.md)
- [Use cases](use-cases.md)
- [v0.3.0 release notes](../releases/v0.3.0.md)

## Positioning

Roadie is a Swift macOS window manager combining:

- automatic `bsp`, `mutableBsp`, `masterStack`, and `float` tiling;
- named, hideable stages inspired by Stage Manager workflows;
- Roadie virtual desktops without controlling native macOS Spaces;
- display parking that keeps stages recoverable when a monitor is unplugged;
- a modular runtime that can split tiling, rail, borders, focus, target mode,
  title-bar actions, and restore safety into separate components;
- CLI commands for BetterTouchTool, Karabiner, shell scripts, or launchers;
- automation surfaces: events, rules, groups, query API, Keyboard Targets,
  Display Grid, Window Grid, and short macro recording.

Roadie keeps SIP enabled and does not use OSAX/SkyLight to control native Spaces.
