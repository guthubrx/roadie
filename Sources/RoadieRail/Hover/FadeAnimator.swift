import AppKit

// SPEC-014 T026 — Animations de fondu entrée/sortie sur NSPanel (FR-011, 200ms).

/// Gère les animations d'opacité sur les NSPanel du rail.
final class FadeAnimator {
    /// Fait apparaître le panel en fondu (alpha 0 → 1).
    /// `orderFrontRegardless()` (et non `orderFront(nil)`) car le process tourne en
    /// `.accessory` (LSUIElement) : il n'est jamais "active app", donc `orderFront`
    /// classique ne dessine pas la fenêtre. Le `Regardless` ignore l'état d'activation.
    func fadeIn(_ panel: NSPanel, duration: TimeInterval = 0.2) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Fait disparaître le panel en fondu (alpha 1 → 0), puis appelle onComplete.
    func fadeOut(_ panel: NSPanel, duration: TimeInterval = 0.2,
                 onComplete: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
            onComplete?()
        }
    }
}
