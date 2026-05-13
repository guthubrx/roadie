# Quickstart: Placement des fenêtres par règle

## Configurer une règle

Ajouter dans `~/.config/roadies/roadies.toml` :

```toml
[[rules]]
id = "bluejay-media"
priority = 100

[rules.match]
app = "BlueJay"

[rules.action]
assign_display = "Built-in Display"
assign_stage = "Media"
follow = false
```

## Valider

```bash
roadie config validate
```

## Relancer Roadie

```bash
./scripts/start
```

## Tester

1. Ouvrir l'application ciblée.
2. Vérifier que sa fenêtre rejoint la stage cible.
3. Vérifier que la stage courante ne change pas si `follow = false`.
4. Passer `follow = true`, relancer, puis vérifier que la stage cible devient active.
