import Foundation
import RoadieAX
import RoadieCore

public struct TargetInspectionIdentity: Codable, Equatable, Sendable {
    public var app: String?
    public var bundleId: String?
    public var title: String?
    public var windowId: UInt32?
    public var displayId: String?
    public var desktopId: Int?
    public var stageId: String?

    public init(
        app: String? = nil,
        bundleId: String? = nil,
        title: String? = nil,
        windowId: UInt32? = nil,
        displayId: String? = nil,
        desktopId: Int? = nil,
        stageId: String? = nil
    ) {
        self.app = app
        self.bundleId = bundleId
        self.title = title
        self.windowId = windowId
        self.displayId = displayId
        self.desktopId = desktopId
        self.stageId = stageId
    }
}

public struct TargetInspectionState: Codable, Equatable, Sendable {
    public var tileable: Bool?
    public var floating: Bool?
    public var pinned: Bool?
    public var focused: Bool?
    public var activeStage: Bool?
    public var source: String

    public init(
        tileable: Bool? = nil,
        floating: Bool? = nil,
        pinned: Bool? = nil,
        focused: Bool? = nil,
        activeStage: Bool? = nil,
        source: String
    ) {
        self.tileable = tileable
        self.floating = floating
        self.pinned = pinned
        self.focused = focused
        self.activeStage = activeStage
        self.source = source
    }
}

public struct TargetInspection: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var target: RoadieTarget
    public var summary: String
    public var identity: TargetInspectionIdentity
    public var state: TargetInspectionState
    public var reasons: [String]
    public var recentEvents: [String]

    public init(
        schemaVersion: Int = 1,
        target: RoadieTarget,
        summary: String,
        identity: TargetInspectionIdentity,
        state: TargetInspectionState,
        reasons: [String],
        recentEvents: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.target = target
        self.summary = summary
        self.identity = identity
        self.state = state
        self.reasons = reasons
        self.recentEvents = recentEvents
    }
}

