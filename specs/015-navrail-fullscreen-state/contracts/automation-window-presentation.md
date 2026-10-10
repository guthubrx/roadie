# Contract: Automation window presentation state

## Surface

`roadie query state --json` et toute surface qui sérialise `RoadieStateSnapshot`.

## Changement

Chaque élément de `windows[]` expose un champ `presentationState`.

## Exemple

```json
{
  "id": "141202",
  "app": "Google Chrome",
  "title": "Horizon Studio",
  "displayId": "AAAAAAAA-0000-4000-8000-000000000001",
  "desktopId": "2",
  "stageId": "3",
  "frame": {
    "x": 150,
    "y": 30,
    "width": 1898,
    "height": 1242
  },
  "isFocused": false,
  "isFloating": false,
  "presentationState": "maximized"
}
```

## Valeurs autorisées

- `normal`
- `maximized`
- `nativeFullscreen`

## Compatibilité

- Le champ est obligatoire dans les snapshots produits après cette feature.
- Le décodage interne reste compatible avec les snapshots historiques où le champ est absent : la valeur par défaut est `normal`.

## Invariants

- `nativeFullscreen` prime sur `maximized`.
- `presentationState` ne modifie pas `isFloating`.
- `presentationState` ne modifie pas `stageId`.
- `presentationState` ne déclenche aucune commande de layout.
