# Feature Specification: RoadieCrossDesktop (SPEC-010)

**Feature Branch**: `010-cross-desktop` | **Created**: 2026-05-01 | **Status**: Implemented (PinEngine + CommandHandler + Module + CLI sub-verbes window space|stick|unstick|pin|unpin + handlers daemon `window.*` câblés via DesktopManager.resolveSelector + DaemonOSAXBridge livrés 2026-05-01. Force-tiling US5 reste P3 non prioritaire selon utilisateur)
**Dependencies**: SPEC-004 fx-framework, SPEC-003 multi-desktop awareness (utilise les desktop UUIDs)
**Input** : « Manipulation programmatique de fenêtre cross-desktop : `roadie window space N`, pinning rules auto, sticky window, always-on-top, force-tiling fenêtres "non-resizable" (FaceTime, Apple Maps - P3 pas prioritaire). Débloque le FR-024 SPEC-003 qui était DEFER V3. Plafond LOC strict 450, cible 300. »

---

## User Scenarios

### User Story 1 - `roadie window space N` (P1) 🎯 MVP

L'utilisateur Bob a une fenêtre Safari sur desktop 1. Il fait `roadie window space 2`. Safari disparaît du desktop 1 et apparaît sur le desktop 2. macOS gère la transition correctement (pas de fenêtre fantôme).

**Independent Test** : ouvrir Safari sur desktop 1, exécuter `roadie window space 2`, switch vers desktop 2 via Mission Control, vérifier que Safari y est.

**Acceptance Scenarios** :
1. **Given** Safari sur desktop 1, 3 desktops configurés. **When** `roadie window space 2`. **Then** osax `move_window_to_space` reçoit l'UUID du desktop 2, Safari y est physiquement déplacée.
2. **Given** la même config. **When** `roadie window space dev` (label SPEC-003). **Then** module résout label → UUID, déplace.
3. **Given** label inconnu. **When** `roadie window space foobar`. **Then** exit code 5 (desktop introuvable, voir SPEC-003 contracts).

### User Story 2 - Pinning rules auto (P1)

Règle config :
```toml
[[fx.cross_desktop.pin_rules]]
bundle_id = "com.tinyspeck.slackmacgap"
desktop_label = "comm"
```

Quand Slack apparaît (peu importe sur quel desktop), le module l'auto-déplace vers le desktop "comm". Si Slack tente de revenir ailleurs (clic Mission Control), la règle ne re-déclenche pas (pas de "lutte" UX).

**Acceptance Scenarios** :
1. **Given** rule Slack→comm, desktop "comm" labellé desktop 3. **When** Slack lancé sur desktop 1. **Then** event window_created → module envoie `move_window_to_space(wid, uuid_comm)` dans 200 ms.
2. **Given** la même rule. **When** Slack déjà ouvert et stable. **Then** aucun event window_created → aucun déplacement (la rule ne s'applique qu'à la création).

### User Story 3 - Sticky window (P2)

`roadie window stick` sur Music → Music apparaît sur tous les desktops simultanément. `roadie window unstick` → comportement normal.

### User Story 4 - Always-on-top (P2)

`roadie window pin` → fenêtre passe à `CGSWindowLevel = .floating` (24). `roadie window unpin` → revient au niveau normal (0). Utile pour Calculator, Notes flottantes.

### User Story 5 - Force-tiling fenêtres non-resizable (P3, pas prioritaire)

Certaines apps (FaceTime, Apple Maps, certaines fenêtres Electron) refusent les frames AX (`AXSize` rejette). Solution : utiliser `CGSSetWindowFrame` direct via osax, qui bypass le AX rejection.

```toml
[fx.cross_desktop.force_tiling]
enabled = true   # default false
bundle_ids = ["com.apple.FaceTime", "com.apple.Maps"]
```

**Note priorité** : reportable sans bloquer le reste de la SPEC. Si scope dérive → drop, livrer en SPEC-010.1.

### Edge Cases

