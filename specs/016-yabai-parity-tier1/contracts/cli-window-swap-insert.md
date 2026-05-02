# Contract — CLI & IPC `window swap` / `window insert` (US1a, US4 / FR-A5-*, FR-A4-*)

**Status**: Done
**Last updated**: 2026-05-02

## 1. `roadie window swap <direction>` (FR-A5-*)

### CLI

```bash
roadie window swap left       # échange focused ↔ neighbor à gauche
roadie window swap right
roadie window swap up
roadie window swap down
```

### Sémantique

- Échange les **références** des 2 fenêtres dans le tree, **sans modifier la structure** (parent, splits, ratios sont préservés).
- Différent de `move` (qui réorganise l'arbre) et de `warp` (qui détache + ré-insère).
- Focus reste sur la même fenêtre logique (qui a changé de position visuellement).

### Acceptance scenarios (récap spec §US1a)

| Scenario | Comportement attendu |
|---|---|
| `[A \| B]`, focus B, `swap left` | `[B \| A]`, focus toujours sur B, ratio préservé |
| `[A \| (B / C)]`, focus A, `swap right` | A échangée avec B (premier leaf vers la droite) |
| Solo dans le tile, `swap left` | no-op + warn `no neighbor in direction left`, exit 1 |
| Focus floating, `swap left` | no-op + warn `cannot swap floating window`, exit 1 |
| Inter-display, `swap right` (neighbor sur display 2) | swap OK, frames adoptées dans les 2 trees respectifs |

### IPC

**Requête** :
```json
{"cmd": "window.swap", "args": {"direction": "left|right|up|down"}}
```

**Réponse OK** :
```json
{
  "status": "ok",
  "data": {
    "swapped_with": 23456,
    "from_wid": 12345,
    "from_display": 1,
    "to_display": 1
  }
}
```

**Réponse erreur (no neighbor)** :
```json
{
  "status": "error",
  "code": "no_neighbor",
  "message": "no neighbor in direction 'left' for wid 12345"
}
```

| Code erreur | Cas |
|---|---|
| `no_focused_window` | Pas de focused window |
| `no_neighbor` | Pas de voisine dans la direction |
| `not_tileable` | Focused window est floating |
| `invalid_direction` | Direction non reconnue |

## 2. `roadie window insert <direction>` (FR-A4-*)

### CLI

```bash
roadie window insert north     # next window splittera au-dessus de focused
roadie window insert south     # en dessous
roadie window insert east      # à droite
roadie window insert west      # à gauche
roadie window insert stack     # empilera (US5/SPEC-017 ; fallback split en attendant)
```

### Sémantique

- Pose un **hint runtime** attaché à la `focusedWindowID`.
- Le hint est consommé par la **prochaine** création de fenêtre dans le tree de la fenêtre cible.
- TTL : 120 s (configurable `[insert] hint_timeout_ms`).
- Si la fenêtre cible est fermée avant consommation → hint orphelin retiré silencieusement.
- Si `tiler.set` change la stratégie → tous les hints sont flushés + log info.
- Si `--insert stack` mais SPEC-017 pas livrée → fallback split par défaut + log info `stack mode not yet implemented, falling back to default split`.

### Acceptance scenarios (récap spec §US4)

| Scenario | Comportement attendu |
|---|---|
| Focus A, `insert east`, ouvrir B | `[A \| B]` (split V à droite) |
| Focus A, `insert south`, ouvrir B | `[A / B]` (split H en bas) |
| Focus A, `insert stack`, ouvrir B | Fallback split par défaut + log info |
| Hint posé, 120 s sans nouvelle fenêtre | Hint expire silencieusement |
| Hint posé, focus change, ouvrir B | Hint reste attaché à la fenêtre originale → split à côté de A, pas du focus courant |
| Hint sur fenêtre A floating, ouvrir B | B floating à la place attendue |
| `insert <dir>` sans focused | Erreur `no_focused_window` |
| `[insert] show_hint = true` | Overlay visuel discret sur le bord cible (V1.1, optionnel V1) |

### IPC

**Requête** :
```json
{"cmd": "window.insert", "args": {"direction": "north|south|east|west|stack"}}
```

**Réponse OK** :
```json
{
  "status": "ok",
  "data": {
    "hint_target_wid": 12345,
    "direction": "east",
    "expires_at": "2026-05-02T18:32:42.000Z"
  }
}
```

**Réponse erreur** :
```json
{
  "status": "error",
  "code": "no_focused_window",
  "message": "no focused window to attach hint to"
}
```

| Code erreur | Cas |
|---|---|
| `no_focused_window` | Pas de focused window |
| `invalid_direction` | Direction non reconnue (hors {north, south, east, west, stack}) |

### Configuration `[insert]`

```toml
[insert]
hint_timeout_ms = 120000        # default 2 min
show_hint = false               # overlay visuel sur le bord cible (V1.1)
```

## 3. Effets de bord

### Sur les events EventBus

- `window.swap` ne publie **pas** d'event spécifique (les frames changent → `window_moved` est publié pour les 2 wid).
- `window.insert` ne publie **pas** d'event spécifique (le hint est silencieux).
- Quand le hint est consommé : pas d'event spécifique non plus (la nouvelle fenêtre déclenche `window_created` standard, le split est implicite dans `window_moved`).

### Sur la persistance

- Aucune persistance pour swap (juste un changement de tree).
- Aucune persistance pour les hints (purement runtime mémoire).

### Sur les rules SPEC-016 US2

- Une rule `space=N` ne déclenche PAS automatiquement un swap (les rules placent les nouvelles fenêtres, ne réorganisent pas l'existant).
- Un swap appliqué à une fenêtre concernée par une rule `manage=off` → no-op + warn (cohérent avec edge case "swap floating").

## 4. Hors scope V1

- `roadie window swap <wid_target>` (swap explicite sans direction). À considérer V2 pour scripting fin.
- `roadie window insert <wid_target> <direction>` (cible explicite hors focused). V2.
- Annulation explicite d'un hint (`roadie window insert cancel`). V2 si demande.
- Hints multiples sur la même fenêtre cible. V1 = remplace silencieusement le hint précédent.
