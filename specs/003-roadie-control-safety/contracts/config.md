# Contrat Config : Roadie Control & Safety

## Sections ajoutees

```toml
[control_center]
enabled = true
show_menu_bar = true
show_recent_errors = true

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

## Validation

- `debounce_ms` doit etre entre 50 et 5000.
- `minimum_match_score` doit etre entre 0 et 1.
- `presets` doit contenir au moins une valeur valide si width adjustment est active.
- Les ratios sont tries, deduplicates et clamps par le loader.
- Une section invalide fait echouer le reload complet, sans remplacer la config active.

## Compatibilite

- Toutes les sections sont optionnelles.
- Les valeurs par defaut preservent le comportement actuel sauf activation du Control Center et des protections de securite.
- Les anciennes configs restent valides si elles ne contiennent pas ces sections.
