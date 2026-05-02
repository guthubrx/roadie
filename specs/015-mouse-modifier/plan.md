# Implementation Plan: Mouse modifier drag & resize

**Branch** : `015-mouse-modifier` | **Date** : 2026-05-02 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/015-mouse-modifier/spec.md`

## Summary

Hook global mouse events (`NSEvent.addGlobalMonitorForEvents`) avec un module `MouseDragHandler` qui :
- Au mouseDown, vérifie si le `MouseConfig.modifier` est pressé (`NSEvent.modifierFlags`).
- Si oui, identifie la fenêtre via `CGWindowList` (= pattern `MouseRaiser`) et démarre une `MouseDragSession`.
- Pendant `mouseDragged`, throttle 30 FPS, applique `setBounds` selon le mode (move : translation ; resize : ancre opposée selon le quadrant).
- Au mouseUp, commit `registry.updateFrame`, et délègue à `LayoutEngine.adaptToManualResize` (si tilée + resize) ou aux hooks SPEC-013 cross-display (si la fenêtre a traversé un display pendant le drag).

Coexistence avec `MouseRaiser` : ajouter un filtre `event.modifierFlags.contains(activeModifier)` au monitor de `MouseRaiser` pour skip son raise quand le modifier est pressé.

~250-350 LOC code + ~150 LOC tests.

## Technical Context

**Language/Version** : Swift 6.0 (SwiftPM)
**Primary Dependencies** : `RoadieCore` (WindowRegistry, AXReader, Logger), `RoadieTiler` (LayoutEngine.adaptToManualResize), Cocoa (NSEvent), AppKit, IOKit (Input Monitoring permission via `IOHIDRequestAccess` déjà en place)
**Storage** : config TOML `~/.config/roadies/roadies.toml` `[mouse]` section, parsée via TOMLKit (déjà présent)
**Testing** : XCTest + suite Swift Testing existante
**Target Platform** : macOS 14+
**Project Type** : single Swift package multi-module
**Performance Goals** : drag ≥ 30 FPS perçu (throttle setBounds à 30ms entre calls)
**Constraints** : zéro permission nouvelle (Input Monitoring déjà acquise), pas de CGEventTap (= scope plus large requis), zéro régression MouseRaiser
**Scale/Scope** : ~300 LOC code Swift (cible), plafond 450. Tests ~150 LOC. ≤ 4 fichiers source touchés.

**Cible LOC effectives** : 300 (code Swift hors tests)
**Plafond strict** : 450 (= +50 %, justification ADR si dépassé)

## Constitution Check

| Gate | État | Justification |
|---|---|---|
| **A. Suckless** | ✅ PASS | Réutilise patterns existants (NSEvent monitor de MouseRaiser, AXReader.setBounds). Aucune nouvelle abstraction au-delà de `MouseDragSession` (struct minimale). |
| **B. Zéro dépendance** | ✅ PASS | NSEvent + Cocoa standard, TOMLKit déjà présent, pas de nouveau package. |
| **C. Identifiants stables** | ✅ PASS | `CGWindowList` retourne cgwid stables. Pas de matching bundleID/title. |
| **D. Fail loud** | ✅ PASS | Permission Input Monitoring absente → log error + skip feature. Pas de retry silencieux. |
| **E. État TOML plat** | ✅ PASS | Config TOML, format texte plat. |
| **F. CLI minimaliste** | ✅ PASS | Aucun verbe CLI ajouté (config-only). |
| **G. LOC** | ✅ PASS | Cible 300 / plafond 450 déclarés. |

**Tous gates PASS.**

## Project Structure

```text
specs/015-mouse-modifier/
├── plan.md              # This file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── mouse-config.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

```text
Sources/
├── RoadieCore/
│   ├── Config.swift               # T002-T003 : MouseConfig + parser TOML
│   ├── MouseDragHandler.swift     # NEW (T010+) : ~200 LOC, hook global mouse events + drag/resize logic
│   └── MouseRaiser.swift          # T030 : skip si modifier pressé
└── roadied/
    └── main.swift                 # T040 : init MouseDragHandler au bootstrap

Tests/
└── RoadieCoreTests/
    ├── MouseConfigTests.swift (NEW)        # T070
    ├── MouseQuadrantTests.swift (NEW)      # T071
    └── MouseDragSessionTests.swift (NEW)   # T072
```

**Structure Decision** : un nouveau fichier `MouseDragHandler.swift` (~200 LOC) qui encapsule le hook NSEvent + state machine drag. Pas de nouveau module SwiftPM (= dans `RoadieCore`).

## Complexity Tracking

> Aucune violation gates constitutionnels. Section vide.
