# Configuration And Rules

## Editing Settings in Roadie

`/settings` opens the settings window. Valid values apply as you type, without
Return. Lists, stages, rules and overrides have built-in editors. Complex
fragments require explicit saving in the advanced editor.
`signals.hooks` can be stored in this editor, but Roadie does not currently
execute them.

Margin and spacing changes retile windows. Display and side overrides retain
priority over general margins. The file remains available for advanced use;
editing it is not required for common settings.

## Configuration File

Roadie reads user configuration from:

```text
~/.config/roadies/roadies.toml
```

Rules created from the interface are stored separately:

```text
~/.config/roadies/roadies.generated.toml
```

Roadie loads both files. `roadies.toml` stays the human-owned source, while
`roadies.generated.toml` contains affinities created from menus.

Useful commands:

```bash
roadie config validate
roadie config show
roadie rules validate --config ~/.config/roadies/roadies.toml
```

## Example File And Validation

A complete, commented example is in `examples/roadies.toml` at the repository root. Copy it as a starting point:

```bash
mkdir -p ~/.config/roadies
cp examples/roadies.toml ~/.config/roadies/roadies.toml
roadie config validate
```

`config validate` reports each problem as one line: level, full key name, message. The messages are in French.

| Level | Example | Meaning |
|---|---|---|
| `error` | `focus.stage_follows_focus  attendu booléen, reçu texte` | The value has the wrong type, or a required key is missing. Roadie keeps the previous valid configuration. |
| `warning` | `tiling.gaps_inr  clé inconnue, ignorée ; vouliez-vous dire « gaps_inner » ?` | Unknown key or table. Roadie ignores it. The suggestion is the closest valid name. |
| `warning` | `desktops.count  clé sans effet` | Roadie reads the key but does not use it. |

Keys without effect today: the whole `[desktops]` table, and `enabled` and `hide_strategy` in `[stage_manager]`. Remove them from your file. Roadie desktops are always available, and you create them with `roadie desktop` commands.

Every table that the rail reads is accepted: `[fx.rail]` and its sub-tables `layout`, `header`, `header.display`, `header.desktop`, `stages`, `preview`, `stacked`, `stage_labels`, and `parallax`.

In **Settings > Rail**, “Aimantation du réordonnancement (%)” stabilizes the preview destination during a right-button drag. `fx.rail.stages.reorder_magnetism` ranges from 0 to 100 (default 50). At 0, it is disabled. The pointer remains free. Changes apply without restarting.

## Layout

Example:

```toml
[tiling]
default_strategy = "bsp"
gaps_outer = 8
gaps_inner = 4
master_ratio = 0.6
smart_gaps_solo = true
```

`default_strategy` accepts `bsp`, `spatialBsp`, `masterStack`, or `float`.
`mutableBsp` and `yabai` remain aliases of `spatialBsp`.
The split menu offers `largest_dim`, `dwindle` and `balanced`.
The latter remains available for existing configurations.

Use cases:

- reduce gaps on a small screen;
- keep `masterStack` as the default for a reading stage;
- enable `smart_gaps_solo` to avoid wasting space with one window.

## Predefined Stages

```toml
[stage_manager]
default_stage = "1"

[[stage_manager.workspaces]]
id = "dev"
display_name = "Dev"

[[stage_manager.workspaces]]
id = "docs"
display_name = "Docs"
```

Use cases:

- give stages stable names;
- align BetterTouchTool shortcuts with human-readable names.

## Nav Rail

```toml
[fx.rail]
renderer = "stacked-previews"
width = 150
auto_hide = false
layout_mode = "overlay"
dynamic_left_gap = false
empty_click_hide_active = false
empty_click_safety_margin = 12
```

Important options:

- `empty_click_hide_active`: allows clicking empty rail space to switch to an empty stage. Default is `false` so a miss-click cannot hide the active stage.
- `empty_click_safety_margin`: minimum horizontal margin before an empty click is accepted.
- `layout_mode = "resize"` reserves space for the rail; `overlay` lets the rail sit above the desktop.
- `hide_on_maximized`: default is `false`. The rail hides in front of a window in native macOS fullscreen only. With `true`, the rail also hides in front of a window that fills the display without native fullscreen (a maximized window). A tiled window alone in its stage does not count as maximized.
- clicks in macOS-reserved areas such as the menu bar are ignored.

## Manual Width Adjustment

```toml
[width_adjustment]
presets = [0.5, 0.67, 0.8, 1.0]
nudge_step = 0.05
minimum_ratio = 0.25
maximum_ratio = 1.5
```

These values are used only by manual `roadie layout width ...` commands in `bsp` and `masterStack`. They do not apply to `spatialBsp`; use `resize` in tree mode.

Use cases:

- quickly move from half width to two thirds of the screen;
- nudge a window by small steps;
- bound ratios to avoid absurd frames.

