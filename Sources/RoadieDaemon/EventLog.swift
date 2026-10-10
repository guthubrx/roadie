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
    private let maxBytes: Int
    private let retainedBackups: Int
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

    public init(
        path: String = Self.defaultPath(),
        maxBytes: Int = Self.defaultMaxBytes,
        retainedBackups: Int = Self.defaultRetainedBackups
    ) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.maxBytes = max(1, maxBytes)
        self.retainedBackups = max(0, retainedBackups)
    }

    public static func defaultPath() -> String {
        if TestEnvironment.isRunningTests {
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

    /// Sûr entre processus et entre threads (SPEC-016 T017) : la vérification de taille, la
    /// rotation et l'ajout se font sous `FileLock` exclusif (`events.jsonl.lock`, un descripteur
    /// par prise, donc valable aussi entre threads), et la ligne complète part en un seul
    /// `write(2)` sur un descripteur `O_APPEND` : aucune ligne coupée ni entrelacée.
    private func write<T: Encodable>(_ value: T) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let line = try Self.encoder.encode(value) + Self.jsonNewline
            try FileLock.withLock(path: FileLock.lockPath(for: url), mode: .exclusive) {
                rotateIfNeededLocked(incomingBytes: line.count)
                try appendLocked(line)
            }
        } catch {
            fputs("roadie: failed to write event log: \(error)\n", stderr)
        }
    }

    private func appendLocked(_ line: Data) throws {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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
        do {
            try FileLock.withLock(path: FileLock.lockPath(for: url), mode: .exclusive) {
                rotateLocked(maxBytes: maxBytes, retainedBackups: retainedBackups, force: false)
            }
        } catch {
            fputs("roadie: failed to rotate event log: \(error)\n", stderr)
        }
    }

    private func rotateIfNeededLocked(incomingBytes: Int) {
        let manager = FileManager.default
        guard maxBytes > 0,
              let attributes = try? manager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue + incomingBytes > maxBytes
        else { return }
        rotateLocked(maxBytes: maxBytes, retainedBackups: retainedBackups, force: true)
    }

    private func rotateLocked(maxBytes: Int, retainedBackups: Int, force: Bool) {
        let manager = FileManager.default
        guard maxBytes > 0,
              let attributes = try? manager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              force || size.intValue > maxBytes
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
