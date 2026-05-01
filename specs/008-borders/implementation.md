# SPEC-008 — Implementation Log

**Date** : 2026-05-01
**Status** : MVP livré (Phase 1+2+3 + US3 stage overrides + BorderOverlay opérationnel).

## Tâches accomplies

- T001-T002 dossiers + Package.swift target dynamicLibrary
- T010 vérif APIs SPEC-004 (FXEvent, FXEventBus, OSAXBridge.setLevel)
- T020 Config.swift (65 LOC) : BordersConfig + StageOverride + RGBA + parseHexColor + activeColor()
- T021 BorderOverlay.swift (88 LOC) : NSWindow borderless transparent + CALayer borderWidth/Color, ignoresMouseEvents=true, collectionBehavior multi-spaces, updateFrame/updateColor/updateThickness/close, deinit safety dispatch main
- T022 Module.swift (114 LOC étendu) : BordersModule singleton, registry `[CGWindowID: BorderOverlay]`, spawnOverlay/closeOverlay/refreshAllColors, dispatch handle window events (Created/Destroyed/Focused/Moved/Resized/StageChanged), helper `nsColor(fromHex:)`
- T030 ConfigTests (7 tests) : parseHex 6/8 chars + sans #, invalid, thickness clamp, stage override
- T031b OverlayTests (7 tests, NEW) : nsColor hex valide/alpha/invalide, BorderOverlay init/updateFrame/updateThickness/updateColor
- T050 stage overrides : `activeColor(forStage:config:)` + `refreshAllColors` au stageChanged event
- T060 LOC mesurées
- T062 implementation.md (ce fichier)

## Limitations runtime (sans osax SPEC-004.1)

- L'overlay utilise `NSWindowLevel.floating` natif. **Sans osax**, l'overlay est au-dessus des fenêtres standard mais pas au-dessus des fenêtres elles-mêmes en `.floating`. Acceptable pour 90% des cas (apps standard).
- **Avec osax** (post-SPEC-004.1) : `OSAXCommand.setLevel` permettrait de forcer un level supérieur via le Window Server. À câbler dans `BorderOverlay.init` (1 ligne) quand l'osax est livré.

## Reportés (SPEC-008.1)

- T040/T041/T045 pulse SPEC-007 : dépend de SPEC-007 mergé pour avoir `AnimationsModule.requestAnimation`. Le module BordersModule a juste à appeler `AnimationsModule.shared?.requestAnimation(...)` au focus_changed quand `pulse_on_focus=true`. ~10 LOC d'ajout.
- T031, T055, T063 : tests integration shell (screenshot pixel sample, 24h stabilité). Nécessitent display réel + machine SIP off pour validation visuelle.
- T061 doc quickstart.md SPEC-004 : à intégrer au merge final.

## Métriques

- **LOC** : 267 effectives (Config 65 + BorderOverlay 88 + Module 114) — **PASS** (cible 200, plafond 280, marge 13 LOC). Le scope BorderOverlay actif a coûté ~140 LOC de plus que la version skeleton du commit précédent.
- **Tests** : 14 nouveaux (Config 7 + Overlay 7) + 0 régression sur 90 = **104 tests, 0 échec** ✅

## Build & test

```bash
swift build       # 1.3 s hot
swift test        # 104 tests, 0 failure
```
