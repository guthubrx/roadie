import Cocoa
import ApplicationServices
import CoreGraphics
import IOKit.hid

// MARK: - Quadrant

/// Zone d'une fenêtre identifiée par le clic, détermine l'ancre du resize.
public enum Quadrant: String, Sendable, Equatable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}

// MARK: - MouseDragHandler

/// SPEC-015 : drag/resize de fenêtre via modifier + clic souris.
///
/// Hook `NSEvent.addGlobalMonitorForEvents` pour observer mouseDown/Dragged/Up.
/// Au mouseDown avec modifier configuré, démarre une `MouseDragSession`. Pendant
/// mouseDragged, applique `setBounds` throttlé à 30ms. Au mouseUp, commit.
@MainActor
public final class MouseDragHandler {
    public weak var registry: WindowRegistry?
    public var config: MouseConfig

    /// Callback appelé au mouseUp si la fenêtre a traversé un display. Le daemon
    /// branche ici sa logique SPEC-013 onDragDrop (réassignation arbre BSP +
    /// adoption desktop en mode per_display).
    public var onDragDrop: ((WindowID) -> Void)?

    /// Callback : retire une fenêtre de l'arbre BSP au 1er drag-move (FR-012).
    public var removeFromTile: ((WindowID) -> Void)?

    /// Callback : applique adaptToManualResize sur une fenêtre tilée resizée
    /// (FR-022). Appelé au mouseUp si la fenêtre est tileable.
    public var adaptResize: ((WindowID, CGRect) -> Void)?

    private var monitor: Any?
    private var session: MouseDragSession?
    private var totalDownEvents: Int = 0

    public init(registry: WindowRegistry, config: MouseConfig) {
        self.registry = registry
        self.config = config
    }

    // MARK: Lifecycle

