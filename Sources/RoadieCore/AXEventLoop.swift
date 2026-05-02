import Foundation
import ApplicationServices
import Cocoa

/// Délégué appelé sur le MainActor à chaque event AX significatif.
@MainActor
public protocol AXEventDelegate: AnyObject {
    func axDidCreateWindow(pid: pid_t, axWindow: AXUIElement)
    /// L'élément peut déjà être détruit côté système — `_AXUIElementGetWindow` peut
    /// retourner nil. Le delegate doit faire un lookup via comparaison CFEqual sur
    /// son registre pour retrouver le wid concerné.
    func axDidDestroyWindow(pid: pid_t, axWindow: AXUIElement)
    func axDidMoveWindow(pid: pid_t, wid: WindowID)
    func axDidResizeWindow(pid: pid_t, wid: WindowID)
    func axDidChangeFocusedWindow(pid: pid_t, axWindow: AXUIElement)
    func axDidActivateApplication(pid: pid_t)
    /// Fenêtre minimisée par l'utilisateur. Doit être retirée du tile.
    func axDidMiniaturizeWindow(pid: pid_t, axWindow: AXUIElement)
    /// Fenêtre dé-minimisée. Doit être ré-insérée dans le tile.
    func axDidDeminiaturizeWindow(pid: pid_t, axWindow: AXUIElement)
}

/// Gère les AXObservers par application.
/// Un thread CFRunLoop est créé pour chaque NSRunningApplication observée.
public final class AXEventLoop: @unchecked Sendable {
    private weak var delegate: AXEventDelegate?
    private var observers: [pid_t: AXObserver] = [:]
    private let lock = NSLock()

    private let notifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXWindowMovedNotification as String,
        kAXWindowResizedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXUIElementDestroyedNotification as String,
        kAXApplicationActivatedNotification as String,
        // kAXMainWindowChangedNotification fire systématiquement quand la main window
        // de l'app change (incluant la création initiale). Indispensable pour les apps
        // Electron qui ne fire pas kAXWindowCreatedNotification fiablement (Cursor, VSCode, …).
        kAXMainWindowChangedNotification as String,
        // Une fenêtre minimisée doit être retirée du tile (l'espace doit se redistribuer),
        // et réinsérée à la dé-minimisation. Ces notifications fire sur l'app element.
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
    ]

    public init(delegate: AXEventDelegate) {
        self.delegate = delegate
    }

    public func observe(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let pid = app.processIdentifier
        lock.lock(); defer { lock.unlock() }
        guard observers[pid] == nil else { return }   // déjà observée

        let appElement = AXUIElementCreateApplication(pid)
        var observerRef: AXObserver?
        let createErr = AXObserverCreate(pid, AXEventLoop.callback, &observerRef)
        guard createErr == .success, let observer = observerRef else {
            logWarn("AXObserverCreate failed", ["pid": String(pid), "bundle": bundleID, "err": String(createErr.rawValue)])
            return
        }

        // Stocker un context pointer vers self pour récupérer le delegate dans le callback.
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        for note in notifications {
            let err = AXObserverAddNotification(observer, appElement, note as CFString, ctx)
            if err != .success && err != .notificationAlreadyRegistered {
                logDebug("addNotification failed", ["pid": String(pid), "note": note, "err": String(err.rawValue)])
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(),
                          AXObserverGetRunLoopSource(observer),
                          .defaultMode)
        observers[pid] = observer
        logInfo("AX observed", ["pid": String(pid), "bundle": bundleID])
    }

    public func unobserve(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                             AXObserverGetRunLoopSource(observer),
                             .defaultMode)
        logInfo("AX unobserved", ["pid": String(pid)])
    }

    /// S'abonne à `kAXUIElementDestroyedNotification` SUR LA FENÊTRE elle-même.
    /// Indispensable pour détecter la fermeture d'une window — sur l'observer de l'app,
    /// cette notification ne fire pas systématiquement (limitation macOS connue,
    /// pattern utilisé par AeroSpace).
    public func subscribeDestruction(pid: pid_t, axWindow: AXUIElement) {
        lock.lock(); defer { lock.unlock() }
        guard let observer = observers[pid] else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, axWindow,
                                            kAXUIElementDestroyedNotification as CFString, ctx)
        if err != .success && err != .notificationAlreadyRegistered {
            logDebug("subscribeDestruction failed", ["pid": String(pid), "err": String(err.rawValue)])
        }
    }

    /// Callback C-compatible. On dispatch tout vers MainActor pour cohérence d'état.
    private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon = refcon else { return }
        let loop = Unmanaged<AXEventLoop>.fromOpaque(refcon).takeUnretainedValue()
        let note = notification as String
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let elementCopy = element   // strong reference for the dispatch
        Task { @MainActor in
            loop.dispatch(note: note, pid: pid, element: elementCopy)
        }
    }

    @MainActor
    private func dispatch(note: String, pid: pid_t, element: AXUIElement) {
        guard let delegate = delegate else { return }
        switch note {
        case kAXWindowCreatedNotification as String:
            delegate.axDidCreateWindow(pid: pid, axWindow: element)
        case kAXUIElementDestroyedNotification as String:
            // Toujours dispatcher : l'élément peut déjà être détruit, le delegate
            // résoudra le wid via lookup dans son registre interne.
            delegate.axDidDestroyWindow(pid: pid, axWindow: element)
        case kAXWindowMovedNotification as String:
            if let wid = axWindowID(of: element) {
                delegate.axDidMoveWindow(pid: pid, wid: wid)
            }
        case kAXWindowResizedNotification as String:
            if let wid = axWindowID(of: element) {
                delegate.axDidResizeWindow(pid: pid, wid: wid)
            }
        case kAXFocusedWindowChangedNotification as String:
            delegate.axDidChangeFocusedWindow(pid: pid, axWindow: element)
        case kAXMainWindowChangedNotification as String:
            // Traité comme un focus change pour les apps qui privilégient main window (Electron).
            delegate.axDidChangeFocusedWindow(pid: pid, axWindow: element)
        case kAXApplicationActivatedNotification as String:
            delegate.axDidActivateApplication(pid: pid)
        case kAXWindowMiniaturizedNotification as String:
            delegate.axDidMiniaturizeWindow(pid: pid, axWindow: element)
        case kAXWindowDeminiaturizedNotification as String:
            delegate.axDidDeminiaturizeWindow(pid: pid, axWindow: element)
        default:
            logDebug("AX note ignored", ["note": note, "pid": String(pid)])
        }
    }
}

