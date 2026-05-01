# Data Model — RoadieAnimations (SPEC-007)

**Date** : 2026-05-01

## Entités

### `EventRule` (Codable, dans `Config.swift`)

Une règle dans `[[fx.animations.events]]`.

```swift
public struct EventRule: Codable, Sendable {
    public let event: String              // "window_open", "desktop_changed", etc.
    public let properties: [String]       // ["alpha", "scale", "translateX", "frame"]
    public let durationMs: Int            // > 0
    public let curve: String              // référence à une courbe nommée
    public let direction: String?         // "horizontal" | "vertical" | "fade" | nil
    public let mode: String?              // "crossfade" | "pulse" | "sequential" | nil

    enum CodingKeys: String, CodingKey {
        case event, properties, curve, direction, mode
        case durationMs = "duration_ms"
    }
}
```

**Validation** :
- `event` doit matcher un des 6 events supportés (FR-005), sinon log error et skip rule
- `properties` non vide, chaque élément ∈ `{alpha, scale, translateX, translateY, frame}`
- `durationMs` > 0 et < 5000 (au-delà = loglag, déconseillé)
- `curve` doit exister dans `BezierLibrary` au moment du reload

### `BezierDefinition` (Codable)

Une courbe nommée dans `[[fx.animations.bezier]]`.

```swift
public struct BezierDefinition: Codable, Sendable {
    public let name: String
    public let points: [Double]    // [p1x, p1y, p2x, p2y]
}
```

**Validation** :
- `name` ASCII, ≤ 32 chars
- `points` contient exactement 4 valeurs
- `p1x` et `p2x` ∈ [0, 1] (CSS standard) ; `p1y` et `p2y` libres (overshoot autorisé pour easeOutBack)

### `BezierLibrary` (collection)

```swift
public final class BezierLibrary {
    private var curves: [String: BezierCurve] = [:]
    public static let builtIn: [String: BezierCurve] = [
        "linear": BezierCurve(p1x: 0.0, p1y: 0.0, p2x: 1.0, p2y: 1.0),
        "ease": BezierCurve(p1x: 0.25, p1y: 0.1, p2x: 0.25, p2y: 1.0),
        "easeInOut": BezierCurve(p1x: 0.42, p1y: 0.0, p2x: 0.58, p2y: 1.0),
    ]

    public func register(_ def: BezierDefinition) -> Bool
    public func curve(named: String) -> BezierCurve?
}
```

### `AnimatedProperty` (enum)

Déjà défini dans SPEC-004 data-model. Rappel :

```swift
public enum AnimatedProperty: String, Sendable {
    case alpha, scale, translateX, translateY, frame
}
```

### `AnimationValue` (enum)

```swift
public enum AnimationValue: Sendable {
    case scalar(Double)        // alpha, scale, translateX, translateY
    case rect(CGRect)          // frame
}
```

### `Animation` (struct)

Déjà défini SPEC-004 data-model. Étendu ici avec les méthodes utilisées par `AnimationQueue` :

```swift
public struct Animation: Sendable {
    public let id: UUID
    public let wid: CGWindowID
    public let property: AnimatedProperty
    public let from: AnimationValue
    public let to: AnimationValue
    public let curve: BezierCurve
    public let startTime: CFTimeInterval
    public let duration: CFTimeInterval

    /// Retourne la valeur interpolée à `now`, ou nil si l'animation est terminée
    public func value(at now: CFTimeInterval) -> AnimationValue? {
        let progress = (now - startTime) / duration
        guard progress < 1.0 else { return nil }
        let easedT = curve.sample(progress)
        return AnimationValue.lerp(from: from, to: to, t: easedT)
    }

    /// Convertit en OSAXCommand pour envoi via bridge
    public func toCommand(value: AnimationValue) -> OSAXCommand {
        switch (property, value) {
        case (.alpha, .scalar(let a)):     return .setAlpha(wid: wid, alpha: a)
        case (.scale, .scalar(let s)):     return .setTransform(wid: wid, scale: s, tx: 0, ty: 0)
        case (.translateX, .scalar(let x)):return .setTransform(wid: wid, scale: 1, tx: x, ty: 0)
        case (.translateY, .scalar(let y)):return .setTransform(wid: wid, scale: 1, tx: 0, ty: y)
        case (.frame, .rect(let r)):       return .setFrame(wid: wid, rect: r)  // requiert ext osax
        default: fatalError("invalid property/value combination")
        }
    }
}
```

### `AnimationKey` (struct, pour coalescing)

```swift
public struct AnimationKey: Hashable, Sendable {
    public let wid: CGWindowID
    public let property: AnimatedProperty
}
```

### `AnimationQueue` (actor)

