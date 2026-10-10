import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

/// Source unique de l'heuristique `maximized` (SPEC-016 FR-027).
/// Une fenêtre qui couvre l'écran n'est « agrandie » que si elle n'est pas la seule fenêtre tilée de son scope :
/// une fenêtre tilée seule remplit naturellement l'écran.
public struct WindowPresentationStateResolver: Sendable {
    public init() {}

    public func state(for entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> WindowPresentationState {
        guard let display = display(for: entry, in: snapshot) else {
            return .normal
        }
        return Self.state(
            for: entry.window,
            on: display,
            isOnlyTiledWindowInScope: Self.isOnlyTiledWindow(entry, tiledCounts: Self.tiledWindowCounts(in: snapshot))
        )
    }

    // O(n) - n = nombre de fenêtres du snapshot (un seul passage pour compter les fenêtres tilées par scope).
    public func statesByWindowID(in snapshot: DaemonSnapshot) -> [WindowID: WindowPresentationState] {
        let tiledCounts = Self.tiledWindowCounts(in: snapshot)
        var states: [WindowID: WindowPresentationState] = [:]
        for entry in snapshot.windows {
            guard let display = display(for: entry, in: snapshot) else {
                states[entry.window.id] = .normal
                continue
            }
            states[entry.window.id] = Self.state(
                for: entry.window,
                on: display,
                isOnlyTiledWindowInScope: Self.isOnlyTiledWindow(entry, tiledCounts: tiledCounts)
            )
        }
        return states
    }

    public static func state(
        for window: WindowSnapshot,
        on display: DisplaySnapshot,
        frameOverride: Rect? = nil,
        isOnlyTiledWindowInScope: Bool = false
    ) -> WindowPresentationState {
        if window.furniture?.isNativeFullscreen == true {
            return .nativeFullscreen
        }
        if isOnlyTiledWindowInScope {
            return .normal
        }
        let frame = frameOverride?.cgRect ?? window.frame.cgRect
        if isMaximized(frame, on: display) {
            return .maximized
        }
        return .normal
    }

    public static func isMaximized(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        framesAreClose(frame, display.visibleFrame.cgRect, tolerance: LayoutTolerance.fullscreenFrame)
            || framesAreClose(frame, display.frame.cgRect, tolerance: LayoutTolerance.fullscreenFrame)
    }

    /// Nombre de fenêtres tilables par scope (display, desktop, stage).
    // O(n) - n = nombre de fenêtres du snapshot.
    static func tiledWindowCounts(in snapshot: DaemonSnapshot) -> [StageScope: Int] {
        tiledWindowCounts(in: snapshot.windows)
    }

    // O(n) - n = nombre de fenêtres de la liste.
    static func tiledWindowCounts(in windows: [ScopedWindowSnapshot]) -> [StageScope: Int] {
        var counts: [StageScope: Int] = [:]
        for entry in windows where entry.window.isTileCandidate {
            if let scope = entry.scope {
                counts[scope, default: 0] += 1
            }
        }
        return counts
    }

    private static func isOnlyTiledWindow(_ entry: ScopedWindowSnapshot, tiledCounts: [StageScope: Int]) -> Bool {
        guard entry.window.isTileCandidate, let scope = entry.scope else { return false }
        return tiledCounts[scope, default: 0] <= 1
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
