# Functional Inventory From The Archived Project

This is a functional inventory only. It captures product ideas from `../39.roadie.old` without reusing its implementation.

## P0: Core Product

- `Stage manager`: named groups of windows, scoped by display and Roadie desktop.
- `Roadie virtual desktops`: no macOS Space control; hide/restore windows ourselves.
- `Multi-display`: each physical display has independent current desktop, active stage, and layout state.
- `Window management modes`: each scope can run `bsp`, `masterStack`, or `float`.
- `Mode switching`: user can change the active scope's mode at runtime without corrupting membership.
- `Focused border`: visible border around the focused window using a SIP-safe overlay.
- `AX-only control`: window discovery and movement through Accessibility, no SkyLight write path.
- `Persistence`: desktop/stage membership survives daemon restart.
- `CLI`: enough commands to inspect and operate the WM without a GUI.
- `No fake implementation`: no compatibility-only stubs, no documented no-op pretending to support a command.

## P1: Tiling And Window Operations

- BSP tiling.
- Master-stack layout.
- Floating mode, both per-window and per-scope.
- Smart gaps when a scope has a single tiled window.
- Configurable outer and inner gaps.
- Per-display layout config.
- Manual resize adapts layout weights.
- Clamp handling: if an app refuses a requested size, absorb actual size into state.
- Idempotent layout flush: no repeated AX writes when nothing changed.
- Move focus by direction.
- Move window by direction.
- Warp window across displays/scopes.
- Swap windows.
- Insert direction for the next window.
- Balance tree.
- Rotate/mirror tree eventually, but not before the base engine is stable.

## P1: Stage And Desktop Operations

- Create, delete, rename, list stages.
- Switch/focus stage.
- Assign a window to a stage.
- Reorder stages.
- Hide active stage.
- Create/list/switch Roadie desktops.
- Back-and-forth desktop switching.
- Desktop labels.
- Preserve active stage per `(display, desktop)`.
- Resolve stage by stable ID and by visible rail position, because shortcuts often target what the user sees.
- Keep stage membership as the source of truth; inverse window indexes are derived and auditable.
- Archive or ignore legacy state instead of letting old files pollute a new session.
- Sticky cross-stage rules: selected apps/windows can appear across stages.
- Scratchpad: special toggleable window group.

## P1: Focus And Mouse

- Click-to-raise.
- Universal click-to-raise must avoid stealing modifier drags.
- Focus follows mouse.
- Mouse follows focus for keyboard-driven focus changes.
- Focus restoration on stage and desktop switch.
- Mouse modifier drag/resize for floating windows.
- Drag-to-adapt for tiled windows.
- Cross-display drag of tiled windows.
- If a clicked window belongs to an inactive stage, the click should switch/summon consistently rather than leaving focus in a contradictory state.

## P1: Observability And Safety

- Structured JSON-lines logs.
- `windows list`.
- `display list/current/focus`.
- `desktop list/current/focus/back/label`.
- `stage list/create/delete/rename/switch/assign/reorder`.
- `tree dump`.
- `state dump`.
- `config show/errors`.
- `metrics`.
- `diag self-test`.
- `daemon health/audit/heal`.
- Event stream/watch.
- Permission diagnostics for Accessibility, Input Monitoring, and Screen Recording.
- Ownership audit for duplicate or orphaned window membership.
- Reconnect/recovery behavior for display changes.
- Explicit handling of corrupted state files: archive, warn, and continue with clean state.
- Observer accounting: per-window observers must be registered and cleaned up predictably.

## P2: UI And Visual Feedback

- Native per-display stage rail side panel.
- Stage thumbnails through the non-DRM capture path, with fallback when capture fails.
- Stage renderer variants: stacked, mosaic, parallax, icons.
- Stage number badges.
- Rail toggle/status.
- One rail per display by default.
- Active-stage halo.
- Renderer selection and renderer-specific preview config.
- Summon inactive-stage window into active stage via explicit button/menu action.
- Move a thumbnail to another stage by drag/drop, with a ghost thumbnail following the cursor.
- Move a thumbnail to an empty rail area to target an empty or newly-created stage.
- Stage reorder via explicit controls; do not overload the same gesture as summon.
- Empty-click hide active stage is risky and should default off or be protected by safety margins.
- Focused-window border configuration:
  - enabled/disabled.
  - thickness.
  - corner radius.
  - active/inactive colors.
  - focused-only option.
  - stage-specific active color overrides.

## P3: Integrations And Deferred Polish

- SketchyBar/top-bar bridge.
- BetterTouchTool-friendly commands.
- Signal hooks: run shell commands on events.
- Rules engine: app/title matching to float, sticky, assign, display, desktop, stage, gaps.
- Window thumbnail command.
- Stage/window event stream for external consumers.
- Advanced visual effects are deferred and not core:
  - animations.
  - blur.
  - inactive opacity/dimming.
  - third-party shadow control.

## Explicitly Not A Goal

- Manipulating native macOS Spaces.
- Depending on SIP-off setup.
- Recreating the old compatibility layer.
- Hiding failures behind stubs.
- Building rail/effects before the core WM works.
- Reusing any source code from the archived implementation.
- Pretending yabai parity exists before each operation has a real tested path.

## State Key

All durable WM state should be addressable with explicit keys:

```text
DisplayUUID
└── RoadieDesktopID
    └── StageID
        ├── WindowManagementMode: bsp | masterStack | float
        ├── Stage membership
        ├── Layout state
        └── Focus history
```

## Mental Model

```text
macOS native Spaces
└── one native Space used by Roadie
    └── Roadie
        ├── Display 1
        │   ├── Desktop 1
        │   │   ├── Stage A  mode=bsp          visible if active
        │   │   ├── Stage B  mode=masterStack  hidden if inactive
        │   │   └── Stage C  mode=float        hidden if inactive
        │   └── Desktop 2
        │       └── independent stages and modes
        └── Display 2
            └── independent current desktop/stage/layout
```
