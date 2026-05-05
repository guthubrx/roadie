# TOML Schema — SPEC-026

## Nouvelles clés / sections

### `[tiling] smart_gaps_solo`

```toml
[tiling]
smart_gaps_solo = false   # Default: false. Si true, gaps_outer/gaps_inner = 0 sur un display contenant 1 seule fenêtre tilée.
```

Type : `Bool`. Validation : aucune (boolean). Si valeur invalide, fallback `false` + log warn.

### `[focus] focus_follows_mouse`, `[focus] mouse_follows_focus`

```toml
[focus]
focus_follows_mouse = false   # Default: false. Si true, hover souris → focus AX.
mouse_follows_focus = false   # Default: false. Si true, raccourci focus → warp curseur au centre de la fenêtre.
```

Type : `Bool` chacun. Indépendants. Activation simultanée OK (anti-feedback loop intégré).

### `[signals]` + `[[signals]]`

```toml
[signals]
enabled = true   # Default: true. Kill-switch global. false = aucun signal n'est lancé.

[[signals]]
event = "window_focused"
cmd = "afplay /System/Library/Sounds/Tink.aiff"

[[signals]]
event = "stage_changed"
cmd = "/Users/moi/scripts/notify-stage.sh"
```

**Events supportés** :
- `window_focused`
- `window_created`
- `window_destroyed`
- `stage_changed`
- `desktop_changed`
- `display_changed`

**Variables d'environnement injectées** (selon disponibilité) :
- `ROADIE_EVENT` : nom de l'event (string)
- `ROADIE_WID` : CGWindowID concerné (string)
- `ROADIE_BUNDLE_ID` : bundleID de l'app (string)
- `ROADIE_STAGE` : stage ID (string)
- `ROADIE_DESKTOP` : desktop ID (string)
- `ROADIE_DISPLAY` : displayUUID (string)

**Timeout** : 5 secondes strict. SIGTERM puis SIGKILL si nécessaire.

### `[[scratchpads]]`

```toml
[[scratchpads]]
name = "term"
cmd = "open -na 'iTerm'"
match.bundle_id = "com.googlecode.iterm2"   # optionnel, override heuristic

[[scratchpads]]
name = "calc"
cmd = "open -na 'Calculator'"
```

`name` : unique. `cmd` : commande shell. `match.bundle_id` : optionnel, force le bundle attaché plutôt que l'heuristic.

### `[[rules]]` extension : `sticky_scope`

```toml
[[rules]]
match.bundle_id = "com.tinyspeck.slackmacgap"
sticky_scope = "stage"   # Default "stage" si absent.

[[rules]]
match.bundle_id = "com.apple.Music"
sticky_scope = "all"
```

**Valeurs** : `"stage"`, `"desktop"`, `"all"`. Valeur invalide → fallback `"stage"` + log warn.

## Compatibilité ascendante

- Toutes les nouvelles clés ont des défauts qui préservent le comportement actuel :
  - `smart_gaps_solo = false` (gaps appliqués comme avant)
  - `focus_follows_mouse = false` (pas de hover focus)
  - `mouse_follows_focus = false` (pas de warp)
  - `signals.enabled = true` mais aucun `[[signals]]` défini = inerte
  - `[[scratchpads]]` absent = commande `roadie scratchpad toggle` retourne erreur explicite
  - `sticky_scope` absent dans une rule = comportement legacy (pas sticky)
- Aucune clé existante n'est modifiée ou supprimée.

## Reload à chaud

`roadie daemon reload` propage toutes les nouvelles clés. Effets de bord :
- Activation/désactivation focus_follows_mouse → install/uninstall NSEvent monitor.
- Modification signals → re-subscribe SignalDispatcher au EventBus.
- Ajout/suppression `[[scratchpads]]` → mise à jour catalogue ScratchpadManager (les états runtime des scratchpads existants persistent).
- Modification `[[rules]] sticky_scope` → re-projection memberWindows au prochain stage_changed.
