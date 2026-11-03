import AppKit
import QuartzCore
import RoadieAX
import RoadieCore

/// Contexte issu du relevé de commande ; aucune lecture AX pendant le rendu.
public struct StageSceneContext: Sendable {
    let display: DisplaySnapshot
    let frame: CGRect
    let stationary: [CGRect]

    /// Soustractions successives : les trous qui se chevauchent ne se remplissent pas.
    func maskPath() -> CGPath {
        var path = CGPath(rect: CGRect(origin: .zero, size: frame.size), transform: nil)
        for stationaryFrame in stationary {
            let rect = stationaryFrame.intersection(frame)
            guard !rect.isNull, !rect.isEmpty else { continue }
            path = path.subtracting(CGPath(rect: CGRect(x: rect.minX - frame.minX,
                y: frame.maxY - rect.maxY, width: rect.width, height: rect.height), transform: nil))
        }
        return path
    }
}

/// Deux captures au maximum, jamais une capture par image. Le writer commun applique
/// les vraies fenêtres une fois, sous le panneau ; un clic peut donc révéler la scène finale.
@MainActor
final class StageSceneTransition {
    enum Phase { case source, applying, target, animating, finished }
    private(set) var phase: Phase = .source
    private let context: StageSceneContext
    private let direction: Direction
    private let policy: MotionPolicy
    private let capture: @MainActor (StageSceneContext) async -> CGImage?
    private let valid: () -> Bool
    private let submit: () -> Void
    private let events: EventLog
    private let clock: () -> Double
    private let presents: Bool
    private var deadline: Double
    private var panel: StageScenePanel?
    private let animationID = "stage-scene-\(UUID().uuidString)"
    private var submitted = false
    private var progress = 0.0
    private var began: Double

    init(context: StageSceneContext, direction: Direction, policy: MotionPolicy,
         events: EventLog, valid: @escaping () -> Bool, submit: @escaping () -> Void,
         presents: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         capture: @escaping @MainActor (StageSceneContext) async -> CGImage? = {
             await RailThumbnailStore.shared.captureScene($0)
         }) {
        self.context = context; self.direction = direction; self.policy = policy
        self.events = events; self.valid = valid; self.submit = submit
        self.presents = presents; self.clock = clock; self.capture = capture
        began = clock(); deadline = began + 0.12
    }

    func start() {
        Task { [weak self] in
            guard let self, phase == .source, valid() else { return }
            guard clock() <= deadline else { fallback("source_late"); return }
            let image = await capture(context)
            log("capture_source", milliseconds: (clock() - began) * 1000)
            guard phase == .source, valid() else { return }
            guard clock() <= deadline else { fallback("source_late"); return }
            guard let image else { fallback("source_nil"); return }
            if presents { panel = StageScenePanel(context: context, source: image) }
            phase = .applying; deadline = clock() + 0.2
            log("source", milliseconds: (clock() - began) * 1000)
            submitOnce()
            beginAnimation()
        }
    }

    /// Appelé par le minuteur existant du runtime. Les délais ne dépendent pas
    /// du retour d'une capture lente : une tâche tardive ne peut réafficher le panneau.
    func pulse(applied: Bool) {
        guard phase != .finished else { return }
        guard valid() else { cancel(); return }
        if phase != .animating, clock() > deadline { fallback("deadline"); return }
        guard phase == .applying, applied else { return }
        phase = .target
        Task { [weak self] in
            guard let self else { return }
            // Laisser WindowServer présenter les dernières écritures AX.
            try? await Task.sleep(for: .milliseconds(16))
            guard phase == .target, valid() else { return }
            let started = clock()
            let target = await capture(context)
            log("capture_target", milliseconds: (clock() - started) * 1000)
            guard phase == .target, valid() else { return }
            guard clock() <= deadline else { fallback("target_late"); return }
            guard let target else { fallback("target_nil"); return }
            log("target", milliseconds: (clock() - started) * 1000)
            phase = .animating
            panel?.setTarget(target)
            panel?.update(progress: progress, direction: direction, distance: 40 * policy.intensity)
        }
    }

    private func beginAnimation() {
        EffectAnimator.shared.animate(id: animationID, from: [0], to: [1], policy: policy) { [weak self] values in
            guard let self, valid() else { self?.cancel(); return }
            progress = values[0]
            panel?.update(progress: progress, direction: direction, distance: 40 * policy.intensity)
        } completion: { [weak self] in
            guard let self else { return }
            log("completed", milliseconds: (clock() - began) * 1000)
            close()
        }
    }

    func cancel() {
        EffectAnimator.shared.cancel(animationID)
        close()
    }
    private func fallback(_ reason: String) {
        events.append(RoadieEvent(type: "effects.scene_direct", details: ["reason": reason]))
        cancel()
        if valid() { submitOnce() }
    }
    private func submitOnce() {
        guard !submitted else { return }
        submitted = true; submit()
    }
    private func close() {
        phase = .finished
        panel?.releaseImages(); panel?.orderOut(nil); panel?.contentView = nil; panel = nil
    }
    private func log(_ stage: String, milliseconds: Double) {
        events.append(RoadieEvent(type: "effects.scene_\(stage)", details: [
            "durationMs": String(format: "%.1f", milliseconds), "direction": direction.rawValue
        ]))
    }
}

@MainActor
private final class StageScenePanel: NSPanel {
    private let outgoing = CALayer()
    private let incoming = CALayer()
    private let size: CGSize
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(context: StageSceneContext, source: CGImage) {
        size = context.frame.size
        super.init(contentRect: RoadieScreenCoordinate.axRectToNS(context.frame),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hasShadow = false; ignoresMouseEvents = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        let root = CALayer(); root.frame = view.bounds; root.masksToBounds = true
        view.layer = root; contentView = view
        outgoing.frame = view.bounds; outgoing.contents = source; outgoing.contentsGravity = .resize
        incoming.frame = view.bounds; incoming.opacity = 0; incoming.contentsGravity = .resize
        root.addSublayer(outgoing); root.addSublayer(incoming)
        // Les fenêtres épinglées ou non déplacées restent réelles, sans translation.
        let mask = CAShapeLayer(); mask.path = context.maskPath(); mask.fillRule = .nonZero; root.mask = mask
        orderFrontRegardless()
    }
    func releaseImages() { outgoing.contents = nil; incoming.contents = nil }
    func setTarget(_ image: CGImage) { incoming.contents = image }
    func update(progress: Double, direction: Direction, distance: Double) {
        let p = min(1, max(0, progress))
        // CALayer utilise ici le repère AppKit : y croît vers le haut.
        let motion: CGSize = switch direction {
        case .up: CGSize(width: 0, height: distance)
        case .down: CGSize(width: 0, height: -distance)
        case .left: CGSize(width: -distance, height: 0)
        case .right: CGSize(width: distance, height: 0)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outgoing.setAffineTransform(CGAffineTransform(translationX: motion.width * p, y: motion.height * p))
        incoming.setAffineTransform(CGAffineTransform(translationX: -motion.width * (1-p), y: -motion.height * (1-p)))
        incoming.opacity = Float(p)
        CATransaction.commit()
    }
}
