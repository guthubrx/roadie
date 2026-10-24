import CoreGraphics
import Foundation

/// Mission Control (et App Exposé) en cours. Pendant l’animation et l’affichage, macOS rapporte des
/// cadres réduits et déplacés pour toutes les fenêtres : les observer ou s’en servir pour écrire
/// rétrécit réellement les fenêtres masquées (SPEC-062). Signature mesurée : le Dock ouvre des
/// fenêtres de niveau 18 couvrant un écran entier, absentes hors Mission Control.
public enum MissionControlProbe {
    static let dockLayer = 18

    /// Une énumération CG des fenêtres à l’écran. O(n).
    public static func isActive() -> Bool {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return isActive(in: raw)
    }

    /// Fonction pure, testable sur une liste CG fournie. O(n).
    static func isActive(in windows: [[String: Any]]) -> Bool {
        windows.contains { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Dock",
                  (info[kCGWindowLayer as String] as? Int) == dockLayer,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.width >= 400 && rect.height >= 300
        }
    }
}
