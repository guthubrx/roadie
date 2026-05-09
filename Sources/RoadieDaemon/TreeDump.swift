import Foundation
import RoadieCore

public struct TreeDump: Equatable, Codable, Sendable {
    public var displays: [TreeDisplay]

    public init(displays: [TreeDisplay]) {
        self.displays = displays
    }
}

public struct TreeDisplay: Equatable, Codable, Sendable {
    public var id: DisplayID
    public var index: Int
    public var name: String
    public var desktops: [TreeDesktop]

    public init(id: DisplayID, index: Int, name: String, desktops: [TreeDesktop]) {
        self.id = id
        self.index = index
        self.name = name
        self.desktops = desktops
    }
}

public struct TreeDesktop: Equatable, Codable, Sendable {
    public var id: DesktopID
    public var active: Bool
    public var stages: [TreeStage]

    public init(id: DesktopID, active: Bool, stages: [TreeStage]) {
        self.id = id
        self.active = active
        self.stages = stages
    }
}

public struct TreeStage: Equatable, Codable, Sendable {
    public var id: StageID
    public var name: String
    public var mode: WindowManagementMode
    public var active: Bool
    public var windows: [TreeWindow]

    public init(id: StageID, name: String, mode: WindowManagementMode, active: Bool, windows: [TreeWindow]) {
        self.id = id
        self.name = name
        self.mode = mode
        self.active = active
        self.windows = windows
    }
}

public struct TreeWindow: Equatable, Codable, Sendable {
    public var id: WindowID
    public var appName: String
    public var title: String
    public var live: Bool

    public init(id: WindowID, appName: String, title: String, live: Bool) {
        self.id = id
        self.appName = appName
        self.title = title
        self.live = live
    }
}

public struct TreeDumpService {
    private let service: SnapshotService
    private let stageStore: StageStore

    public init(service: SnapshotService = SnapshotService(), stageStore: StageStore = StageStore()) {
        self.service = service
        self.stageStore = stageStore
    }

    public func dump() -> TreeDump {
        let snapshot = service.snapshot(followExternalFocus: false, persistState: false)
        let state = stageStore.state()
        let liveWindowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })

        let displays = snapshot.displays.map { display in
            let scopes = state.scopes
                .filter { $0.displayID == display.id }
                .sorted { $0.desktopID.rawValue < $1.desktopID.rawValue }
            let desktops = scopes.map { scope in
                TreeDesktop(
                    id: scope.desktopID,
                    active: state.currentDesktopID(for: display.id) == scope.desktopID,
                    stages: scope.stages.map { stage in
                        TreeStage(
                            id: stage.id,
                            name: stage.name,
                            mode: stage.mode,
                            active: scope.activeStageID == stage.id,
                            windows: stage.members.map { member in
                                let live = liveWindowsByID[member.windowID]
                                return TreeWindow(
                                    id: member.windowID,
                                    appName: live?.appName ?? member.bundleID,
                                    title: live?.title ?? member.title,
                                    live: live != nil
                                )
                            }
                        )
                    }
                )
            }
            return TreeDisplay(id: display.id, index: display.index, name: display.name, desktops: desktops)
        }

        return TreeDump(displays: displays)
    }
}
