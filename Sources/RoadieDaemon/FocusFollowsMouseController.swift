import AppKit
import CoreGraphics
import RoadieAX
import RoadieCore

@MainActor
public final class FocusFollowsMouseController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private var timer: Timer?
    private var lastFocusedWindowID: WindowID?

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
    }

    public func start() {
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

        let snapshot = snapshotService.snapshot()
        guard let target = FocusFollowsMousePicker.targetWindow(at: mousePoint, in: snapshot),
              target.window.id != (snapshot.focusedWindowID ?? lastFocusedWindowID)
        else { return }

        if snapshotService.focus(target.window) {
            lastFocusedWindowID = target.window.id
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
