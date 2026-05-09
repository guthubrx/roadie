import Foundation
import RoadieCore

public struct AutomationQueryResult: Codable, Equatable, Sendable {
    public var kind: String
    public var data: AutomationPayload
}

public struct AutomationQueryService {
    private let service: SnapshotService
    private let configPath: String?
    private let eventLog: EventLog

    public init(service: SnapshotService = SnapshotService(), configPath: String? = nil, eventLog: EventLog = EventLog()) {
        self.service = service
        self.configPath = configPath
        self.eventLog = eventLog
    }

    public func query(_ name: String) -> AutomationQueryResult {
        let snapshot = service.snapshot(followExternalFocus: false, persistState: false)
        let automation = snapshot.automationSnapshot()
        switch name {
        case "state":
            return result(name, automation)
        case "windows":
            return result(name, automation.windows)
        case "displays":
            return result(name, automation.displays)
        case "desktops":
            return result(name, automation.desktops)
        case "stages":
            return result(name, automation.stages)
        case "groups":
            return result(name, automation.groups)
        case "rules":
            let rules = (try? RoadieConfigLoader.load(from: configPath).rules) ?? []
            return result(name, rules.map {
                AutomationRuleSnapshot(id: $0.id, enabled: $0.enabled, priority: $0.priority, description: $0.match.description)
            })
        case "health":
            return result(name, DaemonHealthService(service: service).run())
        case "events":
            return result(name, eventLog.envelopes(limit: 50))
        case "config_reload":
            return result(name, ConfigReloadService(activePath: configPath ?? RoadieConfigLoader.defaultConfigPath(), eventLog: eventLog).state)
        case "restore":
            return result(name, RestoreSafetyService(eventLog: eventLog).load() ?? RestoreSafetySnapshot())
        case "transient":
            return result(name, TransientWindowDetector(service: service, events: eventLog).status())
        case "identity_restore":
            return result(name, LayoutPersistenceV2Service(service: service, events: eventLog).dryRun())
        default:
            return AutomationQueryResult(kind: name, data: .object([
                "error": .string("unknown query")
            ]))
        }
    }

    private func result<T: Encodable>(_ kind: String, _ value: T) -> AutomationQueryResult {
        AutomationQueryResult(kind: kind, data: payload(value))
    }

    private func payload<T: Encodable>(_ value: T) -> AutomationPayload {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let object = try? JSONDecoder().decode(AutomationPayload.self, from: data)
        else {
            return .null
        }
        return object
    }
}

private extension RuleMatch {
    var description: String {
        [
            app.map { "app=\($0)" },
            appRegex.map { "app_regex=\($0)" },
            title.map { "title=\($0)" },
            titleRegex.map { "title_regex=\($0)" },
            role.map { "role=\($0)" },
            stage.map { "stage=\($0)" }
        ].compactMap(\.self).joined(separator: ",")
    }
}
