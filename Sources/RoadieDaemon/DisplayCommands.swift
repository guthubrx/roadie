import Foundation
import RoadieAX
import RoadieCore

public struct DisplayCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog
    private let performance: PerformanceRecorder

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        events: EventLog = EventLog(),
        performance: PerformanceRecorder = PerformanceRecorder()
    ) {
        self.service = service
        self.store = store
        self.events = events
        self.performance = performance
    }

    public func focus(index: Int) -> StageCommandResult {
        let snapshot = commandSnapshot()
        guard let display = snapshot.displays.first(where: { $0.index == index }) else {
            return StageCommandResult(message: "display focus \(index): unknown display", changed: false)
        }
        return focus(display, in: snapshot, label: "\(index)")
    }

    public func focus(_ direction: Direction) -> StageCommandResult {
        let snapshot = commandSnapshot()
        guard let activeDisplay = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "display focus \(direction.rawValue): no active display", changed: false)
        }
        guard let target = DisplayTopology.neighbor(from: activeDisplay, direction: direction, in: snapshot.displays) else {
            return StageCommandResult(message: "display focus \(direction.rawValue): no display", changed: false)
        }
        return focus(target, in: snapshot, label: direction.rawValue)
    }

    private func focus(_ display: DisplaySnapshot, in snapshot: DaemonSnapshot, label: String) -> StageCommandResult {
        let started = Date()
        var state = store.state()
        state.focusDisplay(display.id)
        let desktopID = state.currentDesktopID(for: display.id)
        let scope = state.scope(displayID: display.id, desktopID: desktopID)
        state.update(scope)
        store.save(state)
        let stateUpdatedAt = Date()

        let activeScope = StageScope(displayID: display.id, desktopID: desktopID, stageID: scope.activeStageID)
        let focusedID = scope.stages.first { $0.id == scope.activeStageID }?.focusedWindowID
            ?? scope.memberIDs(in: scope.activeStageID).last
        let focused = focusedID.flatMap { id in
            snapshot.windows.first { $0.window.id == id && $0.scope == activeScope }?.window
        }
        let focusedResult = focused.map { service.focus($0) } ?? false
        let completedAt = Date()
        events.append(RoadieEvent(type: "display_focus", details: [
            "displayIndex": String(display.index),
            "displayID": display.id.rawValue,
            "displayName": display.name,
            "focused": String(focusedResult)
        ]))
        performance.complete(
            performance.start(
                .displayFocus,
                targetContext: PerformanceTargetContext(displayID: display.id.rawValue, desktopID: desktopID.rawValue, stageID: scope.activeStageID.rawValue, windowID: focusedID?.rawValue)
            ),
            result: focusedResult ? .success : .partial,
            steps: [
                PerformanceStep(name: .stateUpdate, startedAt: started, durationMs: stateUpdatedAt.timeIntervalSince(started) * 1000),
                PerformanceStep(name: .focus, startedAt: stateUpdatedAt, durationMs: completedAt.timeIntervalSince(stateUpdatedAt) * 1000)
            ],
            completedAt: completedAt,
            durationMs: completedAt.timeIntervalSince(started) * 1000
        )

        return StageCommandResult(
            message: "display focus \(label): \(display.name) focused=\(focusedResult)",
            changed: true
        )
    }

    private func commandSnapshot() -> DaemonSnapshot {
        service.snapshot(followExternalFocus: false)
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        let state = store.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        if let focusedID = service.focusedWindowID(),
           let focused = snapshot.windows.first(where: { $0.window.id == focusedID }),
           let displayID = focused.scope?.displayID,
           let display = snapshot.displays.first(where: { $0.id == displayID }) {
            return display
        }
        return snapshot.displays.first(where: \.isMain) ?? snapshot.displays.first
    }
}
