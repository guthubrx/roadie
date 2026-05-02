import Foundation
import AppKit
import ApplicationServices

/// Observer qui détecte les clicks sur le bureau (wallpaper).
///
/// Approche retenue : AXObserver sur Finder + kAXMouseDownEvent.
/// Déjà disponible avec la permission Accessibility (pas besoin d'Input Monitoring).
/// Plan B (non utilisé V1) : NSEvent.addGlobalMonitorForEvents — demande Input Monitoring.
///
/// Thread-safety : @MainActor. L'AXObserver callback est réémis via DispatchQueue.main
/// (convention système macOS AX).
@MainActor
public final class WallpaperClickWatcher {
    private weak var registry: WindowRegistry?
    public var onWallpaperClick: ((NSPoint) -> Void)?

    private var axObserver: AXObserver?
    private var finderElement: AXUIElement?
    private var isRunning = false

    public init(registry: WindowRegistry) {
        self.registry = registry
    }

    /// Démarre l'observation. No-op si déjà démarré ou si Finder introuvable / AX absent.
    public func start() {
        guard !isRunning else { return }
        guard let finder = findFinderApp() else {
            logWarn("wallpaper_watcher: Finder not found — watcher disabled")
            return
        }
        let finderElement = AXUIElementCreateApplication(finder.processIdentifier)
        self.finderElement = finderElement

        var observer: AXObserver?
        // Callback C : bridge vers Swift via unsafeBitCast du Unmanaged self.
        let selfPtr = Unmanaged.passRetained(self as AnyObject).toOpaque()
        let err = AXObserverCreateWithInfoCallback(finder.processIdentifier,
            { _, _, _, _, refcon in
                guard let ptr = refcon else { return }
                let watcher = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
                guard let w = watcher as? WallpaperClickWatcher else { return }
                DispatchQueue.main.async { w.handleAXMouseDown() }
            }, &observer)

        guard err == .success, let obs = observer else {
            logWarn("wallpaper_watcher: AXObserver create failed",
                    ["code": String(err.rawValue)])
            Unmanaged<AnyObject>.fromOpaque(selfPtr).release()
            return
        }

        let addErr = AXObserverAddNotification(obs, finderElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)
        if addErr != .success {
            // kAXFocusedUIElementChanged non disponible = permissions AX insuffisantes.
            logWarn("wallpaper_watcher: AXObserverAddNotification failed",
                    ["code": String(addErr.rawValue)])
        }

        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(obs), .defaultMode)
        self.axObserver = obs
        isRunning = true
        logInfo("wallpaper_watcher: started (AX Finder observer)")
    }

    /// Arrête l'observation.
    public func stop() {
        guard isRunning else { return }
        if let obs = axObserver, let el = finderElement {
            AXObserverRemoveNotification(obs, el,
                kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObserver = nil
        finderElement = nil
        isRunning = false
        logInfo("wallpaper_watcher: stopped")
    }

    // MARK: - Internal

    /// Appelé lors d'un événement AX. Vérifie si le click tombe sur le wallpaper.
    func handleAXMouseDown() {
        let point = NSEvent.mouseLocation
        guard isClickOnWallpaper(at: point) else { return }
        onWallpaperClick?(point)
    }

    /// Retourne true si le point ne tombe dans aucune fenêtre trackée ET que
    /// l'élément AX à cette position appartient au bureau Finder.
    /// Visible pour les tests (pas private).
    func isClickOnWallpaper(at point: NSPoint) -> Bool {
        // Test 1 : aucune fenêtre trackée ne contient ce point (coordonnées NS).
        if let reg = registry {
            let inWindow = reg.allWindows.contains { state in
                nsFrame(from: state.frame).contains(point)
            }
            if inWindow { return false }
        }
        // Test 2 : kAXTopLevelUIElement à ce point est nil ou appartient à Finder.
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemElement,
                                                       Float(point.x),
                                                       Float(point.y),
                                                       &element)
        if result != .success || element == nil { return true }
        guard let el = element else { return true }
        var pidValue: pid_t = 0
        AXUIElementGetPid(el, &pidValue)
        return pidValue == findFinderApp()?.processIdentifier
    }

    // MARK: - Private helpers

    private func findFinderApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.finder"
        }
    }

    /// Convertit une frame AX (origin top-left) en frame NS (origin bottom-left).
    private func nsFrame(from axFrame: CGRect) -> NSRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: axFrame.origin.x,
                      y: screenHeight - axFrame.origin.y - axFrame.height,
                      width: axFrame.width,
                      height: axFrame.height)
    }
}
