public enum WindowManagementMode: String, Codable, Sendable, CaseIterable {
    case bsp
    case mutableBsp
    case masterStack
    case float
    case spatialBsp
    case tabbed
    case scrolling

    public init?(roadieValue: String) {
        switch roadieValue {
        case "bsp":
            self = .bsp
        case "mutableBsp", "mutable_bsp", "mutable-bsp", "yabai":
            self = .mutableBsp
        case "masterStack", "master_stack", "master-stack":
            self = .masterStack
        case "float", "floating":
            self = .float
        case "spatialBsp", "spatial_bsp", "spatial-bsp", "spatial", "tree":
            self = .spatialBsp
        case "tabbed", "tabs", "onglets":
            self = .tabbed
        case "scrolling", "scroll", "ribbon", "niri", "ruban":
            self = .scrolling
        default:
            return nil
        }
    }

    public var isTiled: Bool {
        self != .float
    }

    /// Modes où les fenêtres se superposent volontairement (`tabbed`) ou débordent sur les bords du
    /// ruban (`scrolling`) : exclus des heuristiques anti-chevauchement BSP (Spec 164).
    public var allowsWindowOverlapOrOverflow: Bool {
        self == .tabbed || self == .scrolling
    }

    public var usesSpatialBSPOrdering: Bool {
        self == .bsp || self == .mutableBsp
    }

    /// Mode à moteur à arbre BSP persistant (SPEC-017 R1, A8). `mutableBsp` reste décodable dans
    /// `stages.json` jusqu'à sa migration et passe par le même moteur que `spatialBsp`.
    public var usesTreeEngine: Bool {
        self == .spatialBsp || self == .mutableBsp
    }
}
