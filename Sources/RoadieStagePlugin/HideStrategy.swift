import Foundation
import ApplicationServices
import Cocoa
import RoadieCore

/// Implémentation des stratégies de masquage de fenêtres pour le stage manager.
/// Voir ADR-003.
public enum HideStrategyImpl {

    @MainActor
    public static func hide(_ wid: WindowID, registry: WindowRegistry, strategy: HideStrategy) {
        guard let element = registry.axElement(for: wid) else { return }
        // Capturer la frame actuelle pour restauration ultérieure.
        if let frame = AXReader.bounds(element) {
            registry.updateFrame(wid, frame: frame)
        }
        switch strategy {
        case .corner:
            moveOffScreen(element)
        case .minimize:
            AXReader.setMinimized(element, true)
        case .hybrid:
            moveOffScreen(element)
            AXReader.setMinimized(element, true)
        }
    }

    @MainActor
    public static func show(_ wid: WindowID, registry: WindowRegistry, strategy: HideStrategy) {
        guard let element = registry.axElement(for: wid),
              let state = registry.get(wid) else { return }
        switch strategy {
        case .corner:
            AXReader.setBounds(element, frame: state.frame)
        case .minimize:
            AXReader.setMinimized(element, false)
        case .hybrid:
            AXReader.setMinimized(element, false)
            AXReader.setBounds(element, frame: state.frame)
        }
    }

    /// Reproduction littérale de AeroSpace `MacWindow.hideInCorner(.bottomLeftCorner)` :
    /// `position = visibleRect.bottomLeftCorner + (1, -1) + (-windowWidth, 0)`
    /// Source: AeroSpace/Sources/AppBundle/tree/MacWindow.swift, hideInCorner.
    /// L'astuce : positionner la fenêtre simultanément hors champ en x ET en y
    /// (coin bas-gauche, fenêtre dépassant en bas) empêche macOS de clamper la
    /// position en x (clamp ne se déclenche que si la fenêtre semble "rattrapable").
    @MainActor
    private static func moveOffScreen(_ element: AXUIElement) {
        guard let frame = AXReader.bounds(element),
              let screen = NSScreen.main else { return }
        // Conversion visibleFrame NSScreen (origin BL) → AX (origin TL).
        let full = screen.frame
        let visible = screen.visibleFrame
        let visibleAX = CGRect(
            x: visible.origin.x,
            y: full.height - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
        // bottomLeftCorner en AX = (minX, maxY)
        let bottomLeftCorner = CGPoint(x: visibleAX.minX, y: visibleAX.maxY)
        let onePixelOffset = CGPoint(x: 1, y: -1)
        let p = CGPoint(
            x: bottomLeftCorner.x + onePixelOffset.x + (-frame.size.width),
            y: bottomLeftCorner.y + onePixelOffset.y
        )
        var pos = p
        if let value = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }
}
