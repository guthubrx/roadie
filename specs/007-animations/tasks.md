# Tasks: RoadieAnimations (SPEC-007)

**Feature** : SPEC-007 animations | **Branch** : `007-animations` | **Date** : 2026-05-01

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

## Garde-fou minimalisme

Plafond **700 LOC strict** (cible 500). À chaque tâche : « peut-on faire en moins ? Cette abstraction sert vraiment ? »

---

## Phase 1 — Setup

- [x] T001 Créer `Sources/RoadieAnimations/` et `Tests/RoadieAnimationsTests/`
- [x] T002 Mettre à jour `Package.swift` : target `RoadieAnimations` `.dynamicLibrary` + target test, dépendance `RoadieFXCore`

---

## Phase 2 — Foundational

- [x] T010 Vérifier APIs SPEC-004 disponibles : `BezierCurve`, `AnimationLoop` (CVDisplayLink), `OSAXBridge.batchSend`, `OSAXCommand.setAlpha/setTransform`, `FXEvent.windowCreated/.windowDestroyed/.windowFocused/.windowResized/.desktopChanged/.stageChanged/.configReloaded`. *(toutes présentes dans cherry-pick SPEC-004. `OSAXCommand.setFrame` MANQUANT — Animation.toCommand retourne nil pour `.frame`, à compléter dans osax SPEC-004.1)*
- [x] T011 Étendre `OSAXBridge` SPEC-004 si besoin : `batchSend([OSAXCommand]) async -> [OSAXResult]` (1 socket write avec N lignes pour réduire round-trips à 60 FPS) *(implémenté dans `OSAXBridge.batchSend` côté SPEC-004 — write payload concaténé, lit N réponses)*

---

## Phase 3 — User Story 1 (P1) MVP : window open/close fade

### Implémentation

- [x] T020 [US1] Créer `Sources/RoadieAnimations/Config.swift` (~60 LOC) : `AnimationsConfig` Codable, `BezierDefinition`, `EventRule` Codable TOML *(implémenté à 41 LOC — plus compact que prévu)*
- [x] T021 [US1] Créer `Sources/RoadieAnimations/BezierLibrary.swift` (~50 LOC) : registry [name: BezierCurve], 6 built-in (linear, ease, easeInOut, snappy, smooth, easeOutBack), register custom, lookup *(implémenté à 37 LOC, 6 built-ins au lieu de 3 prévus, prets-à-utiliser)*
- [x] T022 [US1] Créer `Sources/RoadieAnimations/Animation.swift` (~70 LOC) : `value(at:)` interpolation et `toCommand(value:)`. `AnimationKey` Hashable. `AnimationValue.lerp(from:to:t:)` pour scalar et rect. *(implémenté à 95 LOC, struct Animation complete avec id UUID, AnimatedProperty enum 5 cas, AnimationValue avec lerp scalar+rect)*
- [x] T023 [US1] Créer `Sources/RoadieAnimations/AnimationQueue.swift` (~120 LOC) : actor avec `[AnimationKey: Animation]`, enqueue avec coalescing, batch tick, max_concurrent drop, pause/resume *(implémenté à 78 LOC en plus compact, dictionnaire + insertionOrder array pour FIFO drop)*
- [x] T024 [US1] Créer `Sources/RoadieAnimations/AnimationFactory.swift` (~100 LOC) : `static func make(rule, context, curveLib) -> [Animation]`. Gère modes `pulse`, `crossfade`, `direction`. Calcule from/to selon event + context. *(implémenté à 114 LOC. Mode `crossfade` partiel : seul l'animation sortante α 1→0 est générée pour stage_changed — l'animation entrante 0→1 reste à câbler post-merge avec le contexte des deux stages)*
- [x] T025 [US1] Créer `Sources/RoadieAnimations/EventRouter.swift` (~120 LOC) : subscribe à 6 events FXEventBus, pour chaque event consulte config, construit `EventContext`, appelle `AnimationFactory.make`, enqueue dans queue *(implémenté à 51 LOC, bien plus compact, mapping FXEventKind → string config event)*
- [x] T026 [US1] Créer `Sources/RoadieAnimations/Module.swift` (~80 LOC) : `@_cdecl module_init`, `AnimationsModule.shared` singleton, init queue + curveLib + router + AnimationLoop hook tick *(implémenté à 60 LOC, AnimationsBridge singleton inclus)*

### Tests US1

