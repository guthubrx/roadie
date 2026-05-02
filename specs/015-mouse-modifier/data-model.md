# Data Model — SPEC-015 Mouse modifier drag & resize

**Date** : 2026-05-02 | **Phase** : 1

## Modèle de données runtime

### `ModifierKey` (enum, RoadieCore/Config.swift)

```swift
public enum ModifierKey: String, Codable, Sendable {
    case ctrl
    case alt        // = option
    case cmd        // = command
    case shift
    case hyper      // ctrl+alt+cmd+shift
    case none
}

extension ModifierKey {
    public var nsFlags: NSEvent.ModifierFlags {
        switch self {
        case .ctrl: return .control
        case .alt: return .option
        case .cmd: return .command
        case .shift: return .shift
        case .hyper: return [.control, .option, .command, .shift]
        case .none: return []
        }
    }
}
```

### `MouseAction` (enum)

```swift
public enum MouseAction: String, Codable, Sendable {
    case move
    case resize
    case none
}
```

### `MouseConfig` (struct)

```swift
public struct MouseConfig: Codable, Sendable {
    public var modifier: ModifierKey      // défaut .ctrl
    public var actionLeft: MouseAction    // défaut .move
    public var actionRight: MouseAction   // défaut .resize
    public var actionMiddle: MouseAction  // défaut .none
    public var edgeThreshold: Int         // défaut 30 (px)
}
```

Sourcé depuis `[mouse]` du TOML, fallback sur defaults par champ + log warn par valeur invalide (FR-002, FR-003).

### `Quadrant` (enum, RoadieCore)

```swift
public enum Quadrant: Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}
```

### `MouseDragSession` (struct, MouseDragHandler.swift)

```swift
public struct MouseDragSession {
    public let wid: WindowID
    public let mode: MouseAction       // .move | .resize
    public let startCursor: CGPoint    // NS coords global
    public let startFrame: CGRect      // AX coords (= state.frame au mouseDown)
    public let quadrant: Quadrant      // pour resize, ignored pour move
    public var lastApply: Date         // throttling
}
```

Vit pendant la durée d'un drag (mouseDown → mouseUp). Détruit au mouseUp.

---

## Persistance

**Aucune** côté SPEC-015 (pas de state runtime persisté). Seule la config TOML est persistée via le fichier utilisateur normal.

---

## Transitions d'état (drag move)

```
mouseDown (Ctrl+LClick) :
  - check modifier match → si oui, identifier wid via CGWindowList
  - vérifier action_left == .move
  - création session = MouseDragSession(wid, .move, cursor, state.frame, .center, now)
  - mark MouseRaiser skip

mouseDragged (≥30ms après dernier apply) :
  - delta = currentCursor - session.startCursor
  - newFrame = session.startFrame.offsetBy(delta)
  - AXReader.setBounds(element, frame: newFrame)
  - registry.updateFrame(wid, newFrame)
  - Si tilée et 1er drag → layoutEngine.removeWindow(wid) + state.isFloating=true

mouseUp :
  - setBounds final (= dernière position)
  - registry.commit
  - Si la fenêtre a traversé un display → déléguer à onDragDrop SPEC-013
  - Détruire la session
```

## Transitions d'état (drag resize)

```
mouseDown (Ctrl+RClick) :
  - vérifier action_right == .resize
  - calculer quadrant via cursor relative à frame
  - session = MouseDragSession(wid, .resize, cursor, state.frame, quadrant, now)

mouseDragged :
  - delta = currentCursor - session.startCursor
  - newFrame = computeResizedFrame(session.startFrame, delta, session.quadrant)
  - setBounds + updateFrame

mouseUp :
  - Si tilée → layoutEngine.adaptToManualResize(wid, newFrame:)
  - Si floating → registry.commit final
```

## Validation rules

| Règle | Quand | Action |
|---|---|---|
| `modifier ∈ {ctrl, alt, cmd, shift, hyper, none}` | parsing TOML | fallback `.ctrl` + warn |
| `action_X ∈ {move, resize, none}` | parsing TOML | fallback `.none` + warn |
| `edge_threshold ∈ [5, 200]` | parsing TOML | clamp et warn |
| `action_left == action_right` (= les 2 sur même action) | runtime | OK, juste 2 boutons font la même chose |
| `Input Monitoring absent` | boot | log error + skip init |

---

## Conformité avec spec FRs

| FR | Adressé par |
|---|---|
| FR-001 (parser) | `Config.swift` extension `MouseConfig` |
| FR-002 (fallback ctrl) | parser tolérant |
| FR-003 (fallback none) | idem |
| FR-004 (reload) | `daemon.reload` re-lit + reinit `MouseDragHandler` |
| FR-010 (identifier fenêtre) | `MouseDragHandler.handleMouseDown` via CGWindowList |
| FR-011 (drag move) | `mouseDragged` avec delta + setBounds |
| FR-012 (sortir du tile) | au 1er drag, `layoutEngine.removeWindow` + `isFloating=true` |
| FR-013 (mouseUp commit) | `mouseUp` final setBounds + updateFrame |
| FR-014 (cross-display) | délégation à `onDragDrop` SPEC-013 si display change |
| FR-020 (quadrant) | `computeQuadrant(cursor, frame, edgeThreshold)` |
| FR-021 (resize) | `computeResizedFrame(startFrame, delta, quadrant)` |
| FR-022 (adapt BSP) | `mouseUp` → `layoutEngine.adaptToManualResize` |
| FR-023 (commit floating) | idem mouseUp |
| FR-030 (skip raise) | `MouseRaiser` early return si modifier match |
| FR-031 (raise normal) | comportement actuel préservé |
| FR-040 (30 FPS) | throttle 30ms |
| FR-041 (perm absente) | `IOHIDRequestAccess` check au boot |
| FR-042 (NSEvent global) | `NSEvent.addGlobalMonitorForEvents` |
