# Configuration et rules

## Modifier les réglages dans Roadie

La commande `/settings` ouvre la fenêtre de paramètres. Les valeurs valides
s'appliquent pendant la saisie, sans Retour. Les listes, stages, règles et
exceptions disposent d'éditeurs intégrés. Les fragments complexes exigent un
enregistrement explicite dans l'éditeur avancé.
Les `signals.hooks` peuvent être enregistrés dans cet éditeur, mais Roadie ne
les exécute pas actuellement.

Une modification de marge ou d'espacement retuile les fenêtres. Les valeurs
par écran ou par côté gardent leur priorité sur la marge générale. Le fichier
reste disponible pour les usages avancés ; son édition n'est pas nécessaire
pour les réglages courants.

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
roadie config validate
roadie config show
roadie rules validate --config ~/.config/roadies/roadies.toml
```

## Fichier d'exemple et validation

Un exemple complet et commenté est dans `examples/roadies.toml`, à la racine du dépôt. Copie-le comme point de départ :

```bash
mkdir -p ~/.config/roadies
cp examples/roadies.toml ~/.config/roadies/roadies.toml
roadie config validate
```

`config validate` signale chaque problème sur une ligne : niveau, nom complet de la clé, message.

| Niveau | Exemple | Sens |
|---|---|---|
| `error` | `focus.stage_follows_focus  attendu booléen, reçu texte` | La valeur a le mauvais type, ou une clé obligatoire manque. Roadie garde la dernière configuration valide. |
| `warning` | `tiling.gaps_inr  clé inconnue, ignorée ; vouliez-vous dire « gaps_inner » ?` | Clé ou table inconnue. Roadie l'ignore. La suggestion est le nom valide le plus proche. |
| `warning` | `desktops.count  clé sans effet` | Roadie lit la clé mais ne l'utilise pas. |

Clés sans effet aujourd'hui : toute la table `[desktops]`, ainsi que `enabled` et `hide_strategy` dans `[stage_manager]`. Retire-les de ton fichier. Les desktops Roadie sont toujours disponibles, et tu les crées avec les commandes `roadie desktop`.

Toutes les tables lues par le rail sont acceptées : `[fx.rail]` et ses sous-tables `layout`, `header`, `header.display`, `header.desktop`, `stages`, `preview`, `stacked`, `stage_labels` et `parallax`.

Dans **Paramètres > Rail**, « Aimantation du réordonnancement (%) » stabilise la destination de l’aperçu lors du glisser droit. La clé `fx.rail.stages.reorder_magnetism` va de 0 à 100 (défaut 50). À 0, elle est désactivée. Le curseur de souris reste libre. Le réglage s’applique sans redémarrage.

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

`default_strategy` accepte `bsp`, `spatialBsp`, `masterStack` ou `float`.
`mutableBsp` et `yabai` restent des alias de `spatialBsp`.
Le menu de découpage propose `largest_dim`, `dwindle` et `balanced`.
Ce dernier choix reste disponible pour les configurations anciennes.

Cas d'usage :

- reduire les gaps sur un petit ecran;
- garder `masterStack` par defaut pour une stage de lecture;
- activer `smart_gaps_solo` pour ne pas gaspiller d'espace avec une seule fenetre.

## Stages predefinies

```toml
[stage_manager]
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
empty_click_hide_active = false
empty_click_safety_margin = 12
```

Options importantes :

- `empty_click_hide_active` : autorise le clic sur zone vide du navrail pour basculer vers une stage vide. Le défaut est `false` pour qu'un clic raté ne masque pas la stage active.
- `empty_click_safety_margin` : marge horizontale minimale avant qu'un clic vide soit accepte.
- `layout_mode = "resize"` reserve une bande au navrail; `overlay` laisse le rail au-dessus du bureau.
- `hide_on_maximized` : le défaut est `false`. Le rail se masque seulement devant une fenêtre en plein écran natif macOS. Avec `true`, le rail se masque aussi devant une fenêtre qui remplit l'écran sans plein écran natif (fenêtre agrandie). Une fenêtre tilée seule dans sa stage ne compte pas comme agrandie.
- les clics dans les zones macOS reservees, comme la barre de menu, sont ignores.

## Ajustement manuel de largeur

```toml
[width_adjustment]
presets = [0.5, 0.67, 0.8, 1.0]
nudge_step = 0.05
minimum_ratio = 0.25
maximum_ratio = 1.5
```

Ces valeurs concernent uniquement les commandes manuelles `roadie layout width ...` en `bsp` et `masterStack`. Elles ne s’appliquent pas à `spatialBsp`. Utilise `resize` dans le mode arbre.

Cas d'usage :

- passer rapidement d'une demi-largeur a deux tiers d'ecran;
- nudger une fenetre par petits pas;
- borner les ratios pour eviter des frames absurdes.

## Typographie

Les tailles de la fenêtre de paramètres et celles des autres surfaces sont
indépendantes. Elles s'appliquent aux interfaces déjà ouvertes.

```toml
[interface]
settings_text_font_size = 16
settings_help_font_size = 14
settings_title_font_size = 22
language = "auto"              # "auto" (langue de macOS), "fr" ou "en" ; Roadie redémarre pour l'appliquer

