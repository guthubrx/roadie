import Foundation

/// Section `[fx.animations]` du roadies.toml.
public struct AnimationsConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var maxConcurrent: Int = 20
    public var bezier: [BezierDefinition] = []
    public var events: [EventRule] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxConcurrent = "max_concurrent"
        case bezier
        case events
    }
}

public struct BezierDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let points: [Double]   // [p1x, p1y, p2x, p2y]
}

public struct EventRule: Codable, Sendable, Equatable {
    public let event: String
    public let properties: [String]
    public let durationMs: Int
    public let curve: String
    public let direction: String?
    public let mode: String?

    enum CodingKeys: String, CodingKey {
        case event, properties, curve, direction, mode
        case durationMs = "duration_ms"
    }

    public init(event: String, properties: [String], durationMs: Int,
                curve: String, direction: String? = nil, mode: String? = nil) {
        self.event = event; self.properties = properties
        self.durationMs = durationMs; self.curve = curve
        self.direction = direction; self.mode = mode
    }
}
