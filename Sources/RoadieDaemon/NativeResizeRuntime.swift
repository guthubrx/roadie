import AppKit
import QuartzCore
import RoadieAX
import RoadieCore
import RoadieTiler

/// Suit le cadre natif de la seule cible ; la disposition ordinaire reste suspendue.
/// Géométrie sur MainActor, observation et writer commun en arrière-plan.
@MainActor
public final class NativeResizeRuntime: NSObject {
    private final class Session {
        let id = UUID()
        let gesture: GestureSession
        let window: WindowSnapshot
        let scope: StageScope
        let original: BSPTree
        let config: TilingConfig
        let prepared: BSPNativeResize
        let permit: InteractiveWritePermit
        var tree: BSPTree
        var windows: [WindowID: WindowSnapshot]
        var dispatcher: InteractiveFrameDispatcher?
        var observed: CGRect
        var endingAt: Date?
        var confirmed = false
        var reading = false
        var finalizing = false
        var updates = 0
        var missingObservations = 0

        init(gesture: GestureSession, window: WindowSnapshot, scope: StageScope, tree: BSPTree,
             config: TilingConfig,
             prepared: BSPNativeResize, windows: [WindowID: WindowSnapshot], permit: InteractiveWritePermit) {
            self.gesture = gesture; self.window = window; self.scope = scope; self.original = tree
            self.tree = tree; self.config = config
            self.prepared = prepared; self.windows = windows; self.permit = permit
            observed = gesture.startFrame ?? window.frame.cgRect
        }
    }

    private let service: SnapshotService
    private let input: UserInputActivity
    private let generations: PlacementGeneration
    private let minimums: @MainActor (StageScope, DaemonSnapshot) -> [WindowID: CGSize]
    private let readFrame: @Sendable (WindowSnapshot) -> CGRect?
    private let automaticCadence: Bool
    private let events: EventLog
    private var session: Session?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var onFinished: (@MainActor () -> Void)?

    public init(service: SnapshotService = SnapshotService(), input: UserInputActivity = .shared,
                generations: PlacementGeneration = .shared, automaticCadence: Bool = true,
                minimums: @escaping @MainActor (StageScope, DaemonSnapshot) -> [WindowID: CGSize] = { _, _ in [:] },
                readFrame: @escaping @Sendable (WindowSnapshot) -> CGRect? = NativeResizeRuntime.visibleFrame,
                events: EventLog = EventLog()) {
        self.service = service; self.input = input; self.generations = generations
        self.automaticCadence = automaticCadence; self.minimums = minimums
        self.readFrame = readFrame; self.events = events
    }

    public var isHoldingLayout: Bool { session != nil }
    var isConfirmed: Bool { session?.confirmed == true }

    public func setCompletion(_ completion: @escaping @MainActor () -> Void) { onFinished = completion }

