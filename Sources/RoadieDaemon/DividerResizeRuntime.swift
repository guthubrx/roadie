import AppKit
import RoadieAX
import RoadieCore
import RoadieTiler

/// Raccorde les poignées au seul processus écrivain (tiler/run), sans acquisition AX dans mouseDragged.
@MainActor
public final class DividerResizeRuntime {
    private let service: SnapshotService
    private let coordinator: DividerResizeCoordinator
    private lazy var controller = SplitResizeController(
        onBegin: { [weak self] handle, point in self?.begin(handle, at: point) ?? false },
        onUpdate: { [weak self] handle, point in self?.coordinator.queue(handle, at: point) },
        onEnd: { [weak self] _, cancelled in self?.end(cancelled: cancelled) }
    )
    private var refreshTimer: Timer?
    private var placementTimer: Timer?
    private var refreshing = false
    private var started = false
    private var lifecycle: UInt64 = 0
    private var visibleHandles: [SplitResizeHandle] = []

    public init(
        service: SnapshotService = SnapshotService(),
        minimums: @escaping (StageScope, DaemonSnapshot) -> [WindowID: CGSize] = { _, _ in [:] }
    ) {
        self.service = service
        coordinator = DividerResizeCoordinator(service: service, minimums: minimums)
    }

    public func start() {
        guard !started else { return }
        started = true
        lifecycle &+= 1
        refreshTimer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
        Task { await refresh() }
    }

    private func begin(_ handle: SplitResizeHandle, at point: CGPoint) -> Bool {
        guard coordinator.begin(handle, at: point) else { return false }
        // Ce minuteur ne tourne que pendant un geste : une seule cible en attente, au plus 20 applications/s.
        placementTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.coordinator.flush()
                if self.controller.isDragging, !self.coordinator.isDragging { self.controller.cancel() }
            }
        }
        if let placementTimer { RunLoop.main.add(placementTimer, forMode: .common) }
        return true
    }

    private func end(cancelled: Bool) {
        placementTimer?.invalidate()
        placementTimer = nil
        coordinator.end(cancelled: cancelled)
    }

    public func stop() {
        started = false
        lifecycle &+= 1
        refreshTimer?.invalidate()
        placementTimer?.invalidate()
        refreshTimer = nil
        placementTimer = nil
        controller.stop()
        coordinator.end(cancelled: true)
        visibleHandles.removeAll()
    }

    /// O(h). Une prise explicite ne doit pas démarrer aussi une session native sur sa voisine.
    public func containsHandle(at point: CGPoint) -> Bool {
        visibleHandles.contains { $0.divider.hitRect.contains(point) }
    }

    private func refresh() async {
        guard started, !refreshing else { return }
        guard service.effectiveConfig.tiling.resizeHandles else {
            controller.stop()
            coordinator.end(cancelled: true)
            visibleHandles.removeAll()
            return
        }
        refreshing = true
        let version = lifecycle
        defer { refreshing = false }
        guard let snapshot = await service.readerSnapshot(followFocus: false), started, version == lifecycle else { return }
        let handles = coordinator.update(snapshot: snapshot)
        visibleHandles = handles
        if controller.isDragging, !coordinator.isDragging { controller.cancel() }
        controller.update(handles: handles)
    }
}

/// Le contexte et l'identité du split sont figés au début ; chaque nouvelle cible est une intention explicite.
@MainActor
final class DividerResizeCoordinator {
    private struct Context {
        var snapshot: DaemonSnapshot
        var tree: BSPTree
        var geometry: CommandTreeGeometry
        var tiling: TilingConfig
    }
    private struct Session {
        var handle: SplitResizeHandle
        var context: Context
        var generation: UInt64
        var pending: CGPoint?
        var minimums: [WindowID: CGSize]
    }

