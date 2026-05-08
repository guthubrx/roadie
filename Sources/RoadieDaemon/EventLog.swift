import Foundation
import RoadieCore

public struct RoadieEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var type: String
    public var scope: StageScope?
    public var details: [String: String]

    public init(
        type: String,
        scope: StageScope? = nil,
        details: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.timestamp = timestamp
        self.type = type
        self.scope = scope
        self.details = details
    }
}

public extension RoadieEventEnvelope {
    init(legacy event: RoadieEvent) {
        let sanitizedType = event.type
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let milliseconds = Int(event.timestamp.timeIntervalSince1970 * 1000)
        let payload = event.details.mapValues { AutomationPayload.string($0) }
        let subject = event.scope.map {
            AutomationSubject(kind: "stage", id: $0.description)
        }
        self.init(
            schemaVersion: 1,
            id: "legacy_\(milliseconds)_\(sanitizedType)",
            timestamp: event.timestamp,
            type: event.type,
            scope: event.scope == nil ? nil : .stage,
            subject: subject,
            correlationId: nil,
            cause: .system,
            payload: payload
        )
    }
}

public struct EventLog: Sendable {
    private let url: URL
    private static let jsonNewline = Data("\n".utf8)

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-events-\(ProcessInfo.processInfo.processIdentifier).jsonl"
        }
        return "~/.roadies/events.jsonl"
    }

    public func append(_ event: RoadieEvent) {
        write(event)
    }

    public func append(_ event: RoadieEventEnvelope) {
        write(event)
    }

    private func write<T: Encodable>(_ value: T) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Self.jsonNewline)
                try handle.close()
            } else {
                try (data + Self.jsonNewline).write(to: url, options: .atomic)
            }
        } catch {
            fputs("roadie: failed to write event log: \(error)\n", stderr)
        }
    }

    public func tail(limit: Int = 20) -> [String] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = raw.split(separator: "\n").map(String.init)
        return Array(lines.suffix(max(1, limit)))
    }

    public func envelopes(limit: Int = 20) -> [RoadieEventEnvelope] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return tail(limit: limit).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            if let envelope = try? decoder.decode(RoadieEventEnvelope.self, from: data) {
                return envelope
            }
            if let legacy = try? decoder.decode(RoadieEvent.self, from: data) {
                return RoadieEventEnvelope(legacy: legacy)
            }
            return nil
        }
    }
}
