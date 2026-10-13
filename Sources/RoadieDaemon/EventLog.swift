import Foundation
import os
import RoadieCore

public struct RoadieEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var type: String
    public var scope: StageScope?
    public var details: [String: String]
    /// Epoch en millisecondes, dérivé de `timestamp` (le format ISO du journal est à la seconde).
    /// Optionnel : les anciennes lignes ne l'ont pas.
    public var tsMs: Int64?
    /// Épisode de la cause en cours (`ep_<epoch ms>`), voir `EpisodeContext`. Optionnel.
    public var episodeId: String?

    public init(
        type: String,
        scope: StageScope? = nil,
        details: [String: String] = [:],
        timestamp: Date = Date(),
        episodeId: String? = nil
    ) {
        self.timestamp = timestamp
        self.type = type
        self.scope = scope
        self.details = details
        self.tsMs = timestamp.epochMilliseconds
        self.episodeId = episodeId
    }
}

/// Épisode de mesure (SPEC-017 A12) : une cause externe (notification AX, commande, glisser,
/// échéance) ouvre un épisode. Ses échos et les échéances qu'il arme le prolongent
/// (`continue()`). Il se ferme après `closeAfter` secondes sans `begin` ni `continue`.
/// Global au processus (`shared`) ; l'horloge est injectable pour les tests.
public final class EpisodeContext: Sendable {
    public static let shared = EpisodeContext()
    public static let defaultCloseAfter: TimeInterval = 1

    private struct State {
        var id: String?
        var cause: String?
        var lastActivity = Date.distantPast
        var lastIdMs: Int64 = 0
    }

    private let now: @Sendable () -> Date
    private let closeAfter: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(closeAfter: TimeInterval = EpisodeContext.defaultCloseAfter, now: @escaping @Sendable () -> Date = { Date() }) {
        self.closeAfter = closeAfter
        self.now = now
    }

    /// Ouvre un nouvel épisode pour une cause externe et retourne son identifiant. O(1).
    @discardableResult
    public func begin(cause: String) -> String {
        let date = now()
        return state.withLock { state in
            // Deux causes dans la même milliseconde gardent des identifiants distincts.
            let ms = max(date.epochMilliseconds, state.lastIdMs + 1)
            let id = "ep_\(ms)"
            state.lastIdMs = ms
            state.id = id
            state.cause = cause
            state.lastActivity = date
            return id
        }
    }

    /// Épisode ouvert, sans le prolonger. nil s'il est fermé.
    public var current: String? {
        let date = now()
        return state.withLock { isOpen($0, at: date) ? $0.id : nil }
    }

    /// Cause qui a ouvert l'épisode courant. nil s'il est fermé.
    public var currentCause: String? {
        let date = now()
        return state.withLock { isOpen($0, at: date) ? $0.cause : nil }
    }

    /// Prolonge l'épisode courant (écho, échéance armée) et retourne son identifiant. nil s'il est fermé.
    @discardableResult
    public func `continue`() -> String? {
        let date = now()
        return state.withLock { state in
            guard isOpen(state, at: date) else { return nil }
            state.lastActivity = date
            return state.id
        }
    }

    private func isOpen(_ state: State, at date: Date) -> Bool {
        state.id != nil && date.timeIntervalSince(state.lastActivity) <= closeAfter
    }

    @discardableResult
    public static func begin(cause: String) -> String { shared.begin(cause: cause) }
    public static var current: String? { shared.current }
    @discardableResult
    public static func `continue`() -> String? { shared.continue() }
}

public extension RoadieEventEnvelope {
    init(legacy event: RoadieEvent) {
        let sanitizedType = event.type
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let milliseconds = event.timestamp.epochMilliseconds
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
        self.tsMs = event.tsMs ?? self.tsMs
    }
}

public struct EventLog: Sendable {
    private let url: URL
    private let maxBytes: Int
    private let retainedBackups: Int
    private let episodes: EpisodeContext
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
        retainedBackups: Int = Self.defaultRetainedBackups,
        episodes: EpisodeContext = .shared
    ) {
        self.episodes = episodes
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

    /// Pose l'épisode courant sur l'événement s'il n'en porte pas (sans prolonger l'épisode).
    public func append(_ event: RoadieEvent) {
        var event = event
        if event.episodeId == nil { event.episodeId = episodes.current }
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

        // OBS-002 : on sélectionne les dernières lignes sur les octets AVANT de décoder. La frontière
        // d'un bloc peut couper un caractère UTF-8 dans la première ligne (partielle, jamais retenue :
        // il y a au moins limit + 1 retours à la ligne). Décoder tout le tampon d'un coup échouerait
        // et viderait le résultat. Décodage tolérant : un octet invalide devient U+FFFD sans perdre la ligne.
        // O(n) - n = octets lus.
        return data.split(separator: 10).suffix(limit).map { String(decoding: $0, as: UTF8.self) }
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
