# Quickstart: Roadie Target Mode

## Lister les cibles Roadie

```bash
roadie targets list
roadie targets list --json
roadie targets list --filter gray --json
```

## Inspecter une fenêtre ou une stage

```bash
roadie targets inspect A
roadie targets inspect window:123 --json
```

## Activer une cible

```bash
roadie targets activate A --action switch
roadie targets activate B --action focus
roadie targets activate C --action send-active
```

## Picker par recherche

```bash
roadie targets pick gray
roadie targets pick work --action switch
roadie targets pick button --source app --include-app-targets --action inspect
```

Si la requete est ambigue, Roadie affiche les candidates et ne change rien.
Si elle est unique, Roadie applique l'action demandee ou l'action par defaut.

## Accès agent

```bash
roadie query targets
```

Un agent peut :

1. lister les cibles en JSON ;
2. choisir une cible par type, nom ou scope ;
3. inspecter avant action ;
4. activer par ID plutôt que par coordonnées écran.

## App targets expérimentaux

Les zones sensibles applicatives sont désactivées par défaut. Une fois activées dans la configuration :

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
app_mouse_actions_enabled = false

[experimental.app_targets]
enabled = true
```

```bash
roadie targets list --source app --json
```

Les actions souris applicatives (`click`, `double-click`, `right-click`) restent
refusees tant que `app_mouse_actions_enabled = false`.

Si l'app ne répond pas vite, Roadie doit retourner un résultat partiel et ne jamais modifier les stages ou layouts.

## Grille récursive

```toml
[experimental.target_grid]
enabled = true
overlay_enabled = true
rows = 3
columns = 3
max_depth = 3
```

```bash
roadie grid show --json
roadie grid show A --visual --duration 2
roadie grid click A
roadie grid drag A L
```

La grille sert de langage spatial pour l'humain et pour l'agent. Elle ne touche
pas au tiler : elle poste seulement les événements souris demandés.

## Record/replay agent-friendly

```toml
[experimental.target_record]
enabled = true
replay_enabled = true
include_ax_context = true
record_text_input = false
```

```bash
roadie record start demo --duration 10
roadie record inspect demo --json
roadie record replay demo
```

Chaque clic conserve la meilleure cible Roadie/AX connue et un chemin de grille
de secours. Le texte saisi n'est pas enregistré par défaut.

## Overlay de hints

Cette livraison expose l'etat de labels sans forcer encore un overlay graphique
complet :

```bash
roadie targets show --json
roadie targets show --labels-only
roadie targets hide
```

`targets show` retourne les memes labels que `targets list`, ce qui permet de
brancher un overlay futur sans dupliquer le moteur de cibles. L'overlay visuel
doit rester separe du navrail pour ne pas toucher aux chemins critiques de
stage switch, focus et bordure.

## Raccourcis externes

BTT ou Karabiner peuvent rester de simples lanceurs :

1. afficher ou recuperer les labels avec `roadie targets show --json`;
2. activer un label avec `roadie targets activate LABEL`;
3. chercher une cible avec `roadie targets pick TEXTE`.

Roadie ne depend pas de BTT au runtime.
