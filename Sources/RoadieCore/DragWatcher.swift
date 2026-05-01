import Cocoa

/// Observe `leftMouseUp` globalement pour détecter la fin d'un drag de fenêtre.
/// Strategy drop-based : on ne réagit pas pendant le drag (les notifs AX move/resize
/// fire en continu mais sont juste mémorisées par le daemon). On adapte le tiling
/// uniquement quand l'utilisateur lâche, garantissant un comportement déterministe
/// et zéro work pendant le drag.
///
/// Nécessite la même perm Input Monitoring que MouseRaiser (déjà accordée si
/// MouseRaiser tourne).
@MainActor
public final class DragWatcher {
    private let onDrop: () -> Void
    private var monitor: Any?

    public init(onDrop: @escaping () -> Void) {
        self.onDrop = onDrop
    }

    public func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            // Hop vers MainActor pour modifier l'état du daemon en sécurité.
            Task { @MainActor in self?.onDrop() }
        }
        logInfo("DragWatcher started")
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
