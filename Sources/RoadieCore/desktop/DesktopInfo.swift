import Foundation

/// Snapshot d'un desktop macOS (Mission Control Space) tel qu'observé par roadie.
/// L'`uuid` est stable entre redémarrages (tant que macOS ne détruit pas le desktop) ;
/// l'`index` est volatile (changera si l'utilisateur réordonne les desktops).
public struct DesktopInfo: Equatable, Sendable {
    public let uuid: String
    public let index: Int
    public let label: String?

    public init(uuid: String, index: Int, label: String? = nil) {
        self.uuid = uuid
        self.index = index
        self.label = label
    }
}
