import AppKit
import CoreGraphics
import RoadieCore

/// Machine à états pure et déterministe de détection des gestes de défilement du ruban `.scrolling`
/// (balayage horizontal 3/4 doigts au trackpad et `⌥ Option + molette`, Spec 166).
public struct ScrollingGestureDetector: Equatable, Sendable {
    public var requiredFingers: Int
    public var horizontalThreshold: CGFloat
    public var dominanceRatio: CGFloat
    public var swipeCooldown: TimeInterval
    public var scrollThreshold: CGFloat
    public var scrollCooldown: TimeInterval

    private var anchor: CGPoint?
    private var triggeredInStroke = false
    private var lastSwipeAt: TimeInterval = -.infinity
    private var overviewAnchor: CGPoint?
    private var overviewTriggeredInStroke = false
    private var lastOverviewSwipeAt: TimeInterval = -.infinity
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollEventAt: TimeInterval = -.infinity
    private var lastScrollTriggerAt: TimeInterval = -.infinity

    public init(
        requiredFingers: Int = 3,
        horizontalThreshold: CGFloat = 0.08,
        dominanceRatio: CGFloat = 1.6,
        swipeCooldown: TimeInterval = 0.22,
        scrollThreshold: CGFloat = 24,
        scrollCooldown: TimeInterval = 0.18
    ) {
        self.requiredFingers = min(4, max(3, requiredFingers))
        self.horizontalThreshold = max(0.02, horizontalThreshold)
        self.dominanceRatio = max(1.0, dominanceRatio)
        self.swipeCooldown = max(0, swipeCooldown)
        self.scrollThreshold = max(4, scrollThreshold)
        self.scrollCooldown = max(0, scrollCooldown)
    }

    public mutating func reset() {
        anchor = nil
        triggeredInStroke = false
        overviewAnchor = nil
        overviewTriggeredInStroke = false
        scrollAccumulator = 0
    }

    /// Détecte un balayage vertical à 4 doigts pour ouvrir (`.up`) ou fermer (`.down`) la vue d'ensemble
    /// sans BetterTouchTool (Spec 166). Cooldown 350 ms, strictement vertical (`|dy| >= 1.6 * |dx|`).
    public mutating func processOverviewTouches(
        _ points: [CGPoint],
        now: TimeInterval,
        verticalThreshold: CGFloat = 0.08,
        cooldown: TimeInterval = 0.35
    ) -> Direction? {
        guard points.count == 4 else {
            overviewAnchor = nil
            overviewTriggeredInStroke = false
            return nil
        }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let centroid = CGPoint(x: sum.x / 4, y: sum.y / 4)
        guard let start = overviewAnchor else {
            overviewAnchor = centroid
            overviewTriggeredInStroke = false
            return nil
        }
        guard !overviewTriggeredInStroke, now - lastOverviewSwipeAt >= cooldown else { return nil }
        let dx = centroid.x - start.x
        let dy = centroid.y - start.y
        guard abs(dy) >= verticalThreshold, abs(dy) >= abs(dx) * dominanceRatio else {
            return nil
        }
        overviewTriggeredInStroke = true
        lastOverviewSwipeAt = now
        // Coordonnées normalisées NSTouch : y = 0 en bas du trackpad, y = 1 en haut.
        return dy > 0 ? .up : .down
    }

    /// Traite les positions normalisées `(0...1, 0...1)` des doigts actuellement en contact sur le trackpad.
    /// Retourne `.left` ou `.right` une seule fois par balayage horizontal franc.
    public mutating func processTouches(
        _ points: [CGPoint],
        now: TimeInterval,
        naturalScrolling: Bool = true
    ) -> Direction? {
        guard points.count == requiredFingers else {
            anchor = nil
            triggeredInStroke = false
            return nil
        }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(points.count)
        let centroid = CGPoint(x: sum.x / count, y: sum.y / count)

        guard let start = anchor else {
            anchor = centroid
            triggeredInStroke = false
            return nil
        }
        guard !triggeredInStroke, now - lastSwipeAt >= swipeCooldown else { return nil }

        let dx = centroid.x - start.x
        let dy = centroid.y - start.y
        guard abs(dx) >= horizontalThreshold, abs(dx) >= abs(dy) * dominanceRatio else {
            return nil
        }

        triggeredInStroke = true
        lastSwipeAt = now
        let movesRight = naturalScrolling ? (dx < 0) : (dx > 0)
        return movesRight ? .right : .left
    }

    /// Traite un événement `⌥ Option + molette/défilement` (horizontal ou vertical cranté).
    /// Retourne `.left` ou `.right` dès que l'accumulateur franchit `scrollThreshold`.
    public mutating func processOptionScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        now: TimeInterval,
        naturalScrolling: Bool = true
    ) -> Direction? {
        let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        guard delta.isFinite, delta != 0 else { return nil }
        if now - lastScrollEventAt > 0.35 {
            scrollAccumulator = 0
        }
        lastScrollEventAt = now
        scrollAccumulator += delta

        guard abs(scrollAccumulator) >= scrollThreshold, now - lastScrollTriggerAt >= scrollCooldown else {
            return nil
        }
        let positive = scrollAccumulator > 0
        scrollAccumulator = 0
        lastScrollTriggerAt = now
        let movesRight = naturalScrolling ? !positive : positive
        return movesRight ? .right : .left
    }
}

