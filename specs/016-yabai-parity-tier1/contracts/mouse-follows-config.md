# Contract — Configuration `[mouse]` étendue (US1b, US1c / FR-A6-*)

**Status**: Done
**Last updated**: 2026-05-02

## 1. Schema `[mouse]` complet (SPEC-015 + SPEC-016)

```toml
[mouse]
# === SPEC-015 (existant) ===
modifier = "ctrl"              # ctrl | alt | cmd | shift | hyper | none
action_left = "move"           # move | resize | none
action_right = "resize"
action_middle = "none"
edge_threshold = 30            # px (5..200)

# === SPEC-016 (nouveau) ===
focus_follows_mouse = "off"    # off | autofocus | autoraise
mouse_follows_focus = false    # bool
idle_threshold_ms = 200        # ms d'immobilité curseur avant migration focus (50..2000)
```

**Defaults appliqués si absente** : `focus_follows_mouse="off"`, `mouse_follows_focus=false`, `idle_threshold_ms=200`. Section `[mouse]` complète absente → daemon démarre avec defaults SPEC-015 + SPEC-016 (rétro-compatible).

## 2. `focus_follows_mouse` (US1b / FR-A6-01..04)

### Modes

| Valeur | Comportement |
|---|---|
| `"off"` | Aucun changement de focus déclenché par la souris (comportement default actuel) |
| `"autofocus"` | Curseur immobile `idle_threshold_ms` ms sur une fenêtre non-focused → focus migre. Pas de raise (fenêtre reste à sa profondeur z-order) |
| `"autoraise"` | Idem mais raise aussi (la fenêtre passe devant) |

### Acceptance (récap spec §US1b)

