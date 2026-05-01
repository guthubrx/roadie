# Implementation Plan: RoadieAnimations (SPEC-007)

**Branch** : `007-animations` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)

## Summary

Module FX engine d'animations 60-120 FPS sur fenêtres tierces. Subscribe à 6 events EventBus, route via config Hyprland-style (Bézier nommés + event rules), enqueue dans une `AnimationQueue` avec coalescing, ticked par `AnimationLoop` SPEC-004 qui spam des `setAlpha` / `setTransform` / `setFrame` à chaque frame display via `OSAXBridge`. Plafond LOC strict **700**, cible **500**.

## Technical Context

**Language** : Swift 5.9+, `@MainActor` pour le module, `actor` pour `AnimationQueue` (thread-safe coalescing)

**Primary Dependencies** :
- `RoadieFXCore.dylib` SPEC-004 (BezierEngine, AnimationLoop CVDisplayLink, OSAXBridge, FXModule, EventBus accessor)
- TOMLKit pour parsing (déjà SPEC-002)
- Aucune dépendance externe nouvelle

**Storage** : aucun (état RAM)

**Testing** :
- Unit `BezierLibraryTests` : load 3 courbes built-in + custom, lookup par nom, fail si nom inconnu
- Unit `EventRouterTests` : event mock + config mock → liste `Animation` attendue
- Unit `AnimationQueueTests` : coalescing wid+property, max_concurrent drop, pause/resume
- Unit `AnimationTests` : interpolation `value(at:)` sur courbe connue à mi-temps
- Integration `tests/integration/18-fx-animations.sh` : ouvre fenêtre + log osax, vérifie séries de `setAlpha` à 60 FPS pendant 200 ms

**Target Platform** : macOS 14+, SIP partial off requis

**Project Type** : Swift target `.dynamicLibrary`

**Performance Goals** : SC-001..SC-008 (frame rate, latence event→anim, coalescing, LOC ≤ 700)

**Constraints** :
- Plafond LOC 700 strict — c'est le module le plus gros mais reste bien borné
- Pas de dépendance externe
- 5 fichiers Swift max (Module + EventRouter + AnimationFactory + AnimationQueue + Config)
- Tests unitaires couvrent ≥ 80% du code logique pure (Bézier, queue, factory)
- Architecture : modules privés à `RoadieAnimations`, seul `Module.swift` expose `@_cdecl module_init`

**Scale/Scope** :
- Jusqu'à 20 animations concurrentes (configurable)
- Bursts de 50 simultanées tolérés
- 1000 OSAX cmds/sec en pic théorique (1 tick = 50 anims × 1 cmd = 50 ; à 60 FPS = 3000/sec, sous limite osax)

## Constitution Check

| Principe | Conformité |
|---|---|
| **A** | ✅ ajout pur |
| **A'** | ✅ 5 fichiers, chacun ≤ 200 LOC effectives |
| **B'** | ✅ aucune dépendance nouvelle |
| **C' (1.3.0)** | ✅ module SIP-off opt-in déclaré famille SPEC-004 |
| **G — Minimalisme** | ✅ plafond strict 700 (cible 500) |
| **I'** | ✅ `.dynamicLibrary` désactivable via flag |
| **H'** | ✅ tests unitaires sur logique pure (Bézier, queue, router) |

✅ Toutes gates passent.

## Project Structure

```text
specs/007-animations/
├── plan.md
├── spec.md
├── data-model.md     # entités Animation, AnimationQueue, EventRule
├── tasks.md
└── checklists/requirements.md

Sources/
└── RoadieAnimations/                # NEW target .dynamicLibrary
    ├── Module.swift                 # ~80 LOC : entry point, vtable, singleton
    ├── EventRouter.swift            # ~120 LOC : matche event → animations
    ├── AnimationFactory.swift       # ~100 LOC : crée Animations selon règle + état actuel fenêtre
    ├── AnimationQueue.swift         # ~120 LOC : actor coalescing, max_concurrent, pause/resume
    ├── BezierLibrary.swift          # ~50 LOC : registry [name: BezierCurve], built-ins
    └── Config.swift                 # ~60 LOC : parsing TOML

Tests/
└── RoadieAnimationsTests/
    ├── BezierLibraryTests.swift     # ~30 LOC
    ├── EventRouterTests.swift       # ~70 LOC
    ├── AnimationFactoryTests.swift  # ~50 LOC
    ├── AnimationQueueTests.swift    # ~80 LOC : coalescing + drop
    └── AnimationTests.swift         # ~30 LOC : value(at:) interpolation

tests/integration/
└── 18-fx-animations.sh              # log osax frame timing
```

