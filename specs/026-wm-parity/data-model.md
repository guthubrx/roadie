# Data Model — SPEC-026 WM-Parity

## Entités nouvelles

### ScratchpadDef (Codable)

Section TOML `[[scratchpads]]`. Persistence : config TOML uniquement, lue au boot et au reload.

| Champ | Type | Default | Validation |
|---|---|---|---|
| name | String | requis | unique parmi tous les scratchpads |
| cmd | String | requis | non-vide ; commande shell |
| match.bundle_id | String? | nil | optionnel, override heuristic matching |

### ScratchpadState (runtime)

In-memory uniquement. Géré par `ScratchpadManager`.

| Champ | Type | Default | Notes |
|---|---|---|---|
| name | String | — | clé d'identification |
| wid | WindowID? | nil | attachée au 1er match post-spawn |
| isVisible | Bool | true | toggle entre true/false |
| lastVisibleFrame | CGRect? | nil | sauvée avant hide |
| spawnedAt | Date? | nil | pour timeout 5s |

### SignalDef (Codable)

Section TOML `[[signals]]`. Validation : `event` ∈ liste fermée.

| Champ | Type | Default | Validation |
|---|---|---|---|
| event | String | requis | ∈ {window_focused, window_created, window_destroyed, stage_changed, desktop_changed, display_changed} |
| cmd | String | requis | non-vide |

### SignalsConfig (extension Config)

Section TOML `[signals]`.

| Champ | Type | Default |
|---|---|---|
| enabled | Bool | true |

### StickyScope (enum, extension RuleDef)

Champ ajouté à `RuleDef` existante de SPEC-016. String enum dans le TOML.

| Valeur | Sémantique |
|---|---|
| `stage` | visible sur toutes stages d'un même (displayUUID, desktopID) |
| `desktop` | visible sur tous desktops d'un même displayUUID |
| `all` | visible sur le display courant peu importe le scope (suit le display actif) |

Default si absent dans une rule sticky : `"stage"`.

## Extensions de structures existantes

### FocusConfig (Config.swift)

Ajout de 2 champs (Bool, default false).

```swift
public struct FocusConfig: Codable, Sendable, Equatable {
    public var stageFollowsFocus: Bool        // existant
    public var assignFollowsFocus: Bool       // existant
    public var focusFollowsMouse: Bool = false   // NEW
    public var mouseFollowsFocus: Bool = false   // NEW
}
```

CodingKeys : `focus_follows_mouse`, `mouse_follows_focus`.

### TilingConfig (Config.swift)

Ajout de 1 champ (Bool, default false).

```swift
public struct TilingConfig: Codable, Sendable, Equatable {
    // ... existant
    public var smartGapsSolo: Bool = false   // NEW
}
```

CodingKey : `smart_gaps_solo`.

### Config (root)

Ajout de 3 sections optionnelles.

```swift
public var scratchpads: [ScratchpadDef] = []
public var signals: SignalsConfig = .init()  // enabled=true par défaut
// signals.signals: [SignalDef] = []
```

### RuleDef (SPEC-016)

Ajout de 1 champ optionnel.

```swift
public var stickyScope: StickyScope? = nil  // NEW, lu via "sticky_scope"
```

## Transitions d'état

### Scratchpad lifecycle

```
        +-------+
        | None  |    (avant 1er toggle)
        +---+---+
            |
   toggle <name> spawn cmd
            v
       +----+-----+        timeout 5s sans match
       | Spawning |---------> log warn, retour à None
       +----+-----+
            | wid match captured
            v
       +----+-----+
       | Visible  |<----+
       +----+-----+     |
            | toggle    |  toggle
            v           |
       +----+-----+-----+
       | Hidden  |
       +---------+
```

### FocusFollowsMouse inhibition

```
   focus change via shortcut (raccourci HJKL/alt+N)
            |
            v
   mouse_follows_focus warp curseur
            |
            v
   inhibitFollowMouseUntil = Date() + 0.2s
            |
            v
   focus_follows_mouse handler tick (peut survenir < 0.2s)
            |
   if Date() < inhibitFollowMouseUntil → SKIP
   else → process normal (set focus si wid sous curseur ≠ focused)
```

## Validation de données

- `ScratchpadDef.name` : doit être unique. Validation au parsing : si doublon, log error + ignore les doublons (premier gagne).
- `SignalDef.event` : doit être dans la liste fermée. Si invalide, log warn + ignore l'entrée.
- `StickyScope` : default `"stage"` si présent mais valeur inconnue, log warn + utilise `"stage"`.
- `smart_gaps_solo` : valeur invalide → false (default), log warn.
