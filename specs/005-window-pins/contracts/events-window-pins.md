# Contrat : événements des pins de fenêtres

## Types d'événements

| Événement | Déclenchement |
|-----------|---------------|
| `window.pin_added` | Une fenêtre est pinée pour la première fois |
| `window.pin_scope_changed` | Une fenêtre déjà pinée change de scope |
| `window.pin_removed` | L'utilisateur retire le pin |
| `window.pin_pruned` | Roadie supprime automatiquement un pin orphelin |

## Détails communs

```json
{
  "windowID": "12345",
  "bundleID": "com.example.App",
  "title": "Window title",
  "pinScope": "desktop",
  "displayID": "display-main",
  "desktopID": "1",
  "stageID": "1"
}
```

## Règles

- Une action utilisateur réussie doit produire exactement un événement `window.pin_added`, `window.pin_scope_changed` ou `window.pin_removed`.
- Un nettoyage automatique peut regrouper plusieurs suppressions, mais chaque fenêtre nettoyée doit rester identifiable dans les détails ou dans des événements séparés.
- Les échecs d'action depuis le menu continuent d'utiliser `titlebar_context_menu.failed` avec un message explicite.
- Les événements de pin doivent être ajoutés au catalogue public d'événements Roadie.