```swift
public actor AnimationQueue {
    private var active: [AnimationKey: Animation] = [:]
    private let maxConcurrent: Int
    private var paused: Bool = false

    public init(maxConcurrent: Int = 20) { self.maxConcurrent = maxConcurrent }

    public func enqueue(_ animation: Animation)
    public func enqueueBatch(_ animations: [Animation])
    public func cancel(wid: CGWindowID)
    public func cancelAll()
    public func tick(now: CFTimeInterval) async -> [OSAXCommand]
    public func pause()
    public func resume()
    public var count: Int { active.count }
}
```

### `EventContext` (struct, passé au router)

Capture l'état actuel de la fenêtre / desktop concerné pour permettre à l'`AnimationFactory` de calculer `from`/`to`.

```swift
public struct EventContext: Sendable {
    public let event: String
    public let timestamp: CFTimeInterval

    // Selon event, certains champs sont remplis
    public var wid: CGWindowID?
    public var currentFrame: CGRect?      // pour resize
    public var currentAlpha: Double?      // pour fade
    public var currentScale: Double?      // pour scale anim
    public var screenWidth: CGFloat?      // pour workspace_switch translate
    public var screenHeight: CGFloat?     // idem
    public var fromDesktopUUID: String?   // workspace_switch
    public var toDesktopUUID: String?
    public var fromStageID: String?       // stage_changed
    public var toStageID: String?
}
```

### `AnimationFactory` (struct ou static)

```swift
public struct AnimationFactory {
    public static func make(rule: EventRule,
                            context: EventContext,
                            curveLib: BezierLibrary) -> [Animation]
}
```

Logique : pour chaque `property` listée dans rule, calcule `from`/`to` selon event + context, retourne un `Animation`. Mode spéciaux (`pulse`, `crossfade`) génèrent plusieurs animations.

---

## Diagramme

```text
                    EventBus emit event (window_created, etc.)
                           │
                           ▼
                    EventRouter
                       │  consulte AnimationsConfig.events
                       │  filtre rules matchantes
                       ▼
                    pour chaque rule :
                       AnimationFactory.make(rule, context, curveLib)
                       └─► [Animation, Animation, ...]
                           │
                           ▼
                       AnimationQueue.enqueueBatch
                           │  coalesce par (wid, property)
                           │  drop oldest si > maxConcurrent
                           ▼
                       active: [AnimationKey: Animation]

                    (CVDisplayLink tick @ 60-120 FPS)
                           │
                           ▼
                       AnimationQueue.tick(now)
                       └─► pour chaque Animation :
                              progress = (now - start) / duration
                              if progress >= 1 → finie, send target, remove
                              else → curve.sample(progress) → value
                              return [OSAXCommand]
                           │
                           ▼
                       OSAXBridge.batchSend([cmd1, cmd2, ...])
                           │  1 socket write avec N JSON-lines
                           ▼
                       roadied.osax (Dock)
                       └─► dispatch main → CGS API call
```

---

## State transitions

### Animation lifecycle

```
[created]  AnimationFactory.make → return Animation
   │
   ▼
[enqueued] AnimationQueue.enqueue → active[key] = anim
   │       (coalescing : si key existe, ancien dropped)
   │
   ▼
[ticking]  pour chaque tick CVDisplayLink :
   │       value = anim.value(at: now)
   │       OSAXBridge.send(toCommand(value))
   │
   ├── value != nil → continue ticking
   │
   └── value == nil (progress >= 1) → finished
                                       │
                                       ▼
                                    [done] retire de active, send target final
```

### AnimationQueue states

```
[ready] (idle ou actif)
   │
   ├── pause() → [paused] (tick devient no-op)
   │              │
   │              └── resume() → [ready]
   │
   └── cancelAll() → [ready] avec active = []
```

---

## Interactions inter-modules

- **SPEC-006 RoadieOpacity** + `animate_dim=true` : OpacityModule appelle directement `AnimationsModule.shared.requestAnimation(...)` (pour dim transitions). Pas besoin de passer par EventBus.
- **SPEC-008 RoadieBorders** : appelle `AnimationsModule.requestPulse(wid, property: .scale)` au focus_changed (animation taille bordure).
- Dans les deux cas : `AnimationsModule` expose une API publique `requestAnimation(wid, property, from, to, curve, duration)` pour les modules pairs.

---

## Compatibilité

- Si SPEC-007 pas chargé : SPEC-006 et SPEC-008 ont leurs fallbacks (set instantané), aucune dépendance dure.
- Si SPEC-007 chargé sans config valide : log error au reload, animations désactivées (équivalent `enabled=false`).
- `enabled=false` : queue ignorée, OSAXBridge.send appelé directement avec target final immédiat (pour cohérence visuelle).
