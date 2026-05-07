import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct DesktopCommandService {
    private let service: SnapshotService
    private let store: StageStore

    public init(service: SnapshotService = SnapshotService(), store: StageStore = StageStore()) {
        self.service = service
        self.store = store
    }

    public func list() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop list: no display", changed: false)
        }
        let state = store.state()
        let current = state.currentDesktopID(for: display.id)
        let ids = desktopIDs(for: display.id, in: state)
        var lines = ["ACTIVE\tID\tSTAGES\tWINDOWS"]
        for id in ids {
            let scopes = state.scopes.filter { $0.displayID == display.id && $0.desktopID == id }
            let stageCount = scopes.flatMap(\.stages).count
            let windowCount = scopes.flatMap(\.stages).flatMap(\.members).count
            lines.append("\(id == current ? "*" : "")\t\(id.rawValue)\t\(stageCount)\t\(windowCount)")
        }
        return StageCommandResult(message: lines.joined(separator: "\n"), changed: false)
    }

    public func focus(_ desktopID: DesktopID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop focus: no display", changed: false)
        }
        return switchDisplay(display, to: desktopID, snapshot: snapshot)
    }

    public func cycle(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop \(direction.rawValue): no display", changed: false)
        }
        var state = store.state()
        for id in (1...6).map({ DesktopID(rawValue: $0) }) {
            _ = state.scope(displayID: display.id, desktopID: id)
        }
        store.save(state)
        let ids = desktopIDs(for: display.id, in: state)
        let current = state.currentDesktopID(for: display.id)
        let index = ids.firstIndex(of: current) ?? 0
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (index + 1) % ids.count
        case .prev:
            nextIndex = (index - 1 + ids.count) % ids.count
        }
        return switchDisplay(display, to: ids[nextIndex], snapshot: snapshot)
    }

    public func last() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop last: no display", changed: false)
        }
        let state = store.state()
        guard let last = state.lastDesktopID(for: display.id) else {
            return StageCommandResult(message: "desktop last: none", changed: false)
        }
        return switchDisplay(display, to: last, snapshot: snapshot)
    }

    private func switchDisplay(
        _ display: DisplaySnapshot,
        to desktopID: DesktopID,
        snapshot: DaemonSnapshot
    ) -> StageCommandResult {
        var state = store.state()
        let previousDesktopID = state.currentDesktopID(for: display.id)
        if previousDesktopID == desktopID {
            return StageCommandResult(message: "desktop focus \(desktopID.rawValue): already active", changed: false)
        }

        var previousScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
        var targetScope = state.scope(displayID: display.id, desktopID: desktopID)
        targetScope.applyConfiguredStages((try? RoadieConfigLoader.load())?.stageManager ?? StageManagerConfig())

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        for window in windowsByID.values where display.frame.cgRect.contains(window.frame.center) && !isHidden(window.frame.cgRect) {
            previousScope.updateFrame(window: window)
        }

        var applied = 0
        let previousWindowIDs = Set(previousScope.stages.flatMap { $0.members.map(\.windowID) })
        let targetStage = targetScope.stages.first { $0.id == targetScope.activeStageID }
        let targetWindowIDs = Set(targetStage?.members.map(\.windowID) ?? [])

        for id in previousWindowIDs.subtracting(targetWindowIDs) {
            guard let window = windowsByID[id] else { continue }
            if service.setFrame(hiddenFrame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window) != nil {
                applied += 1
            }
        }
        for member in targetStage?.members ?? [] {
            guard let window = windowsByID[member.windowID] else { continue }
            if service.setFrame(member.frame.cgRect, of: window) != nil {
                applied += 1
            }
        }

        state.update(previousScope)
        state.update(targetScope)
        state.switchDesktop(displayID: display.id, to: desktopID)
        store.save(state)

        let result = service.apply(service.applyPlan(from: service.snapshot()))
        applied += result.applied + result.clamped
        if let focusedID = targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
           let focused = windowsByID[focusedID] {
            _ = service.focus(focused)
        }

        return StageCommandResult(
            message: "desktop focus \(desktopID.rawValue): hidden=\(previousWindowIDs.subtracting(targetWindowIDs).count) shown=\(targetWindowIDs.count) applied=\(applied) layout=\(result.attempted)",
            changed: true
        )
    }

    private func desktopIDs(for displayID: DisplayID, in state: PersistentStageState) -> [DesktopID] {
        let configured = Set(state.scopes.filter { $0.displayID == displayID }.map(\.desktopID))
        let defaults = Set((1...6).map { DesktopID(rawValue: $0) })
        return Array(configured.union(defaults)).sorted()
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let focusedID = service.focusedWindowID(),
           let entry = snapshot.windows.first(where: { $0.window.id == focusedID }),
           let displayID = entry.scope?.displayID ?? displayID(containing: entry.window.frame.center, in: snapshot.displays) {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
    }

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let visible = display.visibleFrame.cgRect
        return CGRect(x: visible.maxX - 1, y: visible.maxY - 1, width: frame.width, height: frame.height).integral
    }

    private func isHidden(_ frame: CGRect) -> Bool {
        frame.maxX < -1000 || frame.minX < -10000
    }
}
