# Feature Specification: RoadieAnimations (SPEC-007)

**Feature Branch**: `007-animations`
**Created**: 2026-05-01
**Status**: Draft
**Dependencies**: SPEC-004 fx-framework (RoadieFXCore + osax + AnimationLoop CVDisplayLink + BezierEngine). Optionnellement SPEC-006 RoadieOpacity (pour dim animé).
**Input** : « Engine d'animations 60-120 FPS style Hyprland avec courbes Bézier configurables. Fade in/out à l'ouverture/fermeture de fenêtre, slide horizontal sur switch desktop, crossfade sur switch stage, frame interpolée sur resize/tile, focus pulse subtil. Config TOML inspirée Hyprland avec `[[fx.animations.bezier]]` réutilisables et `[[fx.animations.events]]` qui mappent event→propriété→durée→courbe. AnimationQueue avec coalescing (nouvelle anim sur même wid+property remplace l'ancienne). Plafond LOC strict : 700, cible 500. »

---

## Vocabulaire

- **Animation** = changement progressif d'une propriété visuelle d'une fenêtre tierce sur une durée donnée, suivant une courbe Bézier. Implémentée via spam `setAlpha` / `setTransform` / `setFrame` à 60-120 FPS via osax.
- **Bézier curve** = courbe paramétrique 4 points de contrôle, transformant t (progress 0..1) en y (eased value 0..1+overshoot).
- **Event router** = composant qui mappe un event de l'EventBus vers une (ou plusieurs) animation(s) à enqueue.
- **Animation queue** = file d'animations actives, ticked par AnimationLoop CVDisplayLink. Coalescing : 2 animations sur même `(wid, property)` → la nouvelle remplace l'ancienne.
- **Hyprland-style config** = format TOML inspiré du `hyprland.conf` `animations { ... }` avec courbes nommées réutilisables.

---

## User Scenarios & Testing

### User Story 1 - Window open/close fade-in animé (P1) 🎯 MVP

L'utilisateur Bob ouvre une fenêtre Safari. Au lieu d'apparaître brutalement, elle fade-in en 200 ms (α 0→1) avec un scale 0.85→1.0 sur courbe `snappy` (overshoot léger). Quand il la ferme, elle fade-out 150 ms (α 1→0) sur courbe `smooth`.

**Why this priority** : c'est l'effet visuel signature Hyprland, immédiatement perceptible, que l'utilisateur veut explicitement.

**Independent Test** : ouvrir+fermer une fenêtre, mesurer la transition via screenshot tracking (alpha sample sur N frames), vérifier que la durée correspond et que la courbe est respectée.

**Acceptance Scenarios** :
1. **Given** module activé + courbe `snappy` configurée, event `window_open` mappé à α+scale 200ms snappy. **When** une nouvelle fenêtre est créée (event `window_created`). **Then** le module enqueue une animation, AnimationLoop tick et envoie une série de `setAlpha`/`setTransform` interpolés sur 200 ms.
2. **Given** event `window_close` mappé à α 1→0 sur 150 ms `smooth`. **When** une fenêtre est fermée. **Then** le module a 150 ms pour faire le fade avant que macOS détruise la fenêtre. Si macOS détruit avant la fin → animation annulée silencieusement (pas de crash).

### User Story 2 - Workspace switch slide (P1)

Bob bascule du desktop 1 au desktop 2 via Ctrl+→. Au lieu de la transition macOS native, toutes les fenêtres du desktop courant slide horizontalement vers la gauche (translate négatif), tandis que celles du desktop d'arrivée slide-in depuis la droite. Durée 350 ms, courbe `smooth`.

**Why this priority** : différenciateur UX vs comportement macOS natif (lent et figé).

**Independent Test** : capturer screen via screen recording pendant un switch, vérifier le mouvement horizontal cohérent et la synchronisation des deux groupes de fenêtres.

**Acceptance Scenarios** :
1. **Given** event `workspace_switch` mappé à translate horizontal 350 ms. **When** SPEC-003 émet `desktop_changed`. **Then** les fenêtres tracked des deux desktops sont animées en parallèle avec offset opposé.
2. **Given** un switch trop rapide (< 100 ms) entre 3 desktops. **Then** la dernière animation gagne (coalescing par wid+property).

### User Story 3 - Stage switch crossfade (P2)

Bob fait ⌥1 → ⌥2 (switch stage). Le stage 1 fade-out (α 1→0) tandis que le stage 2 fade-in (α 0→1) sur 180 ms `smooth`. Bonus : si SPEC-006 RoadieOpacity stage_hide actif, le crossfade utilise les α du module Opacity au lieu du toggle off/on.

**Independent Test** : 2 stages avec fenêtres distinctes, switch via ⌥1/⌥2, vérifier visuellement le crossfade.

### User Story 4 - Window resize animé (P2)

Quand BSP retile (ajout d'une fenêtre, suppression, drag-to-adapt), au lieu du snap brut, les frames source et target sont interpolées sur 120 ms `snappy`.

**Independent Test** : déclencher un retile, mesurer que les fenêtres bougent en interpolation linéaire vs courbe Bézier.

### User Story 5 - Focus pulse (P3)

À chaque changement de focus, la fenêtre nouvellement focused fait un micro-pulse scale 1.0 → 1.02 → 1.0 sur 250 ms `easeOutBack`. Subtil mais aide à identifier visuellement le focus change.

**Independent Test** : changer focus, vérifier le pulse via screenshot diff sur les frames clés.

### Edge Cases

- **Animation runaway** : module bug qui spam des animations sans fin → AnimationQueue cap `max_concurrent = 20` config (default), drop des plus anciennes en silence avec log
- **macOS détruit fenêtre pendant anim** : `wid_not_found` côté osax → animation annulée, retire le wid de la queue
- **Reload pendant anim** : config rechargée, animations en cours non interrompues mais les nouveaux events utilisent la nouvelle config
- **`enabled = false`** : aucune animation, tout instantané (comportement SPEC-002)
- **CVDisplayLink unavailable** (cas extrême, headless macOS) : fallback `Timer 1/60s` avec warning log, dégradation acceptable
- **Bézier overshoot** : si points de contrôle donnent y > 1 ou < 0 (easeOutBack), l'osax accepte α > 1 = clamp 1, scale > 1 = applique tel quel
- **Animation stop mid-way par focus_changed** : si une animation alpha est en cours sur une fenêtre A et un focus_changed déclenche une nouvelle animation alpha sur A → coalescing : ancienne annulée, nouvelle prend le relai depuis l'α actuelle

---

## Requirements

### Functional Requirements — Engine

- **FR-001** : `BezierEngine.sample(t)` (déjà SPEC-004) DOIT être utilisable par RoadieAnimations sans modification.
- **FR-002** : `AnimationLoop` (déjà SPEC-004) DOIT supporter register/unregister thread-safe d'animations en cours.
- **FR-003** : Au tick (60 ou 120 FPS selon display), pour chaque animation active : calcule progress = (now - start) / duration, échantillonne courbe, calcule property interpolée, envoie via `OSAXBridge.send`.
- **FR-004** : Une animation finie (progress ≥ 1.0) est retirée de la queue, son wid désinscrit.

### Functional Requirements — EventRouter

- **FR-005** : Le module subscribe à 5 events EventBus : `window_created`, `window_destroyed`, `window_focused`, `window_resized`, `desktop_changed`, `stage_changed`.
- **FR-006** : Pour chaque event, l'`EventRouter` consulte la config `[[fx.animations.events]]` et matche les règles applicables.
- **FR-007** : Une règle DOIT spécifier au moins : `event` (key), `properties` (1+ parmi `alpha`, `scale`, `translateX`, `translateY`, `frame`), `duration_ms` (entier > 0), `curve` (référence à une courbe nommée).
- **FR-008** : Curves : 3 courbes built-in (`linear`, `ease`, `easeInOut`) + courbes custom dans `[[fx.animations.bezier]]` config.

### Functional Requirements — AnimationQueue

- **FR-009** : `enqueue(animation)` ajoute une animation à la queue. Si une animation existe déjà sur même `(wid, property)` → l'ancienne est annulée (coalescing), la nouvelle démarre depuis la valeur courante.
- **FR-010** : `max_concurrent` config (default 20) : si queue dépasse, drop la plus ancienne, log warning.
- **FR-011** : `pause()` / `resume()` permettent au module d'arrêter toutes les animations (utilisé pendant `daemon reload` pour éviter état incohérent).

### Functional Requirements — Configuration

- **FR-012** : Section `[fx.animations]` avec sous-tables `[[fx.animations.bezier]]` et `[[fx.animations.events]]` répétables.
- **FR-013** : Validation au reload : courbe nommée référencée dans event DOIT exister, sinon log error + skip cette règle (les autres restent actives).
- **FR-014** : Hot-reload : nouvelle config remplace l'ancienne, animations en cours continuent jusqu'à fin avec ancienne config (pas d'arrêt brutal).

### Functional Requirements — Integration

- **FR-015** : Si SPEC-006 RoadieOpacity chargé ET `animate_dim=true` : le module reçoit des `enqueue(animation)` directement de SPEC-006 plutôt que du focus_changed (delegation propre).
- **FR-016** : Au `shutdown()` : annule toutes animations en cours, applique target final immédiatement (pas de fenêtre figée à mi-animation).

### Configuration

```toml
[fx.animations]
enabled = true
max_concurrent = 20

# Bézier nommés réutilisables (4 control points)
[[fx.animations.bezier]]
name = "snappy"
points = [0.05, 0.9, 0.1, 1.05]

[[fx.animations.bezier]]
name = "smooth"
points = [0.4, 0.0, 0.2, 1.0]

[[fx.animations.bezier]]
name = "easeOutBack"
points = [0.34, 1.56, 0.64, 1.0]

# Events
[[fx.animations.events]]
event = "window_open"
properties = ["alpha", "scale"]
duration_ms = 200
curve = "snappy"

[[fx.animations.events]]
event = "window_close"
properties = ["alpha"]
duration_ms = 150
curve = "smooth"

[[fx.animations.events]]
event = "desktop_changed"
properties = ["translateX"]
duration_ms = 350
curve = "smooth"
direction = "horizontal"  # spécifique à workspace switch

[[fx.animations.events]]
event = "stage_changed"
properties = ["alpha"]
duration_ms = 180
curve = "smooth"
mode = "crossfade"

[[fx.animations.events]]
event = "window_resized"
properties = ["frame"]
duration_ms = 120
curve = "snappy"

[[fx.animations.events]]
event = "window_focused"
properties = ["scale"]
duration_ms = 250
curve = "easeOutBack"
mode = "pulse"            # scale 1 → 1.02 → 1
```

### Key Entities

- `AnimationsModule` : conform `FXModule`
- `AnimationsConfig` : Codable, parse TOML
- `EventRule` : Codable (event, properties, duration_ms, curve_name, direction?, mode?)
- `BezierLibrary` : `[String: BezierCurve]` keyed par nom
- `EventRouter` : matche event → liste d'`Animation` à enqueue
- `Animation` : (déjà data-model SPEC-004) `(id, wid, property, from, to, curve, startTime, duration)`
- `AnimationQueue` : `[Animation]` actor avec coalescing par `(wid, property)`

---

## Success Criteria

- **SC-001** : Frame rate animations : médian ≥ 58 FPS sur display 60 Hz, ≥ 110 FPS sur 120 Hz (perte de frames acceptable < 5 %)
- **SC-002** : Latence event → première frame anim : ≤ **30 ms** (1 tick CVDisplayLink + queue OSAX)
- **SC-003** : Précision Bézier : `BezierEngine.sample(snappy, 0.5)` retourne ≈ 0.86 (table de lookup 256 vs calcul direct, écart ≤ 0.005)
- **SC-004** : Coalescing : 2 enqueue rapides sur même wid+property → seule la 2e termine (test unit)
- **SC-005** : 0 crash sur 24h avec ≥ 100 animations cumulées (mix de tous les events)
- **SC-006** : LOC ≤ **700 strict** (cible 500). Mesure :
  ```bash
  find Sources/RoadieAnimations -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  ```
- **SC-007** : Aucune dépendance externe nouvelle
- **SC-008** : Test stress : 50 animations concurrentes sur même desktop, p99 frame drop ≤ 2 frames sur 100 (vérifier via timestamps log)

---

## Assumptions

- SPEC-004 framework livré et stable depuis ≥ 2 semaines
- `BezierEngine` et `AnimationLoop` de RoadieFXCore SPEC-004 sont opérationnels et testés
- L'utilisateur a SIP partial off et osax installée
- `OSAXBridge.send` peut absorber des bursts de 60 cmds/sec (vérifié SPEC-004 SC-003)

---

## Out of Scope

- **Animations 3D** (rotate, perspective) : non demandées par utilisateur, pas de support `set_transform` rotate dans osax SPEC-004 contrats
- **Spring physics** (animations style SwiftUI/Hyprland spring) : reporté à SPEC-007.1 si demande, V1 = Bézier seulement
- **Animations cross-display** (V3 multi-display) : hors scope
- **Custom user-defined event** (au-delà des 6 events listés FR-005) : reporté
- **Audio sync animations** : hors scope (gimmick)
- **Pause animations sur fenêtre minimisée** : déjà géré naturellement (la fenêtre n'est plus dans le registry)
