import Foundation
import AppKit
import CoreGraphics

/// Overlay graphique : NSWindow borderless transparente qui suit le frame d'une
/// fenêtre tracked et y dessine une bordure colorée via CALayer.
///
/// L'overlay est `ignoresMouseEvents = true` pour que les clics passent à la
/// fenêtre tracked dessous. Son `level` est forcé à `.floating` natif par
/// défaut. Pour rester strictement au-dessus de la fenêtre tracked dans tous
/// les cas (y compris au-dessus de fenêtres elles-mêmes en `.floating`), il
/// faut faire un `OSAXCommand.setLevel` côté osax — ce qui requiert SPEC-004.1.
///
/// Sans l'osax, le comportement est dégradé acceptable : 90 % des fenêtres
/// (standard) sont en-dessous du niveau `.floating` donc l'overlay les
/// recouvre correctement.
@MainActor
public final class BorderOverlay {
    private let window: NSWindow
    private let layer: CALayer
    public private(set) var trackedWID: CGWindowID
    public private(set) var trackedFrame: CGRect
    public private(set) var thickness: Int
    public private(set) var color: NSColor

    /// CGWindowID de l'overlay (différent de `trackedWID`). Permet à un caller
    /// d'envoyer un OSAXCommand.setLevel sur l'overlay pour le forcer au-dessus
    /// des autres fenêtres `.floating` natives. 0 si pas encore résolu.
    public var overlayWindowID: CGWindowID {
        CGWindowID(window.windowNumber)
    }

    public init(wid: CGWindowID, frame: CGRect, thickness: Int, color: NSColor,
                cornerRadius: CGFloat = 10) {
        self.trackedWID = wid
        self.trackedFrame = frame
        self.thickness = thickness
        self.color = color

        let pad = CGFloat(thickness)
        let axInset = frame.insetBy(dx: -pad, dy: -pad)
        let overlayFrame = Self.axToQuartz(axInset)
        let win = NSWindow(
            contentRect: overlayFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isMovable = false

        let view = NSView(frame: NSRect(origin: .zero, size: overlayFrame.size))
        view.wantsLayer = true
        let l = CALayer()
        l.borderWidth = CGFloat(thickness)
        l.borderColor = color.cgColor
        // Le rayon de l'overlay = rayon de la fenêtre tracked + padding (thickness),
        // pour que le contour épouse les coins arrondis de la fenêtre dessous.
        l.cornerRadius = cornerRadius + CGFloat(thickness)
        l.cornerCurve = .continuous
        l.frame = view.bounds
        view.layer = l
        win.contentView = view
        self.window = win
        self.layer = l
        win.orderFront(nil)
    }

    /// Met à jour le frame de la fenêtre tracked. Repositionne l'overlay et
    /// redimensionne le layer en conséquence (avec padding `thickness`).
    public func updateFrame(_ frame: CGRect) {
        trackedFrame = frame
        let pad = CGFloat(thickness)
        let overlayFrame = Self.axToQuartz(frame.insetBy(dx: -pad, dy: -pad))
        window.setFrame(overlayFrame, display: true, animate: false)
        layer.frame = CGRect(origin: .zero, size: overlayFrame.size)
    }

    /// Convertit un frame en coords AX (origin Y=0 en haut du primary, descend)
    /// vers coords Quartz (origin Y=0 en bas du primary, monte) attendues par
    /// `NSWindow.setFrame`. Le primary est l'écran avec `frame.origin == .zero`
    /// — pas forcément `NSScreen.screens[0]` en multi-display.
    private static func axToQuartz(_ axFrame: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let p = primary else { return axFrame }
        let h = p.frame.height
        return CGRect(x: axFrame.origin.x,
                      y: h - axFrame.origin.y - axFrame.height,
                      width: axFrame.width,
                      height: axFrame.height)
    }

    /// Change la couleur de la bordure. Préfère `CALayer.borderColor` direct
    /// (pas d'animation, pas d'allocation NSWindow).
    public func updateColor(_ newColor: NSColor) {
        color = newColor
        layer.borderColor = newColor.cgColor
    }

    /// Change l'épaisseur. Recalcule le frame avec le nouveau padding.
    public func updateThickness(_ newThickness: Int) {
        thickness = newThickness
        layer.borderWidth = CGFloat(newThickness)
        updateFrame(trackedFrame)
    }

    /// SPEC-008 pulse on focus : anime borderWidth `from` → `to` → `from` sur
    /// `duration` secondes via CAKeyframeAnimation native. Pas de dépendance
    /// SPEC-007 RoadieAnimations — ce pulse est local au layer de l'overlay.
    public func pulse(from: Int, to: Int, duration: TimeInterval = 0.25) {
        let anim = CAKeyframeAnimation(keyPath: "borderWidth")
        anim.values = [CGFloat(from), CGFloat(to), CGFloat(from)]
        anim.keyTimes = [0.0, 0.5, 1.0]
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "pulse")
    }

    /// Cache ou montre l'overlay sans le détruire. Utilisé par `focused_only`
    /// pour n'afficher que la bordure de la fenêtre focused tout en gardant
    /// les frames synchronisés des autres overlays.
    public func setHidden(_ hidden: Bool) {
        if hidden { window.orderOut(nil) } else { window.orderFront(nil) }
    }

    /// Ferme l'overlay et libère la NSWindow.
    public func close() {
        window.orderOut(nil)
        window.close()
    }

    deinit {
        // NSWindow doit être fermé sur main thread, mais deinit peut être appelé
        // depuis n'importe où. Si la close() n'a pas été appelée explicitement,
        // on dispatch sur main pour ne pas crash.
        let win = window
        Task { @MainActor in
            win.orderOut(nil)
            win.close()
        }
    }
}
