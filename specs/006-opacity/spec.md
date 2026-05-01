# Feature Specification: RoadieOpacity (SPEC-006)

**Feature Branch**: `006-opacity`
**Created**: 2026-05-01
**Status**: Implemented (focus dimming + per-app rules + extension StageHideOverride sur StageManager livrés 2026-05-01 ; stage_hide via α conformable au protocole, OpacityModule peut s'enregistrer comme hideOverride. animate_dim transitions Bézier disponibles via SPEC-007 si chargé)
**Dependencies**: SPEC-004 fx-framework. Optionnellement SPEC-007 RoadieAnimations (pour transitions animées de la dim, sinon dim instantané).
**Input** : « Module focus dimming (style Hyprland dimstrength). Fenêtre focused α=1.0, autres dimées α=0.85. Per-app rules : Slack toujours α=0.92, etc. Stage hide via opacity (α=0 au lieu d'offscreen) en option, alternative à HideStrategy.corner SPEC-002. Plafond LOC strict 220, cible 150. »

---

## User Scenarios & Testing

### User Story 1 - Focus dimming (P1) 🎯 MVP

L'utilisateur Bob a 4 fenêtres tilées. Il focus la fenêtre A : A reste à α=1.0, B/C/D passent à α=0.85 (subtil mais visible). Il focus B : B revient à 1.0, A descend à 0.85. Effet visuel : on identifie immédiatement la fenêtre active sans lire le contenu.

**Independent Test** : 4 fenêtres tilées + module activé, vérifier visuellement le dim, mesurer α via screenshot diff (pixel sample).

**Acceptance Scenarios** :
1. **Given** module activé `inactive_dim = 0.85`. **When** focus passe de A à B. **Then** B → α=1.0 et A → α=0.85 dans les 100 ms.
2. **Given** une seule fenêtre. **When** elle est focused. **Then** α=1.0 (pas de dim sur soi-même).

### User Story 2 - Per-app baseline (P2)

L'utilisateur veut iTerm2 toujours à α=0.92 (effet glass terminal) même focused. Règle config :

```toml
[[fx.opacity.rules]]
bundle_id = "com.googlecode.iterm2"
alpha = 0.92
```

iTerm2 focused → α=0.92. Autre app focused → iTerm2 dimmed = min(0.92, 0.85) = 0.85.

**Independent Test** : configurer la règle, vérifier visuellement iTerm2 toujours frosted.

**Acceptance Scenarios** :
1. **Given** règle iTerm2 α=0.92. **When** iTerm2 focused. **Then** α=0.92 (pas 1.0).
2. **Given** la même règle. **When** Safari focused (iTerm2 inactif). **Then** iTerm2 α=min(0.92, 0.85)=0.85 (le dim baseline plus restrictif gagne).

### User Story 3 - Stage hide via opacity (P2)

Alternative à `HideStrategy.corner` SPEC-002 : au lieu de déplacer les fenêtres du stage caché en (-w, -h), le module les met à α=0. Avantage : pas de jitter visuel sur les apps qui crashent quand on les déplace offscreen (rares, mais existent).

```toml
[fx.opacity.stage_hide]
enabled = true
preserve_offscreen = false  # si true, fenêtre offscreen ET α=0 (double protection)
```

**Independent Test** : activer + créer 2 stages, vérifier que stage 2 caché = fenêtres invisibles (α=0) sans déplacement.

**Acceptance Scenarios** :
1. **Given** `stage_hide.enabled=true`. **When** stage 2 est désactivé. **Then** ses fenêtres passent α=0, restent à leur position physique.
2. **Given** module pas chargé. **Then** fallback vers `HideStrategy.corner` SPEC-002 (comportement V2 standard).

### Edge Cases

- **App crash sur changement α** : si `setAlpha` retourne erreur côté osax → log warning, retire le wid des tracked. (Très rare, mais arrivé sur certaines vieilles apps Carbon.)
- **`inactive_dim = 1.0`** : équivalent à désactiver le dim sans `enabled=false`. Accepté.
- **`inactive_dim = 0.0`** : fenêtres invisibles, on log warning ("are you sure?") mais on applique.
- **Per-app rule sur app pas lancée** : aucun effet, pas d'erreur.
- **Reload pendant transition** : si une animation dim est en cours (via SPEC-007), elle est annulée et la nouvelle target est appliquée immédiatement.

---

## Requirements

- **FR-001** : Subscribe events `window_focus_changed`, `window_created`, `stage_changed`. Sur chaque, recalcule α target pour chaque fenêtre.
- **FR-002** : `targetAlpha(for window)` = min de `inactive_dim` (si non focused) et de la règle per-app si match (la règle plus contraignante gagne).
- **FR-003** : Si focused : `targetAlpha = 1.0` sauf si règle per-app fixe une valeur explicite (alors elle s'applique aussi sur focused).
- **FR-004** : Validation config : `inactive_dim` ∈ [0.0, 1.0], chaque rule `alpha` ∈ [0.0, 1.0]. Hors range → clamp + log warning.
- **FR-005** : Mode `stage_hide.enabled=true` : intercepte le hide call de `StageManager` via le protocol `StageHideOverride` ajouté dans SPEC-004 (ou ici si absent). Quand un stage est désactivé : envoie `setAlpha(wid, 0.0)` pour ses fenêtres au lieu d'appeler `HideStrategy.corner`.
- **FR-006** : Au `shutdown()`, restaure α=1.0 sur toutes fenêtres tracked (et restaure `HideStrategy.corner` si stage_hide était actif).
- **FR-007** : Hot-reload via `daemon reload` re-lit `[fx.opacity]` config et ré-applique.
- **FR-008** : Optionnel `animate_dim = true` : si SPEC-007 RoadieAnimations chargé, demande une animation `alpha` au lieu de set instantané. Si SPEC-007 absent : ignore le flag, set instantané.

### Configuration

```toml
[fx.opacity]
enabled = true
inactive_dim = 0.85
animate_dim = true

[[fx.opacity.rules]]
bundle_id = "com.googlecode.iterm2"
alpha = 0.92

[fx.opacity.stage_hide]
enabled = true
preserve_offscreen = false
```

### Key Entities

- `OpacityModule` : conform `FXModule`, singleton
- `OpacityConfig` : Codable (enabled, inactive_dim, animate_dim, rules, stage_hide)
- `AppRule` : Codable (bundle_id, alpha)
- `StageHideOverride` (protocol injecté dans `StageManager`)

---

## Success Criteria

- **SC-001** : Latence focus_changed → α appliqué ≤ **100 ms** (sans animation) ou ≤ duration animation + 50 ms (avec)
- **SC-002** : Précision visuelle : `inactive_dim=0.85` → α effectif mesuré 0.85 ± 0.02 par screenshot
- **SC-003** : Per-app rule prend toujours le pas sur baseline (pas de surprise utilisateur)
- **SC-004** : Stage hide via α : 100 % des fenêtres invisibles vs HideStrategy.corner V2 (vérification screenshot)
- **SC-005** : LOC ≤ **220 strict** (cible 150)
- **SC-006** : 0 crash sur 24h
- **SC-007** : Aucune nouvelle dépendance externe

---

## Out of Scope

- **Dim par stage** (couleur dim différente par stage actif) — gimmick, à voir SPEC-006.1 si demande
- **Per-app rules par window title** (genre Chrome onglet "X" α=0.5) — surdimensionné
- **Spring physics sur dim transition** : c'est SPEC-007 RoadieAnimations qui gère, pas ici
