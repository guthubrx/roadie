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

## Control And Safety Sections

Roadie accepts additional safety sections in `roadies.toml`.

```toml
[control_center]
enabled = true
show_menu_bar = true

[config_reload]
watch = true
debounce_ms = 250
keep_previous_on_error = true

[restore_safety]
enabled = true
restore_on_exit = true
crash_watcher = true
snapshot_path = "~/.local/state/roadies/restore.json"

[transient_windows]
enabled = true
pause_tiling = true
recover_offscreen = true

[layout_persistence]
version = 2
stable_identity = true
minimum_match_score = 0.75

[width_adjustment]
presets = [0.5, 0.67, 0.8, 1.0]
nudge_step = 0.05
minimum_ratio = 0.25
maximum_ratio = 1.5
```

`config reload` validates the whole file before replacing the active config. Invalid reloads emit `config.reload_failed` and preserve the previous active config.
