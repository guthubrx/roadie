# SPEC-007 — Implementation Log

**Date** : 2026-05-01
**Status** : MVP livré (Phase 1+2+3+pulse+workspace).

## Tâches accomplies

- T001-T002 dossiers + Package.swift target dynamicLibrary
- T010 vérif APIs SPEC-004 (BezierCurve, AnimationLoop, OSAXBridge.batchSend)
- T020 Config.swift (45 LOC) : AnimationsConfig + BezierDefinition + EventRule Codable
- T021 BezierLibrary.swift (37 LOC) : registry [name: BezierCurve], 6 built-ins, register custom
- T022-T024 Animation.swift (95 LOC) : AnimatedProperty, AnimationValue (lerp scalar+rect), AnimationKey, Animation (value+toCommand)
- T023 AnimationQueue.swift (78 LOC) : actor coalescing, max_concurrent drop, pause/resume, tick→[OSAXCommand]
- T024 AnimationFactory.swift (114 LOC) : make(rule, ctx, lib), gère pulse/crossfade/direction
- T025 EventRouter.swift (51 LOC) : map FXEventKind → config event, enqueue
- T026 Module.swift (60 LOC) : AnimationsModule singleton, subscribe, AnimationLoop tick → batchSend
- T030-T034 Tests : BezierLibrary, Animation, AnimationQueue, AnimationFactory (26 tests cumulés)

## Reste à faire (post merge SPEC-004 + osax)

- Mode `crossfade` dans AnimationFactory : générer 2 anims α concurrentes (out 1→0 + in 0→1) — actuellement seul l'out est fait
- `OSAXCommand.setFrame` côté osax bundle : `Animation.toCommand` retourne nil pour `.frame` aujourd'hui (T011 reportée)
- API publique `requestAnimation` : présente mais consumers (SPEC-006/008) non câblés tant que pas mergés
- Tests integration : nécessitent osax + machine SIP off

## Métriques

- **LOC** : 428 effectives (cible 500, plafond 700) — **PASS** ✅
- **Tests** : 26 nouveaux (BezierLibrary 3 + Animation 8 + AnimationQueue 9 + AnimationFactory 6) + 0 régression sur 90 = **116 tests, 0 échec** ✅

## Build & test

```bash
swift build       # 1.3 s hot
swift test        # 116 tests, 0 failure
```
