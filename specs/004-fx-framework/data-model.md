# Data Model — Framework SIP-off opt-in (SPEC-004)

**Date** : 2026-05-01

## Entités

### `FXModuleVTable` (struct C ABI, exporté par chaque dylib)

Pointeur retourné par `module_init` que chaque dylib expose via `@_cdecl`.

```c
typedef struct FXModuleVTable {
    const char* name;                          // identifiant module ("shadowless")
    const char* version;                       // semver string ("0.1.0")
    void (*subscribe)(void* event_bus_ptr);   // appelé une fois par le loader avec un EventBus opaque
    void (*shutdown)(void);                    // cleanup avant unload (SIGTERM ou daemon quit)
} FXModuleVTable;
```

**Validation** :
- `name` : ASCII, ≤ 32 chars, non vide, unique parmi les modules chargés (sinon doublon → premier gagne, warning)
- `version` : format semver `<major>.<minor>.<patch>`
- Pointeurs de fonction non nuls

---

### `FXModule` (Swift wrapper)

Wrapper Swift autour de la vtable C, manipulé par le `FXRegistry`.

```swift
public final class FXModule: Sendable {
    public let name: String
    public let version: String
    public let path: URL                       // chemin du .dylib
    public let loadedAt: Date

    private let vtable: FXModuleVTable
    private let dylibHandle: UnsafeMutableRawPointer

    public func subscribe(to bus: EventBus)    // wrap vtable.subscribe
    public func shutdown()                     // wrap vtable.shutdown + dlclose
}
```

---

### `FXRegistry` (Swift, daemon-side)

Maintient la liste des modules chargés. Singleton `@MainActor` dans le daemon.

```swift
@MainActor
public final class FXRegistry {
    private var modules: [String: FXModule] = [:]   // keyed par name

    public func register(_ module: FXModule)
    public func unregister(_ name: String)          // appelle shutdown() puis dlclose
    public func module(named: String) -> FXModule?
    public var allModules: [FXModule] { Array(modules.values) }
}
```

---

### `OSAXCommand` (Swift enum, sérialisé en JSON)

Les 8 commandes minimums exposées par `roadied.osax`.

```swift
public enum OSAXCommand: Codable {
    case noop                                              // heartbeat
    case setAlpha(wid: CGWindowID, alpha: Double)          // 0.0 .. 1.0
    case setShadow(wid: CGWindowID, density: Double)       // 0.0 .. 1.0
    case setBlur(wid: CGWindowID, radius: Int)             // 0 .. 100
    case setTransform(wid: CGWindowID, scale: Double, tx: Double, ty: Double)
    case setLevel(wid: CGWindowID, level: Int)             // CGSWindowLevel (NSWindowLevel int)
    case moveWindowToSpace(wid: CGWindowID, spaceUUID: String)
    case setSticky(wid: CGWindowID, sticky: Bool)
}
```

**Sérialisation JSON** (forme wire) :
```jsonc
{"cmd": "set_alpha", "wid": 12345, "alpha": 0.7}
{"cmd": "noop"}
{"cmd": "set_transform", "wid": 12345, "scale": 0.95, "tx": 10, "ty": 0}
```

**Validation** :
- `wid` : `CGWindowID` (UInt32), > 0
- `alpha` / `density` : Double dans [0, 1]
- `radius` : Int dans [0, 100]
- `scale` : Double dans [0, 5] (au-delà = visuel délirant, on refuse)
- `level` : Int dans [-2000, 2000]
- `spaceUUID` : format UUID (validation regex)

---

### `OSAXResult`

```swift
public enum OSAXResult: Codable {
    case ok
    case error(code: String, message: String?)
}
```

Codes d'erreur stables : `wid_not_found`, `unknown_command`, `invalid_parameter`, `cgs_failure`, `permission_denied`, `bridge_disconnected`.

---

### `BezierCurve` (struct, dans `RoadieFXCore`)

Courbe Bézier 4 points avec lookup table 256 samples.

```swift
public struct BezierCurve: Sendable {
    public let p1x: Double; public let p1y: Double
    public let p2x: Double; public let p2y: Double
    private let lookup: [Double]   // 256 samples y précalculés

    public init(p1x: Double, p1y: Double, p2x: Double, p2y: Double)
    public func sample(_ t: Double) -> Double      // O(1) avec interpolation linéaire
}
```

**Validation init** :
- `p1x`, `p2x` ∈ [0, 1] (CSS standard)
- `p1y`, `p2y` libres (peuvent dépasser pour overshoot type easeOutBack)

**Précision garantie** : ≥ 0.005 sur tout t ∈ [0, 1].

---

### `Animation` (struct, dans `RoadieFXCore`)

Une animation en cours. Manipulée par `AnimationLoop` et `AnimationQueue`.

```swift
public struct Animation: Sendable {
    public let id: UUID
    public let wid: CGWindowID
    public let property: AnimatedProperty   // .alpha, .scale, .translate, .frame
    public let from: AnimationValue
    public let to: AnimationValue
    public let curve: BezierCurve
    public let startTime: CFTimeInterval
    public let duration: CFTimeInterval

    public func value(at now: CFTimeInterval) -> AnimationValue?  // nil si finie
}

public enum AnimatedProperty: String, Sendable {
    case alpha, scale, translateX, translateY, frame
}

public enum AnimationValue: Sendable {
    case scalar(Double)
    case rect(CGRect)
}
```

---

### `AnimationLoop` (actor, dans `RoadieFXCore`)

Wrapper `CVDisplayLink`. Tick à 60-120 FPS selon display.

