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
stage = "dev"

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
- `app_regex`: regex tested against app name and bundle ID.
- `title`: exact title.
- `title_regex`: regex title.
- `role`: AX role.
- `subrole`: AX subrole.
- `display`: display ID.
- `desktop`: Roadie desktop ID.
- `stage`: Roadie stage ID.
- `is_floating`: boolean.

At least one match field is required.

## Action Fields

- `manage`: boolean marker for future rule effects.
- `exclude`: boolean, removes window from tiling if true.
- `assign_desktop`: desktop ID or label.
- `assign_stage`: stage name.
- `floating`: boolean.
- `layout`: `tile`, `float`, `master`, `masterStack`, `bsp`, or future-supported mode.
- `gap_override`: integer pixels.
- `scratchpad`: scratchpad name. Si le workflow scratchpad complet n'est pas encore disponible, Roadie doit au minimum stocker et exposer ce marqueur dans l'évaluation de règle et les queries.
- `emit_event`: boolean marker for future event policy.

## Conflict Rules

- `exclude=true` cannot be combined with layout or placement actions (`assign_desktop`, `assign_stage`, `floating`, `layout`, `gap_override`, `scratchpad`).
- invalid regex makes the full config invalid.
- duplicate `id` makes the full config invalid.
- empty `id` makes the rule invalid.

## Evaluation Rules

- disabled rules are ignored and can be listed by diagnostics.
- higher `priority` runs first.
- if priorities are equal, lexical `id` order is used for deterministic output.
- match fields are combined with AND.
- `stop_processing=true` stops after the first matching rule.
- `rules validate` returns non-zero when validation errors exist.
- `rules list` and `rules explain` support `--json` and `--config PATH`.
- `rules explain` accepts synthetic window criteria (`--app`, `--bundle-id`, `--title`, `--role`, `--subrole`, `--display`, `--desktop`, `--stage`, `--floating`, `--tiled`).
- Runtime evaluation publishes `rule.matched`, `rule.applied`, `rule.skipped` and `rule.failed` automation events.
