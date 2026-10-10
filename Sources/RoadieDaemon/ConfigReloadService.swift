import Foundation
import RoadieCore

public enum ConfigReloadValidation: String, Codable, Sendable, Equatable {
    case success
    case failed
    case skipped
}

public enum ConfigReloadStatus: String, Codable, Sendable, Equatable {
    case idle
    case validating
    case applied
    case failedKeepingPrevious = "failed_keeping_previous"
}

public struct ConfigReloadState: Codable, Equatable, Sendable {
    public var activePath: String?
    public var activeVersion: String?
    public var pendingPath: String?
    public var lastValidation: ConfigReloadValidation
    public var lastError: String?
    public var lastAttemptAt: Date?
    public var lastAppliedAt: Date?

    public init(
        activePath: String? = nil,
        activeVersion: String? = nil,
        pendingPath: String? = nil,
        lastValidation: ConfigReloadValidation = .skipped,
        lastError: String? = nil,
        lastAttemptAt: Date? = nil,
        lastAppliedAt: Date? = nil
    ) {
        self.activePath = activePath
        self.activeVersion = activeVersion
        self.pendingPath = pendingPath
        self.lastValidation = lastValidation
        self.lastError = lastError
        self.lastAttemptAt = lastAttemptAt
        self.lastAppliedAt = lastAppliedAt
    }
}

public struct ConfigReloadResult: Codable, Equatable, Sendable {
    public var status: ConfigReloadStatus
    public var path: String
    public var version: String?
    public var appliedAt: Date?
    public var error: String?
    public var activeVersion: String?

    public init(
        status: ConfigReloadStatus,
        path: String,
        version: String? = nil,
        appliedAt: Date? = nil,
        error: String? = nil,
        activeVersion: String? = nil
    ) {
        self.status = status
        self.path = path
        self.version = version
        self.appliedAt = appliedAt
        self.error = error
        self.activeVersion = activeVersion
    }
}

/// Service de configuration du processus. `currentConfig()` donne le rechargement à chaud
/// (SPEC-016 FR-018) ; `reload(path:)` sert la commande explicite `roadie config reload`.
/// L'état mutable est protégé par `lock` : l'instance partagée est lue depuis plusieurs
/// composants (tiler, bordure, focus-souris, rail) potentiellement sur des threads différents.
public final class ConfigReloadService: @unchecked Sendable {
    /// Instance partagée par tous les composants du processus.
    public static let shared = ConfigReloadService()

    private let lock = NSLock()
    private let eventLog: EventLog
    private let now: () -> Date
    private var storedConfig: RoadieConfig
    private var storedState: ConfigReloadState
    /// Signature du fichier correspondant à la dernière tentative de chargement (réussie ou non).
    /// Une version fautive garde sa signature : elle n'est ni reparsée ni rejournalisée.
    private var loadedStamp: [Int64]?

    public var activeConfig: RoadieConfig { lock.withLock { storedConfig } }
    public var state: ConfigReloadState { lock.withLock { storedState } }

    /// `activeConfig` nil : la config est lue au premier appel de `currentConfig()`.
    public init(
        activeConfig: RoadieConfig? = nil,
        activePath: String = RoadieConfigLoader.defaultConfigPath(),
        eventLog: EventLog = EventLog(),
        now: @escaping () -> Date = Date.init
    ) {
        self.eventLog = eventLog
        self.now = now
        self.storedConfig = activeConfig ?? RoadieConfig()
        self.loadedStamp = activeConfig == nil ? nil : Self.stamp(for: activePath)
        self.storedState = ConfigReloadState(
            activePath: activePath,
            activeVersion: Self.version(for: activePath),
            lastValidation: .skipped
        )
    }

    /// Config active, relue seulement si le fichier a changé (date de modification ou taille).
    /// Une config invalide (même validation que `reload`) garde la dernière config valide et
    /// n'est journalisée qu'une fois. Au premier chargement, sans config précédente, la config
    /// décodée est appliquée malgré des erreurs de validation (comportement historique du démarrage).
    /// Lecture, validation et journal se font hors du verrou (T213) : le verrou ne protège que
    /// la comparaison de signature et la publication, pour ne pas bloquer les autres composants.
    // O(1) (un stat par fichier) si inchangé ; O(taille du fichier) au rechargement.
    public func currentConfig() -> RoadieConfig {
        let path = lock.withLock { storedState.activePath } ?? RoadieConfigLoader.defaultConfigPath()
        let stamp = Self.stamp(for: path)
        if let unchanged = lock.withLock({ stamp == loadedStamp ? storedConfig : nil }) {
            return unchanged
        }
        let attemptAt = now()
        let validationError = Self.validationError(path: path)
        let loaded = Result { try RoadieConfigLoader.load(from: path) }
        let version = Self.version(for: path)

        var pendingEvents: [RoadieEvent] = []
        let config: RoadieConfig = lock.withLock {
            // Un autre appel a déjà publié cette version : ni double application ni double journal.
            guard stamp != loadedStamp else { return storedConfig }
            let isFirstLoad = loadedStamp == nil
            loadedStamp = stamp
            storedState.lastAttemptAt = attemptAt
            if let validationError, !isFirstLoad {
                pendingEvents = recordFailure(path: path, message: validationError)
                return storedConfig
            }
            switch loaded {
            case .success(let config):
                storedConfig = config
                storedState.activeVersion = version
                storedState.lastAppliedAt = attemptAt
                if let validationError {
                    pendingEvents = recordFailure(path: path, message: validationError)
                } else {
                    storedState.lastValidation = .success
                    storedState.lastError = nil
                    if !isFirstLoad {
                        pendingEvents = [RoadieEvent(
                            type: "config.reload_applied",
                            details: appliedDetails(path: path),
                            timestamp: attemptAt
                        )]
                    }
                }
            case .failure(let error):
                pendingEvents = recordFailure(path: path, message: "config decode failed: \(error)")
            }
            return storedConfig
        }
        pendingEvents.forEach { eventLog.append($0) }
        return config
    }