[experimental.target_mode]
search_text_font_size = 15
command_text_font_size = 13
search_font_family = "system"
command_font_family = "system"
```

Dans Recherche, choisir séparément la famille et la taille du champ de saisie
et des suggestions. Le menu liste les familles installées. `system`, une valeur
vide ou une famille absente utilise la police macOS.
Voir la [référence des tailles d'interface](features.md).

## Mode Cibles Et Grilles

Les noms utilisateur sont **Mode Cibles**, **Grille Ecran** et **Grille
Fenetre**. Les cles TOML gardent leurs noms techniques pour compatibilite.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = true
overlay_duration_seconds = 10
app_mouse_actions_enabled = true
search_hotkey = "command+control+alt+f"   # "" desactive ; alias "hyper", "ctrl"

[experimental.app_targets]
enabled = true
scope = "frontmost_window"   # ou "visible_windows" (mode lettres sur toutes les fenetres visibles)
max_targets = 150
timeout_ms = 120

[experimental.target_grid]
enabled = true
overlay_enabled = true
rows = 3
columns = 3
max_depth = 3
hint_characters = "azeqsdwxc"
label_placement = "center"
mouse_follow_grid = true
focus_follow_grid = true
wake_mouse_pixels = 1

[experimental.target_record]
enabled = true
indicator = "navrail"
navrail_bottom_offset = 50
```

Cas d'usage :

- activer les labels clavier sur les objets Roadie;
- utiliser Grille Ecran quand toute la surface de l'ecran est la cible;
- utiliser Grille Fenetre quand la fenetre focussee est la surface de travail;
- afficher l'enregistrement de macro dans le navrail sans passer par une notification.

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

## Fenêtres toujours flottantes

Pour garder hors du tuilage certaines fenêtres d'une application seulement (rappels, boîtes de dialogue),
sans écrire de règle complète :

```toml
[[exclusions.floating_windows]]
app = "Thunderbird"        # nom affiché ou identifiant (org.mozilla.thunderbird)
title = "# Reminder"       # # : un nombre ; * : n'importe quel texte ; sans casse
remember_frame = true      # facultatif : rouvre là où vous l'avez laissée (position et taille)
```

La liste se modifie aussi dans Paramètres > Règles et depuis le menu Fenêtre de la barre de titre.
`remember_frame = true` vaut aussi dans l'`action` d'une règle (`action = { exclude = true, remember_frame = true }`).
Une fenêtre flottante qui s'ouvre sur le rail est décalée à sa droite, sauf avec
`[exclusions] floating_avoid_rail = false`.

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
- `layout` : indication enregistrée, sans effet sur le tuilage actuellement.
- `gap_override` : valeur enregistrée, sans effet sur les marges actuellement.
- `scratchpad` : marqueur scratchpad expose dans l'evaluation.
- `emit_event` : marqueur de politique evenementielle.

## Validation

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
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
roadie rules explain --app Firefox --title "Roadie Documentation" --stage docs --json
```

Utilise `explain` avant d'ajouter une rule en production locale. C'est l'equivalent d'un dry-run : Roadie montre quelle rule matcherait et quelles actions seraient appliquees.
