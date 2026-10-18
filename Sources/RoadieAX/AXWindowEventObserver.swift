import AppKit
import ApplicationServices
import Foundation

/// Événement AX transmis au daemon : nom de la notification, application et fenêtre (A12).
public struct AXWindowEvent: Sendable, Equatable {
    public var name: String
    public var pid: pid_t
    public var windowID: UInt32?

    public init(name: String, pid: pid_t, windowID: UInt32?) {
        self.name = name
        self.pid = pid
        self.windowID = windowID
    }
}

/// Observe les notifications AX (windowCreated, focusChanged, miniaturized, etc.) sur toutes
/// les applications regulieres et invoque une callback a chaque evenement. Permet au daemon
/// de reagir instantanement sans attendre le prochain tick de polling.
///
/// Inspire de yabai/event_loop.c et aerospace AxApplication. La callback est appelee sur
/// la main thread (les sources AX sont ajoutees a CFRunLoopGetMain). La callback doit etre
/// idempotente : elle peut etre invoquee plusieurs fois en rafale.
/// Isole sur le MainActor : l'etat (`observers`, `registered`, `isStarted`) n'est touche
/// que depuis la main thread, le compilateur le verifie.
@MainActor
public final class AXWindowEventObserver {
    public typealias Callback = (_ notification: String) -> Void
    public typealias EventCallback = (_ event: AXWindowEvent) -> Void

    private let callback: EventCallback
    /// Notifications posees au niveau application : sans deplacement ni redimensionnement
    /// pour l'ancienne callback, dont le daemon ne sait pas filtrer l'echo.
    private let notifications: [String]
    private let writtenFrames: WrittenFrameRegistry
    private let mouseButtonsPressed: () -> Bool
    private var observers: [pid_t: AXObserver] = [:]
    /// Notifications deja enregistrees (ou refusees definitivement) par application.
    private var registered: [pid_t: Set<String>] = [:]
    /// ID des fenetres surveillees pour leur destruction : un element detruit ne repond plus
    /// a `_AXUIElementGetWindow`, on le retrouve par egalite d'element (CFEqual).
    private var watchedWindowIDs: [pid_t: [AXUIElement: CGWindowID]] = [:]
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

    /// Deplacement et redimensionnement, observes comme yabai (`application.h`). Un echo de nos
    /// propres ecritures est absorbe dans le callback (A1).
    static let frameNotifications: Set<String> = [
        kAXWindowMovedNotification as String,
        kAXWindowResizedNotification as String,
    ]

    /// Notifications qui changent l'ensemble des fenetres : elles invalident les caches AX du pid.
    private static let cacheInvalidatingNotifications: Set<String> = [
        kAXWindowCreatedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    /// Delais entre reessais d'abonnement (s). Une app qui demarre repond souvent
    /// kAXErrorCannotComplete tant que son interface AX n'est pas prete. La somme depasse
    /// la duree de mise de cote d'une app qui ne repond pas.
    private static let retryDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]

    /// Ancienne callback (nom de notification seul), sans deplacement ni redimensionnement.
    public init(onWindowEvent: @escaping Callback) {
        self.callback = { onWindowEvent($0.name) }
        self.notifications = Self.trackedNotifications
        self.writtenFrames = .shared
        self.mouseButtonsPressed = { NSEvent.pressedMouseButtons != 0 }
    }

    /// Callback complete, avec deplacement et redimensionnement ; l'echo est absorbe.
    public convenience init(onEvent: @escaping EventCallback) {
        self.init(writtenFrames: .shared, onEvent: onEvent)
    }

