# Data Model — SPEC-016 Yabai-parity tier-1

**Status**: Done
**Last updated**: 2026-05-02

## Vue d'ensemble

Cette spec ajoute 4 familles d'entités à `RoadieCore` :
1. **Rules** — `RuleDef`, `GridSpec`, `ManageMode`, `RuleEngine`, `RuleParser`.
2. **Signals** — `SignalDef`, `SignalDispatcher`, `SignalEnvironment`.
3. **Mouse follows** — extensions de `MouseConfig` + `MouseFollowFocusWatcher` + `MouseInputCoordinator`.
4. **Insert hints** — `InsertHint`, `InsertDirection`, `InsertHintRegistry`.

Toutes les structs config (TOML-mapped) sont `Codable` + `Sendable`. Les entités runtime (registries, dispatchers, watchers) sont `@MainActor`.

## 1. Rules (US2 / FR-A1-*)

### `RuleDef`

```swift
public struct RuleDef: Sendable {
    // Filtres de match (au moins l'un des deux requis)
    public let app: String?              // bundleID ou localizedName, exact ou regex
    public let title: String?            // regex, optionnel

    // Effets appliqués (au moins l'un requis)
    public let manage: ManageMode?       // .on / .off
    public let float: Bool?              // true → fenêtre floating (sortie BSP)
    public let sticky: Bool?             // true → visible sur tous les desktops
    public let space: Int?               // desktop virtuel cible (1..16)
    public let display: Int?             // display cible (1-based)
    public let grid: GridSpec?           // placement grille NxM

    // Comportement
    public let reapplyOnTitleChange: Bool  // default false (perf)

    // Compilation eager au parsing (cf. R-002)
    internal let _appRegex: NSRegularExpression?
    internal let _titleRegex: NSRegularExpression?

    // Diagnostics
    public let sourceIndex: Int          // index 0-based dans le TOML, pour log "rule #3"
}

public enum ManageMode: String, Codable, Sendable {
    case on, off
}

public struct GridSpec: Sendable, Equatable {
    public let rows: Int       // 1..32
    public let cols: Int       // 1..32
    public let row: Int        // 0..rows-1
    public let col: Int        // 0..cols-1
    public let width: Int      // 1..cols-col
    public let height: Int     // 1..rows-row

    /// Parse "R:C:r:c:w:h" → GridSpec, throws si invalide.
    public static func parse(_ s: String) throws -> GridSpec
}
```

**Format `Codable`** — implémentation manuelle avec `init(from:)` qui :
1. Lit les champs raw du TOML.
2. Compile `app`/`title` regex (si métacaractères présents — cf. R-002 sémantique).
3. Valide les contraintes (`space ∈ 1..16`, `display ≥ 1`, `grid` parsable).
4. Applique l'anti-pattern detection (R-003).
5. Stocke `sourceIndex` (passé via `decoder.userInfo[RuleDef.indexKey]`).

**Invariants** :
- `app != nil || title != nil` (au moins un filtre)
- `manage != nil || float != nil || sticky != nil || space != nil || display != nil || grid != nil` (au moins un effet)
- Si `_appRegex != nil` : la regex matche au moins une string non-vide ET ne matche PAS la string vide (R-003).

### `RuleEngine`

```swift
@MainActor
public final class RuleEngine {
    private var rules: [RuleDef]                  // ordre top-down du TOML
    private weak var registry: WindowRegistry?
    private weak var stageManager: StageManager?
    private weak var desktopRegistry: DesktopRegistry?
    private weak var displayManager: DisplayManager?
    private weak var layoutEngine: LayoutEngine?

    public init(rules: [RuleDef], 
                registry: WindowRegistry,
                stageManager: StageManager,
                desktopRegistry: DesktopRegistry,
                displayManager: DisplayManager,
                layoutEngine: LayoutEngine)

    /// Recharge les rules (appelé par `daemon reload`).
    public func reload(_ rules: [RuleDef])

    /// Évalue les rules pour une nouvelle fenêtre. Premier match wins.
    /// Retourne le RuleDef appliqué (pour log/diagnostic), nil si aucun match.
    /// Appelé par `WindowRegistry.add(window)` SYNCHRONE après l'insertion mais
    /// AVANT que DesktopRegistry.assign(...) ne fasse le routing initial (R-004 risque).
    @discardableResult
    public func applyForNewWindow(_ wid: CGWindowID) -> RuleDef?

    /// Re-évalue toutes les rules sur toutes les fenêtres (opt-in via `roadie rules apply --all`).
    public func applyAll()

    /// Re-évaluation conditionnelle au `window_title_changed` event,
    /// limitée aux rules avec `reapplyOnTitleChange = true`.
    public func handleTitleChange(_ wid: CGWindowID, newTitle: String)

    public var ruleCount: Int { rules.count }
    public func ruleSummaries() -> [(index: Int, app: String?, title: String?, effects: [String])]
}
```

