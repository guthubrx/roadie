# Contrat CLI : Performance ressentie

## `roadie performance summary [--json]`

Affiche un résumé des interactions critiques récentes.

### Sortie texte attendue

```text
TYPE                 COUNT  MEDIAN_MS  P95_MS  SLOW  LAST_MS
stage_switch         12     82         141     0     76
desktop_switch       4      128        190     0     121
alt_tab_activation   6      164        246     1     232
```

### Sortie JSON attendue

```json
{
  "kind": "performance_summary",
  "generated_at": "2026-05-09T06:00:00Z",
  "summary_by_type": [
    {
      "type": "stage_switch",
      "count": 12,
      "median_ms": 82,
      "p95_ms": 141,
      "slow_count": 0,
      "last_ms": 76
    }
  ],
  "slowest_recent": []
}
```

## `roadie performance recent [--limit N] [--json]`

Affiche les dernières interactions critiques.

### Sortie texte attendue

```text
TIME      TYPE               RESULT   TOTAL_MS  TARGET             SLOWEST_STEP
06:01:12  stage_switch       success  76        display=1 stage=2  layout_apply=24
06:01:16  alt_tab_activation success  232       window=4312        restore_target=96
```

## `roadie performance thresholds [--json]`

Affiche les seuils de confort actifs.

### Sortie JSON attendue

```json
{
  "kind": "performance_thresholds",
  "thresholds": [
    {
      "interaction_type": "stage_switch",
      "limit_ms": 150,
      "percentile_target": 95,
      "enabled": true
    },
    {
      "interaction_type": "desktop_switch",
      "limit_ms": 200,
      "percentile_target": 95,
      "enabled": true
    },
    {
      "interaction_type": "alt_tab_activation",
      "limit_ms": 250,
      "percentile_target": 90,
      "enabled": true
    }
  ]
}
```

## Erreurs

- Si aucun historique n'existe encore, la commande retourne un tableau vide et un message texte clair.
- Si `--limit` est invalide, la commande échoue avec un message utilisateur et un code de sortie non nul.
