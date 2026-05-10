# Configuration And Rules

## Configuration File

Roadie reads user configuration from:

```text
~/.config/roadies/roadies.toml
```

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
assign_stage = "shell"
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
- `assign_stage`: target stage.
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

## Explain

```bash
./bin/roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Use `explain` before adding a rule to your local production setup. It is a dry run: Roadie shows which rule would match and which actions would be applied.
