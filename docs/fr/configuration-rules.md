# Configuration et rules

## Fichier de configuration

Roadie lit sa configuration utilisateur ici :

```text
~/.config/roadies/roadies.toml
```

Les rules creees depuis l'interface sont stockees a part :

```text
~/.config/roadies/roadies.generated.toml
```

Roadie charge les deux fichiers. Le fichier `roadies.toml` reste la source
humaine, et `roadies.generated.toml` contient les affinites creees depuis les
menus.

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

`default_strategy` accepte `bsp`, `mutableBsp`, `masterStack` ou `float`.

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

## Navrail

```toml
[fx.rail]
renderer = "stacked-previews"
width = 150
auto_hide = false
layout_mode = "overlay"
dynamic_left_gap = false
empty_click_hide_active = true
empty_click_safety_margin = 12
```

Options importantes :

- `empty_click_hide_active` : autorise le clic sur zone vide du navrail pour basculer vers une stage vide. Mets `false` si tu veux que les zones vides ne fassent rien.
- `empty_click_safety_margin` : marge horizontale minimale avant qu'un clic vide soit accepte.
- `layout_mode = "resize"` reserve une bande au navrail; `overlay` laisse le rail au-dessus du bureau.
- les clics dans les zones macOS reservees, comme la barre de menu, sont ignores.

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
assign_display = "LG HDR 4K"
assign_stage = "shell"
follow = false
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
- `assign_display` : ecran cible, resolu par ID Roadie, nom d'ecran, puis index numerique.
- `assign_stage` : stage cible, resolue par ID puis par nom visible. Si elle n'existe pas, Roadie la cree.
- `follow` : active la destination et focalise la fenetre apres placement si `true`. Par defaut `false`.
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

## Placement automatique

Pour ouvrir une application toujours sur une stage et un ecran precis :

```toml
[[rules]]
id = "slack-com"
priority = 100

[rules.match]
app = "Slack"

[rules.action]
assign_display = "LG HDR 4K"
assign_stage = "Com"
follow = false
```

Roadie ne vole pas le focus par defaut. Si l'ecran cible est absent, la fenetre reste dans son contexte courant et Roadie publie un evenement `rule.placement_deferred`.

Depuis le menu de clic droit de barre de titre, la section
`Affinite d'ouverture` peut creer la meme rule sans modifier `roadies.toml` :

- `Toujours ouvrir cette app ici` : match par app;
- `Toujours ouvrir cette app + ce titre ici` : match par app et titre;
- `Retirer l'affinite pour cette app` : supprime les rules generees pour cette app.

La destination `ici` correspond a l'ecran, au desktop Roadie et a la stage de la
fenetre cliquee. Le daemon recharge automatiquement ces rules generees quand le
fichier change.

## Explain

```bash
./bin/roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Utilise `explain` avant d'ajouter une rule en production locale. C'est l'equivalent d'un dry-run : Roadie montre quelle rule matcherait et quelles actions seraient appliquees.
