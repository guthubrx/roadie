# SPEC-010 — Implementation Log

**Date** : 2026-05-01
**Status** : Logique pure livrée. Câblage CLI + SPEC-003 API reporté post merge.

## Tâches accomplies

- T001-T002 dossiers + Package.swift target dynamicLibrary
- T010 vérif APIs SPEC-004 (OSAXCommand.moveWindowToSpace/setSticky/setLevel)
- T020 Config.swift (44 LOC) : CrossDesktopConfig + PinRule + ForceTilingConfig
- T021 CommandHandler.swift (84 LOC) : LevelTracker + handleSpace/Sticky/Pin/WindowCreated
- T040 PinEngine.swift (30 LOC) : target(forBundleID:) avec labelResolver/indexResolver injectés
- T022 Module.swift (54 LOC) : CrossDesktopModule singleton + `@_cdecl module_init`
- T045 PinEngineTests (7 tests) : no rules, label match, label unknown, index match,
  index invalid, first rule wins, no match for bundleID

## Reportés (post merge)

- T023 sub-verbe `roadie window space|stick|pin` dans CLI : nécessite extension Sources/roadie/main.swift dans le worktree merge
- T024 routes `window.*` dans CommandRouter daemon
- API SPEC-003 publique `MultiDesktopManager.uuidFor(label:)` / `uuidFor(index:)` à câbler dans `makeHandler` (actuellement les resolvers retournent toujours nil)
- T070 Force-tiling LayoutEngine extension : reporté à SPEC-010.1 (P3, pas prioritaire selon utilisateur)
- Tests integration : nécessitent osax + machine SIP off

## Métriques

- **LOC** : 180 effectives — **PASS** (cible 300, plafond 450) ✅
- **Tests** : 7 nouveaux PinEngineTests + 0 régression sur 90 = **97 tests, 0 échec** ✅
