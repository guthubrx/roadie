# Phase 1 — Data Model : Roadie Multi-Display

**Spec** : SPEC-012 | **Date** : 2026-05-02

## Entités principales

### Display

Représente un écran physique connecté.

| Champ | Type | Description | Validation |
|---|---|---|---|
| `id` | `CGDirectDisplayID` (UInt32) | Identifiant Quartz, stable pendant la session | non-zéro |
| `index` | `Int` | Index 1-based dans `NSScreen.screens` | 1..N |
| `uuid` | `String` | UUID stable cross-reboot (depuis `CGDisplayCreateUUIDFromDisplayID`) | format UUID |
| `name` | `String` | Nom localisé (ex: "Built-in Retina Display") | non-vide |
| `frame` | `CGRect` | Rect en coords globales Quartz | width > 0, height > 0 |
| `visibleFrame` | `CGRect` | `frame` moins menu bar et dock | sous-ensemble de frame |
| `isMain` | `Bool` | true si primary screen (`NSScreen.main`) | exactement 1 main par session |
| `isActive` | `Bool` | true si contient la fenêtre frontmost | au plus 1 active |
| `tilerStrategy` | `TilerStrategy` | Stratégie de tiling pour cet écran | bsp / master_stack / floating |
| `gapsOuter` | `Int` | Marge extérieure (px) | 0..100 |
| `gapsInner` | `Int` | Espacement entre fenêtres | 0..100 |

**Source de vérité** : `DisplayRegistry` (in-memory, recalculé à chaque `didChangeScreenParameters`).

**Mise à jour** : observer `NSApplication.didChangeScreenParametersNotification`, reconstruire l'array `displays`.

---

### DisplayRegistry (state in-memory)

Acteur Swift qui détient :

| Champ | Type | Description |
|---|---|---|
| `displays` | `[Display]` | Liste indexée par `index` (1-based) |
| `provider` | `any DisplayProvider` | Source des écrans (NSScreen ou Mock pour tests) |
| `activeID` | `CGDirectDisplayID?` | id de l'écran actif (contient frontmost) |

Méthodes publiques :
- `refresh()` async — re-énumère NSScreen.screens et met à jour `displays`
- `display(at index: Int) -> Display?`
- `display(forID id: CGDirectDisplayID) -> Display?`
- `display(forUUID uuid: String) -> Display?`
- `displayContaining(point: CGPoint) -> Display?` — pour mapping fenêtre → écran (centre frame)
- `setActive(id: CGDirectDisplayID)` — appelé par focus observer
- `count: Int { get }`

---

### WindowEntry (étendu)

Extension de l'entité existante de SPEC-011 :

| Champ | Type | Description |
|---|---|---|
| ... | ... | (champs existants : cgwid, bundleID, title, expectedFrame, stageID) |
| `displayUUID` | `String?` | UUID de l'écran d'origine (NEW) |

Le champ est optionnel pour backward-compatibilité. À la lecture, si `nil`, fallback primary.

---

### LayoutEngine (modifié)

Nouvelle structure interne :

| Champ | Type | Description |
|---|---|---|
| `rootsByDisplay` | `[CGDirectDisplayID: TilingContainer]` | Un arbre par écran |
| `displayRegistry` | `DisplayRegistry?` | Référence au registry pour énumérer les écrans |
| `tilerByDisplay` | `[CGDirectDisplayID: any TilerProtocol]` | Tiler par écran (peut être différent) |

Nouvelles méthodes :
- `applyAll()` — itère sur tous les displays et applique leur layout
- `insertWindow(_ wid:, into displayID:)` — au lieu du global
- `moveWindow(_ wid:, from src:, to dst:)` — déplacement entre arbres
- `setStrategyForDisplay(_ displayID:, strategy:)`

Compat mono-écran : si `rootsByDisplay.count == 1`, comportement strictement équivalent à SPEC-011.

---

### Event (canal observable)

Nouveaux types :

| Champ | Type | Valeurs |
|---|---|---|
| `event` | `String` | `"display_changed"` \| `"display_configuration_changed"` (NEW) |
| `from` | `String` | display index source (display_changed uniquement) |
| `to` | `String` | display index cible (display_changed uniquement) |
| `displays` | `[Display]?` | snapshot des displays (display_configuration_changed uniquement) |
| `ts` | `Int64` | Unix epoch ms |

