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

/// Dernière saisie utilisateur (clic, touche, modificateur) vue par le processus (SPEC-016 FR-009).
/// La stage ne suit un changement de focus que si une saisie a eu lieu dans la seconde qui précède,
/// après la dernière disparition de fenêtre. Sans moniteur actif (tests, CLI), seule l'exclusion
/// de 500 ms après une disparition s'applique.
public final class UserInputActivity: @unchecked Sendable {
    public static let shared = UserInputActivity()

    static let inputWindow: TimeInterval = 1
    static let disappearanceExclusion: TimeInterval = 0.5

    private let lock = NSLock()
    private var monitoring: Bool
    private var lastInputAt: Date?
    private var monitor: Any?

    /// `monitoring: true` simule un moniteur actif (tests).
    public init(monitoring: Bool = false) {
        self.monitoring = monitoring
    }

    /// Installe le moniteur global, une fois par processus, dans chaque processus qui fait
    /// suivre le focus. `.flagsChanged` capte Cmd-Tab, dont le keyDown n'est pas livré.
    @MainActor
    public func startMonitoring() {
        guard lock.withLock({ monitor == nil }) else { return }
        let token = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .flagsChanged]
        ) { [weak self] _ in
            self?.recordInput()
        }
        lock.withLock {
            monitor = token
            monitoring = token != nil
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
            guard monitoring else { return true }
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
