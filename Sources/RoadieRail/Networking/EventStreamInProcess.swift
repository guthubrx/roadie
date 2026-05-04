import Foundation
import RoadieCore

// SPEC-024 — Subscriber direct au EventBus partagé du daemon.
// Remplace EventStream (qui spawnait `roadie events --follow` en sous-process et
// parsait du JSON-lines via Pipe). En mode mono-binaire, le rail vit dans le
// même process que le daemon : on consomme directement les `DesktopEvent` Swift
// publiés sur `EventBus.shared`, zéro sérialisation, zéro round-trip socket.
//
// L'API publique reste identique à EventStream pour ne pas changer les call-sites
// du RailController : `onEvent: ((String, [String: Any]) -> Void)?`, `start()`,
// `stop()`. Le payload est promu de [String: String] (DesktopEvent) à
// [String: Any] pour matcher la signature attendue.

@MainActor
final class EventStreamInProcess {
    var onEvent: ((String, [String: Any]) -> Void)?

    private var task: Task<Void, Never>?

    /// Démarre la subscription. Boucle Async/Await sur `EventBus.shared.subscribe()`.
    func start() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            for await event in EventBus.shared.subscribe() {
                guard let self = self else { return }
                // DesktopEvent.payload est [String: String] ; on le promeut à
                // [String: Any] pour préserver la signature attendue par le rail.
                let payloadAny: [String: Any] = event.payload.reduce(into: [:]) { acc, kv in
                    acc[kv.key] = kv.value
                }
                self.onEvent?(event.name, payloadAny)
            }
        }
    }

    /// Annule la Task de subscription. La continuation `EventBus.shared` est
    /// retirée automatiquement via `onTermination` du AsyncStream.
    func stop() {
        task?.cancel()
        task = nil
    }
}
