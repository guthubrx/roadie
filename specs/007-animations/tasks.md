# Tasks: RoadieAnimations (SPEC-007)

**Feature** : SPEC-007 animations | **Branch** : `007-animations` | **Date** : 2026-05-01

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

## Garde-fou minimalisme

Plafond **700 LOC strict** (cible 500). À chaque tâche : « peut-on faire en moins ? Cette abstraction sert vraiment ? »

---

## Phase 1 — Setup

- [ ] T001 Créer `Sources/RoadieAnimations/` et `Tests/RoadieAnimationsTests/`
- [ ] T002 Mettre à jour `Package.swift` : target `RoadieAnimations` `.dynamicLibrary` + target test, dépendance `RoadieFXCore`

---

## Phase 2 — Foundational

- [ ] T010 Vérifier APIs SPEC-004 disponibles : `BezierCurve`, `BezierEngine`, `AnimationLoop` (CVDisplayLink), `OSAXBridge.batchSend`, `OSAXCommand.setAlpha/setTransform/setFrame`, `FXEvent.windowCreated/.windowDestroyed/.windowFocused/.windowResized/.desktopChanged/.stageChanged/.configReloaded`. Si `setFrame` manque → discuter étendre osax SPEC-004.
- [ ] T011 Étendre `OSAXBridge` SPEC-004 si besoin : `batchSend([OSAXCommand]) async -> [OSAXResult]` (1 socket write avec N lignes pour réduire round-trips à 60 FPS)

---

## Phase 3 — User Story 1 (P1) MVP : window open/close fade

### Implémentation

- [ ] T020 [US1] Créer `Sources/RoadieAnimations/Config.swift` (~60 LOC) : `AnimationsConfig` Codable, `BezierDefinition`, `EventRule` Codable TOML
- [ ] T021 [US1] Créer `Sources/RoadieAnimations/BezierLibrary.swift` (~50 LOC) : registry [name: BezierCurve], 3 built-in (linear, ease, easeInOut), register custom, lookup
- [ ] T022 [US1] Créer `Sources/RoadieAnimations/Animation.swift` (~70 LOC) : extension de la struct SPEC-004 avec `value(at:)` interpolation et `toCommand(value:)`. `AnimationKey` Hashable. `AnimationValue.lerp(from:to:t:)` pour scalar et rect.
- [ ] T023 [US1] Créer `Sources/RoadieAnimations/AnimationQueue.swift` (~120 LOC) : actor avec `[AnimationKey: Animation]`, enqueue avec coalescing, batch tick, max_concurrent drop, pause/resume
- [ ] T024 [US1] Créer `Sources/RoadieAnimations/AnimationFactory.swift` (~100 LOC) : `static func make(rule, context, curveLib) -> [Animation]`. Gère modes `pulse`, `crossfade`, `direction`. Calcule from/to selon event + context.
- [ ] T025 [US1] Créer `Sources/RoadieAnimations/EventRouter.swift` (~120 LOC) : subscribe à 6 events FXEventBus, pour chaque event consulte config, construit `EventContext`, appelle `AnimationFactory.make`, enqueue dans queue
- [ ] T026 [US1] Créer `Sources/RoadieAnimations/Module.swift` (~80 LOC) : `@_cdecl module_init`, `AnimationsModule.shared` singleton @MainActor, init queue + curveLib + router + AnimationLoop hook tick

### Tests US1

