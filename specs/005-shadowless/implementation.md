# SPEC-005 — Implementation Log

**Date** : 2026-05-01
**Status** : MVP livré (Phase 1+2+3).

## Tâches accomplies

| Tâche | Status | Notes |
|---|---|---|
| T001-T002 Setup | ✅ | dossiers Sources/RoadieShadowless + Tests |
| T003 Package.swift | ✅ | target dynamicLibrary + test target + product |
| T010 Vérif APIs SPEC-004 | ✅ | OSAXCommand.setShadow + FXEvent + FXEventBus tous présents |
| T020 Module.swift | ✅ | mono-fichier 82 LOC (cible 80, plafond 120) — PASS |
| T030 ModeMappingTests | ✅ | 7 tests purs sur targetDensity |

## Métriques

- **LOC** : 82 effectives — **PASS** (cible 80, plafond 120)
- **Tests** : 7 nouveaux unitaires + 0 régression sur 90 → **97 tests, 0 échec** ✅
- **Compartimentation** : module = `.dynamicLibrary` séparé, jamais lié au daemon

## Reste à faire (post merge framework)

- T031 integration test 16-fx-shadowless.sh : nécessite osax bundle + machine SIP off
- Hot-reload via configReloaded event : T040-T041 implémentés en logique mais pas de test integration

## Build & test

```bash
swift build       # 0.7 s hot
swift test        # 97 tests, 0 failure
```
