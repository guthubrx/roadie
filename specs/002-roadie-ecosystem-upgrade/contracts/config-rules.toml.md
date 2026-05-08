# Config Rules Contract

## Example

```toml
[[rules]]
id = "terminal-dev"
enabled = true
priority = 10
stop_processing = true

[rules.match]
app = "Terminal"
title_regex = "roadie|vim|zsh"
role = "AXWindow"

[rules.action]
assign_desktop = "dev"
assign_stage = "shell"
floating = false
layout = "tile"
gap_override = 4
emit_event = true
```

## Match Fields

- `app`: exact app name.
- `app_regex`: regex app name.
- `title`: exact title.
- `title_regex`: regex title.
- `role`: AX role.
- `subrole`: AX subrole.
- `display`: display ID or label.
- `desktop`: Roadie desktop ID or label.
- `stage`: Roadie stage ID or name.
- `is_floating`: boolean.

At least one match field is required.

## Action Fields

- `manage`: boolean, default `true`.
- `exclude`: boolean, removes window from tiling if true.
- `assign_desktop`: desktop ID or label.
- `assign_stage`: stage name.
- `floating`: boolean.
- `layout`: `tile`, `float`, `master`, `bsp`, or future-supported mode.
- `gap_override`: integer pixels, non-negative.
- `scratchpad`: scratchpad name. Si le workflow scratchpad complet n'est pas encore disponible, Roadie doit au minimum stocker et exposer ce marqueur dans l'évaluation de règle et les queries.
- `emit_event`: boolean, default `true`.

## Conflict Rules

- `exclude=true` cannot be combined with `layout=tile`.
- `floating=true` cannot be combined with `layout=tile` unless Roadie defines pseudo-tile explicitly.
- invalid regex makes the full config invalid.
- duplicate `id` makes the full config invalid.

## Evaluation Rules

- disabled rules are ignored and can be listed by diagnostics.
- lower `priority` runs first.
- if priorities are equal, file order is stable.
- `stop_processing=true` stops after successful action application.
