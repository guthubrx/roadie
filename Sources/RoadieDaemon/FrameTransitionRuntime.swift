import AppKit
import RoadieAX
import RoadieCore

/// Adaptateur hors geste : mêmes permis, coalescence et writer que le suivi interactif.
/// Aucun succès final n'est déclaré à la planification. O(k) d'état, O(k+p) par lot.
@MainActor
public final class FrameTransitionRuntime {
    public static let shared = FrameTransitionRuntime()
    private final class Session {
        let service: SnapshotService
        let generation: UInt64
        let permit: InteractiveWritePermit
        let config: AnimationsConfig
        let started = ProcessInfo.processInfo.systemUptime
        var dispatcher: InteractiveFrameDispatcher!
        var commands: [WindowID: ApplyCommand] = [:]
        var windows: [WindowID: WindowSnapshot] = [:]
        var frames: [WindowID: Rect] = [:]
        var finished: Set<WindowID> = []
        var ids: Set<String> = []
        var finalSubmitted = false
        var finalResults: [WindowID: ApplyResultItem] = [:]
        init(service: SnapshotService, generation: UInt64, generations: PlacementGeneration) {
            self.service = service; self.generation = generation
            permit = InteractiveWritePermit(generations: generations)
            config = service.effectiveConfig.fx.animations
        }
    }
    private let generations: PlacementGeneration
    private let events: EventLog
    private let isMouseDown: () -> Bool
    private var session: Session?
    private var timer: Timer?
    private(set) var acceptsCommands = false
    public func start() { acceptsCommands = true }
    public var isHoldingLayout: Bool { session.map { $0.permit.isCurrent && ProcessInfo.processInfo.systemUptime - $0.started < 1.5 } ?? false }

    init(generations: PlacementGeneration = .shared, events: EventLog = EventLog(),
         isMouseDown: @escaping () -> Bool = {
             UserInputActivity.shared.isCapturedPointerHeld || NSEvent.pressedMouseButtons != 0
         }) {
        self.generations = generations; self.events = events; self.isMouseDown = isMouseDown
    }

    func schedule(_ plan: ApplyPlan, service: SnapshotService, generation: UInt64, action: AnimationAction,
                  immediateWindowIDs: Set<WindowID> = []) -> ApplyResult? {
        let policy = service.effectiveConfig.fx.animations.policy(for: action)
        guard policy.enabled, !plan.commands.isEmpty, generation == generations.current,
              generation != PlacementGeneration.outsideBudget, !isMouseDown() else { return nil }
        events.append(RoadieEvent(type: "effects.frames_policy", details: [
            "generation": String(generation), "action": action.rawValue,
            "directWindowIDs": immediateWindowIDs.sorted().map { String($0.rawValue) }.joined(separator: ","),
            "frames": plan.commands.map { command in
                let from = command.window.frame, to = command.frame
                return "\(command.window.id.rawValue):\(from.x),\(from.y),\(from.width),\(from.height)->\(to.x),\(to.y),\(to.width),\(to.height);preservesSize=\(command.preservesSize)"
            }.joined(separator: "|")
        ]))
        if session?.generation != generation || session?.finalSubmitted == true {
            let retained = Set(plan.commands.map { "ax-\(ObjectIdentifier(self))-\($0.window.pid)-\($0.window.id.rawValue)" })
            // Révoquer les anciens lots sans perdre la vitesse des fenêtres reprises.
            cancel(preserving: retained)
        }
        let current: Session
        if let existing = session { current = existing }
        else {
            current = Session(service: service, generation: generation, generations: generations)
            session = current
            events.append(RoadieEvent(type: "effects.frames_started", details: ["generation": String(generation), "action": action.rawValue]))
            current.dispatcher = InteractiveFrameDispatcher(service: service, permit: current.permit) { [weak current] result in
                guard let current else { return }
                for item in result.items {
                    if let frame = item.actual { current.windows[item.windowID]?.frame = frame }
                    if current.finalSubmitted, item.requested == current.commands[item.windowID]?.frame {
                        current.finalResults[item.windowID] = item
                    }
                }
            }
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulse() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        let displays = service.cachedGestureSnapshot()?.displays ?? []
        for original in plan.commands {
            var command = original
            if immediateWindowIDs.contains(command.window.id) { command.positionsBeforeResizing = true }
            let window = command.window, id = window.id
            current.commands[id] = command
            current.windows[id] = current.windows[id] ?? window
            current.finished.remove(id)
            var from = current.frames[id]?.cgRect ?? window.frame.cgRect
            var to = command.frame.cgRect
            let animationID = "ax-\(ObjectIdentifier(self))-\(window.pid)-\(id.rawValue)"
            current.ids.insert(animationID)
            if immediateWindowIDs.contains(id), !command.preservesSize {
                EffectAnimator.shared.cancel(animationID)
                current.frames[id] = command.frame
                current.finished.insert(id)
                continue
            }
            // Un pixel de parking peut encore être déclaré visible par WindowServer.
            // Ne jamais réexposer une fenêtre déjà rangée pendant son masquage.
            if command.preservesSize && (!window.isOnScreen
                || window.frame.cgRect.matchesFrame(to)
                || HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: displays)) {
                EffectAnimator.shared.cancel(animationID)
                current.frames[id] = command.frame
                current.finished.insert(id)
                continue
            }
            // Le parking n'est pas une destination visuelle : courte sortie puis parking final.
            if command.preservesSize { to = from.offsetBy(dx: -40 * policy.intensity, dy: 0) }
            else if !window.isOnScreen { from = to.offsetBy(dx: 40 * policy.intensity, dy: 0) }
            EffectAnimator.shared.animate(id: animationID, from: [from.minX, from.minY, from.width, from.height],
                to: [to.minX, to.minY, to.width, to.height], policy: policy) { [weak current] values in
                current?.frames[id] = Rect(x: values[0], y: values[1], width: max(1, values[2]), height: max(1, values[3]))
            } completion: { [weak current] in current?.finished.insert(id) }
        }
        // La première cible part dès maintenant par le writer asynchrone commun.
        if !immediateWindowIDs.isEmpty { pulse() }
        return ApplyResult(attempted: 0, applied: 0, clamped: 0, failed: 0,
            items: plan.commands.map { ApplyResultItem(windowID: $0.window.id, status: .deferred, requested: $0.frame, actual: nil) })
    }

