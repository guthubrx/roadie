import Foundation
import RoadieAX
import RoadieCore

extension WindowSnapshot {
    /// Même critère pour l'occupation des poignées et la capture des bords natifs.
    /// O(t), t = longueur du titre, seulement pour le processus de décoration identifié.
    var isKnownBorderDecoration: Bool {
        appName == "borders" && bundleID.isEmpty
            && role == nil && subrole == nil && furniture == nil
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Le fond sans sous-rôle de Notification Center laisse passer les clics macOS.
    /// Un vrai panneau, même de cette application, reste un obstacle. O(d), d = écrans.
    func isPointerPassthrough(in displays: [DisplaySnapshot]) -> Bool {
        isKnownBorderDecoration || (bundleID == "com.apple.notificationcenterui"
            && !isTileCandidate && subrole == nil && displays.contains { $0.frame == frame })
    }
}
