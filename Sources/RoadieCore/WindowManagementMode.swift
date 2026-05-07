public enum WindowManagementMode: String, Codable, Sendable, CaseIterable {
    case bsp
    case masterStack
    case float

    public init?(roadieValue: String) {
        switch roadieValue {
        case "bsp":
            self = .bsp
        case "masterStack", "master_stack", "master-stack":
            self = .masterStack
        case "float", "floating":
            self = .float
        default:
            return nil
        }
    }
}
