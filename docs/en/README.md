# Roadie Documentation

English guides for the current `main` sources. The [root README](../../README.md) covers setup, permissions, daily commands, and privacy. [Français](../fr/README.md).

## Guides

- [Feature overview](features.md)
- [CLI commands](cli.md)
- [Desktop and stage overview](overview.md)
- [Window switcher](window-switcher.md)
- [Configuration and rules](configuration-rules.md)
- [Events and Query API](events-query.md)
- [Use cases](use-cases.md)
- [Release notes 0.7.0](../releases/v0.7.0.en.md)

`roadie toggle maximize` enlarges the active window while keeping the visible nav rail strip clear. Run it again to restore the layout. Siblings in the same stage are hidden while maximized. Activating another window in that stage restores the layout directly. Switching stages preserves the saved zoom. With auto-hide enabled, a hidden rail frees the entire visible area, just like Roadie fullscreen. When the rail returns on hover or with `roadie rail pin`, the window resizes to make room without leaving maximized mode. The enabled title-bar menu also offers “Fenêtre → Maximiser / restaurer (garder le navrail)”.

`roadie toggle fullscreen` uses the entire visible area and hides the rail, including on hover, without entering macOS fullscreen. `roadie toggle native-fullscreen` uses macOS fullscreen. Switching between the two Roadie zoom modes preserves the original layout; repeating the active mode restores it.

## Current Capabilities

Roadie combines automatic tiling, named stages, and Roadie virtual desktops. Each display keeps its own current desktop, active stage, and layout. It keeps SIP enabled and does not control native macOS Spaces.

- **Reactive tiling:** `spatialBsp` stores an authoritative binary tree. Events update its layout; temporary absences keep their stored places. `mutableBsp` and `yabai` are compatibility aliases. `bsp`, `masterStack`, and `float` remain available.
- **Drag and drop:** same-stage center drops swap windows; edge drops insert them. Cross-display previews follow the pointer, including empty tiled stages. Application minimum sizes can limit the final proportions.
- **Display recovery:** stages are parked when a screen disconnects. Reconnecting preserves useful visible positions and excludes stale window references from visible rail cards.
- **Nav rail:** your chosen order, a reorder preview and adjustable magnetism. Drop onto a card to join it or between cards to create a stage there. The list scrolls and named empty stages remain identifiable.
- **Window switcher:** returns to a window in its desktop, stage and display. Search, arrow keys, mouse navigation and configurable profiles; shortcuts managed by Roadie, BetterTouchTool or an external tool.
- **Window tools:** focus border, focus follows mouse, optional title-bar actions, pins, bookmarks, and persistent groups.
- **Reliable runtime:** local command socket, atomic state writes, shared snapshots, validated configuration reload, hidden-window recovery, and daemon health queries.
- **Automation:** CLI, TOML rules, JSON queries, JSONL events, and read-only performance diagnostics.
- **Command box and settings:** a leading `/` in search, Tab completion and history. `/settings` offers live input, list, stage and rule editors, and independent typography. `/set` also reads, changes or resets a value.
- **Keyboard navigation and visual tools:** target labels, search across visible windows, controls exposed by applications, display/window grids, and short macros.
- **Modular execution:** separate tiler, rail, border, focus, title-bar, and target processes. Dedicated companion-only startup profiles remain future work.

## Update And Check

From the source checkout:

```bash
make install
make restart
roadie query health
```

If a development tmux session is running, use `make stop` first. Installation preserves the existing signing certificate when possible. If the required certificate is missing, it stops before replacing the app.

In `spatialBsp`, use `warp` instead of `layout insert` or `layout join-with`, and `resize` instead of `layout width`. `layout flatten` balances the stored tree.

## Privacy

The application runs locally, with no telemetry or remote upload service in the current sources. State, logs, macros, query exports, and screenshots can still contain window titles or other private data. Review and redact them before sharing. See [Privacy](../../README.md#privacy).
