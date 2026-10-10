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
    /// Notifications deja enregistrees (ou refusees definitivement) par application.
    private var registered: [pid_t: Set<String>] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var isStarted = false

    /// Notifications AX surveillees au niveau application. Cf. yabai event_loop subscriptions.
    /// kAXTitleChangedNotification est volontairement omis : trop bruyant (browsers,
    /// terminaux le firent constamment), et n'a pas d'impact sur la decision tile/no-tile.
    /// kAXApplicationActivatedNotification est omis : declenche surtout des changements
    /// de focus, deja captes par kAXFocusedWindowChangedNotification de l'app cible.
    /// kAXUIElementDestroyedNotification est aussi pose sur chaque fenetre (voir watchDestruction).
    private static let trackedNotifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    /// Notifications qui changent l'ensemble des fenetres : elles invalident le cache AX.
    private static let cacheInvalidatingNotifications: Set<String> = [
        kAXWindowCreatedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    /// Delais entre reessais d'abonnement (s). Une app qui demarre repond souvent
    /// kAXErrorCannotComplete tant que son interface AX n'est pas prete. La somme depasse
    /// la duree de mise de cote d'une app qui ne repond pas.
    private static let retryDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]

    public init(onWindowEvent: @escaping Callback) {
        self.callback = onWindowEvent
    }

    /// Demarre l'observation. A appeler depuis la main thread (les notifications AppKit
    /// reposent sur le RunLoop principal).
    public func start() {
        isStarted = true
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
        isStarted = false
        for pid in Array(observers.keys) {
            unsubscribe(pid: pid)
        }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
    }

    fileprivate func handleEvent(observer: AXObserver, element: AXUIElement, notification: CFString) {
        let name = notification as String
        if name == kAXWindowCreatedNotification as String {
            watchDestruction(of: element, observer: observer)
        }
        if Self.cacheInvalidatingNotifications.contains(name) {
            AXAttributeCache.shared.invalidate()
        }
        callback(name)
    }

    /// Abonne l'application. Les notifications refusees parce que l'app n'est pas prete sont
    /// reessayees avec un delai croissant borne. Abandon au premier delai depasse (app mise de cote).
    private func subscribe(pid: pid_t, attempt: Int = 0) {
        guard isStarted else { return }
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else {
            scheduleRetry(pid: pid, attempt: attempt)
            return
        }

        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let created else {
                scheduleRetry(pid: pid, attempt: attempt)
                return
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observers[pid] = created
            observer = created
        }

        let appElement = AXMessaging.application(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var done = registered[pid] ?? []
        var needsRetry = false
        for notification in Self.trackedNotifications where !done.contains(notification) {
            let error = AXObserverAddNotification(observer, appElement, notification as CFString, context)
            switch error {
            case .success, .notificationAlreadyRegistered, .notificationUnsupported, .notImplemented:
                // Refus definitif (notification non geree par l'app) : ne pas reessayer.
                done.insert(notification)
            default:
                needsRetry = true
            }
            if registry.noteResult(error, pid: pid) { break }
        }
        registered[pid] = done

        if !registry.isQuarantined(pid), let windows = AXApplicationWindows(pid: pid) {
            for entry in windows.entries {
                watchDestruction(of: entry.element, observer: observer)
            }
        }
        if needsRetry {
            scheduleRetry(pid: pid, attempt: attempt)
        }
    }

    private func scheduleRetry(pid: pid_t, attempt: Int) {
        guard attempt < Self.retryDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
            guard let self, self.isStarted, NSRunningApplication(processIdentifier: pid) != nil else { return }
            self.subscribe(pid: pid, attempt: attempt + 1)
        }
    }

    /// Pose kAXUIElementDestroyedNotification sur une fenetre : au niveau application, la
    /// notification n'arrive pas pour les fenetres de toutes les apps. Un doublon est sans effet.
    private func watchDestruction(of window: AXUIElement, observer: AXObserver) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, context)
    }

    private func unsubscribe(pid: pid_t) {
        registered[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
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
    observerInstance.handleEvent(observer: observer, element: element, notification: notification)
}
