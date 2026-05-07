import Foundation
import RoadieAX
import RoadieCore

public struct DisplayCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog

    public init(service: SnapshotService = SnapshotService(), store: StageStore = StageStore(), events: EventLog = EventLog()) {
        self.service = service
        self.store = store
        self.events = events
    }

    public func focus(index: Int) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = snapshot.displays.first(where: { $0.index == index }) else {
            return StageCommandResult(message: "display focus \(index): unknown display", changed: false)
        }

        var state = store.state()
        state.focusDisplay(display.id)
        let desktopID = state.currentDesktopID(for: display.id)
        let scope = state.scope(displayID: display.id, desktopID: desktopID)
        state.update(scope)
        store.save(state)

        let activeScope = StageScope(displayID: display.id, desktopID: desktopID, stageID: scope.activeStageID)
        let focusedID = scope.stages.first { $0.id == scope.activeStageID }?.focusedWindowID
            ?? scope.memberIDs(in: scope.activeStageID).last
        let focused = focusedID.flatMap { id in
            snapshot.windows.first { $0.window.id == id && $0.scope == activeScope }?.window
        }
        let focusedResult = focused.map { service.focus($0) } ?? false
        events.append(RoadieEvent(type: "display_focus", details: [
            "displayIndex": String(index),
            "displayID": display.id.rawValue,
            "displayName": display.name,
            "focused": String(focusedResult)
        ]))

        return StageCommandResult(
            message: "display focus \(index): \(display.name) focused=\(focusedResult)",
            changed: true
        )
    }
}
