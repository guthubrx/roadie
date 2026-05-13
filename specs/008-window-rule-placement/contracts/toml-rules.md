# Contract: règles TOML de placement

## Exemple minimal stage

```toml
[[rules]]
id = "bluejay-media"
priority = 100

[rules.match]
app = "BlueJay"

[rules.action]
assign_stage = "Media"
```

## Exemple écran + stage

```toml
[[rules]]
id = "slack-com-external"
priority = 100

[rules.match]
app = "Slack"

[rules.action]
assign_display = "LG HDR 4K"
assign_stage = "Com"
follow = false
```

## Exemple suivi de focus explicite

```toml
[[rules]]
id = "monitoring-follow"
priority = 100

[rules.match]
app_regex = "Grafana|Prometheus"

[rules.action]
assign_display = "Built-in Display"
assign_stage = "Monitoring"
follow = true
```

## Sémantique

- `assign_display` accepte un ID d'écran Roadie ou un nom d'écran macOS.
- `assign_stage` accepte un ID de stage ou un nom de stage.
- `follow` est optionnel et vaut `false` par défaut.
- Si l'écran cible est absent, Roadie reporte le placement et laisse la fenêtre dans son contexte courant.
- Si la fenêtre est déjà dans la bonne destination, Roadie n'applique rien.