**Cycle de vie** :
- Init : reçoit la liste des rules parsées + références weak vers les composants daemon.
- `applyForNewWindow` : appelé synchronement par `WindowRegistry.add()` via callback `onWindowAdded`.
- `reload` : remplace `rules` (lock-free via @MainActor isolation).

### `RuleParser`

```swift
public enum RuleParser {
    /// Parse la section `[[rules]]` du TOML root. Tolérant : skip les rules invalides + log warn.
    /// Retourne (rulesValides, errors).
    public static func parse(_ tomlRoot: TOMLTable) -> (rules: [RuleDef], errors: [RuleParseError])

    public struct RuleParseError {
        public let index: Int                     // 0-based dans le TOML
        public let reason: String                 // ex: "regex invalid: '['", "anti-pattern: matches all"
        public let raw: String                    // dump TOML de la rule pour log
    }
}
```

## 2. Signals (US3 / FR-A2-*)

### `SignalDef`

```swift
public struct SignalDef: Sendable {
    public let event: String              // validé contre supportedEvents (set fermé)
    public let action: String             // shell command brut, exec via /bin/sh -c

    // Filtres optionnels
    public let app: String?               // exact ou regex
    public let title: String?             // regex

    internal let _appRegex: NSRegularExpression?
    internal let _titleRegex: NSRegularExpression?

    public let sourceIndex: Int

    public static let supportedEvents: Set<String> = [
        "window_created", "window_destroyed", "window_focused",
        "window_moved", "window_resized", "window_title_changed",
        "application_launched", "application_terminated",
        "application_front_switched", "application_visible", "application_hidden",
        "space_changed", "space_created", "space_destroyed",
        "display_added", "display_removed", "display_changed",
        "mouse_dropped",
        "stage_switched", "stage_created", "stage_destroyed",
    ]
}
```

### `SignalDispatcher`

```swift
@MainActor
public final class SignalDispatcher {
    private var signals: [SignalDef]
    private var queue: Deque<DesktopEvent>          // cap 1000
    private let queueCap: Int
    private let timeoutMs: Int                       // default 5000
    private var workerTask: Task<Void, Never>?

    public init(signals: [SignalDef],
                queueCap: Int = 1000,
                timeoutMs: Int = 5000,
                eventBus: EventBus)

    public func reload(_ signals: [SignalDef])

    /// Démarre le worker async qui consomme la queue.
    /// Subscribe à eventBus.subscribe() en interne.
    public func start()

    public func stop()

    public var signalCount: Int { signals.count }
    public var queueDepth: Int { queue.count }      // pour observabilité
    public var totalDispatched: UInt64               // metric simple
    public var totalDropped: UInt64
    public var totalTimeouts: UInt64
}
```

**Architecture interne** :
1. À `start()` : task async qui `for await event in eventBus.subscribe()`.
2. Pour chaque event :
   - Si `event.payload["_inside_signal"] == "1"` → skip (re-entrancy guard, cf. R-006).
   - Sinon → enqueue. Si queue saturée → drop oldest + log warn + `totalDropped += 1`.
3. Worker consomme la queue : pour chaque event poppé, parcourt `signals`, match (event name + filters app/title), exec async (R-004).

### `SignalEnvironment`

```swift
public enum SignalEnvironment {
    /// Construit les env vars ROADIE_* selon le type d'event.
    public static func envVars(for event: DesktopEvent, registry: WindowRegistry) -> [String: String]
}
```

**Mapping event → env vars** (table de référence, à reproduire dans `cli-signals.md`) :

