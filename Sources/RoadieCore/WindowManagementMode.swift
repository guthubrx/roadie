public enum WindowManagementMode: String, Codable, Sendable, CaseIterable {
    case bsp
    case mutableBsp
    case masterStack
    case float

    public init?(roadieValue: String) {
        switch roadieValue {
        case "bsp":
            self = .bsp
        case "mutableBsp", "mutable_bsp", "mutable-bsp":
            self = .mutableBsp
        case "masterStack", "master_stack", "master-stack":
            self = .masterStack
        case "float", "floating":
            self = .float
        default:
            return nil
        }
    }

    public var isTiled: Bool {
        self != .float
    }

    public var usesSpatialBSPOrdering: Bool {
        self == .bsp || self == .mutableBsp
    }
}
