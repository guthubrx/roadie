# SPEC-006 — Implementation Log

**Date** : 2026-05-01
**Status** : MVP livré (Phase 1+2+3+4).

## Tâches accomplies

- T001-T002 dossiers + Package.swift target dynamicLibrary
- T010 vérif SPEC-004 (OK : OSAXCommand.setAlpha + FXEvent.windowFocused/.windowCreated/.stageChanged/.configReloaded)
- T020 Config.swift (32 LOC) : OpacityConfig + AppRule + StageHideConfig + RuleMatcher
- T021 DimEngine.swift (15 LOC) : `targetAlpha` fonction pure
- T022 Module.swift (82 LOC) : OpacityModule singleton, subscribe, handle, shutdown, `@_cdecl module_init`
- T030 DimEngineTests (9 tests purs) : focused/inactive × rule/no-rule × clamp

## Reportés

- T015 StageHideOverride extension SPEC-002 : non fait (le code de StageManager.hide reste celui de SPEC-002 V2). Sera ajouté quand SPEC-006 sera mergé : extension ~10 LOC.
- T040 (US2 per-app rules) : RuleMatcher prêt, intégré dans handle(event:). OK pour MVP.
- T050-T055 (US3 stage_hide via α) : non implémenté (nécessite extension SPEC-002 StageHideOverride).
- T060 (animate_dim avec SPEC-007) : no-op si SPEC-007 absent ; à câbler quand SPEC-007 mergée.
- T031 integration test : nécessite osax bundle + machine SIP off

## Métriques

- **LOC** : 129 effectives — **PASS** (cible 150, plafond 220) ✅
- **Tests** : 9 nouveaux + 0 régression sur 90 = **99 tests, 0 échec** ✅

## Build & test

```bash
swift build       # 9.5 s cold
swift test        # 99 tests, 0 failure
```
