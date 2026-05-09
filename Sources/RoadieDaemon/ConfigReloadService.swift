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

public final class ConfigReloadService: @unchecked Sendable {
    private let eventLog: EventLog
    private let now: () -> Date
    private(set) public var activeConfig: RoadieConfig
    private(set) public var state: ConfigReloadState

    public init(
        activeConfig: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig(),
        activePath: String = RoadieConfigLoader.defaultConfigPath(),
        eventLog: EventLog = EventLog(),
        now: @escaping () -> Date = Date.init
    ) {
        self.eventLog = eventLog
        self.now = now
        self.activeConfig = activeConfig
        self.state = ConfigReloadState(
            activePath: activePath,
            activeVersion: Self.version(for: activePath),
            lastValidation: .skipped
        )
    }

    public func reload(path: String = RoadieConfigLoader.defaultConfigPath()) -> ConfigReloadResult {
        let requestedAt = now()
        state.pendingPath = path
        state.lastAttemptAt = requestedAt
        eventLog.append(RoadieEvent(
            type: "config.reload_requested",
            details: ["path": path],
            timestamp: requestedAt
        ))

        let report = RoadieConfigLoader.validate(path: path)
        guard !report.hasErrors else {
            let message = report.items
                .filter { $0.level == .error }
                .map { "\($0.path): \($0.message)" }
                .joined(separator: "; ")
            state.pendingPath = nil
            state.lastValidation = .failed
            state.lastError = message
            eventLog.append(RoadieEvent(
                type: "config.reload_failed",
                details: ["path": path, "error": message],
                timestamp: now()
            ))
            eventLog.append(RoadieEvent(
                type: "config.active_preserved",
                details: preservedDetails(path: state.activePath ?? path),
                timestamp: now()
            ))
            return ConfigReloadResult(
                status: .failedKeepingPrevious,
                path: path,
                error: message,
                activeVersion: state.activeVersion
            )
        }

        do {
            let config = try RoadieConfigLoader.load(from: path)
            let appliedAt = now()
            let version = Self.version(for: path)
            activeConfig = config
            state.activePath = path
            state.activeVersion = version
            state.pendingPath = nil
            state.lastValidation = .success
            state.lastError = nil
            state.lastAppliedAt = appliedAt
            eventLog.append(RoadieEvent(
                type: "config.reload_applied",
                details: version.map { ["path": path, "version": $0] } ?? ["path": path],
                timestamp: appliedAt
            ))
            return ConfigReloadResult(status: .applied, path: path, version: version, appliedAt: appliedAt)
        } catch {
            let message = "config decode failed: \(error)"
            state.pendingPath = nil
            state.lastValidation = .failed
            state.lastError = message
            eventLog.append(RoadieEvent(
                type: "config.reload_failed",
                details: ["path": path, "error": message],
                timestamp: now()
            ))
            eventLog.append(RoadieEvent(
                type: "config.active_preserved",
                details: preservedDetails(path: state.activePath ?? path),
                timestamp: now()
            ))
            return ConfigReloadResult(
                status: .failedKeepingPrevious,
                path: path,
                error: message,
                activeVersion: state.activeVersion
            )
        }
    }

    public static func version(for path: String) -> String? {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let checksum = data.reduce(UInt64(0)) { (($0 &* 31) &+ UInt64($1)) }
        return "bytes:\(data.count):\(checksum)"
    }

    private func preservedDetails(path: String) -> [String: String] {
        var details = ["path": path]
        if let version = state.activeVersion {
            details["version"] = version
        }
        return details
    }
}