    init(
        writtenFrames: WrittenFrameRegistry,
        mouseButtonsPressed: @escaping () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        onEvent: @escaping EventCallback
    ) {
        self.callback = onEvent
        self.notifications = Self.trackedNotifications + Self.frameNotifications.sorted()
        self.writtenFrames = writtenFrames
        self.mouseButtonsPressed = mouseButtonsPressed
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
            MainActor.assumeIsolated { self?.subscribe(pid: app.processIdentifier) }
        }
        let didTerminate = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.unsubscribe(pid: app.processIdentifier) }
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
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        let isDestroyed = name == kAXUIElementDestroyedNotification as String
        let windowID = (isDestroyed ? watchedWindowIDs[pid]?.removeValue(forKey: element) : nil)
            ?? Self.windowID(of: element, pid: pid)
        if name == kAXWindowCreatedNotification as String {
            watchDestruction(of: element, id: windowID, observer: observer, pid: pid)
        }
        if Self.cacheInvalidatingNotifications.contains(name) {
            AXAttributeCache.shared.invalidate(pid: pid)
            AXWindowIndexCache.shared.invalidate(pid: pid)
        }
        let event = AXWindowEvent(name: name, pid: pid, windowID: windowID)
        let observed = Self.frameNotifications.contains(name) && windowID != nil
            && !AXUnresponsiveApps.shared.isQuarantined(pid)
            ? AXWindowFrameWriter().frame(of: element, pid: pid) : nil
        dispatch(event, observedFrame: observed, now: Date())
    }

    /// Transmet l'evenement, sauf un deplacement ou redimensionnement classe echo par le
    /// registre : il ne planifie aucune passe (A1). Avant d'etre absorbe, un echo de la relecture
    /// confirme le refus de taille en attente (A14), sauf ambiguïté entre générations.
    /// Pendant un appui souris, le maintainer garde la priorité du geste et sa géométrie :
    /// transmettre la notification ne crée ici aucune intention ni génération. O(1).
    func dispatch(_ event: AXWindowEvent, observedFrame: CGRect?, now: Date) {
        if event.name == kAXUIElementDestroyedNotification as String, let windowID = event.windowID {
            writtenFrames.forget(windowID: windowID)
        }
        if Self.frameNotifications.contains(event.name), let windowID = event.windowID, let observedFrame,
           !mouseButtonsPressed(),
           writtenFrames.consumeEcho(windowID: windowID, observed: observedFrame, now: now) {
            return
        }
        callback(event)
    }

    /// ID CoreGraphics d'une fenetre AX, nil pour un element application ou illisible.
    private static func windowID(of element: AXUIElement, pid: pid_t) -> CGWindowID? {
        guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return nil }
        var id = CGWindowID()
        let error = AXUIElementGetWindowID(element, &id)
        AXUnresponsiveApps.shared.noteResult(error, pid: pid)
        return error == .success && id > 0 ? id : nil
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
        for notification in notifications where !done.contains(notification) {
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
                // Application mise de côté : inutile d'attendre un délai par fenêtre restante.
                if watchDestruction(of: entry.element, id: entry.id, observer: observer, pid: pid) { break }
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
    /// Retourne vrai si l'application ne repond plus (mise de cote) : l'appelant interrompt la boucle.
    @discardableResult
    private func watchDestruction(of window: AXUIElement, id: CGWindowID?, observer: AXObserver, pid: pid_t) -> Bool {
        if let id { watchedWindowIDs[pid, default: [:]][window] = id }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, context)
        return AXUnresponsiveApps.shared.noteResult(error, pid: pid)
    }

    /// Fin de l'application ou arret : ses fenetres sortent du registre et des caches.
    private func unsubscribe(pid: pid_t) {
        registered[pid] = nil
        for id in (watchedWindowIDs.removeValue(forKey: pid) ?? [:]).values {
            writtenFrames.forget(windowID: id)
        }
        AXAttributeCache.shared.invalidate(pid: pid)
        AXWindowIndexCache.shared.invalidate(pid: pid)
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
    // Les sources AX sont posees sur le run loop principal : la callback arrive sur la main thread.
    // Les references CF ne quittent pas la main thread : le controle de transfert ne s'applique pas.
    nonisolated(unsafe) let (observer, element, notification) = (observer, element, notification)
    MainActor.assumeIsolated {
        observerInstance.handleEvent(observer: observer, element: element, notification: notification)
    }
}
