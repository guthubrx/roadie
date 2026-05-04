<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="roadie logo" width="128" height="128">
</div>

<div align="center">

# 🚧 UNDER CONSTRUCTION · EN CONSTRUCTION 🚧

**This project is a work in progress. Expect breaking changes, rough edges, and incomplete features.**

**Ce projet est en cours de construction. Attendez-vous à des changements cassants, des aspérités et des fonctionnalités incomplètes.**

</div>

---

# roadie

🇬🇧 **English** · 🇫🇷 [Français](README.fr.md)

> **Work in progress — actively evolving project.** My goal is to make this my daily driver. All feedback is welcome — see [Status](#status).

A small tiling window manager for macOS, written in Swift, that I'm polishing into my everyday workstation.

<p align="center">
  <img src="docs/assets/screenshot-multi-display.png" alt="roadie multi-display screenshot" width="100%">
</p>

## Why this project

I never set out to write a window manager. For years, [yabai](https://github.com/koekeishiya/yabai) has been the foundation of my workstation — a remarkable project, sharply built, whose stability and ergonomics have shaped every macOS tiling user. I still see it as the reference, and roadie's intellectual debt to yabai is total.

The trigger was simple and personal: I never managed to make yabai cohabit with **Stage Manager**. Yet Stage Manager is part of how I work — I want named, hideable, restorable groups of windows, on top of automatic tiling for the visible ones. Several attempts, scripts, workarounds — none held up over time on my setup.

Rather than keep tinkering, I eventually flattened the problem and wrote a small window manager that addresses my specific need:

- BSP / master-stack tiling for visible windows, like yabai.
- A *pseudo* Stage Manager — "stages" that are hideable groups of windows within a single desktop, with perfect layout restoration.
- Multi-desktop awareness, without depending on SkyLight write APIs.

**roadie has no pretension of matching yabai** — yabai's functional depth, robustness, and polish are at another level. roadie is intentionally minimalist, written for my own use, and I'm sharing it publicly because it might serve people in the same situation as me.

### The AeroSpace pivot for desktops

Multi-desktop was the second pivot. On macOS Tahoe 26, Apple has further locked down the SkyLight write APIs (cf. [yabai #2656](https://github.com/koekeishiya/yabai/issues/2656), [ADR-005](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.md) here). The scripting-addition-into-Dock route, long used by yabai to manage native Spaces, is de facto blocked for third-party bundles.

So I adopted the [AeroSpace](https://github.com/nikitabobko/AeroSpace) approach: don't touch native Spaces at all, manage **N virtual desktops** entirely on roadie's side, within a single native Mac Space. Switching desktops means moving the leaving desktop's windows offscreen and restoring the arriving desktop's windows to their saved positions. No SkyLight write calls, no scripting addition, no SIP disabled. Once again, full intellectual debt to AeroSpace, and I want to acknowledge it explicitly.

So roadie is a humble assembly of a bit of yabai (the tiler, AX-only without SIP) and a bit of AeroSpace (virtual desktops), plus the stages layer that I didn't find in either. If you're looking for a real, mature window manager, head to yabai or AeroSpace depending on your needs — these are excellent projects, built for the wider audience.

## What roadie does today

| Capability | State | Source |
|---|---|---|
| BSP + master-stack tiling | OK | SPEC-002 |
| Stage Manager (named groups ⌥1/⌥2/...) | OK | SPEC-002 |
| Virtual desktops (1..16, AeroSpace pivot) | OK | SPEC-011 |
| Multi-display: independent tiling per screen | OK | SPEC-012 |
| Stages scoped per display x desktop | OK | SPEC-018 |
| Drag-to-adapt (manual resize propagates the tree) | OK | SPEC-002 |
| Universal click-to-raise | OK (Electron/JetBrains/Cursor) | SPEC-002 |
| Focused window borders (NSWindow overlay) | OK | SPEC-008 |
| Advanced visual effects (animations, blur, opacity, shadowless) | Framework present, runtime blocked on Tahoe 26 | SPEC-004→010, ADR-005 |
| 13 ready-to-use BTT shortcuts | OK | SPEC-002 |

## Known limitations

- **Inter-app click-to-raise** not 100% guaranteed: without disabled SIP + scripting addition injection into Dock.app (the yabai path), no WM can reach 100% on recent macOS. AeroSpace has the same limitation by design. roadie explicitly chooses not to touch SIP, so accepts this ceiling.
- **SIP-off opt-in visual effects** (Bézier animations, blur, focus dimming, shadowless): the framework is shipped and the `.dylib` modules load correctly, but Apple has silently blocked third-party scripting addition injection into Dock on Tahoe 26 — so the CGS overlay doesn't reach third-party windows. Details: [ADR-005](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.md). Window borders (native NSWindow overlay) work fine without osax.
- **Multi-display** is supported (SPEC-012 V3): see [Multi-display](#multi-display) below.

## Installation (build from source)

### Dependencies

| Tool | Required | Install | Used for |
|---|---|---|---|
| Xcode Command Line Tools (`swift`, `codesign`) | yes | `xcode-select --install` | build, code signing |
| `terminal-notifier` | yes | `brew install terminal-notifier` | clickable native macOS notification when TCC drops |
| `sketchybar` | optional | `brew install FelixKratz/formulae/sketchybar` | top-bar plugin showing desktops × stages (SPEC-023) |
| `jq` | optional | `brew install jq` | JSON parsing in the SketchyBar bridge |
| Self-signed code-signing certificate `roadied-cert` | yes | Keychain Access → Certificate Assistant → Create a Certificate (Self Signed Root, Code Signing) | preserves TCC permissions across rebuilds (cf [ADR-008](docs/decisions/ADR-008-signing-distribution-strategy.md)) |

If you don't want the SketchyBar panel: `ROADIE_WITH_SKETCHYBAR=0 ./scripts/install-dev.sh`.

### Build & install

```bash
git clone https://github.com/guthubrx/roadie.git
cd roadie
./scripts/install-dev.sh        # build + sign + deploy + launchd setup
```

The script checks all dependencies, builds, signs every binary with `roadied-cert`, deploys to `~/Applications/roadied.app/`, and configures launchd. Re-run after every `swift build` to refresh the deployed binary while keeping TCC grants.

Then in System Settings → Privacy & Security:
- **Accessibility** : add `~/Applications/roadied.app` and tick the checkbox
- **Screen Recording** : add `~/Applications/roadied.app` and tick the checkbox (needed for window thumbnail capture)

After ticking, mark the current binary hash as the TCC baseline so future rebuilds can detect drift:

```bash
./scripts/recheck-tcc.sh --mark-toggled
```

```bash
roadied --daemon &
roadie desktop list   # sanity check
```

### TCC drift detection

`install-dev.sh` runs `scripts/recheck-tcc.sh` at the end of each deploy. If the
deployed binary hash differs from the last `--mark-toggled` baseline, you'll get a
clear warning telling you to re-toggle Accessibility (otherwise the daemon will
loop on `permission Accessibility manquante`). Workflow:

```bash
./scripts/install-dev.sh           # deploy + auto-recheck
# → if "drift detected": go to Settings, decoche/recoche roadied
./scripts/recheck-tcc.sh --mark-toggled   # confirm new baseline
```

## Configuration

Everything goes through `~/.config/roadies/roadies.toml`. Minimal example:

```toml
[daemon]
log_level = "info"
socket_path = "~/.roadies/daemon.sock"

[tiling]
default_strategy = "bsp"
gaps_outer = 8
gaps_inner = 6

[desktops]
enabled = true
count = 10
back_and_forth = true

[stage_manager]
enabled = true
hide_strategy = "corner"
default_stage = "1"

[fx.borders]
enabled = true
thickness = 2
corner_radius = 10
active_color = "#7AA2F7"
inactive_color = "#414868"
focused_only = true
```

> To avoid conflicts with native Spaces: in System Settings → Desktop, disable "Displays have separate Spaces" and use **a single native Mac Space**. Roadie ignores native Mac Space switches (native Ctrl+→/←).

## Multi-display

roadie handles multiple physical screens transparently (SPEC-012). Each connected display gets its own independent tiling tree — windows on screen 1 and windows on screen 2 tile separately within each screen's visible area.

```bash
roadie display list                    # enumerate connected screens
roadie display current                 # screen of the frontmost window
roadie display focus 2                 # focus first tiled window on screen 2
roadie display focus next              # cycle to next screen

roadie window display 2                # move frontmost window to screen 2
roadie window display prev             # move to previous screen
```

**Branch/unbranch**: when a screen disconnects, its windows migrate automatically to the primary display. When a screen reconnects, it gets a fresh tiling tree. A `display_configuration_changed` event is emitted on each change (subscribe via `roadie events --follow`).

**Per-display config** (optional, in `roadies.toml`):

```toml
[[displays]]
match_index = 2
default_strategy = "masterStack"
gaps_outer = 0
```

Match criteria: `match_index`, `match_uuid` (cross-reboot stable), or `match_name` (localized screen name).

## Stages per display x desktop

SPEC-018 extends Stage Manager with a per-display x per-desktop scope. In `mode = "per_display"`, each (display UUID, desktop ID) pair gets its own independent set of stages. Stages created on Display 1 are not visible from Display 2, and switching virtual desktops gives a fresh stage context.

Scope is resolved automatically from the cursor position (fallback: frontmost window, then primary display). Power-user scripts can bypass automatic resolution with `--display` and `--desktop` flags:

```bash
roadie stage list --display 1 --desktop 2
roadie stage create "Work" --display 2
```

To activate, add to `~/.config/roadies/roadies.toml`:

```toml
[desktops]
mode = "per_display"
```

Existing stages (mode `global`) are migrated silently on first boot: a `stages.v1.bak/` backup is created, then stages are moved into `<displayUUID>/1/`. Migration status is visible via `roadie daemon status --json`.

See [specs/018-stages-per-display/spec.md](specs/018-stages-per-display/spec.md) for full design details.

## Detailed documentation

The project is developed with [SpecKit](https://github.com/sergeykish/spec-kit) — one spec per major feature, with plan, research, ADRs, tasks, and implementation REX.

### Main specs

- [SPEC-002 — Tiler + Stage Manager](specs/002-tiler-stage/spec.md) (V1)
- [SPEC-011 — Virtual Desktops AeroSpace-style](specs/011-virtual-desktops/spec.md) (V2)
- [SPEC-004 → 010 — SIP-off opt-in family](specs/004-fx-framework/spec.md) (animations, borders, blur, etc.)

### Architecture decisions

- [ADR-001 — Per-app AX, no SkyLight write](docs/decisions/ADR-001-ax-per-app-no-skylight.md)
- [ADR-002 — N-ary tree vs binary BSP](docs/decisions/ADR-002-tree-naire-vs-bsp-binary.md)
- [ADR-003 — Hide via offscreen corner](docs/decisions/ADR-003-hide-corner-vs-minimize.md)
- [ADR-004 — SIP-off opt-in modules](docs/decisions/ADR-004-sip-off-modules.md)
- [ADR-005 — Tahoe 26 osax injection blocked](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.md)

## Credits

- **[yabai](https://github.com/koekeishiya/yabai)** by Åke Kullenberg / koekeishiya — the macOS tiling reference, ten years in production, the inspiration for the entire AX + `_AXUIElementGetWindow` pattern. Without yabai, roadie wouldn't exist.
- **[AeroSpace](https://github.com/nikitabobko/AeroSpace)** by Nikita Bobko — the SkyLight-write-free virtual-desktops pivot, demonstrated in production. Approach taken as-is for SPEC-011.
- **[Hyprland](https://github.com/hyprwm/Hyprland)** — the inspiration for the Bézier curves DSL for animations (SPEC-007), although the blocked osax on Tahoe 26 currently prevents their application to third-party windows.

## Status

A **personal**, **resolutely work-in-progress** project. The code is moving a lot right now and will keep moving significantly in the coming weeks as I use it and discover the rough edges on my own setup. My goal is clear: **make this my daily driver**, the window manager I work with every day, and therefore polish it continuously through real usage.

All feedback, suggestions, bug reports, and improvement ideas are **genuinely** welcome — open an issue on this repo, I'm listening. No promise of a public roadmap or guaranteed support for now, but the project is open to dialogue and every input furthers my understanding of what works or doesn't outside my own environment.

If you're looking for a mature WM for daily use today, head to [yabai](https://github.com/koekeishiya/yabai) or [AeroSpace](https://github.com/nikitabobko/AeroSpace) first — you'll find a much more stable foundation there than what roadie can offer at this stage.

## License

MIT — see [LICENSE](LICENSE).