    public func reload(path: String = RoadieConfigLoader.defaultConfigPath()) -> ConfigReloadResult {
        lock.lock()
        defer { lock.unlock() }
        let requestedAt = now()
        storedState.pendingPath = path
        storedState.lastAttemptAt = requestedAt
        eventLog.append(RoadieEvent(
            type: "config.reload_requested",
            details: ["path": path],
            timestamp: requestedAt
        ))

        if let message = Self.validationError(path: path) {
            recordFailure(path: path, message: message).forEach { eventLog.append($0) }
            return ConfigReloadResult(
                status: .failedKeepingPrevious,
                path: path,
                error: message,
                activeVersion: storedState.activeVersion
            )
        }

        do {
            let config = try RoadieConfigLoader.load(from: path)
            let appliedAt = now()
            let version = Self.version(for: path)
            storedConfig = config
            loadedStamp = Self.stamp(for: path)
            storedState.activePath = path
            storedState.activeVersion = version
            storedState.pendingPath = nil
            storedState.lastValidation = .success
            storedState.lastError = nil
            storedState.lastAppliedAt = appliedAt
            eventLog.append(RoadieEvent(
                type: "config.reload_applied",
                details: appliedDetails(path: path),
                timestamp: appliedAt
            ))
            return ConfigReloadResult(status: .applied, path: path, version: version, appliedAt: appliedAt)
        } catch {
            let message = "config decode failed: \(error)"
            recordFailure(path: path, message: message).forEach { eventLog.append($0) }
            return ConfigReloadResult(
                status: .failedKeepingPrevious,
                path: path,
                error: message,
                activeVersion: storedState.activeVersion
            )
        }
    }

    public static func version(for path: String) -> String? {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let checksum = data.reduce(UInt64(0)) { (($0 &* 31) &+ UInt64($1)) }
        return "bytes:\(data.count):\(checksum)"
    }

    /// Erreurs de validation jointes, nil si la config est valide.
    private static func validationError(path: String) -> String? {
        let report = RoadieConfigLoader.validate(path: path)
        guard report.hasErrors else { return nil }
        return report.items
            .filter { $0.level == .error }
            .map { "\($0.path): \($0.message)" }
            .joined(separator: "; ")
    }

    /// Date de modification et taille du fichier principal et du fichier de règles générées
    /// (tous deux lus par `RoadieConfigLoader.load`). `-1` pour un fichier absent.
    static func stamp(for path: String) -> [Int64] {
        fileModificationStamp(path) + fileModificationStamp(RoadieConfigLoader.generatedRulesPath(for: path))
    }

    /// À appeler sous `lock` : met à jour l'état et renvoie les événements à journaliser.
    private func recordFailure(path: String, message: String) -> [RoadieEvent] {
        storedState.pendingPath = nil
        storedState.lastValidation = .failed
        storedState.lastError = message
        return [
            RoadieEvent(
                type: "config.reload_failed",
                details: ["path": path, "error": message],
                timestamp: now()
            ),
            RoadieEvent(
                type: "config.active_preserved",
                details: preservedDetails(path: storedState.activePath ?? path),
                timestamp: now()
            )
        ]
    }

    private func appliedDetails(path: String) -> [String: String] {
        storedState.activeVersion.map { ["path": path, "version": $0] } ?? ["path": path]
    }

    private func preservedDetails(path: String) -> [String: String] {
        var details = ["path": path]
        if let version = storedState.activeVersion {
            details["version"] = version
        }
        return details
    }
}

/// Date de modification (ns) et taille d'un fichier, via un seul `stat` ; `[-1]` s'il est absent.
/// Sert à détecter un changement sans relire le contenu (config, état des stages).
func fileModificationStamp(_ path: String) -> [Int64] {
    var info = stat()
    guard stat(NSString(string: path).expandingTildeInPath, &info) == 0 else { return [-1] }
    return [Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec), Int64(info.st_size)]
}
