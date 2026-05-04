// Adapted from AeroSpace (MIT, Copyright (c) 2023 Nikita Bobko).
// Original source : AeroSpace/Sources/AppBundle/tree/MacWindow.swift, hideInCorner.
// See THIRD_PARTY_LICENSES.md at the repository root for the full MIT notice.

import Foundation
import ApplicationServices
import Cocoa

/// Implémentation des stratégies de masquage de fenêtres pour le stage manager.
/// Voir ADR-003.
public enum HideStrategyImpl {

    @MainActor
    public static func hide(_ wid: WindowID, registry: WindowRegistry, strategy: HideStrategy) {
        guard let element = registry.axElement(for: wid) else { return }
        // BUGFIX SPEC-013 : capturer dans expectedFrame, PAS dans frame.
        // moveOffScreen va déclencher kAXWindowMovedNotification → axDidMoveWindow
        // → registry.updateFrame(...) qui écrasait state.frame avec la position
        // offscreen. Au show suivant, on tentait de restorer à offscreen → fenêtre
        // invisible. expectedFrame n'est pas modifié par les events AX, c'est notre
        // source de vérité pour la position pré-hide.
        // 2nd BUGFIX : NE PAS écraser expectedFrame si la frame courante est
        // déjà offscreen (cas hide consécutifs sans show entre). Sinon
        // expectedFrame devient offscreen et le show ne sait plus où restorer.
        if let frame = AXReader.bounds(element), isOnScreen(frame) {
            registry.update(wid) { $0.expectedFrame = frame }
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
              let state = registry.get(wid) else {
            logWarn("hide_strategy_show_no_element", ["wid": String(wid)])
            return
        }
        // SPEC-013 fix : restorer depuis expectedFrame (sauvegardée dans hide()).
        // SPEC-025 FR-007 — fallback safe sur primary visible center si :
        //   - expectedFrame == .zero (jamais initialisée)
        //   - ET state.frame est offscreen (= en dehors de tous les displays connus)
        // Garantit qu'une fenêtre show() réapparait toujours quelque part de visible.
        // Cause racine BUG-001 : sans ce fallback, target = state.frame = -2117 → setBounds(-2117) = no-op.
        let target: CGRect
        if state.expectedFrame != .zero, isOnScreen(state.expectedFrame) {
            target = state.expectedFrame
        } else if isOnScreen(state.frame) {
            target = state.frame
        } else {
            target = primaryVisibleCenterRect()
            logWarn("hide_strategy_show_fallback_center", [
                "wid": String(wid),
                "expected_frame_zero": String(state.expectedFrame == .zero),
                "state_frame": "\(Int(state.frame.origin.x)),\(Int(state.frame.origin.y))",
                "fallback": "\(Int(target.origin.x)),\(Int(target.origin.y)) \(Int(target.width))x\(Int(target.height))",
            ])
        }
        switch strategy {
        case .corner:
            AXReader.setBounds(element, frame: target)
        case .minimize:
            AXReader.setMinimized(element, false)
        case .hybrid:
            AXReader.setMinimized(element, false)
            AXReader.setBounds(element, frame: target)
        }
    }

    /// SPEC-025 FR-007 — frame de fallback safe : centre du primary display
    /// visible, ~50% de sa taille. Utilisée par `show()` quand aucune frame
    /// connue (expectedFrame ou state.frame) n'est sur un display connu.
    @MainActor
    private static func primaryVisibleCenterRect() -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let p = primary else {
            return CGRect(x: 100, y: 100, width: 800, height: 600)
        }
        // Calcul en NS coords (origin bottom-left) puis conversion AX (top-left primary).
        let nsFrame = p.visibleFrame
        let w = nsFrame.width * 0.5
        let h = nsFrame.height * 0.5
        let nsX = nsFrame.origin.x + (nsFrame.width - w) / 2
        let nsY = nsFrame.origin.y + (nsFrame.height - h) / 2
        // Conversion vers AX coords (origin top-left du primary).
        let axY = p.frame.height - nsY - h
        return CGRect(x: nsX, y: axY, width: w, height: h)
    }

    /// Reproduction littérale de AeroSpace `MacWindow.hideInCorner(.bottomLeftCorner)` :
    /// `position = visibleRect.bottomLeftCorner + (1, -1) + (-windowWidth, 0)`
    /// Source: AeroSpace/Sources/AppBundle/tree/MacWindow.swift, hideInCorner.
    /// L'astuce : positionner la fenêtre simultanément hors champ en x ET en y
    /// (coin bas-gauche, fenêtre dépassant en bas) empêche macOS de clamper la
    /// position en x (clamp ne se déclenche que si la fenêtre semble "rattrapable").
    ///
    /// SPEC-013 fix : cacher dans le coin du DISPLAY contenant la fenêtre, pas du
    /// primary. Sans ça, hide d'une fenêtre LG la fait apparaître dans le coin du
    /// built-in (= visuellement sur l'autre écran).
    /// Vrai si le centre du frame AX tombe dans un display physique.
    /// Utilisé pour détecter les fenêtres déjà cachées via moveOffScreen.
    @MainActor
    private static func isOnScreen(_ frameAX: CGRect) -> Bool {
        guard screenContaining(frameAX: frameAX) != nil else { return false }
        // Seuil minimal pour rejeter les frames dégénérées (collapsed AX, x20px
        // fantômes) sans exclure toolbars/widgets légitimes (Notes Reminder etc.
        // peuvent descendre sous 100px). 20 = empiriquement sain : moveOffScreen
        // utilisé sur fenêtre offscreen donne typiquement height < 5.
        return frameAX.size.height >= 20
    }

    /// Résout le `NSScreen` contenant le centre d'un `CGRect` exprimé en
    /// coordonnées AX (Y top-down). Retourne nil si aucun écran ne contient
    /// le centre. Utilisé par `isOnScreen` et `moveOffScreen` (déduplication).
    @MainActor
    private static func screenContaining(frameAX: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else { return nil }
        let primaryHeight = primary.frame.height
        let centerNS = CGPoint(x: frameAX.midX,
                               y: primaryHeight - frameAX.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(centerNS) })
    }

    @MainActor
    private static func moveOffScreen(_ element: AXUIElement) {
        guard let frame = AXReader.bounds(element) else { return }
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
        guard let primary else { return }
        let primaryHeight = primary.frame.height
        // Résoudre le screen contenant la fenêtre, fallback primary.
        let screen = screenContaining(frameAX: frame) ?? primary
        // Conversion visibleFrame du SCREEN contenant la fenêtre (NS BL) → AX (TL).
        let visible = screen.visibleFrame
        let visibleAX = CGRect(
            x: visible.origin.x,
            y: primaryHeight - visible.origin.y - visible.height,
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
