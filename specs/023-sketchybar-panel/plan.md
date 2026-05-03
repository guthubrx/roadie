# Plan: SketchyBar plugin desktops × stages

**Spec**: SPEC-023 | **Branch**: `023-sketchybar-panel`

## Vision technique

Plugin SketchyBar pur bash + jq, alimenté par les CLIs roadie existantes. Aucun nouveau code Swift. 4 fichiers, ≤ 250 LOC totales. Versionné dans le repo, installé via symlink vers `~/.config/sketchybar/`.

## Phase 0 — Research

Voir `research.md` :
- Limites SketchyBar : items horizontaux uniquement, pas de layout vertical, pas d'icônes empilées sous un texte → on opte pour un compteur `· N` à côté du nom.
- Les CLIs roadie nécessaires existent toutes : `desktop list --json`, `stage list --display X --desktop N --json`, `windows list --json`, `events --follow --types`.
- Le bridge actuel filtre uniquement `desktop_changed` — extension nécessaire mais simple (1 ligne).

## Phase 1 — Design

Voir `data-model.md` pour la structure des items SketchyBar et le mapping events → updates.

### Architecture

```
~/.config/sketchybar/sketchybarrc
    ├── source $ITEM_DIR/roadie_panel.sh        ← (NEW) crée tous les items
    └── $PLUGIN_DIR/roadie_event_bridge.sh &    ← (UPDATED) écoute plus d'events
            │
            ├── roadie events --follow --types desktop_changed,stage_changed,
            │                                  stage_assigned,window_assigned,
            │                                  window_destroyed,window_created
            │
            └── pour chaque event → sketchybar --trigger roadie_state_changed

scripts/sketchybar/items/roadie_panel.sh        ← items declaration (boot only)
scripts/sketchybar/plugins/roadie_panel.sh     ← handler (re-render à chaque event)
scripts/sketchybar/plugins/roadie_event_bridge.sh ← (étendu)
scripts/sketchybar/install.sh                   ← script d'install symlink
```

### Naming convention items

| Item | Nom SketchyBar | Type |
|---|---|---|
| Header desktop N | `roadie.desktop.N` | label `🏠 Bureau N` (ou label custom) |
| Carte stage M de desktop N | `roadie.stage.N.M` | label `Stage M · K`, click = switch |
| Bouton "+" du desktop N | `roadie.add.N` | label `+`, click = create stage |
| Overflow item | `roadie.overflow` | label `… +K`, click = next desktop |

### Algorithme de re-render (handler)

À chaque trigger `roadie_state_changed` :
1. Lire l'état complet : `roadie desktop list --json` → desktops (max 3 récents) + overflow_count
2. Pour chaque desktop affiché : `roadie stage list --display $uuid --desktop $id --json` → stages
3. Pour chaque stage : compter wids via `roadie windows list --json | jq '[.windows[] | select(.stage == "M" and .desktop_id == N)] | length'`
4. Lire les couleurs actives depuis le TOML utilisateur (parsing `[fx.rail.preview.stage_overrides]`)
5. Remove all current `roadie.*` items
6. Re-add tous les items dans l'ordre voulu (left side de la barre)

Compromise perf : remove-all-then-readd est O(N) à chaque event. Acceptable car N ≤ 3 desktops × 4 stages × 2 = 24 items max. SketchyBar gère ça en < 50 ms.

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| **Article A'** (≤ 200 LOC effectives par fichier) | 4 fichiers × 50-80 LOC = sous le plafond. | ✅ |
| **Article B'** (pas de dépendance externe non justifiée) | `jq` (déjà utilisé), `sketchybar` (déjà installé), `roadie` CLI. Aucune nouvelle. | ✅ |
| **Article D'** (pas de `try!` / `print()`) | Bash + jq, pas de Swift. N/A. | ✅ |
| **Article G'** (LOC plafond cible/strict par SPEC) | Cible 250 LOC totales. | ✅ |

## Phase 2 — Tasks

Voir `tasks.md` (~25 tâches, MVP US1 + US4 install).

## Risques

| Risque | Mitigation |
|---|---|
| `roadie stage list --json --display X --desktop N` n'existe pas tel quel | Vérifier au début de Phase 5 ; sinon adapter en utilisant `roadie desktop current --json` + parsing |
| Couleurs TOML stages_overrides : parsing bash naïf casse | Utiliser `taplo` ou `tomlq` si dispo, sinon parser `awk`-style (très simple, on cherche juste `active_color = "#..."`) |
| Bridge events : la liste des `--types` doit matcher exactement la allow-list du daemon | Vérifier au début ; si rejet, fallback `--follow` sans filter |
| SketchyBar refuse d'ajouter trop d'items | Cap dur côté script à 24 items roadie max |