- [ ] T030 [P] [US1] `Tests/RoadieAnimationsTests/BezierLibraryTests.swift` (~30 LOC) : built-ins présents, register custom, lookup unknown → nil
- [ ] T031 [P] [US1] `Tests/RoadieAnimationsTests/AnimationTests.swift` (~30 LOC) : `value(at:)` à mi-parcours sur courbe linéaire (lerp simple), à 100% retourne nil, sur courbe snappy à 0.5 retourne ≈ 0.86
- [ ] T032 [P] [US1] `Tests/RoadieAnimationsTests/AnimationQueueTests.swift` (~80 LOC) : enqueue 1 → count 1, enqueue 2e sur même key → count toujours 1 (coalescing), enqueue 21 avec max=20 → drop 1 oldest, pause + tick → no-op
- [ ] T033 [P] [US1] `Tests/RoadieAnimationsTests/EventRouterTests.swift` (~70 LOC) : event mock window_created + config 1 rule → factory called avec rule attendue
- [ ] T034 [P] [US1] `Tests/RoadieAnimationsTests/AnimationFactoryTests.swift` (~50 LOC) : rule alpha 200ms snappy + context window_created → 1 Animation alpha 0→1 200ms snappy. Mode pulse → 2 Animations consécutives. Mode crossfade desktop_switch → 2 anims parallèles α opposées.
- [ ] T035 [US1] `tests/integration/18-fx-animations.sh` : ouvre fenêtre, capture 200 ms de logs osax, vérifie ≥ 10 setAlpha cmds répartis sur 200 ms (pas tous en burst à 0 ms ni à 200 ms)

**Checkpoint US1** : window_open + window_close animés ✅

---

## Phase 4 — User Story 2 (P1) : workspace switch slide

- [ ] T040 [US2] Étendre `AnimationFactory` : event `desktop_changed` + direction=horizontal génère 2 batches d'animations (1 par desktop concerné), translate ±screenWidth
- [ ] T045 [US2] Étendre `tests/integration/18-fx-animations.sh` : trigger desktop_changed, vérifier que les fenêtres tracked des 2 desktops reçoivent setTransform translate

**Checkpoint US2** ✅

---

## Phase 5 — User Story 3 (P2) : stage switch crossfade

- [ ] T050 [US3] Étendre `AnimationFactory` : event `stage_changed` + mode=crossfade → 2 anims α concurrentes (out 1→0, in 0→1)
- [ ] T055 [US3] Étendre integration test : trigger stage_changed, vérifier 2 séries setAlpha opposées

**Checkpoint US3** ✅

---

## Phase 6 — User Story 4 (P2) : window resize animé

- [ ] T060 [US4] Étendre `AnimationFactory` : event `window_resized` + property=frame → 1 anim frame interpolée. Nécessite `OSAXCommand.setFrame` côté osax (T011 prérequis).
- [ ] T065 [US4] Test : déclencher retile, vérifier interpolation frame en plusieurs étapes

**Checkpoint US4** ✅

---

## Phase 7 — User Story 5 (P3) : focus pulse

- [ ] T070 [US5] Étendre `AnimationFactory` : event `window_focused` + mode=pulse → 2 anims consécutives scale 1.0→1.02 puis 1.02→1.0
- [ ] T075 [US5] Test : trigger focus_changed, vérifier 2 phases scale

**Checkpoint US5** ✅

---

## Phase 8 — Polish

- [ ] T080 [P] Stress test : `tests/integration/19-fx-anim-stress.sh` lance 50 anims concurrentes, vérifie 0 frame drop > 2/100
- [ ] T081 [P] API publique pour modules pairs : `AnimationsModule.requestAnimation(...)` callable depuis SPEC-006/008 sans passer par EventBus
- [ ] T082 [P] Mesurer LOC final ≤ 700 strict :
  ```bash
  find Sources/RoadieAnimations -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  ```
- [ ] T083 Mettre à jour `quickstart.md` SPEC-004 avec exemple `[fx.animations]` complet
- [ ] T084 REX dans `implementation.md`

---

## Dependencies

Phase 1 → 2 → 3 (US1 MVP) → 4-7 séquentiel ou parallèle → 8

## Implementation Strategy

**MVP = Phase 1+2+3** = 13 tâches → window open/close animé, valide engine
Total : **31 tâches**, ~6-8 jours

## Garde-fou minimalisme

À chaque tâche :
❓ « cette ligne sert SPEC-007 réelle ou un futur ? »
❓ « cette abstraction est-elle justifiée ou peut-on simplifier ? »
❓ « ce mode/option/feature est-il vraiment utilisé ? »
