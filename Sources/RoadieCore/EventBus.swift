import Foundation

/// Event émis sur le canal subscription (`roadie events --follow`).
/// Format JSON-lines (1 event = 1 ligne JSON), spécifié dans contracts/events-stream.md.
public struct DesktopEvent: Sendable {
    public let name: String
    public let ts: Date
    public let payload: [String: String]

    public init(name: String, ts: Date = Date(), payload: [String: String] = [:]) {
        self.name = name
        self.ts = ts
        self.payload = payload
    }

    /// Schema version (V2 = 1). Bump si on renomme/retire un champ d'un event existant.
    public static let schemaVersion: Int = 1

    /// Sérialise en 1 ligne JSON terminée par `\n`. Champs communs : `event`, `ts`, `version`.
    public func toJSONLine() -> String {
        var dict: [String: Any] = [
            "event": name,
            "ts": isoFormatter.string(from: ts),
            "version": Self.schemaVersion,
        ]
        for (k, v) in payload { dict[k] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"event\":\"\(name)\"}\n"
        }
        return s + "\n"
    }
}

/// Pub/sub minimal pour les événements internes (stage_changed, etc.).
/// Multiple subscribers possibles, tous reçoivent tous les events.
@MainActor
public final class EventBus {
    public static let shared = EventBus()

    private var continuations: [UUID: AsyncStream<DesktopEvent>.Continuation] = [:]

    public init() {}

    /// Ouvre un nouveau flux. Le subscriber doit consommer en boucle ; en cas de
    /// disparition (Task cancelled), `onTermination` retire la continuation.
    public func subscribe() -> AsyncStream<DesktopEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Publie un event vers tous les subscribers actifs. No-op si aucun.
    public func publish(_ event: DesktopEvent) {
        for cont in continuations.values {
            cont.yield(event)
        }
    }

    public var subscriberCount: Int { continuations.count }
}

/// Formatter ISO8601 partagé (millisecondes UTC, conforme contracts).
private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
