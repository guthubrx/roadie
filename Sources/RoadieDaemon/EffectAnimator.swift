import AppKit
import RoadieCore

/// Horloge commune aux surfaces Roadie et aux cibles AX. Aucune ressource au repos.
/// O(k) par image ; un seul état courant et une seule cible par identifiant.
@MainActor
final class EffectAnimator {
    static let shared = EffectAnimator()
    private struct Transition {
        var states: [MotionValue]
        var from: [Double]
        var target: [Double]
        var started: Double
        var previous: Double
        var policy: MotionPolicy
        var update: ([Double]) -> Void
        var completion: () -> Void
    }
    private var transitions: [String: Transition] = [:]
    private var timer: Timer?
    private let clock: () -> Double
    private let schedulesTimer: Bool
    var activeCount: Int { transitions.count }
    var hasTimer: Bool { timer != nil }

    init(schedulesTimer: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.schedulesTimer = schedulesTimer; self.clock = clock
    }

    func animate(id: String, from: [Double], to target: [Double], policy: MotionPolicy,
                 update: @escaping ([Double]) -> Void, completion: @escaping () -> Void = {}) {
        guard from.count == target.count, !target.isEmpty,
              from.allSatisfy(\.isFinite), target.allSatisfy(\.isFinite) else { return }
        let old = transitions.removeValue(forKey: id)
        let states = old?.states.count == target.count ? old!.states : from.map { MotionValue(value: $0) }
        let moves = states.indices.contains { states[$0].value != target[$0] || (policy.curve == .spring && states[$0].velocity != 0) }
        guard policy.enabled, policy.curve == .spring || policy.duration > 0, moves else {
            stopTimerIfIdle(); update(target); completion(); return
        }
        let now = clock()
        transitions[id] = Transition(states: states, from: states.map(\.value), target: target,
                                     started: now, previous: now, policy: policy, update: update, completion: completion)
        update(states.map(\.value))
        if schedulesTimer, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func cancel(_ id: String) { transitions.removeValue(forKey: id); stopTimerIfIdle() }
    func stop() { transitions.removeAll(); stopTimerIfIdle() }

    /// Une nouvelle politique termine les effets courants à leur cible, sans retuilage.
    /// Retirer l'état avant les callbacks permet à ceux-ci de démarrer un nouvel effet.
    func finishAll() {
        let current = transitions
        transitions.removeAll()
        stopTimerIfIdle()
        for item in current.values { item.update(item.target); item.completion() }
    }

    /// Point d'entrée déterministe pour tests. Retire l'état avant les callbacks de fin réentrants.
    func tick() {
        let now = clock()
        for id in Array(transitions.keys) {
            guard var item = transitions[id] else { continue }
            let elapsed = max(0, now - item.started)
            var done = false
            if item.policy.curve == .spring {
                for i in item.states.indices {
                    item.states[i].advance(toward: item.target[i], dt: max(0, now - item.previous),
                        stiffness: item.policy.stiffness, damping: 1 + (item.policy.damping - 1) * item.policy.intensity)
                }
                done = elapsed >= 1 || item.states.indices.allSatisfy {
                    abs(item.states[$0].value - item.target[$0]) < 0.001 && abs(item.states[$0].velocity) < 0.001
                }
            } else {
                let duration = item.policy.duration
                let time = min(1, duration > 0 ? elapsed / duration : 1)
                let progress = time + (item.policy.curve.progress(time) - time) * item.policy.intensity
                for i in item.states.indices {
                    let previous = item.states[i].value
                    item.states[i].value = item.from[i] + (item.target[i] - item.from[i]) * progress
                    let dt = now - item.previous
                    item.states[i].velocity = dt > 0 ? (item.states[i].value - previous) / dt : 0
                }
                done = elapsed >= duration
            }
            item.previous = now
            if done { transitions.removeValue(forKey: id) }
            else { transitions[id] = item }
            item.update(done ? item.target : item.states.map(\.value))
            if done { item.completion() }
        }
        stopTimerIfIdle()
    }

    private func stopTimerIfIdle() {
        if transitions.isEmpty { timer?.invalidate(); timer = nil }
    }

    static func policy(_ action: AnimationAction, legacyDuration: Double? = nil) -> MotionPolicy {
        let config = ConfigReloadService.shared.currentConfig().fx.animations
        return config.policy(for: action, legacyDuration: legacyDuration)
    }

    func frame(_ window: NSWindow, to target: CGRect, action: AnimationAction, legacyDuration: Double? = nil, completion: @escaping () -> Void = {}) {
        let source = window.frame
        animate(id: "frame-\(window.windowNumber)", from: [source.minX, source.minY, source.width, source.height],
                to: [target.minX, target.minY, target.width, target.height],
                policy: Self.policy(action, legacyDuration: legacyDuration)) { [weak window] values in
            window?.setFrame(CGRect(x: values[0], y: values[1], width: max(1, values[2]), height: max(1, values[3])), display: true)
        } completion: { completion() }
    }

    /// La restitution du clavier appartient à l'appelant et n'attend jamais ce fondu décoratif.
    func visibility(_ window: NSWindow, visible: Bool, action: AnimationAction, ignoresMouseEvents: Bool = false, completion: @escaping () -> Void = {}) {
        let policy = ConfigReloadService.shared.currentConfig().fx.animations.policy(for: action, usesAppearanceDefaults: true)
        let id = "visibility-\(window.windowNumber)"
        if visible {
            let wasVisible = window.isVisible
            window.ignoresMouseEvents = ignoresMouseEvents
            if !wasVisible { window.alphaValue = policy.enabled ? max(0, 1 - policy.intensity) : 1 }
            window.orderFrontRegardless()
        } else {
            window.resignKey()
            window.ignoresMouseEvents = true
        }
        animate(id: id, from: [window.alphaValue], to: [visible ? 1 : 0], policy: policy,
                update: { [weak window] values in window?.alphaValue = min(1, max(0, values[0])) }, completion: { withExtendedLifetime(window) { completion() } })
    }
}
