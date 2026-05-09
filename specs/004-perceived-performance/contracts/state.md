# Contrat Query/État : Performance ressentie

## `roadie query performance`

Retourne l'état de performance récent sous forme structurée.

```json
{
  "kind": "performance",
  "data": {
    "generated_at": "2026-05-09T06:00:00Z",
    "retention": {
      "storage_path": "~/.local/state/roadies/performance.json",
      "max_interactions": 100,
      "rotation": "fifo"
    },
    "recent_interactions": [
      {
        "id": "perf_123",
        "type": "stage_switch",
        "source": "cli",
        "result": "success",
        "duration_ms": 76,
        "target_context": {
          "display_id": "display-a",
          "desktop_id": 1,
          "stage_id": "2",
          "window_id": 4312
        },
        "steps": [
          {
            "name": "focus",
            "duration_ms": 8,
            "status": "success"
          }
        ],
        "threshold_breach": null
      }
    ],
    "summary_by_type": [
      {
        "type": "stage_switch",
        "count": 12,
        "median_ms": 82,
        "p95_ms": 141,
        "slow_count": 0
      }
    ],
    "thresholds": [
      {
        "interaction_type": "stage_switch",
        "limit_ms": 150,
        "percentile_target": 95,
        "enabled": true
      }
    ],
    "frame_equivalence": [
      {
        "default_tolerance_points": 2,
        "unit": "macos_point"
      }
    ]
  }
}
```

## Compatibilité

- La query `performance` est read-only.
- La query ne doit pas déclencher de snapshot mutateur.
- Les champs inconnus doivent être ignorables par les consommateurs.
- Les seuils par défaut doivent rester documentés dans le contrat.
