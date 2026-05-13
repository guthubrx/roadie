# Configuration And Rules

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
./bin/roadie config validate
./bin/roadie config show
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
```

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

`default_strategy` accepts `bsp`, `mutableBsp`, `masterStack`, or `float`.

Use cases:

- reduce gaps on a small screen;
- keep `masterStack` as the default for a reading stage;
- enable `smart_gaps_solo` to avoid wasting space with one window.

## Predefined Stages

```toml
[stage_manager]
enabled = true
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
empty_click_hide_active = true
empty_click_safety_margin = 12
```

Important options:

- `empty_click_hide_active`: allows clicking empty rail space to switch to an empty stage. Set it to `false` if empty rail areas should do nothing.
- `empty_click_safety_margin`: minimum horizontal margin before an empty click is accepted.
- `layout_mode = "resize"` reserves space for the rail; `overlay` lets the rail sit above the desktop.
- clicks in macOS-reserved areas such as the menu bar are ignored.

## Manual Width Adjustment

```toml
[width_adjustment]
presets = [0.5, 0.67, 0.8, 1.0]
nudge_step = 0.05
minimum_ratio = 0.25
maximum_ratio = 1.5
```

These values are used only by manual `roadie layout width ...` commands.

Use cases:

- quickly move from half width to two thirds of the screen;
- nudge a window by small steps;
- bound ratios to avoid absurd frames.

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
- `layout`: layout hint.
- `gap_override`: gap override.
- `scratchpad`: scratchpad marker exposed by evaluation.
- `emit_event`: event policy marker.

## Validation

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
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
./bin/roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Use `explain` before adding a rule to your local production setup. It is a dry run: Roadie shows which rule would match and which actions would be applied.
