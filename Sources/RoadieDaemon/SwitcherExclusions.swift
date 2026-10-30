import Foundation
import RoadieCore

/// Sens interdit des cartes du sélecteur (session 137) : l'application rejoint une liste des Paramètres, annulable.
enum SwitcherExclusions {
    static let windows = "switcher.excluded_bundles"
    static let clickZones = "switcher.zone_click_excluded_bundles"

    /// Ajoute l'application à la liste (sans doublon). Vrai si la liste a changé. O(n).
    static func add(_ bundleID: String, to id: String, settings: SettingsService = SettingsService()) -> Bool {
        guard !bundleID.isEmpty, let descriptor = SettingsCatalog.find(id: id),
              case .success(.list(let values)) = settings.collection(of: descriptor) else { return false }
        guard !values.contains(.string(bundleID)) else { return false }
        if case .applied = settings.setCollection(id, .list(values + [.string(bundleID)])) { return true }
        return false
    }
}
