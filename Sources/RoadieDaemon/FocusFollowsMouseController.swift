import AppKit
import CoreGraphics
import RoadieAX
import RoadieCore

@MainActor
public final class FocusFollowsMouseController {
    /// Mouvement minimal du curseur entre deux ticks pour agir (FR-011).
    private static let minimumMovement: CGFloat = 2

    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private var timer: Timer?
    private var lastFocusedWindowID: WindowID?
    private var lastMousePoint: CGPoint?

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
    }

    public func start() {
        UserInputActivity.shared.startMonitoring()
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func tick() {
        guard configLoader().focus.focusFollowsMouse,
              let mousePoint = CGEvent(source: nil)?.location
        else { return }

        // FR-011 : agir seulement après un mouvement réel, jamais pendant un clic ou un drag.
        let previousPoint = lastMousePoint
        lastMousePoint = mousePoint
        guard let previousPoint,
              hypot(mousePoint.x - previousPoint.x, mousePoint.y - previousPoint.y) > Self.minimumMovement,
              NSEvent.pressedMouseButtons == 0
        else { return }

        let snapshot = snapshotService.sharedSnapshot()
        guard let target = FocusFollowsMousePicker.targetWindow(at: mousePoint, in: snapshot),
              target.window.id != (snapshot.focusedWindowID ?? lastFocusedWindowID)
        else { return }

        if snapshotService.focus(target.window) {
            lastFocusedWindowID = target.window.id
        }
    }
}

/// Session de geste souris (A4, A17) : ouverte au clic, fermée au relâchement.
/// `windowID == nil` : clic hors de toute fenêtre gérée, aucun geste.
public struct GestureSession: Equatable, Sendable {
    public var windowID: UInt32?
    public var startFrame: CGRect?
    public var startedAt: Date
    public var endedAt: Date?

