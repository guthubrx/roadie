# Comparison: Roadie vs macOS Window Managers, Launchers, and Switchers

*Factual comparison compiled in November 2026 from each project’s public documentation and Roadie’s `main` sources. It is not meant to be exhaustive; if another project has added a feature or changed its model since then, issues and PRs with corrections are welcome.*

[Version française](../fr/comparison.md) · [English documentation](README.md) · [Root README](../../README.md)

---

## Positioning in one sentence

Most macOS power users stitch together **3 to 5 separate apps**: a tiling window manager (AeroSpace, yabai, OmniWM, Rift…), a launcher (Raycast or Alfred), a window switcher (AltTab), and often a hotkey/gesture tool (skhd, BetterTouchTool, Karabiner).

**Roadie unifies these roles into a single local, free, open-source (Apache-2.0) macOS application**—keeping SIP enabled, with no account, no subscription, and no telemetry—while remaining compatible with BetterTouchTool and Karabiner if you prefer keeping them.

---

## 1. macOS Tiling Window Managers

| Criteria | **Roadie** | **AeroSpace** | **yabai** | **OmniWM** | **Rift** | **Amethyst** |
|---|---|---|---|---|---|---|
| **License & price** | Apache-2.0 (free) | MIT (free) | MIT (free) | GPL-2.0 (free) | Open source / MIT (free, Rust) | MIT (free) |
| **Keeps SIP enabled** | Yes (always) | Yes (always) | Partial *(partial SIP disable needed for scripting addition: instant Spaces, shadows, opacity)* | Yes (always) | Yes (always) | Yes (always) |
| **macOS requirement** | macOS 14+ | macOS 13+ | Recent macOS | Apple Silicon, macOS 26+ | Recent macOS | Recent macOS |
| **Layout modes** | `spatialBsp` (persistent tree), `bsp`, `masterStack`, `tabbed`, `scrolling` (Niri ribbon), `float` | i3 tree (`tiles`, `accordion`), `float` | `bsp`, `stack`, `float` | `scrolling` (Niri), `dwindle` BSP, `float` | i3, `bsp`, `scrolling` (Niri), `masterStack`, `stack`, `float` | xmonad (`tall`, `wide`, `bsp`, fullscreen, etc.) |
| **Per-tile / per-column tabs** | **Yes, across all slotted tiled modes** (`spatialBsp`, `scrolling`, `masterStack`, `bsp`): floating bar, `⌥ Option` + drag, drag-out detach, CLI | No *(`accordion` mode; visual tab bars via third-party tools)* | No *(`stack` mode without native tab bar)* | No | Yes *(tab bars on stacked windows)* | No |
| **Scrolling ribbon + multi-display containment** | Yes: 120 Hz ProMotion, 3/4-finger trackpad swipe, `⌥ + scroll`, strict inter-display seam clipping | No | No | Yes: display-synced animations + trackpad swipe | Yes: scrolling columns + smooth animations | No |
| **Virtual workspaces / Stages** | Named stages + per-display virtual desktops (independent from macOS Spaces) + **3D NavRail** | Emulated instant virtual workspaces (per monitor) | Native macOS Spaces | Virtual workspaces | Per-display Spaces | Native macOS Spaces |
| **Overview mode** | Yes (live thumbnails, 4-finger swipe up/down) | No | No *(macOS Mission Control)* | Yes (live thumbnails) | Yes (Niri-style, drag-and-drop) | No |
| **Floating scratchpad** | Yes (named, titlebar action, configurable reboot survival) | Not built-in *(scriptable via workspace)* | Not built-in *(scriptable)* | Yes (up to 10 slots + Quake terminal) | Not built-in | Not built-in |
| **Built-in hotkeys & gestures** | Yes (QWERTY/AZERTY presets, native trackpad; BTT/Karabiner optional) | Yes (`aerospace.toml`) | No *(requires `skhd` or similar)* | Yes | Yes (TOML + trackpad gestures) | Yes |
| **Settings & automation** | Live GUI settings + TOML + CLI + JSON API + rules | TOML + CLI | Shell script + CLI + signals | GUI + `omniwmctl` CLI | GUI + menu bar + TOML + CLI/IPC | Simple GUI + JSON |
| **Built-in launcher & switcher** | **Yes** *(full launcher + Alfred workflows + `⌘ Tab` switcher + zone switcher)* | No | No | Command palette (windows/actions) | No | No |

---

## 2. Launchers, Clipboard & Window Switchers

