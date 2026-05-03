# Research: SketchyBar plugin desktops × stages

**Spec**: SPEC-023 | **Created**: 2026-05-03

## Limites SketchyBar (à connaître pour ne pas tenter l'impossible)

SketchyBar = barre **strictement horizontale** d'items. Chaque item = label + icône + background. Le layout vertical natif n'existe pas. Pour reproduire un mockup style « cartes empilées avec icônes d'app sous le label », il faudrait soit :
- Plusieurs items adjacents qui simulent la hiérarchie (couteux en espace barre)
- Un mode `popup` qui montre des items flottants au survol (existe mais complexe à styliser)

Décision : on opte pour **compteur `· N` à côté du nom du stage** (ex: `Stage 1 (actif) · 3`) au lieu d'icônes empilées. Plus lisible, économe en espace.

## CLIs roadie nécessaires

| CLI | Existe ? | Commentaire |
|---|---|---|
| `roadie desktop list --json` | ✅ | retourne `[{id, label, isActive, ...}]` |
| `roadie desktop current --json` | ✅ | retourne `{id, label, ...}` |
| `roadie stage list --json` | ✅ | retourne `{stages: [{id, displayName, isActive, windowIDs, ...}]}` |
| `roadie stage list --display X --desktop N --json` | ⚠️ à vérifier | flags `--display`/`--desktop` existent (SPEC-018), `--json` à confirmer |
| `roadie windows list --json` | ✅ | retourne `{windows: [{id, stage, desktop_id, ...}]}` |
| `roadie events --follow --types ...` | ✅ | allow-list serveur étendue à 14 types (SPEC-019) |
| `roadie stage <id>` (switch) | ✅ | accepte aussi `--display X --desktop N` (SPEC-022) |
| `roadie stage create <id> <name>` | ✅ | accepte aussi `--display X --desktop N` |

## Pattern de bridge SketchyBar existant

Le fichier `~/.config/sketchybar/sketchybar/plugins/roadie_event_bridge.sh` existe déjà et fonctionne :

```bash
"$ROADIE" events --follow --filter desktop_changed | while IFS= read -r line; do
    FROM=$(echo "$line" | jq -r '.from // ""')
    TO=$(echo "$line" | jq -r '.to // ""')
    sketchybar --trigger roadie_desktop_changed FROM="$FROM" TO="$TO"
done
```

Notre extension : remplacer `--filter desktop_changed` par `--types desktop_changed,stage_changed,stage_assigned,window_assigned,window_destroyed,window_created` et émettre un trigger générique `roadie_state_changed` au lieu de `roadie_desktop_changed`. Le handler re-genère tout.

Note : le flag est `--filter` dans l'existant mais `--types` dans le contrat events-stream depuis SPEC-014. À vérifier en Phase 5 lequel marche, fallback sur l'autre.

## Performance attendue

Pour un setup typique (3 desktops × 3 stages × ~5 wids / stage) :
- `roadie desktop list --json` : ~10 ms
- `roadie stage list --display X --desktop N --json` × 3 : ~30 ms
- `roadie windows list --json` : ~15 ms
- jq parsing + comptage : ~5 ms
- SketchyBar `--remove` puis `--add` × 24 items : ~50 ms

Total ≤ 110 ms par re-render. Acceptable.

Optimisation possible (phase 2) : ne re-générer que la partie modifiée si l'event est ciblé (ex: `window_created` → maj juste le compteur du stage concerné, pas tout reconstruire). Pas dans le MVP.

## Couleurs depuis TOML utilisateur

Parsing du fichier `~/.config/roadies/roadies.toml` pour extraire :

```toml
[fx.rail.preview]
border_color          = "#FFFFFF40"
border_color_inactive = "#7F7F7F33"

[[fx.rail.preview.stage_overrides]]
stage_id     = "1"
active_color = "#9ECE6A"

[[fx.rail.preview.stage_overrides]]
stage_id     = "2"
active_color = "#F7768E"
```

Approche bash pure (pas de lib TOML) : grep + awk sur les patterns connus. Ex :

```bash
get_stage_color() {
    local stage_id="$1"
    local toml="$HOME/.config/roadies/roadies.toml"
    awk -v sid="$stage_id" '
        /^\[\[fx\.rail\.preview\.stage_overrides\]\]/ { in_block = 1; next }
        in_block && /stage_id/ { gsub(/[ "=]/, "", $0); current = substr($0, length("stage_id")+1); next }
        in_block && /active_color/ {
            gsub(/[ "=]/, "", $0); color = substr($0, length("active_color")+1)
            if (current == sid) { print color; exit }
            in_block = 0
        }
    ' "$toml"
}
```

Limite : si l'utilisateur a un format TOML inhabituel (commentaires inline, multi-line strings), le parser bash naïf peut casser. Mitigation : fallback sur la couleur par défaut globale (vert `#34C759`) si `get_stage_color` retourne rien.

Couleurs SketchyBar : format hex AARRGGBB (alpha en premier). Conversion `#RRGGBB` → `0xff` + RRGGBB ou `#RRGGBBAA` → `0x` + AA + RRGGBB. Helper bash inline.

## Sources

- SketchyBar README : <https://github.com/FelixKratz/SketchyBar>
- yabai-sketchybar integration patterns (Discussion GitHub)
- Pattern existant `~/.config/sketchybar/sketchybar/plugins/roadie_*` du repo utilisateur
- contrats events-stream-rail.md du repo (SPEC-014 + SPEC-018)
