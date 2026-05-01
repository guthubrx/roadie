# Feature Specification: RoadieBlur (SPEC-009)

**Feature Branch**: `009-blur` | **Created**: 2026-05-01 | **Status**: Draft
**Dependencies**: SPEC-004 fx-framework
**Input** : « Module simple : `CGSSetWindowBackgroundBlurRadius` sur fenêtres tierces. Blur global on/off + per-app rules (ex Slack toujours blur=30). Plafond LOC strict 150, cible 100. »

---

## User Scenarios

### User Story 1 - Frosted glass per-app (P1) 🎯 MVP

L'utilisateur Bob veut que Slack ait un blur 30 derrière (effet glass). Il configure :
```toml
[fx.blur]
enabled = true
default_radius = 0
[[fx.blur.rules]]
bundle_id = "com.tinyspeck.slackmacgap"
radius = 30
```
Slack apparaît avec un blur subtil derrière son contenu (visible quand fond contrasté).

**Independent Test** : ouvrir Slack + module activé, vérifier visuellement le blur derrière. Quitter+relancer Slack → blur réappliqué.

**Acceptance Scenarios** :
1. **Given** rule Slack radius=30. **When** Slack lancé. **Then** event window_created → module envoie `setBlur(wid, 30)` via osax dans les 100 ms.
2. **Given** la même config. **When** Slack quit. **Then** osax `wid_not_found` log info, aucun crash.

### User Story 2 - Blur global (P2)

`default_radius = 15` → toutes fenêtres ont un blur 15. Permet effet "macOS Big Sur frosted" partout.

### Edge Cases

- **Radius hors range** [0, 100] → clamp + log warning
- **App qui rejette blur** (rare, certaines fenêtres OpenGL) : `cgs_failure` côté osax → log info, ignore
- **shutdown** : restaure `setBlur(wid, 0)` sur toutes wid tracked

---

## Requirements

- **FR-001** : Subscribe events `window_created`, `desktop_changed`. Sur chaque, lookup rule + envoie `setBlur` via osax.
- **FR-002** : Validation : `default_radius` et `rule.radius` ∈ [0, 100], hors range → clamp + log
- **FR-003** : Au shutdown, restaure radius=0 sur toutes wid tracked
- **FR-004** : Hot-reload via `daemon reload`

```toml
[fx.blur]
enabled = true
default_radius = 0       # 0 = no blur global, 30 = effet glass uniforme
[[fx.blur.rules]]
bundle_id = "com.tinyspeck.slackmacgap"
radius = 30
```

### Key Entities

- `BlurModule` : conform `FXModule`
- `BlurConfig` : Codable
- `BlurRule` : Codable

---

## Success Criteria

- **SC-001** : Latence window_created → blur appliqué ≤ **150 ms**
- **SC-002** : LOC ≤ **150 strict** (cible 100)
- **SC-003** : 0 crash sur 24h
- **SC-004** : Aucune dépendance externe nouvelle

---

## Out of Scope

- **Workspace transition blur** (style iOS app switcher) : reporté V3, gimmick
- **Animations de blur** (radius transition) : SPEC-007 fournira si demande
- **Per-window blur** (au-delà bundle_id) : pas applicable, gimmick
