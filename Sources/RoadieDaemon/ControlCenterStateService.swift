import Foundation
import RoadieCore

public struct ControlCenterStateService {
    private let service: SnapshotService
    private let healthService: DaemonHealthService
    private let configPath: String?
    private let eventLog: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        healthService: DaemonHealthService? = nil,
        configPath: String? = nil,
        eventLog: EventLog = EventLog()
    ) {
        self.service = service
        self.healthService = healthService ?? DaemonHealthService(service: service)
        self.configPath = configPath
        self.eventLog = eventLog
    }

    public func state() -> ControlCenterState {
        let snapshot = service.snapshot()
        let health = healthService.run()
        let configReport = RoadieConfigLoader.validate(path: configPath)
        let focusedScope = snapshot.focusedWindowID.flatMap { focusedID in
            snapshot.windows.first { $0.window.id == focusedID }?.scope
        }
        let activeDisplayID = focusedScope?.displayID ?? snapshot.displays.first?.id
        let activeScope = activeDisplayID.flatMap { snapshot.state.activeScope(on: $0) } ?? focusedScope
        let lastError = eventLog.envelopes(limit: 50).reversed().first { event in
            event.type.contains("failed") || event.payload["error"] != nil
        }

        return ControlCenterState(
            daemonStatus: health.failed ? .degraded : .running,
            configPath: configPath ?? RoadieConfigLoader.defaultConfigPath(),
            configStatus: configReport.hasErrors ? .reloadFailed : .valid,
            activeDesktop: activeScope?.desktopID.description,
            activeStage: activeScope?.stageID.rawValue,
            windowCount: snapshot.windows.filter { $0.scope != nil }.count,
            lastError: lastError.map(Self.errorSummary),
            lastReloadAt: lastReloadEventDate(),
            actions: ControlCenterActions(
                canReloadConfig: true,
                canReapplyLayout: !snapshot.windows.isEmpty,
                canRevealConfig: true,
                canRevealState: true,
                canQuitSafely: true
            )
        )
    }

    private func lastReloadEventDate() -> Date? {
        eventLog.envelopes(limit: 50).reversed().first {
            $0.type.hasPrefix("config.reload_") || $0.type == "config.reloaded"
        }?.timestamp
    }

    private static func errorSummary(_ event: RoadieEventEnvelope) -> String {
        if let error = event.payload["error"] {
            return "\(event.type): \(payloadDescription(error))"
        }
        return event.type
    }

    private static func payloadDescription(_ payload: AutomationPayload) -> String {
        switch payload {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): String(value)
        case .object: "object"
        case .array: "array"
        case .null: "null"
        }
    }
}
