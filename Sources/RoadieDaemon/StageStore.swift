import Foundation
import RoadieAX
import RoadieCore

public struct StageStore: Sendable {
    private let url: URL

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-stages-\(ProcessInfo.processInfo.processIdentifier).json"
        }
        return "~/.roadies/stages.json"
    }

    public func state() -> PersistentStageState {
        load()
    }

    public func save(_ state: PersistentStageState) {
        write(state)
    }

    private func load() -> PersistentStageState {
        guard let data = try? Data(contentsOf: url) else { return PersistentStageState() }
        return (try? JSONDecoder().decode(PersistentStageState.self, from: data)) ?? PersistentStageState()
    }

    private func write(_ state: PersistentStageState) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            fputs("roadie: failed to persist stages: \(error)\n", stderr)
        }
    }
}

public struct PersistentStageState: Equatable, Codable, Sendable {
    public var scopes: [PersistentStageScope]

    public init(scopes: [PersistentStageScope] = []) {
        self.scopes = scopes
    }

    public mutating func scope(displayID: DisplayID, desktopID: DesktopID = DesktopID(rawValue: 1)) -> PersistentStageScope {
        if let existing = scopes.first(where: { $0.displayID == displayID && $0.desktopID == desktopID }) {
            return existing
        }
        let created = PersistentStageScope(displayID: displayID, desktopID: desktopID)
        scopes.append(created)
        return created
    }

    public mutating func update(_ scope: PersistentStageScope) {
        scopes.removeAll { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }
        scopes.append(scope)
    }

    public func stageScope(for windowID: WindowID) -> StageScope? {
        for scope in scopes {
            if let stage = scope.stages.first(where: { $0.members.contains(where: { $0.windowID == windowID }) }) {
                return StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
            }
        }
        return nil
    }

    public mutating func pruneMissingWindows(keeping liveWindowIDs: Set<WindowID>) {
        for scopeIndex in scopes.indices {
            scopes[scopeIndex].pruneMissingWindows(keeping: liveWindowIDs)
        }
    }
}

public struct PersistentStageScope: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var activeStageID: StageID
    public var stages: [PersistentStage]

    public init(
        displayID: DisplayID,
        desktopID: DesktopID = DesktopID(rawValue: 1),
        activeStageID: StageID = StageID(rawValue: "1"),
        stages: [PersistentStage] = [PersistentStage(id: StageID(rawValue: "1"))]
    ) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.activeStageID = activeStageID
        self.stages = stages
    }

    public mutating func ensureStage(_ id: StageID) {
        guard !stages.contains(where: { $0.id == id }) else { return }
        stages.append(PersistentStage(id: id))
    }

    public mutating func assign(window: WindowSnapshot, to stageID: StageID) {
        ensureStage(stageID)
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == window.id }
        }
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].members.append(PersistentStageMember(
            windowID: window.id,
            bundleID: window.bundleID,
            title: window.title,
            frame: window.frame
        ))
    }

    public mutating func setMode(_ mode: WindowManagementMode, for stageID: StageID) {
        ensureStage(stageID)
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].mode = mode
    }

    public mutating func remove(windowID: WindowID) {
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == windowID }
        }
    }

    public mutating func updateFrame(window: WindowSnapshot) {
        for stageIndex in stages.indices {
            guard let memberIndex = stages[stageIndex].members.firstIndex(where: { $0.windowID == window.id }) else {
                continue
            }
            stages[stageIndex].members[memberIndex].frame = window.frame
        }
    }

    public mutating func pruneMissingWindows(keeping liveWindowIDs: Set<WindowID>) {
        for stageIndex in stages.indices {
            stages[stageIndex].members.removeAll { !liveWindowIDs.contains($0.windowID) }
        }
    }

    public func memberIDs(in stageID: StageID) -> [WindowID] {
        stages.first(where: { $0.id == stageID })?.members.map(\.windowID) ?? []
    }
}

public struct PersistentStage: Equatable, Codable, Sendable {
    public var id: StageID
    public var name: String
    public var mode: WindowManagementMode
    public var members: [PersistentStageMember]

    public init(
        id: StageID,
        name: String? = nil,
        mode: WindowManagementMode = .bsp,
        members: [PersistentStageMember] = []
    ) {
        self.id = id
        self.name = name ?? "Stage \(id.rawValue)"
        self.mode = mode
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(StageID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Stage \(id.rawValue)"
        self.mode = try c.decodeIfPresent(WindowManagementMode.self, forKey: .mode) ?? .bsp
        self.members = try c.decodeIfPresent([PersistentStageMember].self, forKey: .members) ?? []
    }
}

public struct PersistentStageMember: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var bundleID: String
    public var title: String
    public var frame: Rect

    public init(windowID: WindowID, bundleID: String, title: String, frame: Rect) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
    }
}
