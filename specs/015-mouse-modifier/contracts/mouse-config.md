# Contract — SPEC-015 Mouse modifier drag/resize

**Date** : 2026-05-02 | **Phase** : 1

## TOML config schema

### Section `[mouse]` dans `~/.config/roadies/roadies.toml`

```toml
[mouse]
modifier = "ctrl"               # ctrl | alt | cmd | shift | hyper | none
action_left = "move"            # move | resize | none
action_right = "resize"         # move | resize | none
action_middle = "none"          # move | resize | none
edge_threshold = 30             # px (clamp [5, 200])
```

### Defaults

Si la section `[mouse]` est **absente** : tous les defaults s'appliquent comme ci-dessus.

Si un champ individuel est absent :
- `modifier` → `"ctrl"`
- `action_left` → `"move"`
- `action_right` → `"resize"`
- `action_middle` → `"none"`
- `edge_threshold` → `30`

### Validation

| Champ | Valides | Invalide → |
|---|---|---|
| `modifier` | ctrl, alt, cmd, shift, hyper, none | fallback `ctrl` + log warn |
| `action_*` | move, resize, none | fallback `none` + log warn |
| `edge_threshold` | int 5..200 | clamp + log warn |

---

## Hooks publics

Aucun nouveau verbe CLI ni endpoint JSON-RPC. La feature est **config-only**.

`roadie daemon reload` re-charge la config et reinit le `MouseDragHandler`.

---

## Events émis (informatif)

Optionnel V1 : émettre un event `window_drag_start` / `window_drag_end` via `EventBus.shared` pour SketchyBar. **Reporté V2** sauf demande explicite.

---

## Permissions macOS

- **Input Monitoring** : déjà acquise pour `MouseRaiser`. Aucune nouvelle prompt.
- **Accessibility** : déjà acquise pour AX `setBounds` (= core daemon).

Si Input Monitoring est révoquée par l'utilisateur entre 2 sessions :
- Boot du daemon log : `mouse drag/resize disabled — grant Input Monitoring permission`.
- `MouseDragHandler` ne s'initialise pas.
- `MouseRaiser` est aussi désactivé (déjà géré).
- Le reste du daemon fonctionne normalement (tile, focus via CLI, etc.).

---

## Erreurs et codes

| Cas | Behavior |
|---|---|
| TOML mode invalide | warn log, fallback default |
| Permission absente | error log, feature désactivée |
| `setBounds` AX failed (app non-cooperative) | silently skip ce frame (pattern best-effort) |
| Modifier relâché en cours de drag | continuer le drag jusqu'au mouseUp (pattern standard) |