    private func pulse() {
        guard let current = session else { return }
        guard current.permit.isCurrent else { cancel(); return }
        let needsImmediateEnd = current.config != current.service.effectiveConfig.fx.animations
        let elapsed = ProcessInfo.processInfo.systemUptime - current.started
        guard elapsed < 1.5 else { cancel(); return }
        if current.finalSubmitted {
            if current.dispatcher.isIdle { cancel(completed: true) }
            return
        }
        if current.finished.count == current.commands.count || elapsed >= 1 || needsImmediateEnd {
            current.finalSubmitted = true
            for id in current.ids { EffectAnimator.shared.cancel(id) }
            let commands = current.commands.values.map { command -> ApplyCommand in
                var value = command
                value.window = current.windows[command.window.id] ?? command.window
                return value
            }
            current.dispatcher.submit(commands, generation: current.generation)
        } else {
            let commands = current.frames.compactMap { id, frame -> ApplyCommand? in
                guard let window = current.windows[id], let final = current.commands[id],
                      !window.frame.cgRect.matchesFrame(frame.cgRect) || current.dispatcher.mayChange(window) else { return nil }
                return ApplyCommand(window: window, frame: frame, preservesSize: final.preservesSize,
                                    positionsBeforeResizing: final.positionsBeforeResizing)
            }
            if !commands.isEmpty { current.dispatcher.submit(commands, generation: PlacementGeneration.outsideBudget) }
        }
    }

    public func stop() { acceptsCommands = false; cancel(); EffectAnimator.shared.stop() }

    public func cancel(completed: Bool = false, preserving: Set<String> = []) {
        timer?.invalidate(); timer = nil
        if let current = session {
            events.append(RoadieEvent(type: completed ? "effects.frames_completed" : "effects.frames_cancelled", details: [
                "generation": String(current.generation), "windows": String(current.commands.count),
                "durationMs": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - current.started) * 1000),
                "applied": String(current.finalResults.values.filter { $0.status == .applied }.count),
                "clamped": String(current.finalResults.values.filter { $0.status == .clamped }.count),
                "failed": String(current.finalResults.values.filter { $0.status == .failed }.count)
            ]))
            current.dispatcher?.invalidate()
            for id in current.ids.subtracting(preserving) { EffectAnimator.shared.cancel(id) }
        }
        session = nil
    }
}
