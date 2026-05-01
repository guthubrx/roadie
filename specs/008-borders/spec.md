# Feature Specification: RoadieBorders (SPEC-008)

**Feature Branch**: `008-borders` | **Created**: 2026-05-01 | **Status**: Draft
**Dependencies**: SPEC-004 fx-framework. Optionnel SPEC-007 RoadieAnimations (pour pulse animé).
**Input** : « Bordure colorée statique autour fenêtre focused, style i3/Sway. Couleurs active/inactive configurables. Pulse sur changement focus (utilise SPEC-007). Border config par stage actif (couleur différente par stage). Gradient animé droppé après revue scope (déco non utile). Plafond LOC strict 280, cible 200. »

---

## User Scenarios

### User Story 1 - Focus indicator visuel (P1) 🎯 MVP

L'utilisateur Bob a 4 fenêtres tilées. Une bordure 2 px bleue (`#7AA2F7`) entoure la fenêtre focused. Les autres ont une bordure gris foncé (`#414868`). Quand il change de focus, la bordure suit immédiatement (overlay NSWindow tracking).

**Independent Test** : 4 fenêtres tilées + module activé, vérifier visuellement la bordure bleue 2 px autour de la focused.

**Acceptance Scenarios** :
1. **Given** module activé. **When** focus passe de A à B. **Then** la bordure 2px bleue se déplace vers B en moins de 50 ms.
2. **Given** une fenêtre focused. **When** on la déplace ou la resize. **Then** la bordure suit le frame en temps réel (60 FPS).

### User Story 2 - Pulse au focus change (P2)

Si SPEC-007 RoadieAnimations chargé : à chaque focus_changed, l'épaisseur de la bordure pulse 2px → 4px → 2px sur 250 ms (courbe `easeOutBack`). Sinon : transition instantanée.

**Independent Test** : trigger focus change, observer le pulse.

### User Story 3 - Border par stage (P2)

Chaque stage peut avoir sa propre couleur de bordure :

```toml
[fx.borders]
enabled = true
thickness = 2
active_color = "#7AA2F7"
inactive_color = "#414868"

[[fx.borders.stage_overrides]]
stage_id = "1"
active_color = "#9ECE6A"  # vert pour stage Work

[[fx.borders.stage_overrides]]
stage_id = "2"
active_color = "#F7768E"  # rouge pour stage Personal
```

**Independent Test** : 2 stages avec couleurs différentes, switch ⌥1/⌥2, vérifier que la bordure change de couleur.

### Edge Cases

- **Resize très rapide** : overlay doit suivre sans tearing (60 FPS minimum)
- **Fenêtre derrière une autre** : le border `level` doit forcer dessus mais sans intercepter les clicks (fenêtre ignoresMouseEvents)
- **2+ écrans** (V3) : 1 overlay par display, hors scope V1
- **`enabled = false`** : aucun overlay créé
- **shutdown** : tous overlays détruits proprement
- **Stage override absent** : fallback sur `active_color` global

---

## Requirements

- **FR-001** : Subscribe events `window_focused`, `window_created`, `window_destroyed`, `window_moved`, `window_resized`, `stage_changed`, `desktop_changed`.
- **FR-002** : Maintenir une `NSWindow` overlay borderless transparent par fenêtre tracked, dont le frame suit en live.
- **FR-003** : Overlay propre = `NSWindow` créée par roadie (pas tierce), donc pas besoin d'osax pour la dessiner. SEULEMENT pour `setLevel` qui assure qu'elle reste au-dessus de la window tracked → `OSAXBridge.send(.setLevel)`.
- **FR-004** : Couleur appliquée via `CALayer.borderColor` + `CALayer.borderWidth` sur la contentView.
- **FR-005** : Overlay `ignoresMouseEvents = true` (clicks passent au through à la fenêtre dessous).
- **FR-006** : Au focus_changed : recalcule la couleur (active/inactive selon focus + stage override match), update layer.
- **FR-007** : Si SPEC-007 chargé ET `pulse_on_focus=true` : appelle `AnimationsModule.requestAnimation(scale épaisseur)` au lieu de set instantané.
- **FR-008** : Validation config : `thickness` ∈ [0, 20], couleurs hex `#RRGGBB` ou `#RRGGBBAA`. Hors range → log error + fallback default.
- **FR-009** : Au shutdown : ferme tous overlays, libère ressources.
- **FR-010** : Hot-reload via `daemon reload` : applique nouvelle config, redessine overlays existants.

### Configuration

```toml
[fx.borders]
enabled = true
thickness = 2
active_color = "#7AA2F7"
inactive_color = "#414868"
pulse_on_focus = true

[[fx.borders.stage_overrides]]
stage_id = "1"
active_color = "#9ECE6A"
```

### Key Entities

- `BordersModule` : conform `FXModule`
- `BorderOverlay` : wrapper `NSWindow` + `CALayer`, suit une `wid`
- `BordersConfig` : Codable
- `StageOverride` : Codable

---

## Success Criteria

- **SC-001** : Latence focus → border updated ≤ **50 ms**
- **SC-002** : Border suit resize/move avec ≥ 58 FPS sur 60 Hz display
- **SC-003** : Couleur affichée mesurée (screenshot) à ±2 unités RGB de la config
- **SC-004** : LOC ≤ **280 strict** (cible 200)
- **SC-005** : 0 crash sur 24h (overlays bien libérés au unregister)
- **SC-006** : Aucune dépendance externe nouvelle

---

## Out of Scope

- **Gradient animé borders** (DROPPÉ après revue scope, gimmick déco)
- **Border par-app** (Slack rouge, etc.) — gimmick, à voir SPEC-008.1 si demande
- **Multi-display borders coordination** — V3
- **Border épaisse partielle** (top seulement, etc.) — gimmick
