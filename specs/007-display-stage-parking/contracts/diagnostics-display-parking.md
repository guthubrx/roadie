# Contrat de diagnostic : display parking

## Événements publics

Les événements doivent être suffisamment stables pour être lus dans les logs, hooks ou outils de diagnostic.

### `display.parking_started`

Émis quand Roadie rapatrie des stages depuis un écran disparu.

Champs :

- `origin_display_id`
- `origin_logical_display_id`
- `host_display_id`
- `parked_stage_count`
- `skipped_empty_stage_count`
- `reason`

### `display.parking_restored`

Émis quand Roadie restaure des stages sur un écran reconnu.

Champs :

- `origin_logical_display_id`
- `restored_display_id`
- `restored_stage_count`
- `confidence`
- `reason`

### `display.parking_ambiguous`

Émis quand Roadie refuse une restauration automatique.

Champs :

- `origin_logical_display_id`
- `candidate_display_ids`
- `parked_stage_count`
- `reason`

### `display.parking_noop`

Émis quand un changement d'écran ne demande aucune mutation.

Champs :

- `live_display_count`
- `parked_stage_count`
- `reason`

## Sortie CLI souhaitée

Une commande existante ou nouvelle peut exposer l'état sous forme texte ou JSON. Exemple de forme JSON :

```json
{
  "displays": [
    {
      "displayID": "display-built-in",
      "logicalDisplayID": "logical-built-in",
      "status": "present",
      "stages": [
        {
          "id": "1",
          "name": "Work",
          "parkingState": "native"
        },
        {
          "id": "4",
          "name": "Perso",
          "parkingState": "parked",
          "origin": {
            "logicalDisplayID": "logical-lg-hdr-4k",
            "displayID": "display-old",
            "desktopID": 1,
            "stageID": "4"
          }
        }
      ]
    }
  ]
}
```

## Audit santé

Les checks attendus :

- `stale-scopes` : `warn` si des scopes appartiennent à des écrans absents mais sont conservés.
- `parked-stages` : `ok` si les stages parkées sont visibles sur un écran hôte.
- `ambiguous-restoration` : `warn` si des stages restent parkées faute de match sûr.
- `lost-window-risk` : `fail` uniquement si une fenêtre live n'est ni visible ni récupérable.

## Contraintes de logs

- Les logs ne doivent pas contenir de données personnelles inutiles.
- Les titres de fenêtres peuvent être tronqués si exposés.
- Les raisons doivent être stables pour faciliter les tests.
