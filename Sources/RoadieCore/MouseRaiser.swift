import Cocoa
import ApplicationServices
import CoreGraphics
import IOKit.hid

/// Observe les clics gauche globaux et raise la fenêtre cliquée si elle n'est pas frontmost.
///
/// AeroSpace ne fait pas ça : conséquence — si une fenêtre tilée se retrouve sous une autre
/// (cas de Cursor non-tilé qui s'ouvre par-dessus, ou d'une fenêtre flottante qui chevauche),
/// cliquer sur la fenêtre cachée ne la ramène pas au-dessus.
///
/// On comble ce trou en hookant `NSEvent.addGlobalMonitorForEvents(.leftMouseDown)`,
/// localisant la fenêtre sous le curseur via `CGWindowListCopyWindowInfo`, et en appelant
/// `AXUIElementPerformAction(element, kAXRaiseAction)` dessus.
@MainActor
public final class MouseRaiser {
    private let registry: WindowRegistry
    private var monitor: Any?

    public init(registry: WindowRegistry) {
        self.registry = registry
    }

    public func start() {
        // NSEvent.addGlobalMonitorForEvents nécessite la permission Input Monitoring
        // (kTCCServiceListenEvent) sur macOS 10.15+ et fail silencieusement sans elle.
        // IOHIDRequestAccess force la prompt système la 1ère fois et lit le statut ensuite.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        guard granted else {
            FileHandle.standardError.write("""
            roadied: permission Input Monitoring manquante — click-to-raise désactivé.
            Réglages Système > Confidentialité et sécurité > Surveillance des entrées,
            ajoute ~/Applications/roadied.app et coche-le, puis relance le démon.

            """.data(using: .utf8) ?? Data())
            logWarn("MouseRaiser disabled: Input Monitoring not granted")
            return
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Le monitor fire sur un thread non-main. Dispatch vers MainActor pour
            // accéder au registry en sécurité.
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.handleClick(at: location) }
        }
        logInfo("MouseRaiser started")
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleClick(at nsScreenLocation: CGPoint) {
        // NSEvent.mouseLocation est en coords NSScreen (origin bottom-left).
        // CGWindowList retourne des bounds en coords AX (origin top-left).
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(
            x: nsScreenLocation.x,
            y: screen.frame.height - nsScreenLocation.y
        )

        // Liste des fenêtres on-screen, ordre Z (frontmost en premier).
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return }

        // Trouver la première fenêtre tot-level qui contient le point cliqué.
        for entry in info {
            // Filtrer les niveaux non-fenêtre (menu bar, Dock = layer != 0).
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard rect.contains(cgPoint) else { continue }

            guard let wid = entry[kCGWindowNumber as String] as? CGWindowID else { return }
            // Si on connaît cette fenêtre dans le registry et qu'elle n'est pas déjà focused,
            // la raise. Pas de log si c'est déjà la focused (95 % des clics).
            if let element = registry.axElement(for: wid),
               let state = registry.get(wid),
               registry.focusedWindowID != wid {
                // Combo complet (yabai-style) pour défaire les protections d'activation
                // Sonoma+/Sequoia/Tahoe. Aucune sous-étape ne suffit seule selon les apps :
                //   1. kAXRaiseAction : z-order intra-app
                //   2. kAXMain/kAXFocused : marque la window comme primaire de l'app
                //   3. WindowActivator (SkyLight privée) : bring-to-front inter-app
                //   4. NSRunningApplication.activate(.activateIgnoringOtherApps) :
                //      yieldActivation pattern public, complète SLPS pour les apps
                //      Electron qui se ré-auto-activent (Grayjay, Cursor)
                AXReader.raise(element)
                AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                WindowActivator.bringToFront(pid: state.pid, windowID: wid)
                NSRunningApplication(processIdentifier: state.pid)?.activate(options: [.activateIgnoringOtherApps])
                logInfo("click-to-raise", ["wid": String(wid), "pid": String(state.pid)])
            }
            return   // un seul match : la frontmost à cette position
        }
    }
}
