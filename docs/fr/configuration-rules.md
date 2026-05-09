# Configuration et rules

## Fichier de configuration

Roadie lit sa configuration utilisateur ici :

```text
~/.config/roadies/roadies.toml
```

Commandes utiles :

```bash
./bin/roadie config validate
./bin/roadie config show
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
```

## Layout

Exemple :

```toml
[tiling]
default_strategy = "bsp"
gaps_outer = 8
gaps_inner = 4
master_ratio = 0.6
smart_gaps_solo = true
```

Cas d'usage :

- reduire les gaps sur un petit ecran;
- garder `masterStack` par defaut pour une stage de lecture;
- activer `smart_gaps_solo` pour ne pas gaspiller d'espace avec une seule fenetre.

## Stages predefinies

```toml
[stage_manager]
enabled = true
default_stage = "1"

[[stage_manager.workspaces]]
id = "dev"
display_name = "Dev"

[[stage_manager.workspaces]]
id = "docs"
display_name = "Docs"
```

Cas d'usage :

- donner des noms stables aux stages;
- synchroniser des raccourcis BTT avec des noms humains.

## Ajustement manuel de largeur

```toml
[width_adjustment]
presets = [0.5, 0.67, 0.8, 1.0]
nudge_step = 0.05
minimum_ratio = 0.25
maximum_ratio = 1.5
```

Ces valeurs sont utilisees uniquement par les commandes manuelles `roadie layout width ...`.

Cas d'usage :

- passer rapidement d'une demi-largeur a deux tiers d'ecran;
- nudger une fenetre par petits pas;
- borner les ratios pour eviter des frames absurdes.

## Rules

Les rules automatisent l'assignation ou l'etiquetage des fenetres.

```toml
[[rules]]
id = "terminal-dev"
enabled = true
priority = 20
stop_processing = true

[rules.match]
app = "Terminal"
title_regex = "roadie|zsh"
role = "AXWindow"
stage = "dev"

[rules.action]
assign_desktop = "1"
assign_stage = "shell"
floating = false
layout = "tile"
gap_override = 4
scratchpad = "terminals"
emit_event = true
```

## Champs de match

- `app` : nom exact de l'app.
- `app_regex` : regex testee sur le nom d'app et le bundle ID.
- `title` : titre exact.
- `title_regex` : regex sur le titre.
- `role` : role Accessibility.
- `subrole` : subrole Accessibility.
- `display` : ID d'ecran Roadie.
- `desktop` : desktop Roadie.
- `stage` : stage Roadie.
- `is_floating` : booleen.

Une rule doit avoir au moins un champ de match.

## Actions

- `manage` : marqueur pour effets futurs.
- `exclude` : sort la fenetre du tiling.
- `assign_desktop` : desktop cible.
- `assign_stage` : stage cible.
- `floating` : comportement flottant.
- `layout` : indication de layout.
- `gap_override` : override de gaps.
- `scratchpad` : marqueur scratchpad expose dans l'evaluation.
- `emit_event` : marqueur de politique evenementielle.

## Validation

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
```

Erreurs detectees :

- `id` vide;
- `id` duplique;
- aucun matcher;
- regex invalide;
- `exclude=true` combine avec des actions de placement/layout.

## Explain

```bash
./bin/roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Utilise `explain` avant d'ajouter une rule en production locale. C'est l'equivalent d'un dry-run : Roadie montre quelle rule matcherait et quelles actions seraient appliquees.
