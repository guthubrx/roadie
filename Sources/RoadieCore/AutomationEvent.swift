import Foundation

public struct RoadieEventEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var timestamp: Date
    public var type: String
    public var scope: String?
    public var subject: [String: String]?
    public var correlationId: String?
    public var cause: String
    public var payload: [String: String]

    public init(
        schemaVersion: Int = 1,
        id: String,
        timestamp: Date = Date(),
        type: String,
        scope: String? = nil,
        subject: [String: String]? = nil,
        correlationId: String? = nil,
        cause: String,
        payload: [String: String] = [:]
    ) {
        precondition(schemaVersion > 0, "schemaVersion must be positive")
        precondition(!id.isEmpty, "event id must not be empty")
        precondition(!type.isEmpty, "event type must not be empty")
        precondition(!cause.isEmpty, "event cause must not be empty")
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
