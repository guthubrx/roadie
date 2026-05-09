import Foundation
import RoadieCore

public final class SignalHookDispatcher: @unchecked Sendable {
    public typealias SpawnCommand = @Sendable (_ command: String, _ environment: [String: String]) -> Void

    public static let shared = SignalHookDispatcher()
    public static let disabled = SignalHookDispatcher(spawnCommand: { _, _ in })

    private let configPathProvider: @Sendable () -> String
    private let spawnCommand: SpawnCommand
    private let queue = DispatchQueue(label: "roadie.signal-hooks", qos: .utility)
    private let lock = NSLock()
    private var cachedConfig: SignalsConfig?
    private var cachedConfigDate: Date?

    public init(
        configPathProvider: @escaping @Sendable () -> String = { RoadieConfigLoader.defaultConfigPath() },
        spawnCommand: @escaping SpawnCommand = { command, environment in
            SignalHookDispatcher.defaultSpawnCommand(command: command, environment: environment)
        }
    ) {
        self.configPathProvider = configPathProvider
        self.spawnCommand = spawnCommand
    }

    public func dispatch(_ event: RoadieEvent) {
        guard ProcessInfo.processInfo.environment["ROADIE_SIGNAL_HOOK"] != "1" else { return }
        queue.async { [self] in
            guard let config = signalsConfig(), config.enabled else { return }
            let context = HookContext(legacy: event)
            for hook in matchingHooks(for: context, hooks: config.hooks) {
                spawnCommand(hook.cmd, context.environment)
            }
        }
    }

    public func dispatch(_ event: RoadieEventEnvelope) {
        guard ProcessInfo.processInfo.environment["ROADIE_SIGNAL_HOOK"] != "1" else { return }
        queue.async { [self] in
            guard let config = signalsConfig(), config.enabled else { return }
            let context = HookContext(envelope: event)
            for hook in matchingHooks(for: context, hooks: config.hooks) {
                spawnCommand(hook.cmd, context.environment)
            }
        }
    }

    private func signalsConfig() -> SignalsConfig? {
        let path = NSString(string: configPathProvider()).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil

        lock.lock()
        defer { lock.unlock() }

        if cachedConfigDate == modificationDate, let cachedConfig {
            return cachedConfig
        }
        guard let config = try? RoadieConfigLoader.load(from: url.path) else {
            cachedConfig = nil
            cachedConfigDate = modificationDate
            return nil
        }
        cachedConfig = config.signals
        cachedConfigDate = modificationDate
        return config.signals
    }

    private func matchingHooks(for context: HookContext, hooks: [SignalHookConfig]) -> [SignalHookConfig] {
        hooks.filter { hook in
            context.matches(configuredEvent: hook.event)
        }
    }

    public static func defaultSpawnCommand(command: String, environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var childEnvironment = ProcessInfo.processInfo.environment
        childEnvironment["ROADIE_SIGNAL_HOOK"] = "1"
        childEnvironment.merge(environment) { _, new in new }
        process.environment = childEnvironment
        try? process.run()
    }
}

private struct HookContext: Sendable {
    let rawEventType: String
    let canonicalEventType: String
    let environment: [String: String]

    init(legacy event: RoadieEvent) {
        self.rawEventType = event.type
        self.canonicalEventType = Self.canonicalType(for: event.type)
        self.environment = Self.environment(
            timestamp: event.timestamp,
            rawEventType: event.type,
            canonicalEventType: Self.canonicalType(for: event.type),
            scope: event.scope,
            subject: nil,
            correlationID: nil,
            cause: nil,
            details: event.details.mapValues(AutomationPayload.string)
        )
    }

    init(envelope event: RoadieEventEnvelope) {
        self.rawEventType = event.type
        self.canonicalEventType = Self.canonicalType(for: event.type)
        self.environment = Self.environment(
            timestamp: event.timestamp,
            rawEventType: event.type,
            canonicalEventType: Self.canonicalType(for: event.type),
            scope: nil,
            subject: event.subject,
            correlationID: event.correlationId,
            cause: event.cause.rawValue,
            details: event.payload
        )
    }

    func matches(configuredEvent: String) -> Bool {
        let normalizedConfigured = Self.normalize(configuredEvent)
        return normalizedConfigured == Self.normalize(rawEventType)
            || normalizedConfigured == Self.normalize(canonicalEventType)
    }

    private static func environment(
        timestamp: Date,
        rawEventType: String,
        canonicalEventType: String,
        scope: StageScope?,
        subject: AutomationSubject?,
        correlationID: String?,
        cause: String?,
        details: [String: AutomationPayload]
    ) -> [String: String] {
        var env: [String: String] = [
            "ROADIE_EVENT_TYPE": rawEventType,
            "ROADIE_EVENT_CANONICAL_TYPE": canonicalEventType,
            "ROADIE_EVENT_TIMESTAMP": ISO8601DateFormatter().string(from: timestamp),
        ]

        if let scope {
            env["ROADIE_DISPLAY_ID"] = scope.displayID.rawValue
            env["ROADIE_DESKTOP_ID"] = String(scope.desktopID.rawValue)
            env["ROADIE_STAGE_ID"] = scope.stageID.rawValue
        }
        if let subject {
            env["ROADIE_SUBJECT_KIND"] = subject.kind
            env["ROADIE_SUBJECT_ID"] = subject.id
        }
        if let correlationID, !correlationID.isEmpty {
            env["ROADIE_CORRELATION_ID"] = correlationID
        }
        if let cause, !cause.isEmpty {
            env["ROADIE_CAUSE"] = cause
        }

        for (key, value) in details {
            env["ROADIE_\(envKey(for: key))"] = scalarString(for: value)
        }

        if env["ROADIE_TO"] == nil {
            if canonicalEventType == "stage.changed", let stageID = env["ROADIE_STAGE_ID"] {
                env["ROADIE_TO"] = stageID
            } else if canonicalEventType == "desktop.changed", let desktopID = env["ROADIE_DESKTOP_ID"] {
                env["ROADIE_TO"] = desktopID
            }
        }
        if env["ROADIE_FROM"] == nil {
            if let previousStageID = env["ROADIE_PREVIOUS_STAGE_ID"] {
                env["ROADIE_FROM"] = previousStageID
            } else if let previousDesktopID = env["ROADIE_PREVIOUS_DESKTOP_ID"] {
                env["ROADIE_FROM"] = previousDesktopID
            }
        }

        return env
    }

    private static func scalarString(for payload: AutomationPayload) -> String {
        switch payload {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return ""
        case .object, .array:
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(payload),
                  let text = String(data: data, encoding: .utf8)
            else {
                return ""
            }
            return text
        }
    }

    private static func envKey(for key: String) -> String {
        var result = ""
        var previousWasSeparator = true
        for character in key {
            if character.isLetter || character.isNumber {
                if character.isUppercase && !result.isEmpty && !previousWasSeparator {
                    result.append("_")
                }
                result.append(character.uppercased())
                previousWasSeparator = false
            } else {
                if !previousWasSeparator && !result.isEmpty {
                    result.append("_")
                }
                previousWasSeparator = true
            }
        }
        return result
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .replacingOccurrences(of: "_I_D", with: "_ID")
    }

    private static func normalize(_ eventType: String) -> String {
        eventType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: ".")
    }

    private static func canonicalType(for eventType: String) -> String {
        switch normalize(eventType) {
        case "stage.switch", "rail.stage.switch":
            return "stage.changed"
        case "desktop.focus":
            return "desktop.changed"
        case "display.focus":
            return "display.focused"
        default:
            return normalize(eventType)
        }
    }
}