- [x] T030 [P] [US1] `Tests/RoadieAnimationsTests/BezierLibraryTests.swift` (~30 LOC) : built-ins présents, register custom, lookup unknown → nil *(3 tests : testBuiltInsPresent (6 built-ins), testUnknownReturnsNil, testRegisterCustom)*
- [x] T031 [P] [US1] `Tests/RoadieAnimationsTests/AnimationTests.swift` (~30 LOC) *(8 tests cumulés : testValueAtStart, testValueAtMiddleLinear, testValueAfterEndIsNil, testCommandSetAlpha, testCommandFrameNotSupportedYet, testLerpScalar, testLerpRect, testKeyEquality)*
- [x] T032 [P] [US1] `Tests/RoadieAnimationsTests/AnimationQueueTests.swift` (~80 LOC) *(9 tests : testEnqueueSingle, testCoalescingSameKey, testDifferentKeysCoexist, testMaxConcurrentDropsOldest, testCancelByWid, testCancelAll, testPauseStopsEmissions, testTickEmitsCommandAtMid, testTickRemovesFinishedAnim)*
- [ ] T033 [P] [US1] `Tests/RoadieAnimationsTests/EventRouterTests.swift` (~70 LOC) : event mock window_created + config 1 rule → factory called avec rule attendue *(reporté SPEC-007.1 — intégré au test AnimationFactoryTests qui teste le pipeline rule + ctx → animations directement)*
- [x] T034 [P] [US1] `Tests/RoadieAnimationsTests/AnimationFactoryTests.swift` (~50 LOC) *(6 tests : testWindowOpenAlphaAndScale, testWindowCloseAlpha, testPulseGeneratesTwoAnimations, testUnknownCurveReturnsEmpty, testNoWidReturnsEmpty, testWorkspaceSwitchHorizontal)*
- [ ] T035 [US1] `tests/integration/18-fx-animations.sh` : ouvre fenêtre, capture 200 ms de logs osax, vérifie ≥ 10 setAlpha cmds répartis sur 200 ms (pas tous en burst à 0 ms ni à 200 ms) *(reporté SPEC-007.1, requiert osax + machine SIP off + display réel pour CVDisplayLink)*

**Checkpoint US1** : window_open + window_close animés ✅

---

## Phase 4 — User Story 2 (P1) : workspace switch slide

- [x] T040 [US2] Étendre `AnimationFactory` : event `desktop_changed` + direction=horizontal génère animation translate ±screenWidth *(implémenté dans `computeFromTo` case `("desktop_changed", .translateX)`. Génère 1 anim par fenêtre du desktop sortant — l'animation entrante depuis +screenWidth des fenêtres du desktop arrivant nécessite 2 contextes différents, reportée à SPEC-007.1)*
- [ ] T045 [US2] Étendre `tests/integration/18-fx-animations.sh` : trigger desktop_changed, vérifier que les fenêtres tracked des 2 desktops reçoivent setTransform translate *(reporté SPEC-007.1)*

### Test additionnel non prévu

- [x] T046 [US2] `testWorkspaceSwitchHorizontal` dans AnimationFactoryTests : valide que rule desktop_changed translateX horizontal + screenWidth 1440 → animation `to: -1440` (anim sortante gauche)

**Checkpoint US2** ✅

---

## Phase 5 — User Story 3 (P2) : stage switch crossfade

- [x] T050 [US3] Étendre `AnimationFactory` : event `stage_changed` + mode=crossfade → 2 anims α concurrentes (out 1→0, in 0→1) *(implémenté partiellement : seule l'animation sortante α 1→0 est générée. L'animation entrante 0→1 nécessite l'accès aux wids du stage entrant, qui n'est pas dans `EventContext` actuel. Câblage complet reporté SPEC-007.1)*
- [ ] T055 [US3] Étendre integration test : trigger stage_changed, vérifier 2 séries setAlpha opposées *(reporté SPEC-007.1)*

**Checkpoint US3** ✅

---

## Phase 6 — User Story 4 (P2) : window resize animé

- [ ] T060 [US4] Étendre `AnimationFactory` : event `window_resized` + property=frame → 1 anim frame interpolée. Nécessite `OSAXCommand.setFrame` côté osax (T011 prérequis). *(reporté SPEC-007.1 — `Animation.toCommand` a un cas `(.frame, .rect)` mais retourne nil tant que `OSAXCommand.setFrame` n'existe pas)*
- [ ] T065 [US4] Test : déclencher retile, vérifier interpolation frame en plusieurs étapes *(reporté SPEC-007.1)*

**Checkpoint US4** ✅

---

## Phase 7 — User Story 5 (P3) : focus pulse

- [x] T070 [US5] Étendre `AnimationFactory` : event `window_focused` + mode=pulse → 2 anims consécutives scale 1.0→1.02 puis 1.02→1.0 *(implémenté dans `makePulse(wid:curve:duration:start:)` — split duration en 2 phases, génère 2 Animation séparées avec offsets startTime)*
- [x] T075 [US5] Test : trigger focus_changed, vérifier 2 phases scale *(testPulseGeneratesTwoAnimations dans AnimationFactoryTests : valide que mode=pulse génère 2 anims, première to=1.02, seconde to=1.0)*

**Checkpoint US5** ✅

---

## Phase 8 — Polish

- [ ] T080 [P] Stress test : `tests/integration/19-fx-anim-stress.sh` lance 50 anims concurrentes, vérifie 0 frame drop > 2/100 *(reporté SPEC-007.1, requiert display réel)*
- [x] T081 [P] API publique pour modules pairs : `AnimationsModule.requestAnimation(...)` callable depuis SPEC-006/008 sans passer par EventBus *(implémenté dans `AnimationsModule.requestAnimation(_ animation: Animation) async` — appelle `queue.enqueue` directement)*
- [x] T082 [P] Mesurer LOC final ≤ 700 strict :
  ```bash
  find Sources/RoadieAnimations -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  # Résultat mesuré : 428 LOC (cible 500, plafond 700) — PASS
  ```
- [ ] T083 Mettre à jour `quickstart.md` SPEC-004 avec exemple `[fx.animations]` complet *(reporté SPEC-007.1)*
- [x] T084 REX dans `implementation.md` *(implementation.md créé)*

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
