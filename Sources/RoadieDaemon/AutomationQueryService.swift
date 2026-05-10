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
        switch name {
        case "events":
            return result(name, eventLog.envelopes(limit: 50))
        case "event_catalog":
            return result(name, AutomationEventCatalog().eventTypes)
        case "performance":
            return result(name, PerformanceLogService(eventLog: eventLog).summary())
        case "restore":
            return result(name, RestoreSafetyService(eventLog: eventLog).status())
        default:
            break
        }

        let snapshot = service.snapshot()
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
        default:
            return AutomationQueryResult(kind: name, data: .object([
                "error": .string("unknown query")
            ]))
        }
    }

    private func result<T: Encodable>(_ kind: String, _ value: T) -> AutomationQueryResult {
        AutomationQueryResult(kind: kind, data: payload(value))
    }

    /// Encoder/decoder partages : query() est appele tres frequemment par les outils
    /// externes via subscribe (5Hz). Allouer un encoder/decoder par appel ajoutait
    /// ~250us et 4-5 KB par query.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private func payload<T: Encodable>(_ value: T) -> AutomationPayload {
        guard let data = try? Self.encoder.encode(value),
              let object = try? Self.decoder.decode(AutomationPayload.self, from: data)
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