    public func start() {
        guard config.actionLeft != .none
            || config.actionRight != .none
            || config.actionMiddle != .none else {
            logInfo("MouseDragHandler disabled: all actions = none")
            return
        }
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        guard granted else {
            logWarn("MouseDragHandler disabled: Input Monitoring not granted")
            return
        }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .rightMouseDown, .rightMouseDragged, .rightMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.handle(event: event, at: location) }
        }
        logInfo("MouseDragHandler started", [
            "modifier": config.modifier.rawValue,
            "left": config.actionLeft.rawValue,
            "right": config.actionRight.rawValue,
            "middle": config.actionMiddle.rawValue,
        ])
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        session = nil
    }

    /// Reload : nouvelle config, redémarre le monitor pour qu'il prenne en compte
    /// le modifier / actions à jour.
    public func reload(config newConfig: MouseConfig) {
        stop()
        self.config = newConfig
        start()
    }

    /// Vrai si un drag est actuellement en cours (= bouton mouse pressé).
    /// Utilisé par MouseRaiser pour skip son raise pendant un drag (FR-030).
    public var isDragging: Bool { session != nil }

    /// Vrai si l'event AX `axDidChangeFocusedWindow` doit suivre le focus
    /// (= modifier actuellement pressé). Permet à MouseRaiser de skip son raise.
    public func modifierIsPressed(in event: NSEvent) -> Bool {
        guard config.modifier != .none else { return false }
        // Strip CapsLock du mask : un user avec CapsLock activé ne voit pas son
        // état comme un modifier, et ça polluerait la détection. On ne garde
        // que les vraies touches de modification (shift/ctrl/alt/cmd).
        let mask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let active = event.modifierFlags.intersection(mask)
        let needed = config.modifier.nsFlags
        return active.isSuperset(of: needed)
    }

    // MARK: Event dispatch

    private func handle(event: NSEvent, at location: CGPoint) {
        switch event.type {
        case .leftMouseDown:
            totalDownEvents += 1
            // Log toutes les 10 mouse-down pour vérifier que le monitor capte.
            if totalDownEvents % 10 == 0 {
                logInfo("mouse monitor heartbeat", ["count": String(totalDownEvents)])
            }
            handleMouseDown(event: event, at: location, action: config.actionLeft)
        case .rightMouseDown:
            handleMouseDown(event: event, at: location, action: config.actionRight)
        case .otherMouseDown:
            handleMouseDown(event: event, at: location, action: config.actionMiddle)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            handleMouseDragged(at: location)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            handleMouseUp(at: location)
        default: break
        }
    }

    // MARK: MouseDown

    private func handleMouseDown(event: NSEvent, at location: CGPoint, action: MouseAction) {
        guard action != .none else { return }
        let active = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modPressed = modifierIsPressed(in: event)
        // Diagnostic : logguer chaque mouseDown gauche avec les flags reçus
        // pour identifier pourquoi le modifier ne matche pas.
        logInfo("mouse-down received", [
            "action": action.rawValue,
            "flags_raw": String(active.rawValue),
            "ctrl": active.contains(.control) ? "yes" : "no",
            "alt": active.contains(.option) ? "yes" : "no",
            "cmd": active.contains(.command) ? "yes" : "no",
            "shift": active.contains(.shift) ? "yes" : "no",
            "matches_config": modPressed ? "yes" : "no",
            "config_mod": config.modifier.rawValue,
        ])
        guard modPressed else {
            return
        }
        // Identifier la fenêtre sous le curseur via CGWindowList.
        guard let cgPoint = nsToCG(location) else {
            logWarn("mouse-drag: nsToCG failed, no primary screen?")
            return
        }
        guard let wid = topmostWindowID(at: cgPoint) else {
            logInfo("mouse-drag: no window under cursor", [
                "cg": "\(Int(cgPoint.x)),\(Int(cgPoint.y))",
            ])
            return
        }
        guard let registry = registry else {
            logWarn("mouse-drag: registry deallocated")
            return
        }
        guard let state = registry.get(wid) else {
            logInfo("mouse-drag: wid not in registry", ["wid": String(wid)])
            return
        }
        // Frame en AX (= state.frame).
        let cursorAX = cgPoint
        let quadrant = action == .resize
            ? computeQuadrant(cursor: cursorAX, frame: state.frame,
                              edgeThreshold: CGFloat(config.edgeThreshold))
            : .center
        session = MouseDragSession(
            wid: wid,
            mode: action,
            startCursor: cursorAX,
            startFrame: state.frame,
            quadrant: quadrant,
            lastApply: .distantPast,
            tileableAtStart: state.isTileable
        )
        logInfo("mouse-drag-start", [
            "wid": String(wid),
            "mode": action.rawValue,
            "quadrant": quadrant.rawValue,
        ])
    }

    // MARK: MouseDragged

    private func handleMouseDragged(at location: CGPoint) {
        guard var session = session,
              let cgPoint = nsToCG(location) else { return }
        // Throttle 30 ms (FR-040).
        let now = Date()
        guard now.timeIntervalSince(session.lastApply) >= 0.030 else { return }
        session.lastApply = now
        let delta = CGPoint(x: cgPoint.x - session.startCursor.x,
                            y: cgPoint.y - session.startCursor.y)
        let newFrame: CGRect
        switch session.mode {
        case .move:
            newFrame = session.startFrame.offsetBy(dx: delta.x, dy: delta.y)
            // FR-012 : sortir du tile au 1er drag.
            if session.tileableAtStart, let removeFromTile = removeFromTile {
                removeFromTile(session.wid)
                registry?.update(session.wid) { $0.isFloating = true }
                session.tileableAtStart = false
            }
        case .resize:
            newFrame = computeResizedFrame(start: session.startFrame,
                                           delta: delta,
                                           quadrant: session.quadrant)
        case .none:
            return
        }
        if let element = registry?.axElement(for: session.wid) {
            AXReader.setBounds(element, frame: newFrame)
        }
        registry?.updateFrame(session.wid, frame: newFrame)
        self.session = session
    }

    // MARK: MouseUp

    private func handleMouseUp(at location: CGPoint) {
        guard var session = session else { return }
        // Final setBounds inconditionnel.
        if let cgPoint = nsToCG(location) {
            let delta = CGPoint(x: cgPoint.x - session.startCursor.x,
                                y: cgPoint.y - session.startCursor.y)
            let finalFrame: CGRect
            switch session.mode {
            case .move:
                finalFrame = session.startFrame.offsetBy(dx: delta.x, dy: delta.y)
            case .resize:
                finalFrame = computeResizedFrame(start: session.startFrame,
                                                 delta: delta,
                                                 quadrant: session.quadrant)
            case .none:
                self.session = nil
                return
            }
            if let element = registry?.axElement(for: session.wid) {
                AXReader.setBounds(element, frame: finalFrame)
            }
            registry?.updateFrame(session.wid, frame: finalFrame)
            session.startFrame = finalFrame   // pour les callbacks ci-dessous
        }
        // Callbacks.
        if session.mode == .move {
            onDragDrop?(session.wid)   // SPEC-013 cross-display
        } else if session.mode == .resize, session.tileableAtStart,
                  let registry = registry,
                  let state = registry.get(session.wid) {
            adaptResize?(session.wid, state.frame)
        }
        logInfo("mouse-drag-end", [
            "wid": String(session.wid),
            "mode": session.mode.rawValue,
        ])
        self.session = nil
    }

    // MARK: NS → CG conversion

    /// Convertit NSEvent.mouseLocation (NS coords) en CG coords (top-left du primary).
    private func nsToCG(_ ns: CGPoint) -> CGPoint? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else { return nil }
        return CGPoint(x: ns.x, y: primary.frame.height - ns.y)
    }

    /// Identifie la fenêtre top-level (layer 0) sous le curseur via CGWindowList.
    /// Pattern emprunté à MouseRaiser (déjà battle-tested).
    private func topmostWindowID(at cgPoint: CGPoint) -> WindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard rect.contains(cgPoint) else { continue }
            if let wid = entry[kCGWindowNumber as String] as? CGWindowID {
                return WindowID(wid)
            }
            return nil
        }
        return nil
    }
}