/// Moniteur passif macOS reliant les gestes trackpad multi-doigts et `⌥ + molette` à la navigation
/// du ruban `.scrolling` (Spec 166). Aucun polling périodique : réagit aux changements de réglages
/// et n'émet aucun appel AX tant que la stage active n'est pas en mode `.scrolling`.
@MainActor
public final class ScrollingTrackpadGestureController {
    private let service: SnapshotService
    private let events: EventLog
    private let clock: () -> TimeInterval
    private let onNavigate: @MainActor (Direction) -> Void
    private let onOverviewGesture: @MainActor (Direction) -> Void
    private var detector = ScrollingGestureDetector()
    private var gestureMonitor: Any?
    private var scrollMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var reloadObserver: NSObjectProtocol?
    private var started = false

    public init(
        service: SnapshotService,
        events: EventLog = EventLog(),
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onNavigate: @escaping @MainActor (Direction) -> Void,
        onOverviewGesture: @escaping @MainActor (Direction) -> Void = { _ in }
    ) {
        self.service = service
        self.events = events
        self.clock = clock
        self.onNavigate = onNavigate
        self.onOverviewGesture = onOverviewGesture
    }

    public func start() {
        guard !started else { return }
        started = true
        refreshMonitors()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .roadieSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMonitors() }
        }
        reloadObserver = NotificationCenter.default.addObserver(
            forName: .roadieConfigDidReload, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMonitors() }
        }
    }

    public func stop() {
        started = false
        removeMonitors()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        if let reloadObserver { NotificationCenter.default.removeObserver(reloadObserver) }
        reloadObserver = nil
    }

    private func refreshMonitors() {
        let config = service.effectiveConfig
        let tiling = config.tiling
        let overviewEnabled = config.overview.enabled && config.overview.trackpadGesture
        detector.requiredFingers = tiling.scrollingTrackpadFingers
        guard started, (tiling.scrollingTrackpadGestures || overviewEnabled) else {
            removeMonitors()
            return
        }
        if gestureMonitor == nil {
            gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .gesture) { [weak self] event in
                MainActor.assumeIsolated { self?.handleGesture(event) }
            }
        }
        if tiling.scrollingTrackpadGestures, scrollMonitor == nil {
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handleScrollWheel(event) }
            }
        } else if !tiling.scrollingTrackpadGestures, let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func removeMonitors() {
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        gestureMonitor = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        detector.reset()
    }

    private func isActiveStageScrolling() -> Bool {
        if let snapshot = service.cachedGestureSnapshot(),
           let focused = snapshot.focusedWindowID,
           let scope = snapshot.windows.first(where: { $0.window.id == focused })?.scope {
            return snapshot.state.stage(scope: scope)?.mode == .scrolling
        }
        // Repli : vérifier si la stage active d'au moins un scope visible est en mode `.scrolling`.
        let persisted = service.effectiveStageStore.state()
        return persisted.scopes.contains { scope in
            scope.stages.first(where: { $0.id == scope.activeStageID })?.mode == .scrolling
        }
    }

    private func handleGesture(_ event: NSEvent) {
        let config = service.effectiveConfig
        let touches = event.touches(matching: .touching, in: nil)
        let points = touches.map { CGPoint(x: $0.normalizedPosition.x, y: $0.normalizedPosition.y) }
        let now = clock()

        if config.overview.enabled && config.overview.trackpadGesture,
           let vertical = detector.processOverviewTouches(points, now: now) {
            events.append(RoadieEvent(type: "overview.gesture", details: [
                "source": "trackpad",
                "fingers": "4",
                "direction": vertical.rawValue
            ]))
            onOverviewGesture(vertical)
            return
        }

        guard config.tiling.scrollingTrackpadGestures, isActiveStageScrolling() else {
            return
        }
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        guard let direction = detector.processTouches(points, now: now, naturalScrolling: natural) else { return }
        events.append(RoadieEvent(type: "scrolling.gesture", details: [
            "source": "trackpad",
            "fingers": String(detector.requiredFingers),
            "direction": direction.rawValue
        ]))
        onNavigate(direction)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == .option, isActiveStageScrolling() else { return }
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 12
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        guard let direction = detector.processOptionScroll(
            deltaX: dx,
            deltaY: dy,
            now: clock(),
            naturalScrolling: event.isDirectionInvertedFromDevice
        ) else { return }
        events.append(RoadieEvent(type: "scrolling.gesture", details: [
            "source": "option_scroll",
            "direction": direction.rawValue
        ]))
        onNavigate(direction)
    }
}
