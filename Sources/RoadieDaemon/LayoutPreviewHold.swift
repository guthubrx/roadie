import Foundation
import os

/// Suspension de la disposition pendant l'aperçu actif du lanceur (SPEC-078) : la passe sort tôt,
/// comme pendant Mission Control (SPEC-062), sans relevé ni écriture, pour ne pas défaire les cadres
/// de l'aperçu. L'échéance est courte et renouvelée par le contrôleur : si la barre disparaît sans
/// terminer l'aperçu, la disposition reprend seule. Partagée dans le processus, sous verrou.
public final class LayoutPreviewHold: Sendable {
    public static let shared = LayoutPreviewHold()
    /// Durée d'un maintien sans renouvellement.
    public static let lease: TimeInterval = 1.5

    private let until = OSAllocatedUnfairLock<Date?>(initialState: nil)

    public init() {}

    public func hold(for duration: TimeInterval = LayoutPreviewHold.lease, now: Date = Date()) {
        until.withLock { $0 = now.addingTimeInterval(duration) }
    }

    public func release() {
        until.withLock { $0 = nil }
    }

    public func isHeld(at now: Date = Date()) -> Bool {
        until.withLock { $0.map { now < $0 } ?? false }
    }
}
