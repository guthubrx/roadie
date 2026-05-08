# Product And Architecture Direction

## Goal

Build a reliable macOS tiling window manager with a first-class stage manager.

The implementation must be boring, small, testable, and maintainable. The previous prototype failed partly because too much compatibility code hid broken production paths. This rewrite must not repeat that.

## Non-Negotiables

- Stage manager is core product functionality.
- Roadie virtual desktops are core product functionality.
- Window management mode is switchable by scope: BSP tiling, master-stack, or float.
- Focused-window border is core WM feedback, not decorative polish.
- Stage rail is a real product concept, but it comes after the core WM is reliable.
- CLI and machine-readable observability are core engineering surfaces, not afterthoughts.
- No code copied from the archived project.
- No production stubs.
- No silent no-op paths.
- No large compatibility layer.
- No feature before the previous layer has a working vertical slice.
- Prefer explicit state and typed boundaries over convenience bridges.

## Technical Bias

Prefer AeroSpace-inspired choices when applicable:

- Virtual workspaces/stages by hiding and restoring windows rather than controlling native Spaces.
- N-ary layout tree with adaptive weights rather than a strict binary BSP-only model.
- Swift-native design with small modules and explicit ownership.
- AX-driven window observation and manipulation without SIP-off dependencies.

Use yabai primarily as a reference for proven low-level macOS window-manager behavior, not as the main architecture.

## First Architecture Shape

Core modules, to be created only when implementation starts:

- `RoadieCore`: shared types, logging, config, platform abstractions.
- `RoadieAX`: Accessibility wrappers, observers, window discovery, frame read/write.
- `RoadieTiler`: pure layout tree and layout calculations, no AppKit side effects.
- `RoadieStages`: stage ownership, active stage per display, hide/restore policy.
- `roadied`: daemon orchestration.
- `roadie`: CLI client.

## Stage Manager Model

A stage is a named group of windows scoped by display and virtual desktop.

Initial model:

- `StageScope = displayUUID + desktopID + stageID`
- `Stage` owns an ordered set of window IDs.
- One active stage per display/desktop.
- Active stage is remembered independently for every `(displayUUID, desktopID)`.
- Switching stage hides windows from the old stage and restores/layouts windows from the new stage.
- Hidden windows are moved offscreen first. Native minimize is optional later.
- Stage ownership is single-source-of-truth state. Derived window indexes are rebuildable and auditable.
- A stage may have UI ordering separate from its stable ID, because rail position and stable identity are different concerns.

## Virtual Desktop Model

Roadie does not drive macOS Spaces. Roadie owns its own virtual desktops inside one native macOS Space.

Initial model:

- `RoadieDesktop` is scoped per display unless explicitly configured otherwise.
- Each display has a current desktop ID.
- Switching desktop hides all windows from the outgoing desktop and restores the incoming desktop.
- Each desktop has its own set of stages.
- Desktop switching must restore both window membership and focused/active stage.
- Back-and-forth switching is expected.
- Desktop labels are expected.
- Moving a window to another display must adopt the target display's current Roadie desktop.

## Tiling Model

Initial model:

- One layout tree per active stage scope.
- `Workspace` owns one root `TilingContainer`.
- `TilingContainer` is N-ary and has an orientation.
- `WindowLeaf` represents one tileable window.
- `WindowManagementMode` is chosen per scope and can be changed at runtime:
  - `bsp`: recursive split tiling.
  - `masterStack`: master area plus stack area.
  - `float`: Roadie does not tile that scope; windows keep user frames.
- Layout calculation is pure and testable.
- Applying layout to macOS is a separate flush step.
- Manual resize updates weights from the actual AX frame.
- If an application clamps a requested frame, Roadie must detect and absorb the real frame instead of fighting the app.
- Cross-display layout writes must be isolated: changing one display must not rewrite unrelated displays.

Mandatory invariant:

- Applying the same layout twice without state changes must produce no second AX writes.
- The core tiler must not contain compatibility stubs. A missing operation fails explicitly until implemented.

## Focus, Mouse, And Visual Feedback

Expected behavior:

- Click-to-raise.
- Focus follows mouse, configurable.
- Mouse follows focus, configurable.
- Focus restoration on stage and desktop switch.
- Mouse modifier drag and resize for floating windows.
- Drag-to-adapt for tiled windows.
- Cross-display drag for tiled windows.
- Focused-window border using a SIP-safe overlay.

Border configuration is part of the functional surface:

- enabled/disabled.
- thickness.
- corner radius.
- active/inactive colors.
- focused-only mode.
- optional stage-specific active colors.

## Rail Model

The rail is implemented in `roadied` as a native per-display overlay.

Current rail capabilities:

- One rail per display.
- Non-DRM stage thumbnails with degraded fallback when capture fails.
- Active-stage halo.
- Renderer variants configured from `~/.config/roadies/roadies.toml`: stacked, mosaic, parallax, icons.
- Stage reorder via explicit chevrons above and below the thumbnail stack.
- Window summon/move via explicit thumbnail controls.
- Drag a thumbnail to another visible stage to move that window there.
- Drag a thumbnail to an empty rail area to move it to the first empty stage, or create a new stage if none is available.
- Drag feedback uses a non-interactive thumbnail ghost that follows the cursor.

The rail intentionally does not own window-management policy. It calls the same stage commands as the CLI so state audit, heal, layout maintenance, and keyboard shortcuts keep one source of truth.

## Observability Model

The daemon must be inspectable from the beginning.

Minimum surfaces:

- Human-readable and JSON CLI output.
- `windows`, `display`, `desktop`, `stage`, `tree`, `state`, `config`, `metrics`, `diag`, `daemon health`, `daemon audit`, `daemon heal`.
- Event stream for `desktop_changed`, `stage_changed`, window assignment, focus, and config reload.
- Structured logs for layout writes, skipped writes, clamp detection, stage/desktop switches, and ownership audits.
- Self-test must verify permissions, observers, state consistency, and daemon health.

## Power-User Model

Retained functional ideas, after the core is stable:

- Scratchpad toggle groups.
- Sticky cross-stage windows.
- Rules engine for app/title matching: float, tile, sticky, assign stage, assign desktop, assign display, gaps.
- Signal hooks for shell commands on events.
- BetterTouchTool-friendly command grammar.
- SketchyBar/top-bar integration.

## Implementation Order

1. Define product-level data types: display, desktop, stage, window, mode.
2. Define pure state transitions for desktop switch and stage switch.
3. Define pure layout strategies: BSP, master-stack, float.
4. Build layout calculation and idempotence tests, still without AX.
5. Add AX window read/write as a narrow adapter.
6. Build a daemon that tiles current windows on one display.
7. Add stage ownership and stage switching.
8. Add Roadie virtual desktop switching.
9. Add multi-display.
10. Add focused-window border overlay.
11. Add CLI observability.
12. Only then consider rail UI, thumbnails, advanced commands, and visual effects.

## Success Criteria For The First Useful Version

- Start daemon.
- Detect tileable windows.
- Tile windows on one display.
- Switch between at least two stages.
- Switch between at least two Roadie desktops.
- Change a scope between BSP, master-stack, and float.
- Hide old-stage windows and restore new-stage windows.
- Show a focused-window border.
- CLI can show windows, stages, and tree state.
- Restart preserves stage membership.

## Explicitly Deferred

- Rail UI.
- Animations.
- Blur/opacity/shadow effects.
- SketchyBar integration.
- Native Space manipulation.
- Full yabai command parity.