| Event | Env vars produites |
|---|---|
| `window_created`, `window_destroyed`, `window_focused`, `window_moved`, `window_resized`, `window_title_changed` | `ROADIE_WINDOW_ID`, `ROADIE_WINDOW_PID`, `ROADIE_WINDOW_BUNDLE`, `ROADIE_WINDOW_TITLE`, `ROADIE_WINDOW_FRAME` (`x,y,w,h`) |
| `application_launched`, `application_terminated`, `application_front_switched`, `application_visible`, `application_hidden` | `ROADIE_APP_BUNDLE`, `ROADIE_APP_PID`, `ROADIE_APP_NAME` |
| `space_changed`, `space_created`, `space_destroyed` | `ROADIE_SPACE_FROM`, `ROADIE_SPACE_TO`, `ROADIE_SPACE_LABEL?` |
| `display_added`, `display_removed`, `display_changed` | `ROADIE_DISPLAY_ID`, `ROADIE_DISPLAY_UUID`, `ROADIE_DISPLAY_NAME?`, `ROADIE_DISPLAY_FRAME` |
| `mouse_dropped` | `ROADIE_DROP_X`, `ROADIE_DROP_Y`, `ROADIE_DROP_DISPLAY`, `ROADIE_DROP_FRAME` |
| `stage_switched`, `stage_created`, `stage_destroyed` | `ROADIE_STAGE_ID`, `ROADIE_STAGE_NAME?`, `ROADIE_STAGE_FROM?`, `ROADIE_STAGE_TO?` |

Toutes les env vars qui ne s'appliquent pas restent absentes (pas `""`). Une env var référencée dans une action shell mais absente s'expandera en `""` (comportement `/bin/sh` standard).

**Re-entrancy var commune** : `ROADIE_INSIDE_SIGNAL=1` toujours présente (cf. R-006).

## 3. Mouse follows (US1b/c / FR-A6-*)

### Extension de `MouseConfig` (Config.swift existant)

```swift
public struct MouseConfig: Codable, Sendable, Equatable {
    // Existants SPEC-015
    public var modifier: ModifierKey
    public var actionLeft: MouseAction
    public var actionRight: MouseAction
    public var actionMiddle: MouseAction
    public var edgeThreshold: Int

    // Nouveaux SPEC-016
    public var focusFollowsMouse: FocusFollowMode      // default .off
    public var mouseFollowsFocus: Bool                  // default false
    public var idleThresholdMs: Int                    // default 200
}

public enum FocusFollowMode: String, Codable, Sendable, Equatable {
    case off
    case autofocus     // focus migre, pas de raise
    case autoraise     // focus + raise
}
```

**CodingKeys ajoutées** :
```swift
case focusFollowsMouse = "focus_follows_mouse"
case mouseFollowsFocus = "mouse_follows_focus"
case idleThresholdMs = "idle_threshold_ms"
```

**Décodage tolérant** : valeur invalide pour `focus_follows_mouse` → `.off` + log warn (cohérent SPEC-015 pattern).

### `MouseFollowFocusWatcher`

```swift
@MainActor
public final class MouseFollowFocusWatcher {
    public weak var registry: WindowRegistry?
    public weak var focusManager: FocusManager?
    public weak var coordinator: MouseInputCoordinator?
    public var config: MouseConfig

    private var timer: Timer?
    private var state: MouseFollowState

    public init(config: MouseConfig)

    public func start()
    public func stop()
    public func reload(_ config: MouseConfig)

    /// Tick interne (toutes les 50 ms).
    private func tick()
}

internal struct MouseFollowState {
    var lastCursorPos: NSPoint = .zero
    var lastMoveAt: Date = .distantPast
    var currentHoverWindow: CGWindowID?
}
```

**Algorithme `tick()`** :
1. Si `config.focusFollowsMouse == .off` → return early.
2. Si `coordinator?.dragActive == true` → return early.
3. `pos = NSEvent.mouseLocation`. Si `pos == state.lastCursorPos` (immobile) :
   - Si `Date().timeIntervalSince(state.lastMoveAt) >= config.idleThresholdMs / 1000` :
     - Trouver `WindowState` qui contient `pos` dans son `frame`.
     - Skip Dock/Menu Bar/desktop empty area (heuristique : aucune `WindowState` matchante = skip).
     - Si fenêtre trouvée ET wid != `state.currentHoverWindow` :
       - `state.currentHoverWindow = wid`
       - `focusManager.setFocus(to: wid, source: .mouseFollow)`
       - Si `config.focusFollowsMouse == .autoraise` → `windowActivator.raise(wid)`.
