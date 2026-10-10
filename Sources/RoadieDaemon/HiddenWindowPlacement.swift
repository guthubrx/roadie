import CoreGraphics
import RoadieAX

enum HiddenWindowPlacement {
    /// Frame de masquage : bord droit de l'écran le plus à droite, avec un y pris dans la plage
    /// verticale de CET écran. Un y hors de sa plage laisserait la fenêtre hors de tout écran,
    /// et macOS la replacerait de façon imprévisible. À égalité de bord droit (écrans empilés),
    /// l'écran d'origine de la fenêtre est préféré. O(d), d = nombre d'écrans.
    static func frame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let host = rightmostVisibleFrame(preferring: display, among: displays)
        let y = min(max(frame.minY, host.minY), host.maxY - 1)
        return CGRect(
            x: host.maxX - 1,
            y: y,
            width: frame.width,
            height: frame.height
        ).integral
    }

    private static func rightmostVisibleFrame(preferring display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let preferred = display.visibleFrame.cgRect
        guard let virtualMaxX = displays.map({ $0.visibleFrame.cgRect.maxX }).max(),
              virtualMaxX - preferred.maxX > 1
        else { return preferred }
        return displays
            .map { $0.visibleFrame.cgRect }
            .first { virtualMaxX - $0.maxX <= 1 } ?? preferred
    }

    static func isHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        isPreferred(frame, among: displays) || isLegacyBottomCorner(frame, in: displays)
    }

    /// `isHidden` plus l'ancienne position de masquage très loin à gauche (versions précédentes).
    /// Test unique pour tous les appelants qui filtrent les fenêtres réellement visibles.
    static func isHiddenOrLegacyOffscreen(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        frame.maxX < -1000 || frame.minX < -10000 || isHidden(frame, in: displays)
    }

    static func isPreferred(_ frame: CGRect, among displays: [DisplaySnapshot]) -> Bool {
        guard let virtualMaxX = displays.map({ $0.visibleFrame.cgRect.maxX }).max() else {
            return false
        }
        return abs(frame.minX - (virtualMaxX - 1)) <= 8
    }

    private static func isLegacyBottomCorner(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        displays.contains { display in
            let visible = display.visibleFrame.cgRect
            let nearBottomEdge = abs(frame.minY - (visible.maxY - 1)) <= 64
            let nearLeftEdge = abs(frame.maxX - (visible.minX + 1)) <= 4
            let nearRightEdge = abs(frame.minX - (visible.maxX - 1)) <= 4
            return nearBottomEdge && (nearLeftEdge || nearRightEdge)
        }
    }
}
