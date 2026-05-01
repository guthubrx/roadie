import Foundation
import RoadieCore
import RoadieFXCore

/// Mappe les événements FXEventBus aux règles config et enqueue les Animations.
public final class EventRouter: @unchecked Sendable {
    public let curveLib: BezierLibrary
    public var config: AnimationsConfig
    public let queue: AnimationQueue
    private let lock = NSLock()

    public init(config: AnimationsConfig, queue: AnimationQueue) {
        self.config = config
        self.queue = queue
        var custom: [String: BezierCurve] = [:]
        for def in config.bezier {
            guard def.points.count == 4 else { continue }
            custom[def.name] = BezierCurve(p1x: def.points[0], p1y: def.points[1],
                                           p2x: def.points[2], p2y: def.points[3])
        }
        self.curveLib = BezierLibrary(custom: custom)
    }

    public func handle(event: FXEvent) {
        guard config.enabled else { return }
        let cfgEvent = mapEvent(event.kind)
        let rules = lock.withLock { config.events.filter { $0.event == cfgEvent } }
        guard !rules.isEmpty else { return }
        let ctx = EventContext(eventKind: cfgEvent,
                               timestamp: event.timestamp,
                               wid: event.wid)
        var anims: [Animation] = []
        for rule in rules {
            anims.append(contentsOf: AnimationFactory.make(rule: rule,
                                                           context: ctx,
                                                           curveLib: curveLib))
        }
        if !anims.isEmpty {
            Task { await queue.enqueueBatch(anims) }
        }
    }

    /// Conversion FXEventKind → string config event.
    private func mapEvent(_ kind: FXEventKind) -> String {
        switch kind {
        case .windowCreated:    return "window_open"
        case .windowDestroyed:  return "window_close"
        case .windowFocused:    return "window_focused"
        case .windowResized:    return "window_resized"
        case .desktopChanged:   return "desktop_changed"
        case .stageChanged:     return "stage_changed"
        default:                return kind.rawValue
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