public struct TargetInspectionService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let eventLog: EventLog
    private let targetService: TargetHintService

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        eventLog: EventLog = EventLog(),
        targetService: TargetHintService? = nil
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.eventLog = eventLog
        self.targetService = targetService ?? TargetHintService(service: service, stageStore: stageStore, eventLog: eventLog)
    }

    public func inspect(_ value: String) -> Result<TargetInspection, TargetResolutionError> {
        let report = targetService.list(TargetQueryOptions(source: .all, includeHidden: true, includeAppTargets: service.effectiveConfig.experimental.appTargets.enabled))
        do {
            let target = try TargetHintService.resolve(value, in: report.targets)
            let inspection = inspect(target, snapshot: service.snapshot(followFocus: false), state: stageStore.state())
            eventLog.append(RoadieEvent(type: "targets.inspect", details: [
                "target": target.id,
                "kind": target.kind.rawValue,
            ]))
            return .success(inspection)
        } catch let error as TargetResolutionError {
            eventLog.append(RoadieEvent(type: "targets.inspect_failed", details: [
                "target": value,
                "error": error.description,
            ]))
            return .failure(error)
        } catch {
            return .failure(.unknownTarget(value))
        }
    }

    public static func inspect(target: RoadieTarget, snapshot: DaemonSnapshot, state: PersistentStageState) -> TargetInspection {
        TargetInspectionService().inspect(target, snapshot: snapshot, state: state)
    }

    public func inspect(_ target: RoadieTarget, snapshot: DaemonSnapshot, state: PersistentStageState) -> TargetInspection {
        switch target.kind {
        case .window:
            return inspectWindow(target, snapshot: snapshot, state: state)
        case .stage:
            return inspectStage(target, snapshot: snapshot, state: state)
        case .display:
            return TargetInspection(
                target: target,
                summary: "Display \(target.title)",
                identity: TargetInspectionIdentity(displayId: target.scope.displayId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: target.isActive, activeStage: nil, source: target.source.rawValue),
                reasons: target.diagnostics
            )
        case .desktop:
            return TargetInspection(
                target: target,
                summary: "Desktop \(target.title)",
                identity: TargetInspectionIdentity(displayId: target.scope.displayId, desktopId: target.scope.desktopId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: target.isActive, source: target.source.rawValue),
                reasons: target.diagnostics
            )
        case .bookmark:
            return TargetInspection(
                target: target,
                summary: "Bookmark \(target.title)",
                identity: TargetInspectionIdentity(title: target.subtitle, windowId: target.scope.windowId, displayId: target.scope.displayId, desktopId: target.scope.desktopId, stageId: target.scope.stageId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: target.isActive, activeStage: nil, source: target.source.rawValue),
                reasons: target.diagnostics
            )
        case .appElement:
            return TargetInspection(
                target: target,
                summary: "Zone applicative \(target.title)",
                identity: TargetInspectionIdentity(title: target.title),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: nil, source: target.source.rawValue),
                reasons: target.diagnostics
            )
        case .gridCell:
            return TargetInspection(
                target: target,
                summary: "Cellule grille \(target.title)",
                identity: TargetInspectionIdentity(displayId: target.scope.displayId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: nil, source: target.source.rawValue),
                reasons: target.diagnostics
            )
        }
    }

    private func inspectWindow(_ target: RoadieTarget, snapshot: DaemonSnapshot, state: PersistentStageState) -> TargetInspection {
        guard let windowID = target.scope.windowId.flatMap({ WindowID(rawValue: $0) }),
              let entry = snapshot.windows.first(where: { $0.window.id == windowID })
        else {
            return TargetInspection(
                target: target,
                summary: "Fenêtre disparue \(target.id)",
                identity: TargetInspectionIdentity(windowId: target.scope.windowId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: false, activeStage: false, source: target.source.rawValue),
                reasons: target.diagnostics + ["stale_target"]
            )
        }
        let window = entry.window
        let scope = entry.scope
        let pin = entry.pin ?? state.pin(for: window.id)
        let activeScope = scope.flatMap { snapshot.state.activeScope(on: $0.displayID) }
        var reasons = target.diagnostics
        if !window.isTileCandidate {
            reasons.append("excluded_from_tiling")
        }
        if scope == nil {
            reasons.append("no_stage_scope")
        }
        if let pin {
            reasons.append("pin_scope=\(pin.pinScope.rawValue)")
        }
        return TargetInspection(
            target: target,
            summary: "\(window.appName) \(window.title)",
            identity: TargetInspectionIdentity(
                app: window.appName,
                bundleId: window.bundleID,
                title: window.title,
                windowId: window.id.rawValue,
                displayId: scope?.displayID.rawValue,
                desktopId: scope?.desktopID.rawValue,
                stageId: scope?.stageID.rawValue
            ),
            state: TargetInspectionState(
                tileable: window.isTileCandidate,
                floating: !window.isTileCandidate,
                pinned: pin != nil,
                focused: window.id == snapshot.focusedWindowID,
                activeStage: scope != nil && scope == activeScope,
                source: target.source.rawValue
            ),
            reasons: Array(Set(reasons)).sorted()
        )
    }

    private func inspectStage(_ target: RoadieTarget, snapshot: DaemonSnapshot, state: PersistentStageState) -> TargetInspection {
        guard let displayID = target.scope.displayId.map(DisplayID.init(rawValue:)),
              let desktopID = target.scope.desktopId.map(DesktopID.init(rawValue:)),
              let stageID = target.scope.stageId.map(StageID.init(rawValue:)),
              let scope = state.scopes.first(where: { $0.displayID == displayID && $0.desktopID == desktopID }),
              let stage = scope.stages.first(where: { $0.id == stageID })
        else {
            return TargetInspection(
                target: target,
                summary: "Stage disparue \(target.id)",
                identity: TargetInspectionIdentity(displayId: target.scope.displayId, desktopId: target.scope.desktopId, stageId: target.scope.stageId),
                state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: false, source: target.source.rawValue),
                reasons: target.diagnostics + ["stale_target"]
            )
        }
        let liveIDs = Set(snapshot.windows.map(\.window.id))
        let liveCount = stage.members.filter { liveIDs.contains($0.windowID) }.count
        return TargetInspection(
            target: target,
            summary: "\(stage.name) - \(liveCount) fenêtre(s) live",
            identity: TargetInspectionIdentity(displayId: displayID.rawValue, desktopId: desktopID.rawValue, stageId: stageID.rawValue),
            state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: scope.activeStageID == stageID, source: target.source.rawValue),
            reasons: target.diagnostics + ["windows=\(stage.members.count)", "live_windows=\(liveCount)", "mode=\(stage.mode.rawValue)"]
        )
    }
}
