import Foundation

/// Section `[fx.opacity]` du roadies.toml.
public struct OpacityConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var inactiveDim: Double = 0.85
    public var animateDim: Bool = false
    public var rules: [AppRule] = []
    public var stageHide: StageHideConfig = StageHideConfig()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case inactiveDim = "inactive_dim"
        case animateDim = "animate_dim"
        case rules
        case stageHide = "stage_hide"
    }
}

public struct AppRule: Codable, Sendable, Equatable {
    public let bundleID: String
    public let alpha: Double

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case alpha
    }
}

public struct StageHideConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var preserveOffscreen: Bool = false

    enum CodingKeys: String, CodingKey {
        case enabled
        case preserveOffscreen = "preserve_offscreen"
    }
}

/// Lookup pour rule par bundleID.
public struct RuleMatcher: Sendable {
    public let rules: [AppRule]
    public init(_ rules: [AppRule]) { self.rules = rules }
    public func alpha(for bundleID: String) -> Double? {
        rules.first { $0.bundleID == bundleID }?.alpha
    }
}
