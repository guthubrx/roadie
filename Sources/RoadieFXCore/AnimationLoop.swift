import Foundation
import CoreVideo

/// Wrapper minimaliste autour de `CVDisplayLink` pour ticker à la cadence display.
/// Les modules FX enregistrent un callback qui est appelé à chaque frame (60-120 FPS).
public final class AnimationLoop: @unchecked Sendable {
    public typealias TickHandler = @Sendable (TimeInterval) -> Void

    private var displayLink: CVDisplayLink?
    private var handlers: [(UUID, TickHandler)] = []
    private let lock = NSLock()
    private var startTime: TimeInterval = 0

    public init() {}

    /// Démarre la boucle. Idempotent.
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard status == kCVReturnSuccess, let link else { return }
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let cb: CVDisplayLinkOutputCallback = { _, _, _, _, _, ctx in
            guard let ctx else { return kCVReturnSuccess }
            let loop = Unmanaged<AnimationLoop>.fromOpaque(ctx).takeUnretainedValue()
            loop.tick()
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link, cb, opaque)
        CVDisplayLinkStart(link)
        displayLink = link
        startTime = currentTime()
    }

    /// Arrête la boucle. Idempotent.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        if let link = displayLink { CVDisplayLinkStop(link) }
        displayLink = nil
    }

    /// Enregistre un handler de tick. Retourne un UUID pour unregister.
    @discardableResult
    public func register(_ handler: @escaping TickHandler) -> UUID {
        let id = UUID()
        lock.lock(); defer { lock.unlock() }
        handlers.append((id, handler))
        return id
    }

    public func unregister(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        handlers.removeAll { $0.0 == id }
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return displayLink != nil
    }

    private func tick() {
        let now = currentTime()
        let snapshot: [TickHandler] = lock.withLock { handlers.map { $0.1 } }
        for h in snapshot { h(now) }
    }

    private func currentTime() -> TimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000.0
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