| Criteria | **Roadie** | **Raycast** | **Alfred** | **AltTab** *(open source)* |
|---|---|---|---|---|
| **Model & pricing** | **Free, open source (Apache-2.0)** | Freemium *(Pro ~$8–10/mo for AI, Cloud Sync, >3-month clipboard, custom themes)* | Freemium *(paid Powerpack: £34 or £59 lifetime for workflows, clipboard, snippets)* | Open source GPL-3.0 *(free core)* |
| **100% local, no account/telemetry** | Yes *(only optional network call: manual `roadie update check`)* | No *(account/cloud sync & AI services for Pro)* | Yes (local) | Yes (local) |
| **Workflows / Extensions** | Runs **`.alfredworkflow` files for free** *(92/102 complete on a real corpus)* | **Thousands of React/JS extensions** in the Raycast Store (free) | Native `.alfredworkflow` reference *(Powerpack required)* | No |
| **Secure clipboard history** | Built-in, local `0o600`, skips passwords (`Concealed`/`Transient`/managers) | Built-in *(3-month limit on Free; unlimited on Pro)* | Built-in *(Powerpack required)* | No |
| **Snippets / text expansion** | Built-in *(`{date}`, `{clipboard}`, `{cursor}`, optional auto-expand)* | Built-in *(free locally; sync in Pro)* | Built-in *(Powerpack required)* | No |
| **Offline core utilities** | Calculator, converter (units/bases/time zones), color picker, EN/FR emojis, timer/Pomodoro | Rich calculator, converter, emojis, notes, quicklinks, AI (Pro) | Calculator; rest via workflows | No |
| **Window switcher (`⌘ Tab`)** | Built-in (native `CGEventTap`, thumbnails, search, `W/Q/M/H/S/A/D` actions) | Basic window list inside launcher | No | **Dedicated specialist** *(lightweight, highly configurable)* |
| **Clicked-zone switcher (`Option+Tab`)** | **Yes** *(returns to an exact tab/button/pane, even across stages)* | No | No | No |
| **On-screen label search** | **Yes** *(Accessibility + typo tolerance + display/window grids)* | No | No | No |
| **Tiling window management** | **Full** *(6 modes, per-tile tabs, stages, virtual desktops)* | Basic shortcut window snapping | No | No |

---

## 3. What makes Roadie distinct

- **One cohesive engine**: the launcher understands your stages, virtual desktops, and displays (`safari personal left` opens Safari directly in the *Personal* stage on the left with a live preview).
- **Universal per-tile / per-column tabs**: no need to choose between BSP, scrolling ribbon, and tabs—hold `⌥ Option` anywhere over a target tile or column to stack windows as tabs in `spatialBsp`, `scrolling`, `masterStack`, or `bsp`.
- **Zone switcher (`Option+Tab`) and on-screen search**: jump straight back to a specific sub-tab, field, or button inside a window—even hidden on another stage—with a local snapshot of that area.
- **Free `.alfredworkflow` compatibility**: reuse existing Alfred workflows (and Alfred themes) without a paid Powerpack license.

---

## 4. When to choose another tool (Roadie’s conscious trade-offs)

Different workflows favor different tools. Another project is likely a better fit if:

- **Choose yabai** if you want direct control over **native macOS Spaces**, window shadow removal, or system opacity, and you are fine partially disabling SIP.
- **Choose AeroSpace** if you want a **strictly minimalist, keyboard-only, i3-style** manager with no visual rail, no launcher, and no GUI settings.
- **Choose OmniWM** if you run **Apple Silicon on macOS 26+** and specifically want a Niri-centric WM with a built-in Quake terminal (`libghostty`).
- **Choose Rift** if you prefer a **pure Rust** WM tightly integrated with native macOS Spaces and external bars such as SketchyBar.
- **Choose Raycast** if you rely heavily on a **large React/JS extension store** (Linear, Notion, GitHub, Jira…), cloud sync, or built-in launcher AI.
- **Choose Alfred** if you rely on **Contacts**, compiled AppleScript workflows, or years of native Powerpack muscle memory.
- **Choose AltTab** if you only want a **lightweight, single-purpose `⌘ Tab` replacement** without tiling or a launcher.

### Current trade-offs in Roadie

- **Does not control native macOS Spaces**: Roadie keeps SIP enabled and manages its own stages and per-display virtual desktops instead.
- **Not Apple-notarized yet**: the one-line installer (`scripts/install-release.sh` or Homebrew Cask) verifies SHA-256 and clears quarantine locally; local builds signed with `roadied-cert` preserve Accessibility permissions.
- **No JS/React extension store**: extensibility relies on existing `.alfredworkflow` packages, CLI commands, and TOML rules.
- **Intentional all-in-one scope**: broader than a single-purpose utility (unused modules stay idle with zero timers).
