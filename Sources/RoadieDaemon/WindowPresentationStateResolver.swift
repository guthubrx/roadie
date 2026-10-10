import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct WindowPresentationStateResolver: Sendable {
    public static let maximizedTolerance: CGFloat = 48

    public init() {}

    public func state(for entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> WindowPresentationState {
        guard let display = display(for: entry, in: snapshot) else {
            return .normal
        }
        return Self.state(for: entry.window, on: display)
    }

    public func statesByWindowID(in snapshot: DaemonSnapshot) -> [WindowID: WindowPresentationState] {
        var states: [WindowID: WindowPresentationState] = [:]
        for entry in snapshot.windows {
            states[entry.window.id] = state(for: entry, in: snapshot)
        }
        return states
    }

    public static func state(
        for window: WindowSnapshot,
        on display: DisplaySnapshot,
        frameOverride: Rect? = nil
    ) -> WindowPresentationState {
        if window.furniture?.isNativeFullscreen == true {
            return .nativeFullscreen
        }
        let frame = frameOverride?.cgRect ?? window.frame.cgRect
        if isMaximized(frame, on: display) {
            return .maximized
        }
        return .normal
    }

    public static func isMaximized(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        framesAreClose(frame, display.visibleFrame.cgRect, tolerance: maximizedTolerance)
            || framesAreClose(frame, display.frame.cgRect, tolerance: maximizedTolerance)
    }

    private func display(for entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let displayID = entry.scope?.displayID {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first { display in
            display.frame.cgRect.contains(entry.window.frame.center)
                || display.visibleFrame.cgRect.contains(entry.window.frame.center)
        }
    }

    private static func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
