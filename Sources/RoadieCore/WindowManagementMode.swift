public enum WindowManagementMode: String, Codable, Sendable, CaseIterable {
    case bsp
    case mutableBsp
    case masterStack
    case float
    case spatialBsp

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
        case "spatialBsp", "spatial_bsp", "spatial-bsp", "spatial", "tree", "yabai":
            self = .spatialBsp
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

    /// Mode à arbre BSP persistant (insertion sur le pane focalisé, structure mémorisée).
    public var usesPersistentBSPTree: Bool {
        self == .spatialBsp
    }
}
