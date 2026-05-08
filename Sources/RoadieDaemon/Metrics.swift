import Foundation
import RoadieCore

public struct RoadieMetrics: Equatable, Codable, Sendable {
    public var displays: Int
    public var tileableWindows: Int
    public var scopedWindows: Int
    public var activeStages: Int
    public var persistentScopes: Int
    public var pendingLayoutCommands: Int
    public var staleScopes: Int
    public var duplicateWindows: Int
    public var staleMembers: Int

    public init(
        displays: Int,
        tileableWindows: Int,
        scopedWindows: Int,
        activeStages: Int,
        persistentScopes: Int,
        pendingLayoutCommands: Int,
        staleScopes: Int,
        duplicateWindows: Int,
        staleMembers: Int
    ) {
        self.displays = displays
        self.tileableWindows = tileableWindows
        self.scopedWindows = scopedWindows
        self.activeStages = activeStages
        self.persistentScopes = persistentScopes
        self.pendingLayoutCommands = pendingLayoutCommands
        self.staleScopes = staleScopes
        self.duplicateWindows = duplicateWindows
        self.staleMembers = staleMembers
    }
}

public struct MetricsService {
    private let service: SnapshotService
    private let stageStore: StageStore

    public init(service: SnapshotService = SnapshotService(), stageStore: StageStore = StageStore()) {
        self.service = service
        self.stageStore = stageStore
    }

    public func collect() -> RoadieMetrics {
        let snapshot = service.snapshot()
        let state = stageStore.state()
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        let liveTileableWindowIDs = Set(snapshot.windows.compactMap { $0.window.isTileCandidate ? $0.window.id : nil })
        let plan = service.applyPlan(from: snapshot)
        var owners: [WindowID: Int] = [:]
        var staleMembers = 0

        for scope in state.scopes {
            for stage in scope.stages {
                for member in stage.members {
                    owners[member.windowID, default: 0] += 1
                    if !liveTileableWindowIDs.contains(member.windowID) {
                        staleMembers += 1
                    }
                }
            }
        }

        return RoadieMetrics(
            displays: snapshot.displays.count,
            tileableWindows: snapshot.windows.filter { $0.window.isTileCandidate }.count,
            scopedWindows: snapshot.windows.filter { $0.scope != nil }.count,
            activeStages: snapshot.displays.compactMap { snapshot.state.activeScope(on: $0.id) }.count,
            persistentScopes: state.scopes.count,
            pendingLayoutCommands: plan.commands.count,
            staleScopes: state.scopes.filter { !liveDisplayIDs.contains($0.displayID) }.count,
            duplicateWindows: owners.values.filter { $0 > 1 }.count,
            staleMembers: staleMembers
        )
    }
}