    public init(windowID: UInt32?, startFrame: CGRect?, startedAt: Date, endedAt: Date? = nil) {
        self.windowID = windowID
        self.startFrame = startFrame
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// Dernière saisie utilisateur (clic, touche, modificateur) vue par le processus (SPEC-016 FR-009).
/// La stage ne suit un changement de focus que si une saisie a eu lieu dans la seconde qui précède,
/// après la dernière disparition de fenêtre. Sans moniteur actif (CLI, processus qui ne l'a pas
/// démarré), aucune saisie n'est prouvée : le suivi est refusé (comportement conservateur, T211).
/// Le tiler, le rail, la bordure et le focus-souris démarrent le moniteur.
/// Tient aussi la session de geste souris (SPEC-017 A4, A17).
public final class UserInputActivity: @unchecked Sendable {
    public static let shared = UserInputActivity()

    static let inputWindow: TimeInterval = 1
    static let disappearanceExclusion: TimeInterval = 0.5

    /// Fenêtre gérée sous le curseur (coordonnées CoreGraphics) et sa frame, d'après le dernier snapshot.
    public typealias GestureTarget = @MainActor (CGPoint) -> (windowID: UInt32, frame: CGRect)?
    /// Tous les boutons relâchés ; `gestureEnded` : une session sur une fenêtre gérée vient de se fermer.
    public typealias ReleaseHandler = @MainActor (_ gestureEnded: Bool) -> Void

    private let lock = NSLock()
    private var monitoring: Bool
    private var lastInputAt: Date?
    private var monitors: [Any] = []
    private var gesture: GestureSession?
    private var finishedGesture: GestureSession?
    private var gestureTarget: GestureTarget?
    private var releaseHandler: ReleaseHandler?

    /// `monitoring: true` simule un moniteur actif (tests).
    public init(monitoring: Bool = false) {
        self.monitoring = monitoring
    }

    /// Installe les moniteurs, une fois par processus, dans chaque processus qui fait suivre le
    /// focus ou qui range. `.flagsChanged` capte Cmd-Tab, dont le keyDown n'est pas livré.
    /// Le moniteur global ne voit pas les événements destinés à Roadie (navrail) : un moniteur
    /// local alimente la même session de geste (A17). La saisie qui autorise le suivi du focus
    /// (FR-009) reste celle du moniteur global, comme avant.
    @MainActor
    public func startMonitoring() {
        guard lock.withLock({ monitors.isEmpty }) else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .keyDown, .flagsChanged,
        ]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, recordsInput: true) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, recordsInput: false) }
            return event
        }
        lock.withLock {
            monitors = [global, local].compactMap { $0 }
            monitoring = global != nil
        }
    }

    /// Branche la session de geste sur le tiler : `target` trouve la fenêtre sous le curseur au
    /// clic, `onRelease` reçoit chaque relâchement. Sans branchement, les sessions n'ont pas de cible.
    public func observeGestures(target: @escaping GestureTarget, onRelease: @escaping ReleaseHandler) {
        lock.withLock {
            gestureTarget = target
            releaseHandler = onRelease
        }
    }

    @MainActor
    private func handle(_ event: NSEvent, recordsInput: Bool) {
        switch event.type {
        case .leftMouseDown:
            if let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location {
                mouseDown(at: point)
            }
        case .leftMouseUp:
            mouseUp(leftButton: true)
            return
        case .rightMouseUp, .otherMouseUp:
            mouseUp(leftButton: false)
            return
        default:
            break
        }
        if recordsInput { recordInput() }
    }

    /// Ouvre la session de geste (A4) : fenêtre gérée sous le curseur et sa frame, ou aucune
    /// cible (bureau, navrail, fenêtre exclue). La cible est cherchée hors verrou, car le
    /// snapshot consulte aussi cet objet.
    @MainActor
    func mouseDown(at point: CGPoint, now: Date = Date()) {
        let target = lock.withLock { gestureTarget }?(point)
        lock.withLock {
            gesture = GestureSession(windowID: target?.windowID, startFrame: target?.frame, startedAt: now)
        }
    }

    /// Relâchement d'un bouton. Celui du bouton gauche ferme la session ; une session sans cible
    /// ne produit aucun geste (A17). Un geste encore non consommé sur la même fenêtre garde sa
    /// frame de départ, pour qu'un double geste rapide ne perde pas le premier. Les boutons encore
    /// enfoncés retiennent les passes : l'ordonnanceur relit leur état avant d'agir.
    @MainActor
    func mouseUp(leftButton: Bool, now: Date = Date()) {
        let (ended, handler) = lock.withLock { () -> (Bool, ReleaseHandler?) in
            guard leftButton, var session = gesture else { return (false, releaseHandler) }
            gesture = nil
            guard session.windowID != nil else { return (false, releaseHandler) }
            if let previous = finishedGesture, previous.windowID == session.windowID {
                session.startFrame = previous.startFrame
                session.startedAt = previous.startedAt
            }
            session.endedAt = now
            finishedGesture = session
            return (true, releaseHandler)
        }
        handler?(ended)
    }

    /// Session en cours (bouton gauche enfoncé). nil hors geste.
    public var currentGesture: GestureSession? { lock.withLock { gesture } }

    /// Dernière session terminée sur une fenêtre gérée, consommée une seule fois (A17).
    public func takeGesture() -> GestureSession? {
        lock.withLock {
            defer { finishedGesture = nil }
            return finishedGesture
        }
    }

    public func recordInput(at date: Date = Date()) {
        lock.withLock { lastInputAt = date }
    }

    func allowsFocusChange(now: Date, lastDisappearanceAt: Date?) -> Bool {
        lock.withLock {
            if let lastDisappearanceAt,
               now.timeIntervalSince(lastDisappearanceAt) < Self.disappearanceExclusion {
                return false
            }
            guard monitoring else { return false }
            guard let lastInputAt,
                  now.timeIntervalSince(lastInputAt) <= Self.inputWindow
            else { return false }
            return lastDisappearanceAt.map { lastInputAt > $0 } ?? true
        }
    }
}

public enum FocusFollowsMousePicker {
    public static func targetWindow(at point: CGPoint, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        snapshot.windows
            .filter { entry in
                guard let scope = entry.scope else { return false }
                return entry.window.isTileCandidate
                    && snapshot.state.activeScope(on: scope.displayID) == scope
                    && entry.window.frame.cgRect.contains(point)
            }
            .min { lhs, rhs in
                lhs.window.frame.width * lhs.window.frame.height < rhs.window.frame.width * rhs.window.frame.height
            }
    }
}
