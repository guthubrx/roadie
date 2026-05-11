# Contrat : persistance des pins de fenêtres

## Emplacement

Les pins sont persistés dans l'état Roadie existant `~/.roadies/stages.json`, au même niveau logique que les scopes de stages/desktops.

## Schéma logique

```json
{
  "windowPins": [
    {
      "windowID": 12345,
      "homeScope": {
        "displayID": "display-main",
        "desktopID": 1,
        "stageID": "1"
      },
      "pinScope": "desktop",
      "bundleID": "com.example.App",
      "title": "Window title",
      "lastFrame": {
        "x": 100,
        "y": 100,
        "width": 900,
        "height": 700
      },
      "createdAt": "2026-05-11T10:00:00Z",
      "updatedAt": "2026-05-11T10:00:00Z"
    }
  ]
}
```

## Compatibilité

- L'absence du champ `windowPins` équivaut à une liste vide.
- Les fichiers existants `stages.json` restent valides.
- Les pins avec `windowID` absent des fenêtres live doivent être supprimés au prochain refresh normal.

## Règles d'intégrité

- `windowID` est unique dans `windowPins`.
- `homeScope.displayID` est l'écran d'autorité du pin.
- `pinScope = "desktop"` limite la visibilité au `homeScope.desktopID`.
- `pinScope = "all_desktops"` limite la visibilité au `homeScope.displayID`.
- Un pin ne doit pas ajouter le même `windowID` à plusieurs stages.