## Phase 0 — Research

Toute la recherche a été faite en SPEC-004 (Bézier table lookup, CVDisplayLink, OSAXBridge perf). Pas de research.md spécifique à SPEC-007 — ses choix architecturaux découlent directement de SPEC-004.

## Phase 1 — Design

### Pipeline d'animation

```
EventBus event reçu
   │
   ▼
EventRouter.handle(event)
   │  consulte config.events
   │  pour chaque rule matchante :
   │
   ▼
AnimationFactory.makeAnimations(event, rule, currentState)
   │  pour chaque property :
   │    determine `from` (état actuel via WindowRegistry)
   │    determine `to` (target selon rule + event)
   │    crée Animation(wid, property, from, to, curve, duration)
   │
   ▼
AnimationQueue.enqueueBatch(animations)
   │  coalescing par (wid, property)
   │  si > max_concurrent : drop oldest
   │
   ▼ (CVDisplayLink callback @ 60-120 FPS)
AnimationLoop.tick(dt)
   │  pour chaque Animation active :
   │    progress = (now - start) / duration
   │    if progress >= 1.0 : envoie target final, retire
   │    else :
   │      bezierY = curve.sample(progress)
   │      value = lerp(from, to, bezierY)
   │      OSAXBridge.send(setAlpha/setTransform/setFrame, wid, value)
```

### Mode d'event spéciaux

- `direction = "horizontal"` (workspace_switch) : translate de ±screenWidth selon source/cible
- `direction = "vertical"` : translate de ±screenHeight
- `direction = "fade"` : transition par α (équivalent crossfade)
- `mode = "crossfade"` (stage_changed) : 2 animations concurrentes (out 1→0, in 0→1)
- `mode = "pulse"` (window_focused) : 3 keyframes 0%→50%→100% (1.0 → 1.02 → 1.0), géré par `AnimationFactory` qui crée 2 animations consécutives

### AnimationQueue coalescing

```swift
actor AnimationQueue {
    private var active: [(key: AnimationKey, anim: Animation)] = []
    typealias AnimationKey = Pair(wid: CGWindowID, property: AnimatedProperty)

    func enqueue(_ anim: Animation) {
        let key = AnimationKey(wid: anim.wid, property: anim.property)
        // Coalescing : retire ancien si existe
        active.removeAll { $0.key == key }
        active.append((key: key, anim: anim))

        if active.count > config.maxConcurrent {
            let dropped = active.removeFirst()
            log.warning("dropped animation", key: dropped.key)
        }
    }

    func tick(now: CFTimeInterval) async {
        var done: [AnimationKey] = []
        for (key, anim) in active {
            if let value = anim.value(at: now) {
                await bridge.send(anim.toCommand(value: value))
            } else {
                done.append(key)
            }
        }
        for key in done { active.removeAll { $0.key == key } }
    }
}
```

### Constitution Check (post Phase 1)

- ✅ 5 fichiers Swift principaux + Config = 6 fichiers
- ✅ Chacun ≤ 200 LOC effectives (constitution-002 A')
- ✅ Total ≤ 700 LOC strict
- ✅ Tests unitaires couvrent 4 fichiers principaux (BezierLib, EventRouter, AnimationFactory, AnimationQueue) + Animation (interpolation)
- ✅ Aucune nouvelle dépendance externe

## Complexity Tracking

Le module est plus gros que les autres modules FX (700 plafond vs 220-300 ailleurs). Justification :
- Coordonne 6 events distincts → EventRouter
- 4 propriétés animables (alpha, scale, translate, frame) → AnimationFactory polyvalent
- Coalescing thread-safe → AnimationQueue actor non-trivial
- Config Hyprland-style avec 2 niveaux (bezier + event rules) → Config.swift parsing

Pas plus simple sans perdre la flexibilité. Plafond 700 reste sub-critique vs SPEC-002 daemon (4000 LOC).