    /// O(w + n) hors préparation des chemins. Aucun relevé global : ancrage du clic conservé.
    @discardableResult
    public func begin(_ gesture: GestureSession, snapshot: DaemonSnapshot) -> Bool {
        cancel(reason: "superseded")
        guard let raw = gesture.windowID, let start = gesture.startFrame,
              let location = gesture.startLocation,
              start.insetBy(dx: -8, dy: -8).contains(location),
              !start.insetBy(dx: 8, dy: 8).contains(location),
              snapshot.permissions.accessibilityTrusted,
              let entry = snapshot.windows.first(where: { $0.window.id.rawValue == raw }),
              entry.window.isTileCandidate, entry.window.isOnScreen, entry.pin == nil,
              entry.window.furniture?.isNativeFullscreen != true,
              let scope = entry.scope, snapshot.state.activeScope(on: scope.displayID) == scope,
              snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true,
              service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil,
              let tree = service.effectiveStageStore.state().bspTree(for: scope),
              let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot)
        else { return false }
        let members = snapshot.windows.filter { $0.scope == scope && $0.window.isTileCandidate && $0.pin == nil }
        guard members.count > 1, !members.contains(where: { $0.window.furniture?.isNativeFullscreen == true }) else { return false }
        let known = minimums(scope, snapshot)
        guard let prepared = BSPNativeResize(tree: tree, windowID: entry.window.id, in: geometry.container,
            innerGap: geometry.innerGap, excluding: geometry.absent, knownMinimums: known, startFrame: start)
        else { return false }
        let current = Session(gesture: gesture, window: entry.window, scope: scope, tree: tree,
            config: service.effectiveConfig.tiling, prepared: prepared,
            windows: Dictionary(members.map { ($0.window.id, $0.window) }, uniquingKeysWith: { a, _ in a }),
            permit: InteractiveWritePermit(generations: generations))
        session = current
        let id = current.id
        current.dispatcher = InteractiveFrameDispatcher(service: service, permit: current.permit) { [weak self] result in
            guard let self, let live = self.session, live.id == id else { return }
            for item in result.items {
                if let actual = item.actual { live.windows[item.windowID]?.frame = actual }
            }
        }
        if automaticCadence { startCadence(for: start) }
        pulse()
        return true
    }

    public func end(at date: Date = Date()) {
        guard let current = session, current.endingAt == nil else { return }
        current.endingAt = date
        pulse()
    }

    public func cancel(reason: String = "context_changed") {
        guard let current = session else { return }
        current.dispatcher?.invalidate()
        session = nil
        stopCadence()
        if current.confirmed {
            events.append(RoadieEvent(type: "native_resize_cancelled", scope: current.scope, details: ["reason": reason]))
        }
        onFinished?()
    }

    /// O(1) côté callback ; une seule observation active, sans attente AX ni disque ici.
    @objc func pulse() {
        guard let current = session, !current.finalizing else { return }
        if let end = current.endingAt, Date().timeIntervalSince(end) > 2 {
            cancel(reason: "end_timeout"); return
        }
        guard current.permit.isCurrent else { cancel(reason: "generation_changed"); return }
        if automaticCadence, NSEvent.pressedMouseButtons & 1 == 0, current.endingAt == nil {
            current.endingAt = Date()
        }
        if let active = input.currentGesture,
           active.windowID != current.gesture.windowID || active.startedAt != current.gesture.startedAt {
            cancel(reason: "new_gesture"); return
        }
        guard !current.reading else { return }
        current.reading = true
        let service = service, readFrame = readFrame, window = current.window
        let id = current.id, scope = current.scope
        let observation = Task.detached(priority: .userInitiated) {
            (readFrame(window), service.effectiveStageStore.state(), service.effectiveConfig.tiling,
             service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID, ProcessInfo.processInfo.systemUptime)
        }
        Task { [weak self] in
            let (frame, state, config, zoom, completedAt) = await observation.value
            guard let self, let live = self.session, live.id == id else { return }
            live.reading = false
            // Sous charge, le retour au MainActor peut attendre. Ne jamais finaliser sur
            // un cadre acquis avant cette attente ; le prochain tick relira la cible.
            guard ProcessInfo.processInfo.systemUptime - completedAt < 0.1 else { return }
            let pinned = Set(state.windowPins.map(\.windowID))
            guard live.permit.isCurrent, config == live.config, zoom == nil,
                  pinned.isDisjoint(with: live.windows.keys),
                  state.bspTree(for: live.scope) == live.original,
                  state.isActiveTreeScope(live.scope)
            else { self.cancel(reason: "observation_invalid"); return }
            guard let frame, frame.width > 0, frame.height > 0,
                  frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite
            else {
                live.missingObservations += 1
                if live.missingObservations >= 3 { self.cancel(reason: "window_unavailable") }
                return
            }
            live.missingObservations = 0
            self.receive(frame, current: live)
            if let end = live.endingAt {
                let now = Date()
                // Même budget que l'observation du geste existant : la dernière frame
                // peut arriver après mouseUp. Le suivi des voisines continue pendant ce délai.
                if now.timeIntervalSince(end) >= 0.3 {
                    self.finalize(live)
                }
            }
        }
    }

    private func receive(_ frame: CGRect, current: Session) {
        guard frame != current.observed else { return }
        current.observed = frame
        current.windows[current.window.id]?.frame = Rect(frame)
        service.publishNativeObservation(windowID: current.window.id, frame: frame)
        guard let layout = current.prepared.layout(observedFrame: frame) else { return }
        if !current.confirmed {
            guard layout.tree != current.original else { return }
            current.confirmed = true
            input.confirmNativeResize(current.gesture)
            events.append(RoadieEvent(type: "native_resize_started", scope: current.scope,
                details: ["windowID": String(current.window.id.rawValue)]))
        }
        current.tree = layout.tree
        let commands = current.windows.values.compactMap { window -> ApplyCommand? in
            guard window.id != current.window.id, let target = layout.frames[window.id],
                  !target.matchesFrame(window.frame.cgRect) || current.dispatcher?.mayChange(window) == true
            else { return nil }
            return ApplyCommand(window: window, frame: Rect(target))
        }
        let generation = current.permit.advance()
        current.dispatcher?.submit(commands, generation: generation)
        current.updates += 1 // Pas d'E/S de journal à chaque image du geste.
    }

    private func finalize(_ current: Session) {
        guard !current.finalizing else { return }
        current.finalizing = true
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(0.5)
            while current.dispatcher?.isIdle == false, Date() < deadline, current.permit.isCurrent {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard let self, self.session?.id == current.id else { return }
            if let active = self.input.currentGesture,
               active.startedAt != current.gesture.startedAt || active.windowID != current.gesture.windowID {
                self.cancel(reason: "new_gesture_at_commit"); return
            }
            if current.confirmed && current.permit.isCurrent {
                do {
                    guard self.service.effectiveConfig.tiling == current.config,
                          self.service.effectiveIntentStore.intent(for: current.scope)?.zoomedWindowID == nil
                    else { self.cancel(reason: "configuration_at_commit"); return }
                    let saved = try self.service.effectiveStageStore.mutateChecked { state -> Bool in
                        let pinned = Set(state.windowPins.map(\.windowID))
                        guard state.isActiveTreeScope(current.scope),
                              state.bspTree(for: current.scope) == current.original,
                              pinned.isDisjoint(with: current.windows.keys) else { return false }
                        state.setBSPTree(current.tree, for: current.scope)
                        return true
                    }
                    if saved { self.input.completeNativeResize(current.gesture) }
                    self.events.append(RoadieEvent(type: "native_resize_finished", scope: current.scope,
                        details: ["saved": String(saved), "drained": String(current.dispatcher?.isIdle == true),
                                  "updates": String(current.updates)]))
                } catch {
                    self.events.append(RoadieEvent(type: "native_resize_failed", scope: current.scope,
                        details: ["error": String(describing: error)]))
                }
            }
            current.dispatcher?.invalidate()
            self.session = nil
            self.stopCadence()
            self.onFinished?()
        }
    }

    private func startCadence(for frame: CGRect) {
        let rect = RoadieScreenCoordinate.axRectToNS(frame)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            let link = screen.displayLink(target: self, selector: #selector(pulse))
            displayLink = link
            link.add(to: .main, forMode: .common)
        } else {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulse() }
            }
            fallbackTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopCadence() {
        displayLink?.invalidate(); displayLink = nil
        fallbackTimer?.invalidate(); fallbackTimer = nil
    }

    /// Lecture ciblée WindowServer, identité CG/PID stricte. Aucun repli par titre ni inventaire AX.
    /// Les coordonnées CG sont celles utilisées par la géométrie AX de Roadie. O(1) fenêtre demandée.
    public nonisolated static func visibleFrame(_ window: WindowSnapshot) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.id.rawValue) as? [[String: Any]],
              let info = infos.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == window.id.rawValue
                  && ($0[kCGWindowOwnerPID as String] as? Int32) == window.pid }),
              (info[kCGWindowIsOnscreen as String] as? Bool) != false,
              let bounds = info[kCGWindowBounds as String] as? [String: Any]
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}
