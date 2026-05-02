import Foundation

// MARK: - DesktopChangeEvent

/// Event émis sur le canal events à chaque transition de desktop (R-007, FR-016).
/// Format JSON-lines, sérialisé avec les champs du contrat events-stream.md.
public struct DesktopChangeEvent: Sendable {
    public let event: String
    public let from: String
    public let to: String
    public let fromLabel: String
    public let toLabel: String
    public let desktopID: String   // utilisé pour stage_changed
    public let ts: Int64

    public init(event: String, from: String, to: String,
                fromLabel: String = "", toLabel: String = "",
                desktopID: String = "",
                ts: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.event = event
        self.from = from
        self.to = to
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.desktopID = desktopID
        self.ts = ts
    }

    /// Sérialise en JSON-line terminée par `\n`.
    /// Contrat events-stream.md :
    ///   desktop_changed → from, to, from_label?, to_label?, ts
    ///   stage_changed   → desktop_id, from, to, ts
    public func toJSONLine() -> String {
        var dict: [String: Any] = ["event": event, "from": from, "to": to, "ts": ts]
        if event == "stage_changed" {
            dict["desktop_id"] = desktopID
        } else {
            if !fromLabel.isEmpty { dict["from_label"] = fromLabel }
            if !toLabel.isEmpty { dict["to_label"] = toLabel }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"event\":\"\(event)\",\"from\":\"\(from)\",\"to\":\"\(to)\"}\n"
        }
        return s + "\n"
    }
}

// MARK: - DesktopEventBus

/// Actor pub/sub pour les events desktop_changed.
/// Plusieurs subscribers (AsyncStream) peuvent coexister — chacun reçoit tous les events (R-007).
public actor DesktopEventBus {
    private var continuations: [UUID: AsyncStream<DesktopChangeEvent>.Continuation] = [:]

    public init() {}

    /// Publie un event vers tous les subscribers actifs.
    /// M1 : si une continuation retourne `.dropped` (terminée), on l'identifie
    /// et on la retire pour éviter de re-tenter lors des publications suivantes.
    public func publish(_ event: DesktopChangeEvent) {
        var dead: [UUID] = []
        for (id, cont) in continuations {
            if case .dropped = cont.yield(event) {
                dead.append(id)
            }
        }
        for id in dead {
            continuations.removeValue(forKey: id)
        }
    }

    /// Ouvre un flux pour un subscriber. Le subscriber doit itérer sur le stream ;
    /// quand la Task est annulée, `onTermination` retire automatiquement la continuation.
    public func subscribe() -> AsyncStream<DesktopChangeEvent> {
        let id = UUID()
        // Swift 6 : `onTermination` est un closure @Sendable exécuté hors isolation de
        // l'actor. La capture `[weak self]` introduit un warning Sendable strict car `self`
        // est un actor. Solution : capturer `self` comme référence forte — un actor étant
        // une classe, la capture forte est sûre (pas de cycle de rétention ici, le stream
        // ne vit pas plus longtemps que le bus en pratique). `id` est capturé par valeur.
        let busCapture: DesktopEventBus = self
        return AsyncStream { continuation in
            continuation.onTermination = { _ in
                Task {
                    await busCapture.removeContinuation(id: id)
                }
            }
            Task {
                await busCapture.addContinuation(id: id, continuation: continuation)
            }
        }
    }

    private func addContinuation(id: UUID,
                                 continuation: AsyncStream<DesktopChangeEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    public var subscriberCount: Int { continuations.count }
}
