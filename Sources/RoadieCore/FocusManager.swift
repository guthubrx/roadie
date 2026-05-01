import Foundation
import ApplicationServices
import Cocoa

/// Synchronise l'état focus interne avec macOS.
/// Différenciateur du projet : utilise `kAXApplicationActivatedNotification` pour rattraper
/// les clics souris qui ne déclenchent pas correctement `kAXFocusedWindowChangedNotification`
/// sur les apps Electron / JetBrains.
@MainActor
public final class FocusManager {
    private let registry: WindowRegistry

    public init(registry: WindowRegistry) {
        self.registry = registry
    }

    /// Re-synchronise le focus à partir du système.
    /// Appelé à chaque kAXApplicationActivatedNotification + kAXFocusedWindowChangedNotification.
    public func refreshFromSystem() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            registry.setFocus(nil)
            return
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        guard let focused = AXReader.focusedWindow(of: appElement),
              let wid = axWindowID(of: focused)
        else {
            return
        }
        registry.setFocus(wid)
    }

    public func setFocus(to wid: WindowID) {
        guard let element = registry.axElement(for: wid) else {
            logWarn("setFocus: window AX element missing", ["wid": String(wid)])
            return
        }
        AXReader.raise(element)
        // Activer l'app pour que le focus visuel suive
        if let state = registry.get(wid),
           let app = NSRunningApplication(processIdentifier: state.pid) {
            app.activate()
        }
        registry.setFocus(wid)
    }
}
