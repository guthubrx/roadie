import AppKit
import ApplicationServices
import RoadieAX

/// Focus clavier de l'application au premier plan à l'ouverture de la barre (session 097). Le panneau
/// prend le clavier sans activer Roadie. Fermé par Échap, il ne rend pas la frappe à l'application
/// restée active : dans T3 Code, la zone de saisie gardait le focus AX (`kept=true`) sans recevoir la
/// frappe, et les écritures AX le lui faisaient perdre. La fenêtre redevient donc clé par SkyLight
/// (session 098, ADR 020) ; l'élément sert seulement au diagnostic.
struct LauncherFocusSnapshot: @unchecked Sendable {
    let pid: pid_t
    let bundleID: String
    let window: AXUIElement?
    let element: AXUIElement?

    /// 100 ms au plus par lecture : une application figée ne retarde pas la barre plus longtemps.
    static let timeout: Float = 0.1

    /// Lu avant l'affichage du panneau, quand l'application a encore le clavier.
    static func capture(_ application: NSRunningApplication) -> LauncherFocusSnapshot {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        return LauncherFocusSnapshot(pid: application.processIdentifier, bundleID: application.bundleIdentifier ?? "",
                                     window: Self.element(app, kAXFocusedWindowAttribute),
                                     element: Self.element(app, kAXFocusedUIElementAttribute))
    }

    /// Fenêtre rendue clé. Les détails servent à l'événement `launcher.focus_restore` : `kept` dit si
    /// l'élément avait encore le focus de l'application, `key` si SkyLight a accepté la demande.
    func restore() -> [String: String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        return ["bundleID": bundleID, "saved": element == nil ? "none" : "element", "kept": String(focusIsSaved(app)),
                "key": String(window.map { WindowKeyFocus.makeKey(pid: pid, window: $0) } ?? false)]
    }

    /// L'élément enregistré a-t-il le focus de l'application ?
    func focusIsSaved(_ app: AXUIElement? = nil) -> Bool {
        let app = app ?? AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        guard let element, let current = Self.element(app, kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(current, element)
    }

    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
