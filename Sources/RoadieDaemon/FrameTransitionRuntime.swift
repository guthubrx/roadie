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
        /// Échéance attendue de la courbe temporelle (0 = ressort sans borne fixe, Lot G).
        var expectedEnd: TimeInterval = 0
        var dispatcher: InteractiveFrameDispatcher!
        var commands: [WindowID: ApplyCommand] = [:]
        var windows: [WindowID: WindowSnapshot] = [:]
        var frames: [WindowID: Rect] = [:]
        var finished: Set<WindowID> = []
        var ids: Set<String> = []
        var focusAfterScenePlacement: (() -> Void)?
        var scene: StageSceneTransition?
        var isScheduling = false
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
    private let sceneCapture: @MainActor (StageSceneContext) async -> CGImage?
    private let presentsScenes: Bool
    var isAnimatingScene: Bool { session?.scene?.phase == .animating }
    private var session: Session?
    private var timer: Timer?
    /// Résultats finaux seulement : les images intermédiaires ne sont pas des placements.
    public var onFinalResult: ((ApplyResult, ApplyPlan, UInt64) -> Void)?
    /// Appelé dès que la session se termine et que `isHoldingLayout` redevient faux (Lot E : réarme
    /// immédiatement `TickScheduler` pour les échéances `refusal_confirm` et événements retenus).
    public var onTransitionEnded: (() -> Void)?
    /// Cadence de publication vers le dispatcher AX (alignée sur `EffectAnimator` à 60 Hz, Lot E).
    static let frameInterval: TimeInterval = 1.0 / 60
    /// Garde-fou léger hors transition de scène (les images sont poussées en phase par `EffectAnimator`, Lot F).
    static let watchdogInterval: TimeInterval = 0.1
    /// Budget adaptatif d'images intermédiaires (Lot G) : une application lente (> 40 ms par lot,
    /// ex. redimensionnement Electron/web 5K) ne démarre pas d'écriture intermédiaire si sa durée
    /// mesurée dépasse le temps restant avant la cible finale.
    static let slowWriteThreshold: TimeInterval = 0.04
    static func shouldRunIntermediate(estimatedWriteDuration: TimeInterval, remaining: TimeInterval) -> Bool {
        guard estimatedWriteDuration > slowWriteThreshold, remaining.isFinite else { return true }
        return estimatedWriteDuration <= remaining
    }

    static func optimizedFinalCommands(
        _ commands: [ApplyCommand],
        windows: [WindowID: WindowSnapshot],
        mayChange: (WindowSnapshot) -> Bool
    ) -> [ApplyCommand] {
        commands.map { command in
            var value = command
            let latest = windows[command.window.id] ?? command.window
            value.window = latest
            // Si aucun lot intermédiaire ne peut encore modifier la fenêtre et que la taille
            // observée correspond déjà à la cible finale (ex. échange de même taille ou déparquage
            // de stage), éviter le double `AXSize` tout en conservant position + relecture + Spec043.
            if !value.preservesSize, !value.positionsBeforeResizing,
               !mayChange(latest),
               abs(latest.frame.width - value.frame.width) <= 0.5,
               abs(latest.frame.height - value.frame.height) <= 0.5 {
                value.preservesSize = true
            }
            return value
        }
    }

    private(set) var acceptsCommands = false
    public func start() { acceptsCommands = true }
    public var isHoldingLayout: Bool { session.map { $0.permit.isCurrent && ProcessInfo.processInfo.systemUptime - $0.started < 1.5 } ?? false }

    init(generations: PlacementGeneration = .shared, events: EventLog = EventLog(),
         presentsScenes: Bool = true,
         sceneCapture: @escaping @MainActor (StageSceneContext) async -> CGImage? = { await RailThumbnailStore.shared.captureScene($0) },
         isMouseDown: @escaping () -> Bool = {
             UserInputActivity.shared.isCapturedPointerHeld || NSEvent.pressedMouseButtons != 0
         }) {
        self.generations = generations; self.events = events; self.isMouseDown = isMouseDown
        self.sceneCapture = sceneCapture; self.presentsScenes = presentsScenes
    }

    func schedule(_ plan: ApplyPlan, service: SnapshotService, generation: UInt64, action: AnimationAction,
                  immediateWindowIDs: Set<WindowID> = [], transitionDirection: Direction? = nil,
                  displays: [DisplaySnapshot]? = nil, stageScene: StageSceneContext? = nil) -> ApplyResult? {
        let policy = service.effectiveConfig.fx.animations.policy(for: action)
        guard policy.enabled, !plan.commands.isEmpty, generation == generations.current,
              generation != PlacementGeneration.outsideBudget, !isMouseDown() else { return nil }
        events.append(RoadieEvent(type: "effects.frames_policy", details: [
            "generation": String(generation), "action": action.rawValue,
            "direction": transitionDirection?.rawValue ?? "none",
            "directWindowIDs": immediateWindowIDs.sorted().map { String($0.rawValue) }.joined(separator: ","),
            "frames": plan.commands.map { command in
                let from = command.window.frame, to = command.frame
                return "\(command.window.id.rawValue):\(from.x),\(from.y),\(from.width),\(from.height)->\(to.x),\(to.y),\(to.width),\(to.height);preservesSize=\(command.preservesSize)"
            }.joined(separator: "|")
        ]))
        let isScene = stageScene != nil && transitionDirection != nil && action == .stage
        if session?.generation != generation || session?.finalSubmitted == true || session?.scene != nil || isScene {
            let retained = Set(plan.commands.map { "ax-\(ObjectIdentifier(self))-\($0.window.pid)-\($0.window.id.rawValue)" })
            // Révoquer les anciens lots sans perdre la vitesse des fenêtres reprises.
            cancel(preserving: retained, notifyEnded: false)
        }
        let current: Session
        if let existing = session { current = existing }
        else {
            current = Session(service: service, generation: generation, generations: generations)
            session = current
            events.append(RoadieEvent(type: "effects.frames_started", details: ["generation": String(generation), "action": action.rawValue]))
            current.dispatcher = InteractiveFrameDispatcher(
                service: service,
                permit: current.permit,
                allowIntermediateStart: { [weak current] _, estimated in
                    guard let current else { return false }
                    let remaining = current.expectedEnd > 0
                        ? max(0, current.expectedEnd - ProcessInfo.processInfo.systemUptime)
                        : .infinity
                    return Self.shouldRunIntermediate(estimatedWriteDuration: estimated, remaining: remaining)
                }
            ) { [weak self, weak current] result, generation in
                guard let current else { return }
                var final: [ApplyResultItem] = []
                for item in result.items {
                    if let frame = item.actual { current.windows[item.windowID]?.frame = frame }
                    if current.finalSubmitted, generation == current.generation, item.requested == current.commands[item.windowID]?.frame {
                        current.finalResults[item.windowID] = item
                        final.append(item)
                    }
                }
                if !final.isEmpty {
                    let result = ApplyResult(attempted: final.count,
                        applied: final.filter { $0.status == .applied }.count,
                        clamped: final.filter { $0.status == .clamped }.count,
                        failed: final.filter { $0.status == .failed }.count, items: final)
                    self?.onFinalResult?(result, ApplyPlan(commands: Array(current.commands.values)), current.generation)
                }
                if let self, self.session === current, current.finalSubmitted, current.dispatcher.isIdle, current.scene == nil {
                    self.cancel(completed: true)
                }
            }
            if !isScene {
                // Horloge 60 Hz unique en phase avec EffectAnimator : zéro gigue inter-timers (Lot F).
                EffectAnimator.shared.addTickObserver(id: ObjectIdentifier(self)) { [weak self] in
                    self?.pulse()
                }
            }
            let interval = isScene ? Self.frameInterval : Self.watchdogInterval
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulse() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if let stageScene, let transitionDirection, action == .stage {
            // Un changement de stage utilise uniquement les cadres finaux sous deux images.
            // Aucun aller-retour AX pour produire une image d'animation.
            current.commands = Dictionary(plan.commands.map { original in
                var command = original
                if immediateWindowIDs.contains(command.window.id) { command.positionsBeforeResizing = true }
                return (command.window.id, command)
            }, uniquingKeysWith: { _, last in last })
            current.windows = Dictionary(plan.commands.map { ($0.window.id, $0.window) }, uniquingKeysWith: { _, last in last })
            let scene = StageSceneTransition(context: stageScene, direction: transitionDirection, policy: policy,
                events: events, valid: { [weak current] in current?.permit.isCurrent == true }, submit: { [weak current] in
                    guard let current, current.permit.isCurrent else { return }
                    current.finalSubmitted = true
                    let commands = Self.optimizedFinalCommands(
                        Array(current.commands.values),
                        windows: current.windows,
                        mayChange: { current.dispatcher.mayChange($0) }
                    )
                    current.dispatcher.submit(commands, generation: current.generation)
                }, presents: presentsScenes, capture: sceneCapture)
            current.scene = scene; scene.start()
            return ApplyResult(attempted: 0, applied: 0, clamped: 0, failed: 0,
                items: plan.commands.map { ApplyResultItem(windowID: $0.window.id, status: .deferred, requested: $0.frame, actual: nil) })
        }
        if policy.curve == .spring {
            current.expectedEnd = 0
        } else {
            current.expectedEnd = max(current.expectedEnd, ProcessInfo.processInfo.systemUptime + policy.duration)
        }
        let animationDisplays = displays ?? service.cachedGestureSnapshot()?.displays ?? []
        let distance = 40 * policy.intensity
        // Repère AX : y croît vers le bas. Hors navigation, garder le déplacement gauche historique.
        let motion: CGSize = switch transitionDirection ?? .left {
        case .left: CGSize(width: -distance, height: 0)
        case .right: CGSize(width: distance, height: 0)
        case .up: CGSize(width: 0, height: -distance)
        case .down: CGSize(width: 0, height: distance)
        }
        // Préparer toutes les commandes avant de lancer EffectAnimator : une completion synchrone
        // (cible déjà atteinte ou durée nulle) ne doit jamais déclencher une soumission finale
        // partielle avant l'enregistrement des fenêtres suivantes du lot.
        var prepared: [(command: ApplyCommand, animationID: String)] = []
        prepared.reserveCapacity(plan.commands.count)
        for original in plan.commands {
            var command = original
            if immediateWindowIDs.contains(command.window.id) { command.positionsBeforeResizing = true }
            let window = command.window, id = window.id
            current.commands[id] = command
            current.windows[id] = current.windows[id] ?? window
            current.finished.remove(id)
            let animationID = "ax-\(ObjectIdentifier(self))-\(window.pid)-\(id.rawValue)"
            current.ids.insert(animationID)
            prepared.append((command, animationID))
        }
        current.isScheduling = true
        for (command, animationID) in prepared {
            let window = command.window, id = window.id
            var from = current.frames[id]?.cgRect ?? window.frame.cgRect
            var to = command.frame.cgRect
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
                || HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: animationDisplays)) {
                EffectAnimator.shared.cancel(animationID)
                current.frames[id] = command.frame
                current.finished.insert(id)
                continue
            }
            // Le parking n'est pas une destination visuelle : courte sortie puis parking final.
            if command.preservesSize { to = from.offsetBy(dx: motion.width, dy: motion.height) }
            else if !window.isOnScreen || HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: animationDisplays) {
                from = to.offsetBy(dx: -motion.width, dy: -motion.height)
            }
            EffectAnimator.shared.animate(id: animationID, from: [from.minX, from.minY, from.width, from.height],
                to: [to.minX, to.minY, to.width, to.height], policy: policy) { [weak current] values in
                current?.frames[id] = Rect(x: values[0], y: values[1], width: max(1, values[2]), height: max(1, values[3]))
            } completion: { [weak self, weak current] in
                guard let self, let current, self.session === current else { return }
                current.finished.insert(id)
                if !current.isScheduling, current.finished.count == current.commands.count { self.pulse() }
            }
        }
        current.isScheduling = false
        // La première cible ou un lot déjà achevé synchroniquement part dès maintenant.
        if !immediateWindowIDs.isEmpty || current.finished.count == current.commands.count { pulse() }
        return ApplyResult(attempted: 0, applied: 0, clamped: 0, failed: 0,
            items: plan.commands.map { ApplyResultItem(windowID: $0.window.id, status: .deferred, requested: $0.frame, actual: nil) })
    }

    /// Ne pas activer une fenêtre encore au parking pendant la capture source.
    func deferStageFocus(generation: UInt64, _ focus: @escaping () -> Void) -> Bool {
        guard let current = session, current.generation == generation, current.scene != nil else { return false }
        current.focusAfterScenePlacement = focus
        return true
    }

    private func pulse() {
        guard let current = session else { return }
        guard current.permit.isCurrent else { cancel(); return }
        let needsImmediateEnd = current.config != current.service.effectiveConfig.fx.animations
        let elapsed = ProcessInfo.processInfo.systemUptime - current.started
        guard elapsed < 1.5 else { cancel(); return }
        if let scene = current.scene {
            if needsImmediateEnd { scene.cancel(); if !current.finalSubmitted {
                current.finalSubmitted = true
                let commands = Self.optimizedFinalCommands(
                    Array(current.commands.values),
                    windows: current.windows,
                    mayChange: { current.dispatcher.mayChange($0) }
                )
                current.dispatcher.submit(commands, generation: current.generation)
            } }
            let applied = current.finalSubmitted && current.dispatcher.isIdle
            scene.pulse(applied: applied)
            if scene.phase == .finished, applied {
                // AXRaise peut attendre l'application. Le faire après les images évite
                // de bloquer leur horloge et de consommer le budget de capture cible.
                if let focus = current.focusAfterScenePlacement {
                    current.focusAfterScenePlacement = nil
                    focus()
                }
                cancel(completed: true)
            }
            return
        }
        if current.finalSubmitted {
            if current.dispatcher.isIdle { cancel(completed: true) }
            return
        }
        if current.finished.count == current.commands.count || elapsed >= 1 || needsImmediateEnd {
            current.finalSubmitted = true
            for id in current.ids { EffectAnimator.shared.cancel(id) }
            let commands = Self.optimizedFinalCommands(
                Array(current.commands.values),
                windows: current.windows,
                mayChange: { current.dispatcher.mayChange($0) }
            )
            current.dispatcher.submit(commands, generation: current.generation)
        } else {
            let remaining = current.expectedEnd > 0
                ? max(0, current.expectedEnd - ProcessInfo.processInfo.systemUptime)
                : .infinity
            let commands = current.frames.compactMap { id, frame -> ApplyCommand? in
                guard let window = current.windows[id], let final = current.commands[id],
                      !window.frame.cgRect.matchesFrame(frame.cgRect) || current.dispatcher.mayChange(window) else { return nil }
                let estimated = current.dispatcher.lastWriteDuration(for: window.pid)
                guard Self.shouldRunIntermediate(estimatedWriteDuration: estimated, remaining: remaining) else { return nil }
                return ApplyCommand(window: window, frame: frame, preservesSize: final.preservesSize,
                                    positionsBeforeResizing: final.positionsBeforeResizing)
            }
            if !commands.isEmpty {
                current.dispatcher.submit(commands, generation: PlacementGeneration.outsideBudget, intermediate: true)
            }
        }
    }

    public func stop() { acceptsCommands = false; cancel(); EffectAnimator.shared.stop() }

    public func cancel(completed: Bool = false, preserving: Set<String> = [], notifyEnded: Bool = true) {
        timer?.invalidate(); timer = nil
        EffectAnimator.shared.removeTickObserver(id: ObjectIdentifier(self))
        let hadSession = session != nil
        if let current = session {
            events.append(RoadieEvent(type: completed ? "effects.frames_completed" : "effects.frames_cancelled", details: [
                "generation": String(current.generation), "windows": String(current.commands.count),
                "durationMs": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - current.started) * 1000),
                "applied": String(current.finalResults.values.filter { $0.status == .applied }.count),
                "clamped": String(current.finalResults.values.filter { $0.status == .clamped }.count),
                "failed": String(current.finalResults.values.filter { $0.status == .failed }.count)
            ]))
            current.scene?.cancel()
            current.dispatcher?.invalidate()
            for id in current.ids.subtracting(preserving) { EffectAnimator.shared.cancel(id) }
        }
        session = nil
        if hadSession, notifyEnded {
            onTransitionEnded?()
        }
    }
}
