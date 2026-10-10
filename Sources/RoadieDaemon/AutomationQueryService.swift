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
        case "targets":
            return result(name, TargetHintService(service: service, eventLog: eventLog).list())
        case "components":
            let entries = ComponentLockFile.registry().map { entry -> AutomationPayload in
                .object([
                    "component": .string(entry.component),
                    "pid": .int(Int(entry.pid)),
                    "startedAt": .string(ISO8601DateFormatter().string(from: entry.startedAt))
                ])
            }
            return AutomationQueryResult(kind: name, data: .array(entries))
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
            // Config courante (comme `state`), sauf fichier explicite.
            guard let configPath else { return result(name, automation.rules) }
            let rules = (try? RoadieConfigLoader.load(from: configPath).rules) ?? []
            return result(name, AutomationSnapshotService.ruleSnapshots(rules))
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
