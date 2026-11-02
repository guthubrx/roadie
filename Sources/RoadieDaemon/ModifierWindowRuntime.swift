import AppKit
import RoadieAX
import RoadieCore
import RoadieTiler

/// Un seul écrivain pour la source et ses voisines, sans inventaire AX pendant le geste.
@MainActor
public final class ModifierWindowRuntime {
    private final class Session {
        let id = UUID()
        let source: ScopedWindowSnapshot
        let context: DropPreviewContext
        let config: TilingConfig
        let geometry: ModifierWindowGeometry
        let prepared: BSPNativeResize?
        let permit = InteractiveWritePermit(generations: .shared)
        let startedAt = Date()
        var dispatcher: InteractiveFrameDispatcher!
        let originals: [WindowID: Rect]
        var windows: [WindowID: WindowSnapshot]
        var touched: Set<WindowID> = []
        var point: CGPoint
        var lastProcessedPoint: CGPoint?
        var candidate: DropPreviewCandidate?
        var checkedAt = Date.distantPast
        var renewedAt = Date.distantPast
        var ending = false

        init(source: ScopedWindowSnapshot, context: DropPreviewContext, config: TilingConfig,
             geometry: ModifierWindowGeometry, prepared: BSPNativeResize?) {
            self.source = source; self.context = context; self.config = config; self.geometry = geometry
            self.prepared = prepared; point = geometry.origin
            originals = Dictionary(context.snapshot.windows.map { ($0.window.id, $0.window.frame) }, uniquingKeysWith: { a, _ in a })
            windows = Dictionary(context.snapshot.windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private let service: SnapshotService
    private let input: UserInputActivity
    private let events: EventLog
    private let minimums: (StageScope, DaemonSnapshot) -> [WindowID: CGSize]
    private let completed: () -> Void
    private let automaticCadence: Bool
    private var session: Session?
    private var timer: Timer?
    private let engine: DropPreviewEngine
    private let overlay = DropPreviewOverlayWindow()

    public init(service: SnapshotService, input: UserInputActivity = .shared, events: EventLog = EventLog(),
         minimums: @escaping (StageScope, DaemonSnapshot) -> [WindowID: CGSize] = { _, _ in [:] },
         automaticCadence: Bool = true, completed: @escaping () -> Void = {}) {
        self.service = service; self.input = input; self.events = events; self.minimums = minimums
        self.completed = completed; engine = DropPreviewEngine(service: service)
        self.automaticCadence = automaticCadence
    }

    var isActive: Bool { session != nil }
    var identifier: UUID? { session?.id }
    var isEnding: Bool { session?.ending == true }

    /// Sélection stricte en Z : une surface opaque inéligible protège toutes celles de derrière.
    static func target(at point: CGPoint, snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        guard snapshot.permissions.accessibilityTrusted,
              let entry = snapshot.windows.first(where: { entry in entry.window.isOnScreen
                  && !entry.window.isKnownBorderDecoration
                  // Le conteneur transparent de Notification Center couvre tout l'écran (CG layer21).
                  && !(entry.window.bundleID == "com.apple.notificationcenterui" && !entry.window.isTileCandidate
                       && entry.window.subrole == nil && snapshot.displays.contains(where: { $0.frame == entry.window.frame }))
                  && entry.window.frame.cgRect.contains(point) }),
              entry.window.pid != getpid(), entry.window.furniture?.isNativeFullscreen != true,
              entry.window.isTileCandidate || entry.window.subrole == "AXStandardWindow",
              entry.scope.map({ snapshot.state.activeScope(on: $0.displayID) == $0 }) ?? true else { return nil }
        return entry
    }

    @discardableResult
    func begin(source: ScopedWindowSnapshot, snapshot: DaemonSnapshot, at point: CGPoint,
               operation: ModifierWindowOperation) -> Bool {
        guard session == nil, Self.target(at: point, snapshot: snapshot)?.window.id == source.window.id else { return false }
        let config = service.publishedConfig.tiling
        let state = service.effectiveStageStore.state()
        let known = source.scope.map { minimums($0, snapshot) } ?? [:]
        var prepared: BSPNativeResize?
        if operation == .resize, source.pin == nil, let scope = source.scope,
           snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true {
            guard let tree = state.bspTree(for: scope),
                  let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot),
                  let resize = BSPNativeResize(tree: tree, windowID: source.window.id, in: geometry.container,
                      innerGap: geometry.innerGap, excluding: geometry.absent, knownMinimums: known,
                      startFrame: source.window.frame.cgRect) else { return false }
            prepared = resize
        }
        FrameTransitionRuntime.shared.cancel()
        _ = PlacementGeneration.shared.next()
        let geometry = ModifierWindowGeometry(frame: source.window.frame.cgRect, origin: point, operation: operation,
            available: prepared?.movableEdges ?? [.left, .right, .up, .down],
            minimum: known[source.window.id] ?? CGSize(width: 80, height: 80))
        let current = Session(source: source, context: DropPreviewContext(snapshot: snapshot, persistedStateBeforeSnapshot: state),
                              config: config, geometry: geometry, prepared: prepared)
        current.dispatcher = InteractiveFrameDispatcher(service: service, permit: current.permit) { [weak current] result, _ in
            guard let current else { return }
            for item in result.items { if let frame = item.actual { current.windows[item.windowID]?.frame = frame } }
        }
        input.claimExplicitResize()
        input.setCapturedPointerHeld(true)
        session = current
        if automaticCadence {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        events.append(RoadieEvent(type: "modifier_gesture.started", scope: source.scope,
            details: ["operation": operation.rawValue, "windowID": String(source.window.id.rawValue),
                      "startX": String(Double(point.x)), "startY": String(Double(point.y))]))
        return true
    }

    func update(at point: CGPoint) { if !sessionIsEnding { session?.point = point } }
    private var sessionIsEnding: Bool { session?.ending == true }

    func flush() {
        guard let current = session, !current.ending else { return }
        guard valid(current) else { abandon(current, reason: "context_changed"); return }
        if Date().timeIntervalSince(current.renewedAt) > 0.4 {
            current.renewedAt = Date(); WindowDragActivity.shared.markActive(windowID: current.source.window.id)
        }
        guard current.lastProcessedPoint != current.point else { return }
        current.lastProcessedPoint = current.point
        guard let frame = current.geometry.target(at: current.point) else { return }
        var frames: [WindowID: Rect] = [:]
        if current.geometry.operation == .resize {
            if let prepared = current.prepared {
                guard let result = prepared.layout(observedFrame: frame) else { return }
                frames = result.frames.mapValues(Rect.init)
            } else { frames[current.source.window.id] = Rect(frame) }
        } else {
            let tiled = current.source.pin == nil && current.source.window.isTileCandidate
                && current.source.scope.flatMap { current.context.snapshot.state.stage(scope: $0)?.mode } != .float
            if tiled {
                current.candidate = engine.candidate(sourceWindowID: current.source.window.id,
                    at: RoadieScreenCoordinate.axRectToNS(CGRect(origin: current.point, size: .zero)).origin,
                    context: current.context)
            }
            if let candidate = current.candidate {
                if service.publishedConfig.tiling.liveDragPreview { frames = candidate.placements }
                if service.publishedConfig.fx.dropPreview == "real" {
                    frames[current.source.window.id] = candidate.placements[current.source.window.id] ?? Rect(candidate.frame)
                    overlay.hide()
                } else { frames[current.source.window.id] = Rect(frame); overlay.show(candidate) }
            } else { frames[current.source.window.id] = Rect(frame); overlay.hide() }
        }
        submit(frames, current: current)
    }

    /// Cadence bornée des lectures JSON ; aucune observation AX, même à 120Hz.
    private func valid(_ current: Session, force: Bool = false) -> Bool {
        guard current.permit.isCurrent, service.publishedConfig.tiling == current.config else { return false }
        if let latest = service.cachedGestureSnapshot() {
            guard latest.displays == current.context.snapshot.displays else { return false }
            if let pids = latest.existingWindowPIDs, pids[current.source.window.id] != current.source.window.pid { return false }
        }
        if !force, Date().timeIntervalSince(current.checkedAt) < 0.25 { return true }
        current.checkedAt = Date()
        return contextMatches(current, state: service.effectiveStageStore.state())
    }

    private func contextMatches(_ current: Session, state: PersistentStageState) -> Bool {
        var scopes = Set([current.source.scope, current.candidate?.scope].compactMap { $0 })
        for entry in current.context.snapshot.windows where current.touched.contains(entry.window.id) {
            if let scope = entry.scope { scopes.insert(scope) }
        }
        for scope in scopes {
            func stage(_ state: PersistentStageState) -> PersistentStage? {
                state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                    .stages.first { $0.id == scope.stageID }
            }
            guard state.currentDesktopID(for: scope.displayID) == scope.desktopID,
                  state.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?.activeStageID == scope.stageID,
                  let before = stage(current.context.persistedStateBeforeSnapshot), let now = stage(state),
                  before.bspTree == now.bspTree, before.mode == now.mode,
                  before.members.map(\.windowID) == now.members.map(\.windowID),
                  before.members.map(\.confirmedClosedAt) == now.members.map(\.confirmedClosedAt) else { return false }
        }
        let pin = state.windowPins.first { $0.windowID == current.source.window.id }
        return pin?.homeScope == current.source.pin?.homeScope && pin?.pinScope == current.source.pin?.pinScope
    }

    private func submit(_ frames: [WindowID: Rect], current: Session) {
        let eligible = frames.filter { current.windows[$0.key] != nil }
        current.touched.formUnion(eligible.keys)
        let commands = current.touched.compactMap { id -> ApplyCommand? in
            guard let window = current.windows[id], let target = eligible[id] ?? current.originals[id],
                  !window.frame.cgRect.matchesFrame(target.cgRect) || current.dispatcher.mayChange(window) else { return nil }
            return ApplyCommand(window: window, frame: target)
        }
        if !commands.isEmpty || !current.dispatcher.isIdle {
            current.dispatcher.submit(commands, generation: current.permit.advance())
        }
    }

    func end(cancelled: Bool = false, matching id: UUID? = nil) {
        guard let current = session, !current.ending, id == nil || current.id == id else { return }
        if !cancelled { flush() }
        guard session === current, valid(current, force: true) else { abandon(current, reason: "context_changed"); return }
        current.ending = true; timer?.invalidate(); timer = nil; overlay.hide()
        if cancelled { submit([:], current: current) }
        Task { [weak self, current] in
            let deadline = Date().addingTimeInterval(2)
            while !current.dispatcher.isIdle, current.permit.isCurrent, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard let self, self.session === current else { return }
            guard current.dispatcher.isIdle, self.valid(current, force: true) else { self.abandon(current, reason: "drain_or_context"); return }
            let committed = cancelled ? false : self.commit(current)
            self.abandon(current, reason: cancelled ? "cancelled" : committed ? "finished" : "commit_rejected")
        }
    }

    private func commit(_ current: Session) -> Bool {
        do {
            if let scope = current.source.scope, let prepared = current.prepared {
                guard let actual = current.windows[current.source.window.id]?.frame,
                      let final = prepared.layout(observedFrame: actual.cgRect) else { return false }
                return try service.effectiveStageStore.mutateChecked { state -> Bool in
                    guard contextMatches(current, state: state) else { return false }
                    state.setBSPTree(final.tree, for: scope); return true
                }
            } else if current.geometry.operation == .move, let candidate = current.candidate {
                return StageCommandService(service: service, store: service.effectiveStageStore, events: events).place(
                    windowID: candidate.sourceWindowID, displayID: candidate.displayID,
                    orderedWindowIDs: candidate.orderedWindowIDs, placements: candidate.placements, treeMutation: candidate.treeMutation,
                    deferGeometryUsing: current.context.snapshot, validating: { self.contextMatches(current, state: $0) }).outcome != .failed
            } else if current.source.pin != nil, let frame = current.windows[current.source.window.id]?.frame {
                return try service.effectiveStageStore.mutateChecked { state -> Bool in
                    guard contextMatches(current, state: state), let index = state.windowPins.firstIndex(where: { $0.windowID == current.source.window.id }) else { return false }
                    state.windowPins[index].lastFrame = frame; state.windowPins[index].updatedAt = Date(); return true
                }
            } else if current.geometry.operation == .resize, current.source.window.isTileCandidate, let scope = current.source.scope,
                      current.context.snapshot.state.stage(scope: scope)?.mode != .float {
                input.recordCompletedGesture(GestureSession(windowID: current.source.window.id.rawValue,
                    startFrame: current.source.window.frame.cgRect, startedAt: current.startedAt, endedAt: Date(),
                    didDrag: true, startLocation: current.geometry.origin))
            }
            return true
        } catch {
            events.append(RoadieEvent(type: "modifier_gesture.failed", scope: current.source.scope, details: ["reason": String(describing: error)]))
            return false
        }
    }

    func cancelImmediately(reason: String) { if let current = session { abandon(current, reason: reason) } }

    private func abandon(_ current: Session, reason: String) {
        guard session === current else { return }
        current.dispatcher.invalidate(); timer?.invalidate(); timer = nil; overlay.hide(); session = nil
        WindowDragActivity.shared.release(); input.setCapturedPointerHeld(false)
        events.append(RoadieEvent(type: "modifier_gesture.ended", scope: current.source.scope,
            details: ["reason": reason, "windowID": String(current.source.window.id.rawValue)]))
        completed()
    }
}
