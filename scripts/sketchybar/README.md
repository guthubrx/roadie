# SketchyBar plugin — roadie desktops × stages (SPEC-023)

## Aperçu

Affiche dans la barre du haut macOS (SketchyBar) l'organisation desktops × stages courante de roadie : header par desktop, cartes stages avec couleur du stage actif, compteur de fenêtres, bouton `+` pour créer un stage, overflow `… +N` si > 3 desktops.

## Prérequis

- [SketchyBar](https://github.com/FelixKratz/SketchyBar) installé : `brew install FelixKratz/formulae/sketchybar`
- roadie daemon en cours d'exécution (`~/.local/bin/roadie daemon status` doit répondre)
- `~/.config/sketchybar/sketchybar/{items,plugins}/` doivent exister

## Installation

```bash
cd /path/to/roadies-repo
./scripts/sketchybar/install.sh
sketchybar --reload
```

L'install :
1. Symlinke les 5 fichiers (`items/roadie_panel.sh`, `plugins/roadie_panel.sh`, `plugins/roadie_event_bridge.sh`, `lib/colors.sh`, `lib/state.sh`) depuis `scripts/sketchybar/` vers `~/.config/sketchybar/sketchybar/`
2. Backup les fichiers existants (suffix `.bak.<timestamp>`)
3. Ajoute (idempotent) 2 lignes dans `~/.config/sketchybar/sketchybarrc`

Mode `--dry-run` pour voir ce qui serait fait sans rien modifier.

## Désinstallation

```bash
./scripts/sketchybar/install.sh --uninstall
sketchybar --reload
```

Retire les symlinks et restore les `.bak` les plus récents si présents.

## Comportement

- **Click sur une carte stage** → switch vers ce stage (CLI `roadie stage <id> --desktop N`)
- **Click sur le `+`** d'un desktop → crée un nouveau stage (CLI `roadie stage create`)
- **Click sur l'overflow `… +N`** → cycle vers le desktop suivant non affiché
- **Couleurs** : héritées de `[fx.rail.preview.stage_overrides]` du TOML utilisateur (vert stage 1, rouge stage 2, etc.). Fallback global `border_color` ou vert système Apple.

## Limitations

- **Cap à 3 desktops** affichés simultanément. Au-delà, un item `… +N` cliquable cycle vers les autres.
- **Pas d'icônes d'apps** dans les cartes stage (limitation SketchyBar : pas de layout vertical). Compteur `· N` à côté du nom à la place.
- **Parsing texte des CLIs** roadie (les `--json` ne sont pas encore implémentés en sortie JSON valide). À promouvoir en P3.

## Debug

Logs : `tail -f /tmp/roadie-sketchybar.log` montre les renders.
Re-render manuel : `sketchybar --trigger roadie_state_changed`.