```swift
public actor AnimationLoop {
    private var displayLink: CVDisplayLink?
    private var animations: [UUID: Animation] = [:]
    private var onTick: ((CFTimeInterval) -> Void)?

    public func start()
    public func stop()
    public func register(_ animation: Animation)
    public func unregister(_ id: UUID)
    public func setOnTick(_ callback: @escaping (CFTimeInterval) -> Void)
}
```

---

### `OSAXBridge` (actor, dans `RoadieFXCore`)

Client socket Unix vers `roadied.osax`. Queue async + retry + UID match.

```swift
public actor OSAXBridge {
    private let socketPath: String              // /var/tmp/roadied-osax.sock
    private var connection: SocketConnection?   // nil si déco
    private var queue: [(OSAXCommand, CheckedContinuation<OSAXResult, Never>)] = []

    public init(socketPath: String = "/var/tmp/roadied-osax.sock")
    public func connect() async                 // non bloquant, log warning si échoue
    public func send(_ cmd: OSAXCommand) async -> OSAXResult
    public func disconnect()
    public var isConnected: Bool { connection != nil }
}
```

**État queue** : capped à 1000 entries. Au-delà : nouvelle commande remplace la plus ancienne (FIFO drop), log warning. Reconnect retry toutes les 2 s.

---

### `FXConfig` (Swift, dans `RoadieFXCore`)

Section `[fx]` du `roadies.toml`, parsée au boot.

```swift
public struct FXConfig: Codable, Sendable {
    public var dylibDir: String                 // défaut "~/.local/lib/roadie/"
    public var osaxSocketPath: String           // défaut "/var/tmp/roadied-osax.sock"
    public var checksumFile: String?            // défaut nil

    enum CodingKeys: String, CodingKey {
        case dylibDir = "dylib_dir"
        case osaxSocketPath = "osax_socket_path"
        case checksumFile = "checksum_file"
    }
}
```

---

## Diagramme relations

```text
                       roadied (daemon, user-space, SIP-on safe)
                       ┌──────────────────────────────────────┐
                       │                                       │
                       │  FXLoader (boot)                      │
                       │  ├── csrutil status (info only)      │
                       │  ├── glob $dylibDir/*.dylib           │
                       │  └── dlopen + dlsym module_init       │
                       │       │                               │
                       │       ▼                               │
                       │  FXModuleVTable (C ABI)               │
                       │       │                               │
                       │       ▼                               │
                       │  FXRegistry  ────► FXModule(s)        │
                       │                       │                │
                       │                       │ subscribe       │
                       │                       ▼                │
                       │                   EventBus             │
                       │                       │ events          │
                       │                       ▼                │
                       │              chaque .dylib chargé      │
                       │              ├── RoadieFXCore.dylib    │
                       │              │   ├── BezierCurve       │
                       │              │   ├── AnimationLoop     │
                       │              │   ├── OSAXBridge ───────┼──┐
                       │              │   └── FXConfig          │  │
                       │              │                          │  │
                       │              ├── RoadieShadowless.dylib │  │ socket /var/tmp/roadied-osax.sock
                       │              ├── ...                   │  │ JSON-lines
                       │              └── (autres modules)      │  │
                       │                                          │  │
                       └──────────────────────────────────────────┼──┘
                                                                  │
                                                                  ▼
                                          Dock process (SIP partial off requis)
                                          ┌──────────────────────────────────┐
                                          │                                   │
                                          │  roadied.osax (.mm bundle)        │
                                          │  ├── socket Unix server          │
                                          │  ├── UID match check             │
                                          │  ├── parse JSON-lines            │
                                          │  ├── dispatch main thread Dock   │
                                          │  └── 8 handlers CGS              │
                                          │      ├── set_alpha               │
                                          │      ├── set_shadow              │
                                          │      ├── set_blur                │
                                          │      ├── set_transform           │
                                          │      ├── set_level               │
                                          │      ├── move_window_to_space    │
                                          │      ├── set_sticky              │
                                          │      └── noop                    │
                                          │                                   │
                                          └──────────────────────────────────┘
```

---

## State Transitions

### `FXModule` lifecycle

```text
[init]  dlopen + dlsym OK → register dans FXRegistry
   │
   ▼
[ready] subscribe(bus) appelé → module reçoit les events
   │
   ▼ (SIGTERM ou daemon quit)
[stopping] shutdown() appelé → cleanup observers
   │
   ▼
[unloaded] dlclose() → handle libéré
```

### `OSAXBridge` connection state

```text
[disconnected] (initial) → connect() async → essaie socket
   │
   ├── succès ─→ [connected] → send/receive
   │                │
   │                ▼ (lecture renvoie EOF / EPIPE)
   │             [disconnected] → retry 2s
   │
   └── échec (ENOENT, etc.) ─→ [disconnected] → retry 2s, log warning
```

### `OSAXCommand` queue

```text
send(cmd) async
   │
   ├── connected → write socket + await ack → return OSAXResult
   │
   └── disconnected → enqueue (drop oldest if > 1000) → wait reconnect → flush queue
```

---

## Compatibilité avec V1 / V2

- **Aucune entité V1 modifiée**
- Le `EventBus` introduit en SPEC-003 est étendu avec un `subscribe(observer:)` public pour permettre aux modules de s'abonner. Les observers existants (interne au daemon) restent inchangés
- Aucun champ ajouté à `WindowState` ou `Stage` ou `DesktopState`
- Le binaire daemon reste sans symbole CGS d'écriture (vérifié par SC-007)
