# Contract — EventBus interne (in-process)

**Statut** : nouveau contrat introduit par SPEC-024.
**Scope** : interne au process `roadied`. Non exposé aux clients externes.

## Objectif

Permettre au module `RoadieRail` (UI panel) de consommer les events tiling/stages/desktops/windows/displays sans passer par le serveur IPC public Unix-socket. Élimine la sérialisation JSON, la latence socket, les helpers tolérants côté rail.

## Implémentation choisie

Étendre **`DesktopEventBus`** (existant dans `Sources/RoadieDesktops/EventBus.swift`) pour porter l'ensemble des events publiés par le daemon. Le bus reste un `actor` Swift avec subscribers `AsyncStream`.

## Schéma

### Type d'event unifié

```swift
public enum RoadieEvent: Sendable {
    case stageChanged(from: StageID?, to: StageID, desktopID: Int, displayUUID: String)
    case desktopChanged(from: Int, to: Int, fromLabel: String, toLabel: String)
    case windowCreated(wid: CGWindowID, pid: pid_t, bundle: String, title: String)
    case windowDestroyed(wid: CGWindowID, pid: pid_t)
    case windowFocused(wid: CGWindowID, prev: CGWindowID?)
    case windowAssigned(wid: CGWindowID, stageID: StageID, displayUUID: String)
    case windowUnassigned(wid: CGWindowID, stageID: StageID, displayUUID: String)
    case stageCreated(stageID: StageID, displayUUID: String)
    case stageDeleted(stageID: StageID, displayUUID: String)
    case stageRenamed(stageID: StageID, newName: String)
    case displayConfigurationChanged(displays: [DisplayInfo])
    case thumbnailUpdated(wid: CGWindowID)
    case configReloaded
}
```

### Bus

```swift
public actor RoadieEventBus {
    private var continuations: [UUID: AsyncStream<RoadieEvent>.Continuation] = [:]

    public func publish(_ event: RoadieEvent) { /* yield à tous les subscribers */ }
    public func subscribe() -> AsyncStream<RoadieEvent> { /* nouvelle continuation */ }
    public var subscriberCount: Int { continuations.count }
}
```

Note : si la généralisation depuis `DesktopEventBus` s'avère plus coûteuse en LOC qu'un wrapper, on peut garder les deux bus en parallèle (`DesktopEventBus` pour `desktop_changed`/`stage_changed` + nouveau bus pour les autres) — décision laissée à l'implémentation, l'objectif minimaliste prévaut.

## Producteurs (publishers)

Le `Daemon` (et ses sous-composants) publient sur le bus :

- `StageManager` → `.stageChanged`, `.stageCreated`, `.stageDeleted`, `.stageRenamed`, `.windowAssigned`, `.windowUnassigned`
- `DesktopRegistry` (existant) → `.desktopChanged`
- `GlobalObserver` (RoadieCore) → `.windowCreated`, `.windowDestroyed`, `.windowFocused`
- `ScreenObserver` → `.displayConfigurationChanged`
- `ThumbnailCache` → `.thumbnailUpdated`
- `ConfigReloader` → `.configReloaded`

Chacun de ces composants publie déjà ces events, mais aujourd'hui ils sont sérialisés directement vers le serveur IPC. Refactor : ils publient sur le bus interne, et le serveur IPC subscribe au bus pour faire la sérialisation JSON.

## Consommateurs (subscribers)

V2 :

1. **`IPCServer.eventForwarder`** (existant, refactor) : subscribe au bus, sérialise chaque event en JSON-line, écrit sur les connections socket en mode `events --follow`.
2. **`RailController`** (nouveau, in-process) : subscribe au bus, dispatche sur `handleEvent(_ event:)` avec switch sur le case enum.

Tout subscriber reçoit **tous** les events. Filtrage côté consommateur si besoin.

## Garanties

- **Order** : un subscriber reçoit les events dans l'ordre de publication (garanti par `AsyncStream` + actor isolation).
- **Delivery** : best-effort, pas de retry. Si un subscriber est lent, sa continuation accumule les events jusqu'à backpressure (`AsyncStream` buffer par défaut). Acceptable car les consommateurs (RailController, IPCServer) sont rapides.
- **Lifecycle** : un subscriber désinscrit automatiquement quand sa Task est annulée (via `onTermination`).

## Anti-patterns à éviter

- ❌ **Bypass du bus** : le module RailController ne doit pas appeler directement `stageManager.stagesV2[...]` pour réagir à un changement. Il subscribe au bus, et lit l'état actuel via API publique du `Daemon` quand il en a besoin (ex: `daemon.snapshot()`).
- ❌ **Sérialisation interne** : zéro JSON entre le bus et les consommateurs. Le JSON est uniquement sérialisé au point de sortie vers les clients externes (IPCServer).
- ❌ **Mutex global** : pas de `DispatchQueue.sync` entre le bus et les consommateurs. L'isolation actor + `AsyncStream` suffit.

## Tests

Tests unitaires (à ajouter dans `Tests/RoadieDesktopsTests/EventBusTests.swift` ou nouveau fichier) :

- `RoadieEventBusTests.testPublishToMultipleSubscribers` : 3 subscribers, 1 publish → tous reçoivent.
- `RoadieEventBusTests.testSubscriberCancellationCleansUp` : cancel Task → continuation retirée → subscriberCount décroît.
- `RoadieEventBusTests.testEventOrderPreserved` : 100 publish séquentiels → subscriber reçoit dans l'ordre.

## Métriques

Le bus expose `subscriberCount` pour debug/observability. À logger au boot (`{"msg": "rail subscribed", "subscribers": 2}` après init).