## Typography

Settings-window font sizes and other interface sizes are independent.
Changes apply to interfaces that are already open.

```toml
[interface]
settings_text_font_size = 16
settings_help_font_size = 14
settings_title_font_size = 22

[experimental.target_mode]
search_text_font_size = 15
command_text_font_size = 13
search_font_family = "system"
command_font_family = "system"
```

Under **Recherche** (Search), choose separate families and sizes for the input field and
suggestions. The menu lists installed families. `system`, an empty value or a
missing family falls back to the macOS font.
See the [interface size reference](features.md).

## Keyboard Targets And Grids

The user-facing names are **Keyboard Targets**, **Display Grid**, and **Window
Grid**. The TOML keys keep their lower-level names for compatibility.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = true
overlay_duration_seconds = 10
app_mouse_actions_enabled = true
search_hotkey = "command+control+alt+f"   # "" disables; aliases "hyper", "ctrl"

[experimental.app_targets]
enabled = true
scope = "frontmost_window"   # or "visible_windows" (label mode on every visible window)
max_targets = 150
timeout_ms = 120

[experimental.target_grid]
enabled = true
overlay_enabled = true
rows = 3
columns = 3
max_depth = 3
hint_characters = "azeqsdwxc"
label_placement = "center"
mouse_follow_grid = true
focus_follow_grid = true
wake_mouse_pixels = 1

[experimental.target_record]
enabled = true
indicator = "navrail"
navrail_bottom_offset = 50
```

Use cases:

- enable keyboard-addressable labels over Roadie objects;
- use Display Grid when a whole display is the interaction surface;
- use Window Grid when the focused window is the interaction surface;
- keep macro recording visible in the nav rail while avoiding notifications.

## Rules

Rules automate window assignment or labeling.

```toml
[[rules]]
id = "terminal-dev"
enabled = true
priority = 20
stop_processing = true

[rules.match]
app = "Terminal"
title_regex = "roadie|zsh"
role = "AXWindow"
stage = "dev"

[rules.action]
assign_desktop = "1"
assign_display = "LG HDR 4K"
assign_stage = "shell"
follow = false
floating = false
layout = "tile"
gap_override = 4
scratchpad = "terminals"
emit_event = true
```

## Always-floating windows

To keep only some of an app's windows out of tiling (reminders, dialogs) without writing a full rule:

```toml
[[exclusions.floating_windows]]
app = "Thunderbird"        # displayed name or bundle ID (org.mozilla.thunderbird)
title = "# Reminder"       # #: a number; *: any text; case-insensitive
```

The list can also be edited in Settings > Règles and from the title bar Window menu.

## Match Fields

- `app`: exact app name.
- `app_regex`: regex tested against app name and bundle ID.
- `title`: exact title.
- `title_regex`: title regex.
- `role`: Accessibility role.
- `subrole`: Accessibility subrole.
- `display`: Roadie display ID.
- `desktop`: Roadie desktop.
- `stage`: Roadie stage.
- `is_floating`: boolean.

A rule must have at least one match field.

## Actions

- `manage`: marker for future effects.
- `exclude`: removes the window from tiling.
- `assign_desktop`: target desktop.
- `assign_display`: target display, resolved by Roadie ID, display name, then numeric index.
- `assign_stage`: target stage, resolved by ID then visible name. If it does not exist, Roadie creates it.
- `follow`: activates the destination and focuses the window after placement when `true`. Defaults to `false`.
- `floating`: floating behavior.
- `layout`: stored hint; it does not currently affect tiling.
- `gap_override`: stored value; it does not currently affect margins.
- `scratchpad`: scratchpad marker exposed by evaluation.
- `emit_event`: event policy marker.

## Validation

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
```

Detected errors:

- empty `id`;
- duplicate `id`;
- no matcher;
- invalid regex;
- `exclude=true` combined with placement/layout actions.

## Automatic Placement

To always open an application on a specific stage and display:

```toml
[[rules]]
id = "slack-com"
priority = 100

[rules.match]
app = "Slack"

[rules.action]
assign_display = "LG HDR 4K"
assign_stage = "Com"
follow = false
```

Roadie does not steal focus by default. If the target display is missing, the window stays in its current context and Roadie emits `rule.placement_deferred`.

From the title bar right-click menu, the `Affinité d'ouverture` section can create
the same rule without editing `roadies.toml`:

- `Toujours ouvrir cette app ici`: match by app;
- `Toujours ouvrir cette app + ce titre ici`: match by app and title;
- `Retirer l'affinité pour cette app`: deletes generated rules for that app.

`Here` means the clicked window's display, Roadie desktop, and stage. The daemon
automatically reloads generated rules when the generated file changes.

## Explain

```bash
roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Use `explain` before adding a rule to your local production setup. It is a dry run: Roadie shows which rule would match and which actions would be applied.
