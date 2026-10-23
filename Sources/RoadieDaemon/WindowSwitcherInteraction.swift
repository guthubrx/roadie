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
            case .left where dx < -1 && abs(dy) < 1,
                 .right where dx > 1 && abs(dy) < 1:
                candidates.append((i, abs(dx), 0))
            case .up where dy < -1, .down where dy > 1:
                candidates.append((i, abs(dy), abs(dx)))
            default: break
            }
        }
        return candidates.min { ($0.primary, $0.secondary, $0.index) < ($1.primary, $1.secondary, $1.index) }?.index
    }

    static func visible(_ setting: String, automatic: Bool) -> Bool {
        setting == "always" || (setting != "never" && automatic)
    }
}
