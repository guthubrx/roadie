# Contrat : Événements Menu Pin

## Événements Publics

| Événement | Quand |
|-----------|-------|
| `pin_popover.shown` | Le menu du bouton est affiché |
| `pin_popover.ignored` | Le bouton ou menu est omis pour raison de sûreté |
| `pin_popover.action` | Une action du menu est exécutée |
| `window.pin_collapsed` | Une fenêtre pinée est repliée |
| `window.pin_restored` | Une fenêtre pinée repliée est restaurée |

## Détails Minimaux

```json
{
  "windowID": "12345",
  "app": "iTerm2",
  "title": "Terminal",
  "pinScope": "desktop",
  "presentation": "collapsed",
  "reason": "eligible"
}
```

## Règles

- Une action utilisateur réussie doit produire un seul événement métier principal.
- Les omissions de placement doivent être throttled si elles sont fréquentes.
- Les événements ne doivent pas contenir de données sensibles au-delà du titre déjà visible de la fenêtre.
- Les événements doivent être ajoutés au catalogue public quand ils sont destinés aux hooks ou abonnements.