---

## Transitions d'état

### Branchement d'un nouvel écran

```
[displays = [d0]]
    │
    ▼ NSApplication.didChangeScreenParameters
[refresh() : displays = [d0, d1]]
    │
    ▼ display_configuration_changed event
[apply([[displays]] config si match d1)]
    │
    ▼ rootsByDisplay[d1.id] = TilingContainer()
[applyAll() — d1 vide pour l'instant]
```

### Déconnexion d'un écran

```
[displays = [d0, d1], rootsByDisplay = {d0:..., d1:[w1, w2]}]
    │
    ▼ NSApplication.didChangeScreenParameters
[refresh() : displays = [d0]]
    │
    ▼ migrate windows (w1, w2) from d1 to d0
[for w in [w1, w2]:
    adjust w.frame to fit d0.visibleFrame
    AXReader.setBounds(w, newFrame)
    rootsByDisplay[d0.id].insert(w)
    rootsByDisplay[d1.id] = nil
    update WindowEntry.displayUUID = d0.uuid]
    │
    ▼ display_configuration_changed event
[applyAll() — d0 contient toutes les fenêtres]
```

### Déplacement explicite (`roadie window display N`)

```
[wid focused, current display = src, request → dst]
    │
    ▼ DisplayRegistry.display(at: N) → dst (validation FR-010)
[remove wid from rootsByDisplay[src.id]]
    │
    ▼ compute new frame:
[newOrigin = dst.visibleFrame.center - oldFrame.size / 2]
[clamp newFrame to dst.visibleFrame]
[AXReader.setBounds(wid, newFrame)]
    │
    ▼ rootsByDisplay[dst.id].insert(wid)
[update WindowEntry.displayUUID = dst.uuid]
    │
    ▼ applyLayout(displayID: src) + applyLayout(displayID: dst)
[focus_changed event si dst != src.isActive]
```

### Restauration au boot avec displayUUID

```
[load state.toml → WindowEntry { cgwid, displayUUID, expectedFrame, ... }]
    │
    ▼ DisplayRegistry.display(forUUID: displayUUID)
    │
    ├─ found → restore at expectedFrame on that display
    │
    └─ not found (écran disparu) → log warn + fallback primary
        [adjust frame to primary.visibleFrame]
        [insert in rootsByDisplay[primary.id]]
```

---

## Validation des contraintes

| Contrainte spec | Vérifié par |
|---|---|
| FR-001 (énumération NSScreen) | `DisplayRegistry.refresh()` |
| FR-002 (observer didChangeScreen) | `DisplayRegistry.init` ajoute observer |
| FR-005 (centre frame → écran) | `DisplayRegistry.displayContaining(point:)` |
| FR-008 (window display N) | `LayoutEngine.moveWindow(from:to:)` |
| FR-010 (range check) | handler `window.display` valide N ∈ [1..count] |
| FR-015 (recovery <500ms) | `DisplayRegistry.handleScreenChange` synchrone |
| FR-020 (displayUUID) | `WindowEntry` champ optionnel |
| FR-024 (0 régression mono) | tests SPEC-011 inchangés passent |

---

## Format disque exemple

```toml
# ~/.config/roadies/desktops/1/state.toml
id = 1
label = ""
layout = "bsp"
gaps_outer = 8
gaps_inner = 4
active_stage_id = 1

[[stages]]
id = 1
label = "1"
windows = [12345, 67890]

[[windows]]
cgwid = 12345
bundle_id = "com.apple.terminal"
title = "iTerm — Mac"
expected_x = 100.0
expected_y = 100.0
expected_w = 800.0
expected_h = 600.0
stage_id = 1
display_uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230"  # NEW

[[windows]]
cgwid = 67890
bundle_id = "org.mozilla.firefox"
title = "Mozilla"
expected_x = 2200.0
expected_y = 100.0
expected_w = 1600.0
expected_h = 900.0
stage_id = 1
display_uuid = "AB123456-1234-1234-1234-1234567890AB"
```

Fenêtre 12345 sur écran primary (UUID `37D8832A...`), fenêtre 67890 sur écran 4K externe (UUID `AB123456...`). Au prochain boot, chaque fenêtre est restaurée sur son écran d'origine.