| Scenario | Comportement |
|---|---|
| `autofocus`, curseur immobile 200 ms sur fenêtre non-focused | Focus migre, pas de raise |
| `autoraise`, idem | Focus + raise |
| `off`, idem | Aucun changement |
| Jitter (curseur en mouvement continu), survol furtif | Pas de migration tant que pas immobile `idle_threshold_ms` |
| Survol Dock/MenuBar/desktop empty | Aucun changement (zones non-fenêtre) |
| Drag actif (SPEC-015) | Watcher suspendu jusqu'au release |
| Modale système (Save dialog) | Watcher suspendu (la modale capture l'event handling) |

### Implémentation

- `MouseFollowFocusWatcher` polling `Timer` 50 ms + `NSEvent.mouseLocation`.
- Coordination avec `MouseDragHandler` (SPEC-015) via `MouseInputCoordinator.dragActive` flag.
- Aucune permission supplémentaire requise (Input Monitoring déjà demandée par SPEC-015 pour `addGlobalMonitorForEvents`).

### Détails techniques

- **Coût CPU** : ~0.8 % à 20 Hz polling (extrapolé de SPEC-014 EdgeMonitor à 12 Hz mesuré 0.5 %).
- **Latence perçue** : `idle_threshold_ms + 50ms` (worst case = idle + 1 tick).
- **Default 200 ms** : bon compromis entre réactivité et anti-jitter (mesuré subjectivement).

## 3. `mouse_follows_focus` (US1c / FR-A6-05..06)

### Comportement

Quand `mouse_follows_focus = true`, **toutes** les commandes qui changent le focus via clavier téléportent le curseur au centre de la nouvelle fenêtre focused via `CGWarpMouseCursorPosition`.

### Liste exhaustive des commandes concernées

| Commande | Source détectée | Téléporte ? |
|---|---|---|
| `roadie focus <dir>` | `.keyboard` | Oui |
| `roadie window swap <dir>` (US1a) | `.keyboard` | Oui |
| `roadie window warp <dir>` | `.keyboard` | Oui |
| `roadie window display <sel>` | `.keyboard` | Oui |
| `roadie window desktop <sel>` | `.keyboard` | Oui |
| `roadie desktop focus <N>` | `.keyboard` | Oui |
| `roadie stage <id>` | `.keyboard` | Oui |
| Click souris (MouseRaiser) | `.mouseClick` | **Non** (curseur déjà sur la fenêtre par construction) |
| `focus_follows_mouse` autofocus/autoraise | `.mouseFollow` | **Non** (curseur déjà sur la fenêtre) |
| Rule SPEC-016 US2 (rule applique focus) | `.rule` | Non (déclenchement automatique, pas user) |
| App active externe (NSApp.activate) | `.external` | Non (l'app a son propre comportement) |

### Implémentation

- Surcharge de `FocusManager.setFocus(to:source:)` avec une nouvelle enum `FocusSource`.
- À chaque changement de focus : si `mouseFollowsFocus && source == .keyboard`, calculer `centerPoint` du `frame` de la nouvelle fenêtre et `CGWarpMouseCursorPosition`.

### Conversion Y axis

Important : `frame` côté Cocoa est en coordonnées **NS** (Y croissant vers le haut, origine bas-gauche), `CGWarpMouseCursorPosition` attend des coordonnées **CG** (Y croissant vers le bas, origine haut-gauche).

Conversion :
```swift
let screen = NSScreen.screens.first { $0.frame.contains(frame) } ?? NSScreen.main!
let nsCenter = NSPoint(x: frame.midX, y: frame.midY)
let cgY = screen.frame.maxY - nsCenter.y    // flip Y
let cgPoint = CGPoint(x: nsCenter.x, y: cgY)
CGWarpMouseCursorPosition(cgPoint)
CGAssociateMouseAndMouseCursorPosition(true)  // important : ré-associe après warp
```

### Multi-display

- Si la nouvelle fenêtre est sur un autre display que le curseur courant → téléportation cross-display fonctionne nativement (`CGWarpMouseCursorPosition` accepte n'importe quelle coord).
- Le mouvement est **instantané** (< 1 frame), pas d'animation native (volontaire — yabai pareil).

## 4. Coexistence avec SPEC-015 (mouse modifier)

### Architecture

```
                  ┌───────────────────────────┐
                  │ MouseInputCoordinator     │
                  │ - dragActive: Bool        │
                  └─────────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                                   ▼
  ┌─────────────────────┐               ┌─────────────────────────┐
  │ MouseDragHandler     │               │ MouseFollowFocusWatcher │
  │ (SPEC-015)           │ notifyStarted │ (SPEC-016)              │
  │                      │ ───────────►  │                         │
  │ NSEvent monitor      │               │ Timer 50ms polling      │
  │ Modifier+click drag  │               │ NSEvent.mouseLocation   │
  └──────────────────────┘               └─────────────────────────┘
```

### Règles de cohabitation

| État | `MouseDragHandler` | `MouseFollowFocusWatcher` |
|---|---|---|
| Idle | Hook actif (attend modifier+click) | Polling actif |
| Drag actif | Owns le drag, modifie frames | Suspendu (`return` early dans tick) |
| Drag fini | `notifyDragEnded()` | Reprend, recompute hover state |

### Flag `dragActive` lecture

Lockless via `@MainActor` isolation : Swift garantit l'atomicité des accès dans le main actor. Pas de mutex.

## 5. CLI

Pas de nouveau verbe CLI dédié pour ces options. La config se modifie dans `~/.config/roadies/roadies.toml` puis :

```bash
roadie daemon reload
```

`focus_follows_mouse` et `mouse_follows_focus` sont rechargés sans redémarrer le daemon ni casser les fenêtres en place.

## 6. IPC

Pas de commande IPC dédiée. La config est lue au boot et au reload via `daemon.reload`.

Diagnostic via `daemon.status` (extension de la sortie) :

```json
{
  "mouse": {
    "modifier": "ctrl",
    "focus_follows_mouse": "autofocus",
    "mouse_follows_focus": true,
    "idle_threshold_ms": 200,
    "drag_active": false,
    "current_hover_window": 12345
  }
}
```

## 7. Erreurs & dégradation

| Cas | Comportement |
|---|---|
| `focus_follows_mouse = "weird"` | Fallback `"off"` + log warn (parser tolérant) |
| `mouse_follows_focus = "yes"` | Fallback `false` + log warn (TOML attend bool, pas string) |
| `idle_threshold_ms = -50` | Clamp à 50 ms (min) + log warn |
| `idle_threshold_ms = 99999` | Clamp à 2000 ms (max) + log warn |
| `CGWarpMouseCursorPosition` échoue | Silently skipped (rare, log debug uniquement) |

## 8. Hors scope V1

- `mouse_follows_focus_animation = true` (animation fluide curseur). V2 si demande.
- `focus_follows_mouse_per_app = ["Slack", "Discord"]` (whitelist d'apps). V2.
- `focus_follows_mouse_threshold_pixels = N` (focus migre au franchissement d'une frontière, pas à l'idle). Pattern KWin. V2.
- Détection automatique modale système (suspension auto). V1 fonctionne en pratique car les modales sont au-dessus du z-order et le watcher voit la modale comme la "fenêtre" — comportement acceptable.