- **Desktop UUID change pendant le delay** : Mission Control peut réindexer les UUID (rare). → relire l'UUID actuel juste avant le call osax.
- **Rule sur app pas en bundleID** (apps custom) : bundleID vide → log info, ignore
- **Module desactivé** : commands `roadie window space` retournent error "module not loaded"
- **`unpin` sur fenêtre jamais pinned** : no-op, exit 0
- **Sticky + move_window_to_space** : conflit logique. La sticky a priorité (la fenêtre reste sticky, le move est ignoré).
- **shutdown** : restaure tous les niveaux modifiés (set_level back to 0), retire sticky, mais NE déplace PAS les fenêtres (conserve l'état actuel)

---

## Requirements

### Window→desktop programmatique

- **FR-001** : Commande CLI `roadie window space <selector>` avec selectors : `N` (index 1-based), `<label>`. Délègue au daemon qui appelle module via FXRegistry.
- **FR-002** : Module envoie `OSAXCommand.moveWindowToSpace(wid: frontmost, spaceUUID: resolved)`. Sur ack OK, retour exit 0.
- **FR-003** : Si selector invalide → exit 2. Si desktop introuvable → exit 5. Si module pas chargé → exit 4.

### Pinning rules

- **FR-004** : Subscribe event `window_created`. Pour chaque, lookup rule par bundleID + match `desktop_label` ou `desktop_index`. Si match → `moveWindowToSpace`.
- **FR-005** : Une rule ne s'applique QU'À la création (pas à `window_focused` ni autres events). Pas de "lutte" UX.

### Sticky / always-on-top

- **FR-006** : Commande CLI `roadie window stick [bool]` → `OSAXCommand.setSticky(wid: frontmost, sticky: bool)`. Default `true` si pas d'arg.
- **FR-007** : Commande CLI `roadie window pin` → `setLevel(wid, level: 24)` (NSWindowLevel.floating). `unpin` → `setLevel(wid, level: 0)`.
- **FR-008** : Module track les wids modifiés pour restauration au shutdown.

### Force-tiling (P3, optionnel)

- **FR-009** : Si `force_tiling.enabled=true` ET wid bundleID match liste : intercepte event `window_resized` via hook spécial dans Tiler (extension SPEC-002 +20 LOC max), envoie `setFrame` direct via osax au lieu d'AX.
- **FR-010** : Sinon : laisse Tiler V2 essayer AX comme d'habitude.

### Configuration

```toml
[fx.cross_desktop]
enabled = true

[[fx.cross_desktop.pin_rules]]
bundle_id = "com.tinyspeck.slackmacgap"
desktop_label = "comm"

[[fx.cross_desktop.pin_rules]]
bundle_id = "com.apple.MobileSMS"
desktop_index = 3

[fx.cross_desktop.force_tiling]
enabled = false
bundle_ids = []
```

### Key Entities

- `CrossDesktopModule` : conform `FXModule`
- `PinRule` : Codable (bundle_id, desktop_label?, desktop_index?)
- `PinEngine` : matche window_created → rule → move command
- `LevelTracker` : registry [wid: original_level] pour restauration shutdown
- `StickyTracker` : registry [wid: was_sticky]

---

## Success Criteria

- **SC-001** : `roadie window space 2` complété en ≤ **300 ms** (resolve label + osax round-trip + macOS transition)
- **SC-002** : Pin rule sur Slack lancé → déplacement visible en ≤ **300 ms** après window_created
- **SC-003** : 100 % des wids tracked restaurent leur niveau au shutdown
- **SC-004** : LOC ≤ **450 strict** (cible 300)
- **SC-005** : 0 crash sur 24h
- **SC-006** : Aucune dépendance externe nouvelle

---

## Out of Scope

- **Création / destruction de desktops macOS** : `space --create` yabai-style. Mac gère ses spaces nativement, on ne touche pas.
- **Réordonner desktops** : idem.
- **Window swap cross-desktop** : `--swap --space` yabai-style. Possible mais bas ROI, à voir SPEC-010.1 si demande.
- **Cross-display** : reporté V3 (SPEC-003 multi-display).
