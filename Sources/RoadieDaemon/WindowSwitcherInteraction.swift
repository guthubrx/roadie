import CoreGraphics
import RoadieCore

enum SwitcherDirection { case left, right, up, down }

/// Coordonnées de grille retournées par WindowSwitcherGrid (origine en haut). O(n).
enum SwitcherNavigation {
    static func destination(from index: Int, direction: SwitcherDirection, frames: [CGRect]) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let origin = frames[index]
        var candidates: [(index: Int, primary: CGFloat, secondary: CGFloat)] = []
        for (i, frame) in frames.enumerated() where i != index {
            let dx = frame.midX - origin.midX, dy = frame.midY - origin.midY
            switch direction {
            case .left where dx < -1, .right where dx > 1:
                // Les cartes de la vue spatiale n'ont pas toutes la même hauteur.
                let rowDistance = max(0, abs(dy) - (origin.height + frame.height) / 2)
                candidates.append((i, rowDistance, abs(dx)))
            case .up where dy < -1, .down where dy > 1:
                let columnDistance = max(0, abs(dx) - (origin.width + frame.width) / 2)
                candidates.append((i, columnDistance, abs(dy)))
            default: break
            }
        }
        return candidates.min { ($0.primary, $0.secondary, $0.index) < ($1.primary, $1.secondary, $1.index) }?.index
    }

    static func visible(_ setting: String, automatic: Bool) -> Bool {
        setting == "always" || (setting != "never" && automatic)
    }
}

/// Maj seule pendant le sélecteur (session 139), comme dans AltTab : relâchée sans pas entre-temps (Tab, flèche),
/// elle recule d'une carte. Maj + Tab garde son seul recul : un pas pendant que Maj est tenue annule le sien.
struct SwitcherShiftTap: Equatable {
    private var down = false
    private var stepped = false

    /// `initiallyDown` : Maj déjà tenue à l'ouverture (⌘⇧Tab), qui compte comme un pas.
    init(initiallyDown: Bool = false) {
        down = initiallyDown
        stepped = initiallyDown
    }

    /// Un pas du sélecteur pendant que Maj est tenue. O(1).
    mutating func noteStep() {
        if down { stepped = true }
    }

    /// État de Maj relevé ; vrai quand Maj vient d'être relâchée seule. O(1).
    mutating func update(shift: Bool) -> Bool {
        defer { down = shift }
        if shift, !down { stepped = false }
        return !shift && down && !stepped
    }
}