/// Helpers AX pour lecture d'attributs (utilisés par le daemon).
public enum AXReader {
    public static func bounds(_ element: AXUIElement) -> CGRect? {
        var posRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success
        else { return nil }
        // Guard les casts : en cas de fenêtre zombie ou mauvais type, retourner nil
        // au lieu de trap (`as!` est un crash hard).
        guard let pRaw = posRaw, CFGetTypeID(pRaw) == AXValueGetTypeID(),
              let sRaw = sizeRaw, CFGetTypeID(sRaw) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue((pRaw as! AXValue), .cgPoint, &pos)
        AXValueGetValue((sRaw as! AXValue), .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    public static func setBounds(_ element: AXUIElement, frame: CGRect) {
        var pos = frame.origin
        var size = frame.size
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s)
        }
    }

    public static func subrole(_ element: AXUIElement) -> AXSubrole {
        var raw: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &raw)
        return AXSubrole(rawAXValue: raw as? String)
    }

    public static func title(_ element: AXUIElement) -> String {
        var raw: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &raw)
        return (raw as? String) ?? ""
    }

    public static func isMinimized(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &raw)
        return (raw as? Bool) ?? false
    }

    public static func isFullscreen(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &raw)
        return (raw as? Bool) ?? false
    }

    public static func setMinimized(_ element: AXUIElement, _ value: Bool) {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value as CFBoolean)
    }

    /// Toggle fullscreen natif macOS (la fenêtre va sur son propre Space).
    public static func setFullscreen(_ element: AXUIElement, _ value: Bool) {
        AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, value as CFBoolean)
    }

    /// Ferme la fenêtre via le close button AX (équivalent ⌘W mais via API).
    /// Retourne true si le bouton a pu être pressé.
    @discardableResult
    public static func close(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        let btn = value as! AXUIElement
        return AXUIElementPerformAction(btn, kAXPressAction as CFString) == .success
    }

    public static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    public static func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    public static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success
        else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }
}
