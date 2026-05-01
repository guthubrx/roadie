# SPEC-008 — Implementation Log

**Date** : 2026-05-01
**Status** : Logique pure livrée. Overlay NSWindow reporté post merge.

## Tâches accomplies

- T001-T002 dossiers + Package.swift target dynamicLibrary
- T010 vérif APIs SPEC-004 (FXEvent, FXEventBus, OSAXBridge.setLevel)
- T020 Config.swift : BordersConfig + StageOverride + RGBA + parseHexColor + activeColor()
- T022 Module.swift : BordersModule singleton, subscribe, handle, colorFor(wid:)
- T030 ConfigTests : parseHex 6/8 chars + sans #, invalid, thickness clamp, stage override

## Reportés (overlay NSWindow)

- T021 BorderOverlay.swift : nécessite `AppKit` + `OSAXBridge.setLevel` réel pour positionner au-dessus
- T040 pulse animation via SPEC-007 : prêt à câbler quand SPEC-007 mergé
- Tests integration : nécessitent osax + machine SIP off

## Métriques

- **LOC** : 125 effectives — **PASS** (cible 200, plafond 280) ✅
- **Tests** : 7 nouveaux ConfigTests + 0 régression sur 90 = **97 tests, 0 échec** ✅