4. Sinon (curseur a bougé) : `state.lastCursorPos = pos; state.lastMoveAt = Date()`.

### `MouseInputCoordinator`

```swift
@MainActor
public final class MouseInputCoordinator {
    public private(set) var dragActive: Bool = false

    public weak var dragHandler: MouseDragHandler?
    public weak var followWatcher: MouseFollowFocusWatcher?

    public init()

    /// Appelé par MouseDragHandler quand un drag commence.
    public func notifyDragStarted()

    /// Appelé par MouseDragHandler au mouseUp.
    public func notifyDragEnded()
}
```

**Patron de coordination** : pas de hook event-by-event partagé. Le coordinator expose `dragActive` que les autres composants consultent (poll). MouseDragHandler appelle `notifyDragStarted/Ended` aux moments clés. Léger, lockless, pas de contention.

### Extension `FocusManager`

```swift
public extension FocusManager {
    enum FocusSource {
        case keyboard       // commande CLI / IPC
        case mouseClick     // user click via MouseRaiser
        case mouseFollow    // focus_follows_mouse autofocus/autoraise
        case rule           // RuleEngine apply
        case external       // app a appelé NSApp.activate ou similaire
    }

    /// Surcharge de setFocus pour propager la source.
    /// Si mouseFollowsFocus == true ET source == .keyboard, téléporte le curseur (FR-A6-05/06).
    func setFocus(to wid: CGWindowID, source: FocusSource)
}
```

**Mécanisme téléportation** :
- À chaque `setFocus(.., source:)`, si `MouseConfig.mouseFollowsFocus && source == .keyboard` :
  - Lire `windowState.frame` de la nouvelle fenêtre focused.
  - `centerPoint = NSPoint(x: frame.midX, y: frame.midY)`.
  - `CGWarpMouseCursorPosition(CGPoint(x: centerPoint.x, y: convertedY))` (note : conversion Y axis NS↔CG via `NSScreen.frame.height - y`).

## 4. Insert hints (US4 / FR-A4-*)

### `InsertDirection`

```swift
public enum InsertDirection: String, Codable, Sendable, Equatable {
    case north, south, east, west
    case stack                          // fallback split par défaut tant que SPEC-017 pas livrée
}
```

### `InsertHint`

```swift
public struct InsertHint: Sendable, Equatable {
    public let targetWid: CGWindowID
    public let direction: InsertDirection
    public let createdAt: Date
    public let expiresAt: Date         // = createdAt + ttl

    public var isExpired: Bool { Date() > expiresAt }
}
```

### `InsertHintRegistry`

```swift
@MainActor
public final class InsertHintRegistry {
    public let ttlMs: Int                // default 120000
    private var hints: [CGWindowID: InsertHint] = [:]
    private var gcTimer: Timer?

    public init(ttlMs: Int = 120000)

    /// Pose un hint pour une fenêtre cible. Remplace s'il existait déjà pour ce wid.
    public func set(targetWid: CGWindowID, direction: InsertDirection)

    /// Consume le hint pour `parentWid`. Retourne nil si absent ou expiré.
    /// Le hint est retiré de la map après consume (1-shot).
    public func consume(parentWid: CGWindowID) -> InsertHint?

    /// Cleanup : retire le hint si la fenêtre cible disparaît.
    public func handleWindowDestroyed(_ wid: CGWindowID)

    /// Flush tous les hints (appelé sur tiler.set strategy change).
    public func flushAll(reason: String)

    public var activeHintCount: Int { hints.count }
    public var allHints: [InsertHint] { Array(hints.values) }
}
```

**Cycle de vie** :
- À `start()` : `gcTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true)` purge les hints expirés.
- À `consume(parentWid:)` : O(1) lookup.
- À `handleWindowDestroyed(_:)` : appelé via subscription EventBus (`window_destroyed`).
- À `flushAll(reason:)` : log info + clear map.

**Coordination avec `LayoutEngine`** :
- `LayoutEngine.insert(_ wid:)` consulte d'abord `hintRegistry.consume(parentWid:)`.
- Si hint trouvé ET tree de `wid` == tree de `targetWid` → applique direction.
- Sinon → algo split-largest existant.

