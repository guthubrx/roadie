# Implementation Log — SPEC-015 Mouse modifier drag & resize

**Démarré** : 2026-05-02
**Terminé** : 2026-05-02
**Branche** : `015-mouse-modifier`
**Statut** : ✅ Implémentation complète, prête pour test runtime utilisateur

## Récapitulatif

| Phase | Statut | Tasks |
|---|---|---|
| 1. Setup | ✅ Done | T001 |
| 2. Foundational | ✅ Done | T002-T008 |
| 3. US1 (drag move) | ✅ Done | T010-T015 |
| 4. US2 (drag resize quadrant) | ✅ Done | T020-T023 |
| 5. US3 (config TOML) | ✅ Done | T030-T031 |
| 6. US4 (MouseRaiser coexistence) | ✅ Done | T040 |
| 7. Bootstrap | ✅ Done | T050-T051 |
| 8. Polish | ✅ Done | T060-T065 |

24/24 tasks complètes.

## Files touched

**Modifiés** (4) :
- `Sources/RoadieCore/Config.swift` (+ ModifierKey, MouseAction, MouseConfig + parser tolérant)
- `Sources/RoadieCore/MouseRaiser.swift` (+ skipWhenModifier param)
- `Sources/roadied/main.swift` (+ init MouseDragHandler bootstrap, callbacks branchés)
- `CHANGELOG.md`

**Créés** (3) :
- `Sources/RoadieCore/MouseDragHandler.swift` (~270 LOC : Quadrant enum, MouseDragHandler classe, MouseDragSession struct, computeQuadrant, computeResizedFrame, ModifierKey.nsFlags extension)
- `Tests/RoadieCoreTests/MouseConfigTests.swift` (5 cas)
- `Tests/RoadieCoreTests/MouseQuadrantTests.swift` (13 cas)

## Architecture

```
NSEvent.addGlobalMonitorForEvents
    │
    ▼
MouseDragHandler.handle(event:at:)
    │
    ├── mouseDown : handleMouseDown → check modifier → identifie wid via CGWindowList
    │     → crée MouseDragSession (mode, startCursor, startFrame, quadrant)
    │
    ├── mouseDragged : throttle 30ms → calcule delta → setBounds + updateFrame
    │     ├── mode=.move : translation simple, sortie du tile au 1er drag
    │     └── mode=.resize : computeResizedFrame(quadrant) avec ancre opposée fixe
    │
    └── mouseUp : setBounds final → callbacks (onDragDrop SPEC-013, adaptResize BSP)
```

## Build & Tests

```
$ swift build → Build complete
$ swift test  → 39 suites, 0 failures
```

## Test runtime à effectuer (manuel)

1. **Drag move** : Ctrl + clic gauche au milieu d'une fenêtre → drag → la fenêtre suit. Au lâcher, position commitée. Si tilée, devient floating.
2. **Drag resize** : Ctrl + clic droit dans un coin TL → drag → resize TL avec BR fixe.
3. **Config flexibility** : changer `modifier="alt"` dans toml → reload → Alt+drag actif.
4. **Coexistence raiser** : clic simple = raise classique ; Ctrl+clic = drag uniquement (pas de raise).

## REX — Retour d'Expérience

**Tâches complétées** : 24/24

### Ce qui a bien fonctionné
- Pure functions `computeQuadrant` et `computeResizedFrame` 100 % testables sans hook NSEvent → 13 cas en 1 fichier de test.
- Réutilisation du pattern `MouseRaiser` (CGWindowList scan, NSEvent monitor) → minimum d'inventer.
- Callbacks `removeFromTile`/`adaptResize`/`onDragDrop` permettent au handler de rester dans `RoadieCore` sans dépendance directe à `LayoutEngine` (decoupling propre).

### Difficultés rencontrées
- **Conversion NS→CG cursor** : NSEvent.mouseLocation est en NS coords (Y bottom-up depuis primary), CGWindowList bounds en CG (Y top-down). Utilisation du primary screen.height pour flip Y, comme déjà fait dans MouseRaiser.
- **Throttling setBounds** : 30 ms entre 2 calls + setBounds final inconditionnel au mouseUp pour éviter une dernière position désynchro.

### Connaissances acquises
- Pattern AeroSpace/yabai mouse_modifier : modifier vérifié au mouseDown, l'état "drag actif" persiste jusqu'au mouseUp même si modifier relâché entre temps.
- `event.modifierFlags.intersection(.deviceIndependentFlagsMask)` pour ignorer les flags volatils (CapsLock, fonctions touchpad).

### Recommandations
- Si latence runtime perçue : ajuster throttle à 16 ms (60 FPS) au lieu de 30 ms.
- Smooth resize centre (= scale uniforme depuis le centre) reportable V2 si demandé.
- Émission events `window_drag_start` / `window_drag_end` reportable V2 (pour SketchyBar).
