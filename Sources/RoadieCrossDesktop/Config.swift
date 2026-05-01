import Foundation

/// Section `[fx.cross_desktop]` du roadies.toml.
public struct CrossDesktopConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var pinRules: [PinRule] = []
    public var forceTiling: ForceTilingConfig = ForceTilingConfig()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case pinRules = "pin_rules"
        case forceTiling = "force_tiling"
    }
}

public struct PinRule: Codable, Sendable, Equatable {
    public let bundleID: String
    public let desktopLabel: String?
    public let desktopIndex: Int?

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case desktopLabel = "desktop_label"
        case desktopIndex = "desktop_index"
    }

    public init(bundleID: String, desktopLabel: String? = nil, desktopIndex: Int? = nil) {
        self.bundleID = bundleID
        self.desktopLabel = desktopLabel
        self.desktopIndex = desktopIndex
    }
}

public struct ForceTilingConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var bundleIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case enabled
        case bundleIDs = "bundle_ids"
    }
}
