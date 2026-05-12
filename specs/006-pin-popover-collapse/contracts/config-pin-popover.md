# Contrat : Configuration du Menu Pin

## Table TOML

```toml
[experimental.pin_popover]
enabled = false
show_on_unpinned = true
button_size = 12.5
button_color = "#0A84FF"
titlebar_height = 36
leading_exclusion = 64
trailing_exclusion = 16
collapse_enabled = true
proxy_height = 28
proxy_min_width = 160
```

## Règles de Validation

| Clé | Règle |
|-----|-------|
| `enabled` | booléen |
| `show_on_unpinned` | booléen |
| `button_size` | nombre entre 8 et 28 |
| `button_color` | couleur hexadécimale `#RRGGBB` ou `#RRGGBBAA` |
| `titlebar_height` | nombre entre 16 et 96 |
| `leading_exclusion` | nombre entre 0 et 240 |
| `trailing_exclusion` | nombre entre 0 et 240 |
| `collapse_enabled` | booléen |
| `proxy_height` | nombre entre 18 et 64 |
| `proxy_min_width` | nombre entre 80 et 360 |

## Compatibilité

- Absence de la table : fonctionnalité désactivée et comportement existant inchangé.
- Valeur invalide : la validation de config doit signaler une erreur claire.
- Désactivation : le bouton, le menu bouton et les proxies repliés ne sont pas affichés, mais le menu clic droit de barre de titre reste disponible selon sa propre configuration.
