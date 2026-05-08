import Foundation
import RoadieCore

public enum ConfigReloadStatus: String, Codable, Sendable, Equatable {
    case idle
    case validating
    case applied
    case failedKeepingPrevious = "failed_keeping_previous"
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
        eventLog.append(envelope("config.reload_requested", path: path, timestamp: requestedAt))
        state.pendingPath = path
        state.lastAttemptAt = requestedAt

        let report = RoadieConfigLoader.validate(path: path)
        guard !report.hasErrors else {
            let message = report.items
                .filter { $0.level == .error }
                .map { "\($0.path): \($0.message)" }
                .joined(separator: "; ")
            state.pendingPath = nil
            state.lastValidation = .failed
            state.lastError = message
            eventLog.append(envelope("config.reload_failed", path: path, error: message, timestamp: now()))
            eventLog.append(envelope("config.active_preserved", path: state.activePath ?? path, version: state.activeVersion, timestamp: now()))
            return ConfigReloadResult(
                status: .failedKeepingPrevious,
                path: path,
                error: message,
                activeVersion: state.activeVersion
            )
        }

        do {
            let config = try RoadieConfigLoader.load(from: path)
            let version = Self.version(for: path)
            activeConfig = config
            state.activePath = path
            state.activeVersion = version
            state.pendingPath = nil
            state.lastValidation = .success
            state.lastError = nil
            state.lastAppliedAt = now()
            eventLog.append(envelope("config.reload_applied", path: path, version: version, timestamp: state.lastAppliedAt ?? now()))
            return ConfigReloadResult(status: .applied, path: path, version: version, appliedAt: state.lastAppliedAt)
        } catch {
            let message = "config decode failed: \(error)"
            state.pendingPath = nil
            state.lastValidation = .failed
            state.lastError = message
            eventLog.append(envelope("config.reload_failed", path: path, error: message, timestamp: now()))
            eventLog.append(envelope("config.active_preserved", path: state.activePath ?? path, version: state.activeVersion, timestamp: now()))
            return ConfigReloadResult(status: .failedKeepingPrevious, path: path, error: message, activeVersion: state.activeVersion)
        }
    }

    public static func version(for path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)) else {
            return nil
        }
        return "bytes:\(data.count):\(data.reduce(0) { (($0 &* 31) &+ UInt64($1)) })"
    }

    private func envelope(
        _ type: String,
        path: String,
        version: String? = nil,
        error: String? = nil,
        timestamp: Date
    ) -> RoadieEventEnvelope {
        var payload: [String: AutomationPayload] = ["path": .string(path)]
        payload["version"] = version.map(AutomationPayload.string)
        payload["error"] = error.map(AutomationPayload.string)
        return RoadieEventEnvelope(
            id: "config_reload_\(UUID().uuidString)",
            timestamp: timestamp,
            type: type,
            scope: .config,
            subject: AutomationSubject(kind: "config", id: path),
            cause: .configReload,
            payload: payload
        )
    }
}
