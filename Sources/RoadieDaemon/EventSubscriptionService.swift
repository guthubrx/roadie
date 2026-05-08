import Foundation
import RoadieCore

public struct EventSubscriptionOptions: Equatable, Sendable {
    public var fromNow: Bool
    public var initialState: Bool
    public var types: Set<String>
    public var scopes: Set<AutomationScope>

    public init(fromNow: Bool = false, initialState: Bool = false, types: Set<String> = [], scopes: Set<AutomationScope> = []) {
        self.fromNow = fromNow
        self.initialState = initialState
        self.types = types
        self.scopes = scopes
    }
}

public struct EventSubscriptionCursor: Equatable, Sendable {
    public var offset: UInt64

    public init(offset: UInt64 = 0) {
        self.offset = offset
    }
}

public struct EventSubscriptionService: Sendable {
    private let url: URL

    public init(path: String = EventLog.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public func start(options: EventSubscriptionOptions = EventSubscriptionOptions()) -> EventSubscriptionCursor {
        guard options.fromNow,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return EventSubscriptionCursor(offset: 0)
        }
        return EventSubscriptionCursor(offset: size.uint64Value)
    }

    public func initialEvents(snapshot: RoadieStateSnapshot, options: EventSubscriptionOptions) -> [RoadieEventEnvelope] {
        guard options.initialState else { return [] }
        return [
            RoadieEventEnvelope(
                id: "state_snapshot_\(Int(snapshot.generatedAt.timeIntervalSince1970 * 1000))",
                timestamp: snapshot.generatedAt,
                type: "state.snapshot",
                scope: .system,
                subject: AutomationSubject(kind: "system", id: "roadie"),
                correlationId: nil,
                cause: .system,
                payload: [
                    "activeDisplayId": snapshot.activeDisplayId.map(AutomationPayload.string) ?? .null,
                    "activeDesktopId": snapshot.activeDesktopId.map(AutomationPayload.string) ?? .null,
                    "activeStageId": snapshot.activeStageId.map(AutomationPayload.string) ?? .null,
                    "focusedWindowId": snapshot.focusedWindowId.map(AutomationPayload.string) ?? .null,
                    "displayCount": .int(snapshot.displays.count),
                    "windowCount": .int(snapshot.windows.count)
                ]
            )
        ]
    }

    public func readAvailable(from cursor: EventSubscriptionCursor, options: EventSubscriptionOptions = EventSubscriptionOptions()) -> (events: [RoadieEventEnvelope], cursor: EventSubscriptionCursor) {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return ([], cursor)
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: cursor.offset)
            let data = try handle.readToEnd() ?? Data()
            let newOffset = try handle.offset()
            guard !data.isEmpty,
                  let raw = String(data: data, encoding: .utf8)
            else {
                return ([], EventSubscriptionCursor(offset: newOffset))
            }
            let events = raw
                .split(separator: "\n")
                .compactMap { decodeEnvelope(String($0)) }
                .filter { event in
                    (options.types.isEmpty || options.types.contains(event.type)) &&
                    (options.scopes.isEmpty || event.scope.map { options.scopes.contains($0) } == true)
                }
            return (events, EventSubscriptionCursor(offset: newOffset))
        } catch {
            return ([], cursor)
        }
    }

    private func decodeEnvelope(_ line: String) -> RoadieEventEnvelope? {
        guard let data = line.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let envelope = try? decoder.decode(RoadieEventEnvelope.self, from: data) {
            return envelope
        }
        if let legacy = try? decoder.decode(RoadieEvent.self, from: data) {
            return RoadieEventEnvelope(legacy: legacy)
        }
        return nil
    }
}
