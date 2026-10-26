import AppKit
import Foundation
import RoadieAX

/// Ordonnanceur unique des passes du tiler, sur le thread principal (SPEC-017 R5, A1, A6, A12, A20).
/// - Aucun événement perdu : une demande rejoint la demande en attente, l'échéance la plus proche gagne.
/// - Regroupement court : 15 ms pour un événement, 30 ms pour un changement externe de frame.
/// - Aucune passe tant qu'une attente bloque (bouton de souris enfoncé, écran en reconfiguration,
///   veille). La demande reste en attente ; elle part au déblocage (relâchement, fin de « heal »,
///   réveil) ou au filet périodique.
/// - Un seul minuteur, armé sur la plus proche de deux échéances : la demande en attente et
///   l'échéance interne du maintainer (`nextDeadline`, réelle même passée). Il est réarmé après
///   chaque passe, et après une commande appliquée sur un arbre (`rearm`, T219).
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

    /// Plancher d'une échéance interne, appliqué seulement à l'armement du minuteur (T211) : une
    /// échéance que la passe ne solde pas ne peut pas emballer la boucle au-delà d'environ
    /// 66 passes par seconde.
    static let minimumDeadlineDelay: TimeInterval = 0.015

    private struct Pending {
        var cause: String
        var dueAt: Date
        var requestedAt: Date
        var coalescing: Coalescing
        /// Premier déclenchement retenu par une attente (bouton enfoncé, écrans), pour `live_tick`.
        var heldSince: Date?
    }

    private let tick: @MainActor (String) -> MaintenanceTick
    private let nextDeadline: @MainActor (Date) -> Date?
    private let isBlocked: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let schedule: Schedule
    private let episodes: EpisodeContext
    private let events: EventLog?
    /// Changement observé (SPEC-048) : toute demande hors filet périodique signale aux lecteurs
    /// que le dernier relevé publié peut être périmé.
    private let onObservationChange: @MainActor () -> Void
    private var pending: Pending?
    /// Échéance interne sur laquelle le minuteur est armé, et instant de l'armement. `fire()` la
    /// déclenche même si le maintainer ne la rend plus (échéance future seulement, T211).
    private var armedDeadline: (due: Date, armedAt: Date)?
    private var cancelTimer: (() -> Void)?

    public init(
        tick: @escaping @MainActor (String) -> MaintenanceTick,
        nextDeadline: @escaping @MainActor (Date) -> Date?,
        isBlocked: @escaping @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        now: @escaping @MainActor () -> Date = { Date() },
        schedule: @escaping Schedule = TickScheduler.dispatchAfter,
        episodes: EpisodeContext = .shared,
        events: EventLog? = EventLog(),
        onObservationChange: @escaping @MainActor () -> Void = {}
    ) {
        self.onObservationChange = onObservationChange
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
        if coalescing != .safetyNet { onObservationChange() }
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
        request(cause: "drag", delay: .event)
    }

    /// Réarme le minuteur sans passe (T219) : une commande vient d'appliquer un arbre et le
    /// maintainer en suit les échéances (refus, stabilité). O(1) hors `nextDeadline`.
    public func rearm() {
        arm()
    }

    /// Minuteur échu : une passe pour la demande échue, sinon pour l'échéance interne armée si
    /// elle est échue (T211). Bloqué, il garde tout en attente et ne réarme pas (pas de boucle) :
    /// le déblocage réarme.
    private func fire() {
        cancelTimer = nil
        let date = now()
        guard !isBlocked() else {
            if pending?.heldSince == nil { pending?.heldSince = date }
            return
        }
        if let current = pending, current.dueAt <= date {
            pending = nil
            run(current.cause, requested: current, due: current.dueAt, requestedDelay: current.coalescing.delay, at: date)
        } else if let deadline = armedDeadline, deadline.due <= date {
            // Échéance armée par l'épisode en cours (garde, refus, rafale) : il reste ouvert (A20).
            // Le maintainer la nomme (`deadline:<nom>`, contrat des événements).
            episodes.continue()
            run("deadline", requested: nil, due: deadline.due, requestedDelay: deadline.due.timeIntervalSince(deadline.armedAt), at: date)
        }
        arm()
    }

    /// Un seul minuteur, sur l'échéance la plus proche. Le plancher s'applique ici seulement :
    /// l'échéance gardée pour `fire()` reste la vraie (T211). O(1) hors `nextDeadline`.
    private func arm() {
        cancelTimer?()
        cancelTimer = nil
        let date = now()
        armedDeadline = nextDeadline(date).map { ($0, date) }
        let floored = armedDeadline.map { max($0.due, date.addingTimeInterval(Self.minimumDeadlineDelay)) }
        guard let due = [pending?.dueAt, floored].compactMap({ $0 }).min() else { return }
        cancelTimer = schedule(max(0, due.timeIntervalSince(date))) { [weak self] in self?.fire() }
    }

    /// Passe, puis trace `live_tick` (latence depuis la demande, durée) comme avant la SPEC-017,
    /// pour comparer les mesures avec le même outil (Article XXII). La latence se décompose
    /// (T221) : délai demandé (regroupement ou échéance), retenue par une attente (bouton
    /// enfoncé), retard d'exécution après l'échéance (file principale). Une passe d'une seconde
    /// ou plus nomme les applications qui ont fait attendre ses appels AX (SPEC-086).
    private func run(_ cause: String, requested: Pending?, due: Date, requestedDelay: TimeInterval, at start: Date) {
        AXCallTimings.shared.reset()
        let result = tick(cause)
        guard let events else { return }
        let isEvent = requested.map { $0.coalescing != .safetyNet } ?? false
        let duration = now().timeIntervalSince(start)
        let slowApps = duration >= 1 ? AXCallTimings.shared.drainSlowest(minimumSeconds: 0.2, limit: 3) : ""
        guard isEvent || result.commands > 0 || result.failed > 0 || !slowApps.isEmpty else { return }
        let ms = { (seconds: TimeInterval) in String(format: "%.1f", max(0, seconds) * 1000) }
        var details = [
            "notification": cause,
            "fast": String(requested?.coalescing == .event),
            "requestedDelayMs": ms(requestedDelay),
            "dueLagMs": ms(start.timeIntervalSince(due)),
            "heldByGestureMs": ms(requested?.heldSince.map { start.timeIntervalSince($0) } ?? 0),
            "latencyMs": ms(requested.map { start.timeIntervalSince($0.requestedAt) } ?? 0),
            "durationMs": ms(duration),
            "commands": String(result.commands),
            "applied": String(result.applied),
            "failed": String(result.failed),
        ]
        if !slowApps.isEmpty { details["axSlowApps"] = slowApps }
        events.append(RoadieEvent(type: "live_tick", details: details))
    }

    /// Minuterie de production : file principale.
    public nonisolated static func dispatchAfter(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