## 5. Schéma config TOML complet

```toml
# Section existante SPEC-015 ÉTENDUE
[mouse]
modifier = "ctrl"
action_left = "move"
action_right = "resize"
action_middle = "none"
edge_threshold = 30

# Nouveaux SPEC-016
focus_follows_mouse = "off"            # off | autofocus | autoraise
mouse_follows_focus = false
idle_threshold_ms = 200

# Nouvelles sections SPEC-016

[[rules]]
app = "1Password"
title = "1Password mini"
manage = "off"

[[rules]]
app = "Slack"
space = 5

[[signals]]
event = "window_focused"
action = "echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log"

[insert]
hint_timeout_ms = 120000
show_hint = false                      # overlay visuel sur le bord cible (V1.1, optionnel)

[signals]                              # section globale (≠ array [[signals]])
timeout_ms = 5000
queue_cap = 1000
```

**Defaults appliqués si section/clé absente** :
| Section | Clé | Default |
|---|---|---|
| `[mouse]` | `focus_follows_mouse` | `"off"` |
| `[mouse]` | `mouse_follows_focus` | `false` |
| `[mouse]` | `idle_threshold_ms` | `200` |
| `[insert]` | `hint_timeout_ms` | `120000` |
| `[insert]` | `show_hint` | `false` |
| `[signals]` (global) | `timeout_ms` | `5000` |
| `[signals]` (global) | `queue_cap` | `1000` |
| `[[rules]]` | (absente) | `[]` (aucune rule) |
| `[[signals]]` | (absente) | `[]` (aucun signal) |

## 6. Persistance

**Aucune persistance** propre à SPEC-016. Tout vit en mémoire (`RuleEngine.rules`, `SignalDispatcher.signals`, `InsertHintRegistry.hints`). Reload depuis TOML à chaque `daemon reload`.

Cohérent constitution principe E (TOML plat = source de vérité unique).

## 7. Observabilité

Métriques exposées via `roadie daemon status` :

```json
{
  "rules": {
    "loaded": 12,
    "rejected_at_parse": 1,
    "applied_total": 247
  },
  "signals": {
    "loaded": 5,
    "rejected_at_parse": 0,
    "queue_depth": 0,
    "dispatched_total": 1893,
    "dropped_total": 0,
    "timeouts_total": 2
  },
  "insert_hints": {
    "active": 0,
    "consumed_total": 47,
    "expired_total": 12
  }
}
```

## 8. Edge cases & invariants (récap)

| Edge case | Comportement |
|---|---|
| Rule `app=".*"` | REJECT au parsing + log error (R-003) |
| Rule regex cassé `app="["` | Skip cette rule + log warn, autres rules continuent (R-002) |
| Signal queue saturée (1000+) | Drop oldest FIFO + log warn + `totalDropped++` (R-005) |
| Signal action timeout | SIGTERM → +1s SIGKILL → log warn + `totalTimeouts++` (R-004) |
| Cascade re-entrancy (action shell crée fenêtre) | Bloquée par `_inside_signal` flag (R-006) |
| `focus_follows_mouse` pendant drag SPEC-015 | Suspendu via `coordinator.dragActive == true` (R-007) |
| `focus_follows_mouse` survol Dock/MenuBar | No-op (registry.windowAt(point) retourne nil) |
| `mouse_follows_focus` après focus via clic | Skip téléportation (`source == .mouseClick`) |
| `--insert` puis fenêtre apparaît sur autre display | Hint NON consommé (tree différent), reste actif (R-008) |
| `--insert` puis fenêtre cible fermée avant ouverture | Hint orphelin retiré sur `window_destroyed` (R-008) |
| `--insert stack` quand SPEC-017 pas livrée | Fallback split par défaut + log info (FR-A4-04) |
| Daemon reload pendant action shell en cours | Action en cours termine, prochain trigger utilise nouvelle config |
| `space=N` rule + `display=M` rule simultanément | Les deux s'appliquent (séquence : space d'abord, display ensuite via desktop-per-display SPEC-013) |
| Rule modifie `manage=off` puis CLI `tiling.reserve <wid> false` | CLI gagne pour la session courante, rule s'applique à la prochaine ouverture |
