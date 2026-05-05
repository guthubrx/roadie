import Foundation
import AppKit
import ApplicationServices
import RoadieCore

/// SPEC-026 US5 — focus_follows_mouse.
/// Observe NSEvent.mouseMoved global ; après un throttle 100ms, identifie la
/// fenêtre sous le curseur et la focalise via FocusManager.setFocus(_:).
/// Skip si :
///   - un drag souris est actif (MouseDragHandler.isDragging)
///   - le focus est inhibé post-warp curseur (FocusManager.isFollowMouseInhibited)
///   - aucun changement de wid (déjà focused)
@MainActor
public final class FocusFollowsMouseWatcher {
    private weak var registry: WindowRegistry?
    private weak var focusManager: FocusManager?
    private weak var mouseDragHandler: MouseDragHandler?

    private var monitor: Any?
    private var lastApply: Date = .distantPast
    private var skippedZombieUntil: [WindowID: Date] = [:]
    private static let throttleSeconds: TimeInterval = 0.1

    public init(registry: WindowRegistry,
                focusManager: FocusManager,
                mouseDragHandler: MouseDragHandler) {
        self.registry = registry
        self.focusManager = focusManager
        self.mouseDragHandler = mouseDragHandler
    }

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        logInfo("focus_follows_mouse_started")
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            logInfo("focus_follows_mouse_stopped")
        }
    }

    private func handle(event: NSEvent) {
        // Throttle 100ms.
        let now = Date()
        guard now.timeIntervalSince(lastApply) >= Self.throttleSeconds else { return }
        lastApply = now
        // Skip si drag actif (priorité au drag).
        if mouseDragHandler?.isDragging == true { return }
        // Skip si focus inhibé post-warp (anti-feedback loop).
        if focusManager?.isFollowMouseInhibited() == true { return }
        guard let registry = registry, let focusManager = focusManager else { return }
        // NS coords → CG (top-left, primary screen height-flip).
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else { return }
        let nsLoc = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: nsLoc.x, y: primary.frame.height - nsLoc.y)
        guard let wid = topmostWindowID(at: cgPoint) else { return }
        // Skip si déjà focused.
        if registry.focusedWindowID == wid { return }
        // Skip si récemment marquée zombie (échec setFocus).
        if let until = skippedZombieUntil[wid], Date() < until { return }
        // Skip helper windows.
        if let state = registry.get(wid), state.isHelperWindow { return }
        // Skip wids zombies (sans AXElement). Évite le loop : sans ce skip,
        // setFocus échoue silencieusement, registry.focusedWindowID ne change
        // pas, au prochain mouseMoved on re-trigger sur la même wid morte.
        guard registry.axElement(for: wid) != nil else {
            // Cache la wid 1s pour ne pas re-essayer immédiatement.
            skippedZombieUntil[wid] = Date().addingTimeInterval(1.0)
            return
        }
        // Inhibit le warp : pas besoin de bouger le curseur, il est déjà sur
        // la fenêtre cible (c'est ce qui vient de déclencher le focus).
        focusManager.setInhibitWarp(durationSeconds: 0.4)
        focusManager.setFocus(to: wid)
        logInfo("focus_follows_mouse_triggered", ["wid": String(wid)])
    }

    /// Identifie la fenêtre top-level sous le curseur via CGWindowList.
    /// Pattern emprunté à MouseRaiser/MouseDragHandler.
    private func topmostWindowID(at cgPoint: CGPoint) -> WindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for win in info {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(cgPoint) {
                if let n = win[kCGWindowNumber as String] as? Int { return WindowID(n) }
            }
        }
        return nil
    }
}
