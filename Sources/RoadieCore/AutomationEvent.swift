import Foundation

public struct AutomationScope: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "automation scope must not be empty")
        self.rawValue = rawValue
    }

    public static let system = AutomationScope(rawValue: "system")
    public static let application = AutomationScope(rawValue: "application")
    public static let window = AutomationScope(rawValue: "window")
    public static let display = AutomationScope(rawValue: "display")
    public static let desktop = AutomationScope(rawValue: "desktop")
    public static let stage = AutomationScope(rawValue: "stage")
    public static let layout = AutomationScope(rawValue: "layout")
    public static let rule = AutomationScope(rawValue: "rule")
    public static let command = AutomationScope(rawValue: "command")

    public var description: String { rawValue }
}

public struct AutomationSubject: Codable, Equatable, Hashable, Sendable {
    public var kind: String
    public var id: String

    public init(kind: String, id: String) {
        precondition(!kind.isEmpty, "subject kind must not be empty")
        precondition(!id.isEmpty, "subject id must not be empty")
        self.kind = kind
        self.id = id
    }
}

public struct AutomationCause: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "automation cause must not be empty")
        self.rawValue = rawValue
    }

    public static let ax = AutomationCause(rawValue: "ax")
    public static let command = AutomationCause(rawValue: "command")
    public static let rule = AutomationCause(rawValue: "rule")
    public static let startup = AutomationCause(rawValue: "startup")
    public static let configReload = AutomationCause(rawValue: "config_reload")
    public static let system = AutomationCause(rawValue: "system")

    public var description: String { rawValue }
}

public indirect enum AutomationPayload: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AutomationPayload])
    case array([AutomationPayload])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AutomationPayload].self) {
            self = .object(value)
        } else if let value = try? container.decode([AutomationPayload].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                AutomationPayload.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported automation payload value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct RoadieEventEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var timestamp: Date
    public var type: String
    public var scope: AutomationScope?
    public var subject: AutomationSubject?
    public var correlationId: String?
    public var cause: AutomationCause
    public var payload: [String: AutomationPayload]

    public init(
        schemaVersion: Int = 1,
        id: String,
        timestamp: Date = Date(),
        type: String,
        scope: AutomationScope? = nil,
        subject: AutomationSubject? = nil,
        correlationId: String? = nil,
        cause: AutomationCause,
        payload: [String: AutomationPayload] = [:]
    ) {
        precondition(schemaVersion > 0, "schemaVersion must be positive")
        precondition(!id.isEmpty, "event id must not be empty")
        precondition(!type.isEmpty, "event type must not be empty")
        self.schemaVersion = schemaVersion
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.scope = scope
        self.subject = subject
        self.correlationId = correlationId
        self.cause = cause
        self.payload = payload
    }
}
