# Data Model — SPEC-014 Stage Rail UI

**Status**: Draft
**Last updated**: 2026-05-02

## Vue d'ensemble

Le rail manipule trois familles d'entités :
1. **State holders** SwiftUI (`@Observable`) côté rail : reflètent l'état IPC fetched du daemon.
2. **Messages IPC** (envelopes JSON-lines) côté socket : sérialisation requêtes/réponses.
3. **Models côté daemon** : ThumbnailEntry (cache LRU), WallpaperClickEvent, extension de `WindowState` pour exposer la dernière vignette connue.

Tous les types sont `Sendable` et `Codable` quand transmis cross-process.

## Entités côté rail (process `roadie-rail`)

### `RailState`

State holder global du rail. Une instance pour tous les panels.

```swift
@Observable
final class RailState {
    /// Desktop courant (id 1..N). Mis à jour sur event `desktop_changed`.
    var currentDesktopID: Int = 1

    /// Liste ordonnée des stages du desktop courant.
    var stages: [StageVM] = []

    /// ID de la stage active (= isActive == true).
    var activeStageID: String = "1"

    /// Map wid → vignette PNG la plus récente.
    var thumbnails: [CGWindowID: ThumbnailVM] = [:]

    /// État de la connexion daemon.
    var connectionState: ConnectionState = .disconnected

    /// Mode display (per_display / global).
    var displayMode: DisplayMode = .perDisplay

    /// Liste des écrans connus (mis à jour sur `didChangeScreenParametersNotification`).
    var screens: [ScreenInfo] = []
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting(attempt: Int)
    case connected
    case offline(reason: String)
}

enum DisplayMode: String, Codable {
    case perDisplay = "per_display"
    case global
}

struct ScreenInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
    let displayUUID: String
}
```

**Invariants** :
- `stages.count >= 1` quand `connectionState == .connected` (le daemon garantit toujours au moins 1 stage).
- `stages.first(where: { $0.id == activeStageID })` n'est jamais `nil` quand connecté.

### `StageVM`

View model d'une stage rendue dans une carte.

```swift
struct StageVM: Identifiable, Equatable {
    let id: String                // ex: "1", "2", "comm"
    let displayName: String       // ex: "Work"
    let isActive: Bool
    let windowIDs: [CGWindowID]   // ordre = z-order MRU dans la stage
    let desktopID: Int
}
```

### `WindowVM`

View model d'une fenêtre (chip).

```swift
struct WindowVM: Identifiable, Equatable {
    let id: CGWindowID
    let bundleID: String
    let title: String
    let appName: String           // localisé, pour fallback texte
    let isFloating: Bool
}
```

### `ThumbnailVM`

Conteneur de vignette PNG.

```swift
struct ThumbnailVM: Equatable {
    let wid: CGWindowID
    let pngData: Data             // ~30 KB max
    let size: CGSize              // résolution réelle (max 320×200)
    let degraded: Bool            // true si fallback icône d'app
    let capturedAt: Date
}
```

**Cycle de vie** :
- TTL implicite 10 s : si `Date().timeIntervalSince(capturedAt) > 10`, le rail rerequête au daemon avant affichage.
- Eviction quand `windowIDs` ne référence plus la fenêtre (cleanup observable).

## Entités côté daemon (extensions de `roadied`)

### `ThumbnailCache`

Cache LRU des vignettes côté daemon.

```swift
final class ThumbnailCache {
    private var entries: [CGWindowID: ThumbnailEntry]
    private var accessOrder: [CGWindowID]  // MRU front
    let capacity: Int = 50

    func get(wid: CGWindowID) -> ThumbnailEntry?
    func put(_ entry: ThumbnailEntry)
    func evictWid(_ wid: CGWindowID)
    func clear()
}

struct ThumbnailEntry: Sendable {
    let wid: CGWindowID
    let pngData: Data
    let size: CGSize
    let degraded: Bool
    let capturedAt: Date
}
```

**Invariants** :
- `entries.count <= capacity`
- `accessOrder.count == entries.count`
- Eviction LRU quand `entries.count == capacity` et insertion d'un nouveau wid.

### `SCKCaptureService`

Wrapper ScreenCaptureKit pour capture périodique.

```swift
@MainActor
final class SCKCaptureService {
    /// Mappage wid → SCStream actif. Un stream par fenêtre observée.
    private var streams: [CGWindowID: SCStream] = [:]

    /// Démarre la capture périodique (0.5 Hz) d'une fenêtre.
    /// Idempotent : si un stream existe déjà, no-op.
    func observe(wid: CGWindowID) async throws

    /// Stoppe l'observation d'une fenêtre.
    func unobserve(wid: CGWindowID) async

    /// État de la permission Screen Recording.
    var screenRecordingGranted: Bool { get async }
}
```

**Lifecycle** : démarre observation quand le daemon reçoit une première requête `roadie window thumbnail <wid>`. Arrête observation après 30 s sans requête (économise CPU/batterie).

### `WallpaperClickWatcher`

Observer kAX qui détecte les clicks sur le bureau.

```swift
@MainActor
final class WallpaperClickWatcher {
    weak var registry: WindowRegistry?
    var onWallpaperClick: ((NSPoint) -> Void)?

    func start()
    func stop()

    private func isClickOnWallpaper(at point: NSPoint) -> Bool {
        // Test 1 : aucune fenêtre tracked dans le registry n'inclut point
        // Test 2 : kAXTopLevelUIElement à point retourne nil ou Finder desktop
    }
}
```

