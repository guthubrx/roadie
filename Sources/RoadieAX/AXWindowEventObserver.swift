import AppKit
import ApplicationServices
import Foundation

/// Observe les notifications AX (windowCreated, focusChanged, miniaturized, etc.) sur toutes
/// les applications regulieres et invoque une callback a chaque evenement. Permet au daemon
/// de reagir instantanement sans attendre le prochain tick de polling.
///
/// Inspire de yabai/event_loop.c et aerospace AxApplication. La callback est appelee sur
/// la main thread (les sources AX sont ajoutees a CFRunLoopGetMain). La callback doit etre
/// idempotente : elle peut etre invoquee plusieurs fois en rafale.
public final class AXWindowEventObserver: @unchecked Sendable {
    public typealias Callback = (_ notification: String) -> Void

    private let callback: Callback
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    /// Notifications AX surveillees. Cf. yabai event_loop subscriptions.
    /// kAXTitleChangedNotification est volontairement omis : trop bruyant (browsers,
    /// terminaux le firent constamment), et n'a pas d'impact sur la decision tile/no-tile.
    /// kAXApplicationActivatedNotification est omis : declenche surtout des changements
    /// de focus, deja captes par kAXFocusedWindowChangedNotification de l'app cible.
    private static let trackedNotifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    public init(onWindowEvent: @escaping Callback) {
        self.callback = onWindowEvent
    }

    /// Demarre l'observation. A appeler depuis la main thread (les notifications AppKit
    /// reposent sur le RunLoop principal).
    public func start() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            subscribe(pid: app.processIdentifier)
        }

        let center = NSWorkspace.shared.notificationCenter
        let didLaunch = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            self?.subscribe(pid: app.processIdentifier)
        }
        let didTerminate = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.unsubscribe(pid: app.processIdentifier)
        }
        workspaceTokens = [didLaunch, didTerminate]
    }

    /// Arrete l'observation et libere les sources RunLoop.
    public func stop() {
        for (_, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observers.removeAll()
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
    }

    fileprivate func handleEvent(notification: CFString) {
        callback(notification as String)
    }

    private func subscribe(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createResult == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.trackedNotifications {
            // Erreurs ignorees : certaines apps n'autorisent pas certaines notifications.
            _ = AXObserverAddNotification(observer, appElement, notification as CFString, context)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
    }

    private func unsubscribe(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }
}

/// Callback C-compatible pour AXObserverCreate. Reroute vers l'instance Swift.
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let observerInstance = Unmanaged<AXWindowEventObserver>.fromOpaque(context).takeUnretainedValue()
    observerInstance.handleEvent(notification: notification)
}
