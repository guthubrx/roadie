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
    private var isReading = false

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
    }

    public func start() {
        UserInputActivity.shared.startMonitoring()
        schedule(interval: Self.timerInterval(enabled: configLoader().focus.focusFollowsMouse))
    }

    /// Option désactivée : un réveil par seconde suffit pour voir un rechargement à chaud (SPEC-051 A-05).
    nonisolated static func timerInterval(enabled: Bool) -> TimeInterval {
        enabled ? 0.1 : 1
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func tick() async {
        guard !isReading else { return }
        let enabled = configLoader().focus.focusFollowsMouse
        let interval = Self.timerInterval(enabled: enabled)
        if timer?.timeInterval != interval { schedule(interval: interval) }
        guard enabled, let mousePoint = CGEvent(source: nil)?.location else { return }

        // FR-011 : agir seulement après un mouvement réel, jamais pendant un clic ou un drag.
        let previousPoint = lastMousePoint
        lastMousePoint = mousePoint
        guard let previousPoint,
              hypot(mousePoint.x - previousPoint.x, mousePoint.y - previousPoint.y) > Self.minimumMovement,
              NSEvent.pressedMouseButtons == 0
        else { return }

        isReading = true
        defer { isReading = false }
        guard let snapshot = await snapshotService.readerSnapshot(),
              configLoader().focus.focusFollowsMouse, NSEvent.pressedMouseButtons == 0,
              let currentPoint = CGEvent(source: nil)?.location,
              hypot(currentPoint.x - mousePoint.x, currentPoint.y - mousePoint.y) <= Self.minimumMovement
        else { return }
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
    /// Preuve de mouvement avec le bouton gauche enfoncé ; un clic seul ne demande aucune attente AX.
    public var didDrag: Bool

    public init(windowID: UInt32?, startFrame: CGRect?, startedAt: Date, endedAt: Date? = nil, didDrag: Bool = false) {
        self.windowID = windowID
        self.startFrame = startFrame
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.didDrag = didDrag
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
    private var physicalReleaseObservedAt: Date?
    private var gestureTarget: GestureTarget?
    private var releaseHandler: ReleaseHandler?
    private var dragStartHandler: (@MainActor (GestureSession) -> Void)?

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
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp,
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
    public func observeGestures(target: @escaping GestureTarget,
                                onDragStart: (@MainActor (GestureSession) -> Void)? = nil,
                                onRelease: @escaping ReleaseHandler) {
        lock.withLock {
            gestureTarget = target
            dragStartHandler = onDragStart
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
        case .leftMouseDragged:
            mouseDragged()
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
            physicalReleaseObservedAt = nil
            gesture = GestureSession(windowID: target?.windowID, startFrame: target?.frame, startedAt: now)
        }
    }

    @MainActor
    func mouseDragged() {
        let first = lock.withLock { () -> GestureSession? in
            guard var current = gesture, !current.didDrag else { return nil }
            current.didDrag = true
            gesture = current
            return current
        }
        if let first { lock.withLock { dragStartHandler }?(first) }
    }

    /// Relâchement d'un bouton. Celui du bouton gauche ferme la session ; une session sans cible
    /// ne produit aucun geste (A17). Un geste encore non consommé sur la même fenêtre garde sa
    /// frame de départ, pour qu'un double geste rapide ne perde pas le premier. Les boutons encore
    /// enfoncés retiennent les passes : l'ordonnanceur relit leur état avant d'agir.
    @MainActor
    func mouseUp(leftButton: Bool, now: Date = Date()) {
        let (ended, handler) = lock.withLock { () -> (Bool, ReleaseHandler?) in
            physicalReleaseObservedAt = nil
            return (leftButton ? finishGestureLocked(at: now) : false, releaseHandler)
        }
        handler?(ended)
    }

    /// Session en cours (bouton gauche enfoncé). nil hors geste.
    public var currentGesture: GestureSession? { lock.withLock { gesture } }

    /// Une poignée a réellement accepté le clic : elle remplace les interprétations natives
    /// courante et antérieure en attente. Le blocage physique des boutons reste indépendant. O(1).
    @MainActor
    public func claimExplicitResize() {
        lock.withLock {
            gesture = nil
            finishedGesture = nil
            physicalReleaseObservedAt = nil
        }
    }

    /// L'état physique peut précéder mouseUp : attendre son callback 300 ms au plus après
    /// relâchement observé, puis conserver le geste récupéré pour la passe qui consulte la garde.
    /// Un bouton encore appuyé reste bloquant, sans durée maximale de glissement. O(1).
    public func blocksLayout(mouseButtonsPressed: Bool, now: Date = Date()) -> Bool {
        lock.withLock {
            if mouseButtonsPressed {
                physicalReleaseObservedAt = nil
                return true
            }
            guard gesture != nil else { physicalReleaseObservedAt = nil; return false }
            guard let releasedAt = physicalReleaseObservedAt else {
                physicalReleaseObservedAt = now
                return true
            }
            guard releasedAt.addingTimeInterval(0.3) <= now else { return true }
            // Callback perdu : la passe qui consulte la garde peut consommer la session terminée.
            // Aucun handler n'est rappelé ici ; mouseUp tardif ne trouve plus de session à rejouer.
            _ = finishGestureLocked(at: releasedAt)
            return false
        }
    }

    /// Uniquement sous lock : fermeture/coalescence partagée par mouseUp et sa récupération.
    /// Ne déclenche aucun callback. La date reste celle du premier relâchement physique observé.
    private func finishGestureLocked(at endedAt: Date) -> Bool {
        guard var session = gesture else { return false }
        gesture = nil
        physicalReleaseObservedAt = nil
        guard session.windowID != nil else { return false }
        if let previous = finishedGesture, previous.windowID == session.windowID {
            session.startFrame = previous.startFrame
            session.startedAt = previous.startedAt
            session.didDrag = previous.didDrag || session.didDrag
        }
        session.endedAt = endedAt
        finishedGesture = session
        return true
    }

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
    /// Au clic, inclut une bande de 8 points autour du cadre pour les poignées de resize.
    /// Le contenu d'une fenêtre reste prioritaire ; dans un interstice, prend le bord le plus proche.
    /// Une fenêtre visible sous le point qui n'est pas éligible (non gérée, panneau, stage
    /// inactive) masque celles de derrière : aucune cible.
    /// O(n), uniquement pour les gestes : le focus au mouvement garde son test strict.
    public static func gestureTargetWindow(at point: CGPoint, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        let windows = snapshot.windows.filter { !$0.window.isKnownBorderDecoration }
        let frontIndex = windows.firstIndex {
            $0.window.isOnScreen && $0.window.frame.cgRect.contains(point)
        }
        if let frontIndex, isEligible(windows[frontIndex], in: snapshot) {
            return windows[frontIndex]
        }
        func distance(_ entry: ScopedWindowSnapshot) -> CGFloat {
            let frame = entry.window.frame.cgRect
            let dx = max(frame.minX - point.x, point.x - frame.maxX, 0)
            let dy = max(frame.minY - point.y, point.y - frame.maxY, 0)
            return dx * dx + dy * dy
        }
        // Un intérieur inéligible bloque seulement les poignées situées derrière lui en Z.
        // Le cadre décoratif d'une fenêtre située devant ne masque pas sa propre poignée.
        return windows.prefix(frontIndex ?? windows.count).filter { entry in
            isEligible(entry, in: snapshot)
                && entry.window.frame.cgRect.insetBy(dx: -8, dy: -8).contains(point)
        }.min { lhs, rhs in
            let left = distance(lhs), right = distance(rhs)
            if left != right { return left < right }
            let leftFocused = lhs.window.id == snapshot.focusedWindowID
            let rightFocused = rhs.window.id == snapshot.focusedWindowID
            if leftFocused != rightFocused { return leftFocused }
            return lhs.window.id.rawValue < rhs.window.id.rawValue
        }
    }

    /// Fenêtre que l'utilisateur voit sous le point, si elle est gérée dans la stage active.
    /// Une fenêtre plus petite cachée derrière n'est jamais choisie.
    // O(n) - n = fenêtres du snapshot.
    public static func targetWindow(at point: CGPoint, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        guard let front = frontWindow(at: point, in: snapshot), isEligible(front, in: snapshot) else { return nil }
        return front
    }

    /// Première fenêtre visible qui contient le point. `snapshot.windows` suit l'ordre CoreGraphics
    /// (devant vers derrière) : c'est la fenêtre que l'utilisateur voit à cet endroit.
    // O(n) - n = fenêtres du snapshot.
    public static func frontWindow(at point: CGPoint, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        snapshot.windows.first { $0.window.isOnScreen && $0.window.frame.cgRect.contains(point) }
    }

    private static func isEligible(_ entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> Bool {
        guard let scope = entry.scope else { return false }
        return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
    }
}
