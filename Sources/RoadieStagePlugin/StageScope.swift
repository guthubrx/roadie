import Foundation
import RoadieCore

/// Clé composite identifiant un stage dans un contexte (display, desktop, stageID).
/// En mode global (V1 compat), utilise le sentinel `.global(_:)` qui ignore
/// les dimensions display/desktop.
public struct StageScope: Hashable, Sendable, Codable {
    public let displayUUID: String
    public let desktopID: Int
    public let stageID: StageID

    public init(displayUUID: String, desktopID: Int, stageID: StageID) {
        self.displayUUID = displayUUID
        self.desktopID = desktopID
        self.stageID = stageID
    }

    /// Sentinel pour mode `global` (sans contexte display/desktop).
    /// Utilisé par FlatStagePersistence et pour la compat ascendante V1.
    public static func global(_ stageID: StageID) -> StageScope {
        StageScope(displayUUID: "", desktopID: 0, stageID: stageID)
    }

    /// True si ce scope est le sentinel mode global (displayUUID vide + desktopID == 0).
    public var isGlobal: Bool {
        displayUUID.isEmpty && desktopID == 0
    }
}
