import Foundation
import RoadieAX

extension WindowSnapshot {
    /// Même critère pour l'occupation des poignées et la capture des bords natifs.
    /// O(t), t = longueur du titre, seulement pour le processus de décoration identifié.
    var isKnownBorderDecoration: Bool {
        appName == "borders" && bundleID.isEmpty
            && role == nil && subrole == nil && furniture == nil
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
