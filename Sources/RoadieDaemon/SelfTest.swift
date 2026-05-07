import Foundation
import RoadieCore

public enum SelfTestLevel: String, Codable, Sendable {
    case ok
    case warn
    case fail
}

public struct SelfTestCheck: Equatable, Codable, Sendable {
    public var level: SelfTestLevel
    public var name: String
    public var message: String

    public init(level: SelfTestLevel, name: String, message: String) {
        self.level = level
        self.name = name
        self.message = message
    }
}

public struct SelfTestReport: Equatable, Codable, Sendable {
    public var checks: [SelfTestCheck]

    public init(checks: [SelfTestCheck]) {
        self.checks = checks
    }

    public var failed: Bool {
        checks.contains { $0.level == .fail }
    }
}

public struct SelfTestService {
    private let service: SnapshotService
    private let stageStore: StageStore

    public init(service: SnapshotService = SnapshotService(), stageStore: StageStore = StageStore()) {
        self.service = service
        self.stageStore = stageStore
    }

    public func run() -> SelfTestReport {
        let snapshot = service.snapshot()
        let state = stageStore.state()
        let plan = service.applyPlan(from: snapshot)
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        var checks: [SelfTestCheck] = []

        checks.append(SelfTestCheck(
            level: snapshot.permissions.accessibilityTrusted ? .ok : .fail,
            name: "accessibility",
            message: "accessibilityTrusted=\(snapshot.permissions.accessibilityTrusted)"
        ))
        checks.append(SelfTestCheck(
            level: snapshot.displays.isEmpty ? .fail : .ok,
            name: "displays",
            message: "count=\(snapshot.displays.count)"
        ))
        checks.append(SelfTestCheck(
            level: activeDisplayIsLive(state: state, liveDisplayIDs: liveDisplayIDs) ? .ok : .warn,
            name: "active-display",
            message: state.activeDisplayID.map { "id=\($0.rawValue)" } ?? "none"
        ))
        checks.append(SelfTestCheck(
            level: plan.commands.isEmpty ? .ok : .warn,
            name: "layout-idempotence",
            message: "pendingCommands=\(plan.commands.count)"
        ))
        checks.append(SelfTestCheck(
            level: staleScopeCount(in: state, liveDisplayIDs: liveDisplayIDs) == 0 ? .ok : .warn,
            name: "stale-scopes",
            message: "count=\(staleScopeCount(in: state, liveDisplayIDs: liveDisplayIDs))"
        ))
        checks.append(SelfTestCheck(
            level: focusedWindowIsScoped(snapshot) ? .ok : .warn,
            name: "focused-window",
            message: snapshot.focusedWindowID.map { "id=\($0.rawValue)" } ?? "none"
        ))
        let tinyTiles = tinyTileCount(in: snapshot)
        checks.append(SelfTestCheck(
            level: tinyTiles == 0 ? .ok : .warn,
            name: "tile-sizes",
            message: "tinyTiles=\(tinyTiles)"
        ))

        return SelfTestReport(checks: checks)
    }

    private func activeDisplayIsLive(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> Bool {
        guard let activeDisplayID = state.activeDisplayID else { return true }
        return liveDisplayIDs.contains(activeDisplayID)
    }

    private func staleScopeCount(in state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> Int {
        state.scopes.filter { !liveDisplayIDs.contains($0.displayID) }.count
    }

    private func focusedWindowIsScoped(_ snapshot: DaemonSnapshot) -> Bool {
        guard let focusedWindowID = snapshot.focusedWindowID else { return true }
        return snapshot.windows.contains { $0.window.id == focusedWindowID && $0.scope != nil }
    }

    private func tinyTileCount(in snapshot: DaemonSnapshot) -> Int {
        var count = 0
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }
            let windows = snapshot.windows.filter {
                $0.scope == scope && $0.window.isTileCandidate
            }
            guard windows.count > 1 else { continue }
            let container = display.visibleFrame.cgRect
            let minimumSide = max(120, min(container.width, container.height) * 0.18)
            count += windows.filter {
                $0.window.frame.width < minimumSide || $0.window.frame.height < minimumSide
            }.count
        }
        return count
    }
}