### Extension `WindowState` (RoadieCore)

Pas de modification structurelle. Le cache des thumbnails est externe (`ThumbnailCache`).

## Messages IPC

### Envelope commune

Tous les messages requêtes/réponses suivent le format JSON-lines existant SPEC-002 (1 ligne = 1 message). Une commande génère exactement 1 réponse (sauf `events --follow` qui est un flux).

### Nouvelle commande : `window thumbnail <wid>`

**Requête** :
```json
{"cmd": "window.thumbnail", "wid": 12345}
```

**Réponse OK** :
```json
{
  "status": "ok",
  "data": {
    "png_base64": "iVBORw0KGgoAAAANSUhEUgAA...",
    "wid": 12345,
    "size": [320, 200],
    "degraded": false,
    "captured_at": "2026-05-02T17:30:42.123Z"
  }
}
```

**Réponse fallback (Screen Recording non accordée)** :
```json
{
  "status": "ok",
  "data": {
    "png_base64": "<icone app PNG base64>",
    "wid": 12345,
    "size": [128, 128],
    "degraded": true,
    "captured_at": "2026-05-02T17:30:42.123Z"
  }
}
```

**Erreur (wid inconnue)** :
```json
{"status": "error", "code": "wid_not_found", "message": "window 12345 not in registry"}
```

### Nouvelle commande : `tiling reserve`

Permet au rail de demander au tiler de réserver une zone d'edge (US6).

**Requête** :
```json
{"cmd": "tiling.reserve", "edge": "left", "size": 408, "display_id": 1234}
```

**Réponse** :
```json
{"status": "ok"}
```

`size = 0` annule la réservation pour cet edge/display.

### Nouvelle commande : `rail status`

CLI helper pour debug ou scripts shell.

**Requête** :
```json
{"cmd": "rail.status"}
```

**Réponse** :
```json
{
  "status": "ok",
  "data": {
    "running": true,
    "pid": 12345,
    "since": "2026-05-02T16:00:00Z",
    "panels_open": 2,
    "screens_visible": ["DUUID-1", "DUUID-2"]
  }
}
```

### Extension : événements push (`events --follow`)

Nouveaux types d'événements émis par le daemon :

#### `wallpaper_click`
```json
{
  "event": "wallpaper_click",
  "ts": "2026-05-02T17:31:05.456Z",
  "version": 1,
  "x": 800,
  "y": 600,
  "display_id": 1234
}
```

#### `stage_renamed`
```json
{
  "event": "stage_renamed",
  "ts": "2026-05-02T17:31:10.000Z",
  "version": 1,
  "stage_id": "1",
  "old_name": "Work",
  "new_name": "Coding"
}
```

#### `thumbnail_updated`
```json
{
  "event": "thumbnail_updated",
  "ts": "2026-05-02T17:31:12.500Z",
  "version": 1,
  "wid": 12345
}
```

(le rail peut alors fetch la nouvelle vignette via `window.thumbnail`)

## Schéma config TOML

Section `[fx.rail]` à ajouter à `~/.config/roadies/roadies.toml` :

```toml
[fx.rail]
enabled = true                        # active la détection daemon-side du wallpaper-click
reclaim_horizontal_space = false      # le tiler retiles quand le rail apparaît
wallpaper_click_to_stage = true       # active le geste click-bureau → stage
panel_width = 408                     # px
edge_width = 8                        # px
fade_duration_ms = 200
hide_debounce_ms = 100
mouse_poll_interval_ms = 80
thumbnail_refresh_hz = 0.5            # Hz
```

Defaults au cas où la section est absente : tous les bools `false` sauf `wallpaper_click_to_stage = true`. Le rail démarre quand même (les actions UI fonctionnent), seuls les flags daemon-side sont au défaut.

## Persistance

Aucune donnée propre au rail n'est persistée. Tout vit en mémoire. Le state est rebuild au démarrage depuis le daemon.

Exception : le **PID-lock** `~/.roadies/rail.pid` (cf R-006) — fichier texte 1 ligne contenant le PID.

## Observabilité

- Log côté rail : `~/.local/state/roadies/rail.log` (JSON-lines structurés via stderr redirigé).
- Metrics exposables (futur) : nombre de fades par minute, latence moyenne fetch thumbnail, latence event → render. Out of scope V1.

## Edge cases & invariants

| Edge case | Comportement |
|---|---|
| Daemon down au démarrage du rail | Connection state `.offline`, panel affiche "daemon offline", actions désactivées |
| Daemon redémarre pendant rail visible | Reconnexion exponentielle, state rebuild après reconnect, événements ratés rejoués (best effort) |
| `stages.count == 0` | Impossible par invariant SPEC-002, mais le rail affiche "No stages on this desktop" si ça arrive |
| `currentDesktopID` change rapidement | Debounce 50 ms : ignore les changements suivis dans cet intervalle |
| `thumbnails[wid]` absent | Display de l'icône d'app en attendant fetch async |
| Drag chip vers la même stage | No-op (pas de requête daemon inutile) |
| Wallpaper-click sur un desktop sans fenêtre tilée | No-op silencieux (pas de stage vide créée) |
| Multi-display : écran débranché pendant drag | Drag annulé, fenêtre laissée à sa stage source |
