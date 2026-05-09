# Contrat Événements : Performance ressentie

## `performance.interaction_completed`

Émis lorsqu'une interaction critique se termine.

```json
{
  "type": "performance.interaction_completed",
  "scope": "performance",
  "subject": {
    "kind": "interaction",
    "id": "perf_123"
  },
  "payload": {
    "interaction_type": "stage_switch",
    "result": "success",
    "duration_ms": 76,
    "target": {
      "display_id": "display-a",
      "desktop_id": 1,
      "stage_id": "2",
      "window_id": 4312
    },
    "steps": [
      { "name": "state_update", "duration_ms": 4, "status": "success" },
      { "name": "hide_previous", "duration_ms": 18, "count": 2, "status": "success" },
      { "name": "restore_target", "duration_ms": 22, "count": 3, "status": "success" },
      { "name": "focus", "duration_ms": 8, "status": "success" }
    ]
  }
}
```

## `performance.threshold_breached`

Émis lorsqu'une interaction dépasse un seuil de confort.

```json
{
  "type": "performance.threshold_breached",
  "scope": "performance",
  "subject": {
    "kind": "interaction",
    "id": "perf_456"
  },
  "payload": {
    "interaction_type": "alt_tab_activation",
    "duration_ms": 412,
    "limit_ms": 250,
    "dominant_step": "restore_target",
    "message": "AltTab activation exceeded comfort threshold; restore_target dominated the interaction."
  }
}
```

## Garanties

- Les événements de performance sont additionnels et ne remplacent pas les événements existants de stage, desktop, focus ou layout.
- Les événements de performance ne doivent pas modifier l'état Roadie.
- Les mesures peuvent être absentes si l'interaction échoue avant son démarrage, mais une interaction démarrée doit se terminer par un résultat ou être ignorée explicitement.
