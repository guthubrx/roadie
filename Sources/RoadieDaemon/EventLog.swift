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
    public static let defaultMaxBytes = 10 * 1024 * 1024
    public static let defaultRetainedBackups = 2

    /// Encoder partage. JSONEncoder est thread-safe pour `encode` independants.
    /// Eviter de l'allouer a chaque event log evite ~150us et 2-3 KB d'allocations
    /// par evenement (mesure simple sur Swift 5.10).
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Verrou de fichier global. EventLog est instancie ~15x dans le daemon (un par
    /// service) avec des `append` concurrents (Task @MainActor + workers). Sans verrou,
    /// `seekToEnd + write + write(newline)` est non-atomique : deux events peuvent
    /// s'entrelacer ou la rotation peut couper un event en deux. Un verrou statique
    /// keye sur le path resoudrait des paths multiples ; pour l'instant, un seul fichier
    /// d'event est utilise donc un verrou unique suffit.
    private static let writeLock = NSLock()

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
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(value)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Self.jsonNewline)
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

    /// Decoder partage. Meme rationale que `encoder` plus haut.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func envelopes(limit: Int = 20) -> [RoadieEventEnvelope] {
        let decoder = Self.decoder
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
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
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
