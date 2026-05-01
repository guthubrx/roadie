# Implementation Plan: RoadieBorders (SPEC-008)

**Branch** : `008-borders` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)

## Summary

Module FX qui dessine une bordure colorée autour de la fenêtre focused via une `NSWindow` overlay borderless qui suit le frame de la fenêtre tracked. Couleurs configurables active/inactive + override par stage. Pulse animé optionnel via SPEC-007. Plafond LOC strict **280**, cible **200**.

## Technical Context

**Language** : Swift 5.9+, AppKit (NSWindow, NSView, CALayer)

**Primary Dependencies** : `RoadieFXCore.dylib` SPEC-004 (FXModule, EventBus accessor, OSAXBridge pour setLevel). Optionnel `RoadieAnimations.dylib` SPEC-007 (requestAnimation).

**Storage** : aucun

**Testing** : unit sur `OverlayConfig.color(for stageID:)` (mapping stage→color), `frameTracker` (calcule rect overlay = rect window + thickness/2 padding). Integration : ouvrir fenêtre, vérifier overlay créée, vérifier `ignoresMouseEvents = true`.

**Target Platform** : macOS 14+, SIP partial off requis pour `setLevel` au-dessus correctement

**Project Type** : Swift target `.dynamicLibrary`

**Performance Goals** : SC-001 latence ≤ 50 ms, SC-002 60 FPS resize/move, SC-004 LOC ≤ 280

**Constraints** :
- Plafond 280 LOC strict
- 3 fichiers Swift max (Module + BorderOverlay + Config)
- Overlay NSWindow propre = pas besoin d'osax pour dessiner (juste setLevel)
- `ignoresMouseEvents = true` impératif (sinon UX cassée)

## Constitution Check

✅ Toutes gates passent. Module simple, pluggable, < 280 LOC.

## Project Structure

```text
specs/008-borders/
├── plan.md, spec.md, tasks.md, checklists/requirements.md

Sources/
└── RoadieBorders/                   # NEW target .dynamicLibrary
    ├── Module.swift                 # ~80 LOC
    ├── BorderOverlay.swift          # ~120 LOC : NSWindow + CALayer + tracking frame
    └── Config.swift                 # ~40 LOC

Tests/
└── RoadieBordersTests/
    └── ConfigTests.swift            # ~40 LOC : color(for:), parsing hex
```

## Phase 0/1 — Design

### `BorderOverlay` skeleton

```swift
@MainActor
final class BorderOverlay {
    private let window: NSWindow
    private let layer: CALayer
    private var trackedWID: CGWindowID
    private var trackedFrame: CGRect

    init(wid: CGWindowID, frame: CGRect, thickness: Int, color: NSColor) {
        let pad = CGFloat(thickness)
        let overlayFrame = frame.insetBy(dx: -pad/2, dy: -pad/2)
        self.window = NSWindow(contentRect: overlayFrame, styleMask: .borderless, ...)
        self.window.isOpaque = false
        self.window.backgroundColor = .clear
        self.window.ignoresMouseEvents = true
        self.window.level = .floating  // sera forcé via osax setLevel ensuite
        self.layer = CALayer()
        self.layer.borderWidth = CGFloat(thickness)
        self.layer.borderColor = color.cgColor
        self.window.contentView?.layer = self.layer
        self.window.contentView?.wantsLayer = true
        self.window.orderFront(nil)
    }

    func updateFrame(_ frame: CGRect) { ... }
    func updateColor(_ color: NSColor) { layer.borderColor = color.cgColor }
    func close() { window.orderOut(nil) }
}
```

### `BordersModule` flow

```
event window_focused / created / moved / resized
   │
   ▼
look up BorderOverlay for wid (create if missing)
   │
   ▼
overlay.updateFrame(window.frame) + updateColor(active or inactive)
   │
   ▼ (optionnel SPEC-007)
animations.requestAnimation(thickness pulse) si pulse_on_focus
```

✅ Toutes gates passent post-design.