// MARK: - MouseDragSession

public struct MouseDragSession {
    public let wid: WindowID
    public let mode: MouseAction
    public let startCursor: CGPoint
    public var startFrame: CGRect
    public let quadrant: Quadrant
    public var lastApply: Date
    public var tileableAtStart: Bool
}

// MARK: - Quadrant computation (FR-020)

/// Calcule le quadrant du clic dans la frame. Pure function, testable.
/// `edgeThreshold` est la distance en px d'un bord pour matcher un quadrant
/// "edge" (T/B/L/R) au lieu de centre/coin.
public func computeQuadrant(cursor: CGPoint, frame: CGRect, edgeThreshold: CGFloat) -> Quadrant {
    let dx = cursor.x - frame.minX
    let dy = cursor.y - frame.minY
    let nearLeft = dx < edgeThreshold
    let nearRight = dx > frame.width - edgeThreshold
    let nearTop = dy < edgeThreshold
    let nearBottom = dy > frame.height - edgeThreshold
    if nearLeft && nearTop { return .topLeft }
    if nearRight && nearTop { return .topRight }
    if nearLeft && nearBottom { return .bottomLeft }
    if nearRight && nearBottom { return .bottomRight }
    if nearTop { return .top }
    if nearBottom { return .bottom }
    if nearLeft { return .left }
    if nearRight { return .right }
    // Center : tomber sur le quadrant le plus proche en regardant les 1/3.
    let third = CGPoint(x: frame.width / 3, y: frame.height / 3)
    let inLeftThird = dx < third.x
    let inRightThird = dx > 2 * third.x
    let inTopThird = dy < third.y
    let inBottomThird = dy > 2 * third.y
    if inLeftThird && inTopThird { return .topLeft }
    if inRightThird && inTopThird { return .topRight }
    if inLeftThird && inBottomThird { return .bottomLeft }
    if inRightThird && inBottomThird { return .bottomRight }
    if inTopThird { return .top }
    if inBottomThird { return .bottom }
    if inLeftThird { return .left }
    if inRightThird { return .right }
    return .center
}

// MARK: - Resize frame computation (FR-021)

/// Calcule la nouvelle frame d'un resize selon le quadrant et le delta.
/// L'ancre est le coin/bord opposé au quadrant cliqué.
public func computeResizedFrame(start: CGRect, delta: CGPoint, quadrant: Quadrant) -> CGRect {
    let minSize: CGFloat = 100   // taille minimum sane
    var newFrame = start
    switch quadrant {
    case .topLeft:
        newFrame.origin.x += delta.x
        newFrame.origin.y += delta.y
        newFrame.size.width -= delta.x
        newFrame.size.height -= delta.y
    case .top:
        newFrame.origin.y += delta.y
        newFrame.size.height -= delta.y
    case .topRight:
        newFrame.origin.y += delta.y
        newFrame.size.width += delta.x
        newFrame.size.height -= delta.y
    case .right:
        newFrame.size.width += delta.x
    case .bottomRight, .center:
        newFrame.size.width += delta.x
        newFrame.size.height += delta.y
    case .bottom:
        newFrame.size.height += delta.y
    case .bottomLeft:
        newFrame.origin.x += delta.x
        newFrame.size.width -= delta.x
        newFrame.size.height += delta.y
    case .left:
        newFrame.origin.x += delta.x
        newFrame.size.width -= delta.x
    }
    // Clamp taille minimum.
    if newFrame.size.width < minSize {
        if quadrant == .topLeft || quadrant == .left || quadrant == .bottomLeft {
            newFrame.origin.x = start.maxX - minSize
        }
        newFrame.size.width = minSize
    }
    if newFrame.size.height < minSize {
        if quadrant == .topLeft || quadrant == .top || quadrant == .topRight {
            newFrame.origin.y = start.maxY - minSize
        }
        newFrame.size.height = minSize
    }
    return newFrame
}

// MARK: - ModifierKey nsFlags

extension ModifierKey {
    public var nsFlags: NSEvent.ModifierFlags {
        switch self {
        case .ctrl: return .control
        case .alt: return .option
        case .cmd: return .command
        case .shift: return .shift
        case .hyper: return [.control, .option, .command, .shift]
        case .none: return []
        }
    }
}
