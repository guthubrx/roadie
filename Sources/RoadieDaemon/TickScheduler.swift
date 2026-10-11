import AppKit
import Foundation

/// Ordonnanceur unique des passes du tiler, sur le thread principal (SPEC-017 R5, A1, A6, A12, A20).
/// - Aucun événement perdu : une demande rejoint la demande en attente, l'échéance la plus proche gagne.
/// - Regroupement court : 15 ms pour un événement, 30 ms pour un changement externe de frame.
/// - Aucune passe tant qu'une attente bloque (bouton de souris enfoncé, écran en reconfiguration,
///   veille). La demande reste en attente ; elle part au déblocage (relâchement, fin de « heal »,
///   réveil) ou au filet périodique.
/// - Un seul minuteur, armé sur la plus proche de deux échéances : la demande en attente et
///   l'échéance interne du maintainer (`nextDeadline`). Il est réarmé après chaque passe.
/// - Pas de passe de suite parce qu'une passe « a agi » (A1) : seuls un nouvel événement ou une
///   échéance identifiée en déclenchent une.
@MainActor
public final class TickScheduler {
    public enum Coalescing: Sendable {
        /// Création, destruction, focus, fin de geste, changement de bureau ou d'application : 15 ms.
        case event
        /// Déplacement ou redimensionnement non écho (changement externe) : 30 ms.
        case externalChange
        /// Filet périodique : immédiat, n'ouvre pas d'épisode.
        case safetyNet

        var delay: TimeInterval {
            switch self {
            case .event: 0.015
            case .externalChange: 0.030
            case .safetyNet: 0
            }
        }
    }

    /// Programme `action` après le délai donné ; renvoie de quoi l'annuler.
    public typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    /// Plancher d'une échéance interne : une échéance déjà passée après une passe (erreur du
    /// maintainer) ne peut pas emballer la boucle au-delà d'environ 66 passes par seconde.
    static let minimumDeadlineDelay: TimeInterval = 0.015

    private struct Pending {
        var cause: String
        var dueAt: Date
        var requestedAt: Date
        var coalescing: Coalescing
    }

    private let tick: @MainActor (String) -> MaintenanceTick
    private let nextDeadline: @MainActor (Date) -> Date?
    private let isBlocked: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let schedule: Schedule
    private let episodes: EpisodeContext
    private let events: EventLog?
    private var pending: Pending?
    private var cancelTimer: (() -> Void)?

    public init(
        tick: @escaping @MainActor (String) -> MaintenanceTick,
        nextDeadline: @escaping @MainActor (Date) -> Date?,
        isBlocked: @escaping @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        now: @escaping @MainActor () -> Date = { Date() },
        schedule: @escaping Schedule = TickScheduler.dispatchAfter,
        episodes: EpisodeContext = .shared,
        events: EventLog? = EventLog()
    ) {
        self.tick = tick
        self.nextDeadline = nextDeadline
        self.isBlocked = isBlocked
        self.now = now
        self.schedule = schedule
        self.episodes = episodes
        self.events = events
    }

    /// Demande une passe. Un événement ouvre un épisode (ou prolonge celui de la demande en
    /// attente) ; un changement externe prolonge l'épisode ouvert, car c'est souvent la réponse
    /// d'une application à notre écriture (A12). La cause gardée est la première de la demande,
    /// sauf une cause du filet, remplacée par un événement. O(1) hors `nextDeadline`.
    public func request(cause: String, delay coalescing: Coalescing = .event) {
        let date = now()
        switch coalescing {
        case .event:
            if pending == nil || pending?.coalescing == .safetyNet {
                episodes.begin(cause: cause)
            } else {
                episodes.continue()
            }
        case .externalChange:
            if episodes.continue() == nil { episodes.begin(cause: cause) }
        case .safetyNet:
            break
        }
        let dueAt = date.addingTimeInterval(coalescing.delay)
        if var current = pending {
            current.dueAt = min(current.dueAt, dueAt)
            if current.coalescing == .safetyNet, coalescing != .safetyNet {
                current = Pending(cause: cause, dueAt: current.dueAt, requestedAt: date, coalescing: coalescing)
            }
            pending = current
        } else {
            pending = Pending(cause: cause, dueAt: dueAt, requestedAt: date, coalescing: coalescing)
        }
        arm()
    }

    /// Relâchement de tous les boutons (A4, A11). Une fin de geste sur une fenêtre gérée, ou une
    /// demande retenue pendant l'appui, donne une passe 15 ms plus tard, le temps que les autres
    /// moniteurs du même relâchement (dépôt du glisser) aient agi. Sinon, seules les échéances
    /// internes retenues pendant l'appui sont réarmées.
    public func buttonsReleased(gestureEnded: Bool) {
        guard gestureEnded || pending != nil else {
            arm()
            return
        }
        let releaseDue = now().addingTimeInterval(Coalescing.event.delay)
        if var current = pending {
            current.dueAt = max(current.dueAt, releaseDue)
            pending = current
        }
        request(cause: "gesture_end", delay: .event)
    }

    /// Minuteur échu : une passe pour la demande échue, sinon pour l'échéance interne échue.
    /// Bloqué, il garde tout en attente et ne réarme pas (pas de boucle) : le déblocage réarme.
    private func fire() {
        cancelTimer = nil
        guard !isBlocked() else { return }
        let date = now()
        if let current = pending, current.dueAt <= date {
            pending = nil
            run(current.cause, requested: current, at: date)
        } else if let deadline = nextDeadline(date), deadline <= date {
            // Échéance armée par l'épisode en cours (garde, refus, rafale) : il reste ouvert (A20).
            episodes.continue()
            run("deadline", requested: nil, at: date)
        }
        arm()
    }

    /// Un seul minuteur, sur l'échéance la plus proche. O(1) hors `nextDeadline`.
    private func arm() {
        cancelTimer?()
        cancelTimer = nil
        let date = now()
        var due = pending?.dueAt
        if let deadline = nextDeadline(date) {
            let floored = max(deadline, date.addingTimeInterval(Self.minimumDeadlineDelay))
            due = min(due ?? floored, floored)
        }
        guard let due else { return }
        cancelTimer = schedule(max(0, due.timeIntervalSince(date))) { [weak self] in self?.fire() }
    }

    /// Passe, puis trace `live_tick` (latence depuis la demande, durée) comme avant la SPEC-017,
    /// pour comparer les mesures avec le même outil (Article XXII).
    private func run(_ cause: String, requested: Pending?, at start: Date) {
        let result = tick(cause)
        guard let events else { return }
        let isEvent = requested.map { $0.coalescing != .safetyNet } ?? false
        guard isEvent || result.commands > 0 || result.failed > 0 else { return }
        events.append(RoadieEvent(type: "live_tick", details: [
            "notification": cause,
            "fast": String(requested?.coalescing == .event),
            "delayMs": String(format: "%.1f", (requested?.coalescing.delay ?? 0) * 1000),
            "latencyMs": String(format: "%.1f", requested.map { start.timeIntervalSince($0.requestedAt) * 1000 } ?? 0),
            "durationMs": String(format: "%.1f", now().timeIntervalSince(start) * 1000),
            "commands": String(result.commands),
            "applied": String(result.applied),
            "failed": String(result.failed),
        ]))
    }

    /// Minuterie de production : file principale.
    public nonisolated static func dispatchAfter(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
