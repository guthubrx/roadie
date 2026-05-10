# Contrat : configuration du menu contextuel de barre de titre

## TOML

```toml
[experimental.titlebar_context_menu]
enabled = false
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
```

## Valeurs par Défaut

- La section absente equivaut a `enabled = false`.
- Les valeurs invalides doivent etre refusees par la validation config ou ramenees a une valeur sure documentee.
- `enabled = false` doit garantir zero capture de clic droit hors comportements deja existants.

## Validation

- `height` doit rester dans une plage raisonnable : 12 a 96 px.
- `leading_exclusion` et `trailing_exclusion` doivent etre positives ou nulles.
- Si les trois familles de destinations sont desactivees, le menu ne doit pas s'afficher.

## Compatibilité

- Cette section ne change pas `[focus]`, `[tiling]`, `[stage_manager]`, ni les reglages du navrail.
- Les configurations existantes sans section experimental restent valides.