    private let service: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let generations: PlacementGeneration
    private let events: EventLog
    private let minimums: (StageScope, DaemonSnapshot) -> [WindowID: CGSize]
    private let apply: (StageScope, UInt64, DaemonSnapshot) -> (MaintenanceTick, [WindowID: Rect])
    private var contexts: [StageScope: Context] = [:]
    private var session: Session?

    init(
        service: SnapshotService,
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() },
        generations: PlacementGeneration = .shared,
        events: EventLog = EventLog(),
        minimums: @escaping (StageScope, DaemonSnapshot) -> [WindowID: CGSize] = { _, _ in [:] },
        apply: ((StageScope, UInt64, DaemonSnapshot) -> (MaintenanceTick, [WindowID: Rect]))? = nil
    ) {
        self.service = service
        self.configLoader = configLoader
        self.generations = generations
        self.events = events
        self.minimums = minimums
        self.apply = apply ?? { scope, generation, snapshot in
            var frames: [WindowID: Rect] = [:]
            let tick = service.applyTreeScope(scope, cause: "window.resize.divider", generation: generation, using: snapshot,
                onApplied: { result in
                    frames = Dictionary(result.items.compactMap { item in item.actual.map { (item.windowID, $0) } },
                                        uniquingKeysWith: { _, last in last })
                })
            return (tick, frames)
        }
    }

    var isDragging: Bool { session != nil }

    /// O(d·w + h·w) : écrans, fenêtres et séparations. Ce contrôle spatial est effectué au refresh,
    /// pas à chaque mouvement ; toute surface occupée doit rester accessible à son application.
    func update(snapshot: DaemonSnapshot) -> [SplitResizeHandle] {
        let config = configLoader()
        guard config.tiling.resizeHandles, snapshot.permissions.accessibilityTrusted else {
            end(cancelled: true)
            contexts.removeAll()
            return []
        }
        if let session {
            let old = session.context
            if config.tiling != old.tiling || snapshot.displays != old.snapshot.displays
                || snapshot.state.activeScope(on: session.handle.scope.displayID) != session.handle.scope
                || Set(snapshot.windows.filter { $0.scope == session.handle.scope }.map(\.window.id))
                    != Set(old.snapshot.windows.filter { $0.scope == session.handle.scope }.map(\.window.id))
                || !valid(session) {
                end(cancelled: true)
            }
        }
        var next: [StageScope: Context] = [:]
        var handles: [SplitResizeHandle] = []
        let state = service.effectiveStageStore.state()
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true,
                  service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil,
                  let tree = state.bspTree(for: scope),
                  let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot)
            else { continue }
            let windows = snapshot.windows.filter { $0.scope == scope && $0.window.isTileCandidate }
            guard windows.count > 1,
                  !windows.contains(where: { $0.window.furniture?.isNativeFullscreen == true }),
                  !windows.contains(where: { $0.pin != nil }) else { continue }
            let frames = geometry.frames(of: tree)
            // Tant que les cadres réels ne suivent pas l'arbre, aucune surface de prise ne les recouvre.
            guard windows.allSatisfy({ entry in
                frames[entry.window.id].map { $0.matchesFrame(entry.window.frame.cgRect) } ?? false
            }) else { continue }
            // Même derrière une fenêtre tuilée, une autre application peut être visible dans son interstice.
            // Les cadres réels des fenêtres tuilées comptent aussi : la tolérance de placement ne libère pas des pixels.
            let occupied = snapshot.windows.compactMap { entry -> CGRect? in
                let window = entry.window
                guard window.isOnScreen else { return nil }
                // JankyBorders expose un rectangle CG plein autour d'un contenu transparent.
                // Exception étroite : une vraie fenêtre ou une application AX illisible reste protégée.
                let borderDecoration = window.appName == "borders" && window.bundleID.isEmpty
                    && window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && window.role == nil && window.subrole == nil && window.furniture == nil
                return borderDecoration ? nil : window.frame.cgRect
            }
            let dividers = tree.dividers(in: geometry.container, innerGap: geometry.innerGap, excluding: geometry.absent)
            handles += dividers.filter { divider in
                !divider.hitRect.isEmpty && !occupied.contains { $0.intersects(divider.hitRect) }
            }.map { SplitResizeHandle(scope: scope, divider: $0) }
            next[scope] = Context(snapshot: snapshot, tree: tree, geometry: geometry, tiling: config.tiling)
        }
        contexts = next
        return handles
    }

    /// O(n) : validation de l'arbre et des minimums au début d'une session.
    func begin(_ handle: SplitResizeHandle, at point: CGPoint) -> Bool {
        guard session == nil, let context = contexts[handle.scope],
              handle.divider.hitRect.contains(point),
              context.tree.dividers(in: context.geometry.container, innerGap: context.geometry.innerGap,
                                    excluding: context.geometry.absent).contains(handle.divider)
        else { return false }
        let candidate = Session(handle: handle, context: context, generation: generations.current,
                                minimums: minimums(handle.scope, context.snapshot))
        guard valid(candidate) else { return false }
        session = candidate
        return true
    }

    /// O(1). La cible la plus récente remplace la précédente ; aucune E/S ni lecture AX.
    func queue(_ handle: SplitResizeHandle, at point: CGPoint) {
        guard session?.handle.scope == handle.scope, session?.handle.divider.path == handle.divider.path,
              point.x.isFinite, point.y.isFinite else { return }
        session?.pending = point
    }

    /// Une application passe par le même point d'écriture que les commandes, avec ses protections.
    func flush() {
        guard var current = session, let point = current.pending else { return }
        guard valid(current) else { session = nil; return }
        current.pending = nil
        let context = current.context
        guard let changed = context.tree.movingDivider(
            at: current.handle.divider.path, to: point, in: context.geometry.container,
            innerGap: context.geometry.innerGap, excluding: context.geometry.absent,
            knownMinimums: current.minimums
        ), changed != context.tree,
           context.geometry.frames(of: changed) != context.geometry.frames(of: context.tree)
        else { session = current; return }
        do {
            let saved = try service.effectiveStageStore.mutateChecked { state -> Bool in
                guard Self.isActive(current.handle.scope, in: state),
                      state.bspTree(for: current.handle.scope) == context.tree else { return false }
                state.setBSPTree(changed, for: current.handle.scope)
                return true
            }
            guard saved else { session = nil; return }
            current.generation = generations.next()
            current.context.tree = changed
            session = current
            let (result, frames) = apply(current.handle.scope, current.generation, context.snapshot)
            guard generations.current == current.generation, session?.generation == current.generation else { return }
            guard result.failed == 0, !result.accessibilityDenied else { session = nil; return }
            for index in current.context.snapshot.windows.indices {
                if let frame = frames[current.context.snapshot.windows[index].window.id] {
                    current.context.snapshot.windows[index].window.frame = frame
                }
            }
            session = current
        } catch {
            session = nil
            events.append(RoadieEvent(type: "command_failed", scope: current.handle.scope,
                                     details: ["command": "window.resize.divider", "error": String(describing: error)]))
        }
    }

    func end(cancelled: Bool) {
        if !cancelled { flush() }
        session = nil
    }

    private func valid(_ session: Session) -> Bool {
        let scope = session.handle.scope
        let state = service.effectiveStageStore.state()
        return configLoader().tiling == session.context.tiling
            && generations.current == session.generation
            && Self.isActive(scope, in: state)
            && state.bspTree(for: scope) == session.context.tree
            && service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil
    }

    private static func isActive(_ scope: StageScope, in state: PersistentStageState) -> Bool {
        guard state.currentDesktopID(for: scope.displayID) == scope.desktopID,
              let stored = state.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }),
              stored.activeStageID == scope.stageID,
              stored.stages.first(where: { $0.id == scope.stageID })?.mode.usesTreeEngine == true else { return false }
        return true
    }
}
