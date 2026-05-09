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
    private let hookDispatcher: SignalHookDispatcher
    private static let jsonNewline = Data("\n".utf8)
    public static let defaultMaxBytes = 10 * 1024 * 1024
    public static let defaultRetainedBackups = 2

    public init(path: String = Self.defaultPath(), hookDispatcher: SignalHookDispatcher = Self.defaultHookDispatcher()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.hookDispatcher = hookDispatcher
    }

    public static func defaultHookDispatcher() -> SignalHookDispatcher {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return .disabled
        }
        return .shared
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-events-\(ProcessInfo.processInfo.processIdentifier).jsonl"
        }
        return "~/.roadies/events.jsonl"
    }

    public func append(_ event: RoadieEvent) {
        write(event)
        hookDispatcher.dispatch(event)
    }

    public func append(_ event: RoadieEventEnvelope) {
        write(event)
        hookDispatcher.dispatch(event)
    }

    private func write<T: Encodable>(_ value: T) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            rotateIfNeeded()
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
        let limit = max(1, limit)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return [] }

        var offset = fileSize
        var data = Data()
        let chunkSize: UInt64 = 64 * 1024
        while offset > 0 {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            do {
                try handle.seek(toOffset: offset)
                let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()
                data.insert(contentsOf: chunk, at: 0)
            } catch {
                break
            }
            let lineCount = data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            if lineCount > limit { break }
        }

        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        return Array(raw.split(separator: "\n").suffix(limit).map(String.init))
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

    public func rotateIfNeeded(maxBytes: Int = Self.defaultMaxBytes, retainedBackups: Int = Self.defaultRetainedBackups) {
        let manager = FileManager.default
        guard maxBytes > 0,
              let attributes = try? manager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxBytes
        else { return }

        if retainedBackups > 0 {
            for index in stride(from: retainedBackups, through: 1, by: -1) {
                let source = backupURL(index)
                let destination = backupURL(index + 1)
                if manager.fileExists(atPath: destination.path) {
                    try? manager.removeItem(at: destination)
                }
                if manager.fileExists(atPath: source.path), index < retainedBackups {
                    try? manager.moveItem(at: source, to: destination)
                }
            }
            let firstBackup = backupURL(1)
            if manager.fileExists(atPath: firstBackup.path) {
                try? manager.removeItem(at: firstBackup)
            }
            try? manager.moveItem(at: url, to: firstBackup)
        } else {
            try? manager.removeItem(at: url)
        }
    }

    private func backupURL(_ index: Int) -> URL {
        URL(fileURLWithPath: "\(url.path).\(index)")
    }
}
