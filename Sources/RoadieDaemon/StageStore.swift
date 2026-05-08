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
    public var desktopSelections: [PersistentDesktopSelection]
    public var desktopLabels: [PersistentDesktopLabel]
    public var activeDisplayID: DisplayID?

    public init(
        scopes: [PersistentStageScope] = [],
        desktopSelections: [PersistentDesktopSelection] = [],
        desktopLabels: [PersistentDesktopLabel] = [],
        activeDisplayID: DisplayID? = nil
    ) {
        self.scopes = scopes
        self.desktopSelections = desktopSelections
        self.desktopLabels = desktopLabels
        self.activeDisplayID = activeDisplayID
    }

    enum CodingKeys: String, CodingKey {
        case scopes
        case desktopSelections
        case desktopLabels
        case activeDisplayID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.scopes = try c.decodeIfPresent([PersistentStageScope].self, forKey: .scopes) ?? []
        self.desktopSelections = try c.decodeIfPresent([PersistentDesktopSelection].self, forKey: .desktopSelections) ?? []
        self.desktopLabels = try c.decodeIfPresent([PersistentDesktopLabel].self, forKey: .desktopLabels) ?? []
        self.activeDisplayID = try c.decodeIfPresent(DisplayID.self, forKey: .activeDisplayID)
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

    public mutating func migrateDisconnectedDisplays(keeping liveDisplayIDs: Set<DisplayID>, fallbackDisplayID: DisplayID) {
        let staleScopes = scopes.filter { !liveDisplayIDs.contains($0.displayID) }
        guard !staleScopes.isEmpty else { return }

        scopes.removeAll { !liveDisplayIDs.contains($0.displayID) }
        for staleScope in staleScopes {
            var target = scope(displayID: fallbackDisplayID, desktopID: staleScope.desktopID)
            target.mergeDisconnectedScope(staleScope)
            update(target)
        }

        desktopSelections.removeAll { !liveDisplayIDs.contains($0.displayID) }
        desktopLabels.removeAll { !liveDisplayIDs.contains($0.displayID) }
        if activeDisplayID.map({ !liveDisplayIDs.contains($0) }) == true {
            activeDisplayID = fallbackDisplayID
        }
    }

    public func currentDesktopID(for displayID: DisplayID) -> DesktopID {
        desktopSelections.first { $0.displayID == displayID }?.currentDesktopID ?? DesktopID(rawValue: 1)
    }

    public func lastDesktopID(for displayID: DisplayID) -> DesktopID? {
        desktopSelections.first { $0.displayID == displayID }?.lastDesktopID
    }

    public mutating func focusDisplay(_ displayID: DisplayID) {
        activeDisplayID = displayID
    }

    public func label(displayID: DisplayID, desktopID: DesktopID) -> String? {
        desktopLabels.first { $0.displayID == displayID && $0.desktopID == desktopID }?.label
    }

    public mutating func setLabel(_ label: String, displayID: DisplayID, desktopID: DesktopID) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        desktopLabels.removeAll { $0.displayID == displayID && $0.desktopID == desktopID }
        guard !trimmed.isEmpty else { return }
        desktopLabels.append(PersistentDesktopLabel(displayID: displayID, desktopID: desktopID, label: trimmed))
    }

    public mutating func switchDesktop(displayID: DisplayID, to desktopID: DesktopID) {
        if let index = desktopSelections.firstIndex(where: { $0.displayID == displayID }) {
            let current = desktopSelections[index].currentDesktopID
            if current != desktopID {
                desktopSelections[index].lastDesktopID = current
                desktopSelections[index].currentDesktopID = desktopID
            }
        } else {
            desktopSelections.append(PersistentDesktopSelection(
                displayID: displayID,
                currentDesktopID: desktopID,
                lastDesktopID: desktopID == DesktopID(rawValue: 1) ? nil : DesktopID(rawValue: 1)
            ))
        }
    }
}

public struct PersistentDesktopLabel: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var label: String

    public init(displayID: DisplayID, desktopID: DesktopID, label: String) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.label = label
    }
}

public struct PersistentDesktopSelection: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var currentDesktopID: DesktopID
    public var lastDesktopID: DesktopID?

    public init(displayID: DisplayID, currentDesktopID: DesktopID = DesktopID(rawValue: 1), lastDesktopID: DesktopID? = nil) {
        self.displayID = displayID
        self.currentDesktopID = currentDesktopID
        self.lastDesktopID = lastDesktopID
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

    public mutating func applyConfiguredStages(_ config: StageManagerConfig) {
        if stages.isEmpty {
            activeStageID = StageID(rawValue: config.defaultStage)
        }
        for workspace in config.workspaces {
            let id = StageID(rawValue: workspace.id)
            if let index = stages.firstIndex(where: { $0.id == id }) {
                if stages[index].name == "Stage \(id.rawValue)" {
                    stages[index].name = workspace.displayName
                }
            } else {
                stages.append(PersistentStage(id: id, name: workspace.displayName))
            }
        }
    }

    public mutating func createStage(_ id: StageID, name: String? = nil) -> Bool {
        guard !stages.contains(where: { $0.id == id }) else { return false }
        stages.append(PersistentStage(id: id, name: name))
        return true
    }

    public mutating func renameStage(_ id: StageID, to name: String) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
        stages[index].name = name
        return true
    }

    public mutating func reorderStage(_ id: StageID, to position: Int) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
        let stage = stages.remove(at: index)
        let targetIndex = min(max(position - 1, 0), stages.count)
        stages.insert(stage, at: targetIndex)
        return true
    }

    public mutating func deleteEmptyInactiveStage(_ id: StageID) -> Bool {
        guard id != activeStageID,
              let index = stages.firstIndex(where: { $0.id == id }),
              stages[index].members.isEmpty
        else { return false }
        stages.remove(at: index)
        return true
    }

    public mutating func assign(window: WindowSnapshot, to stageID: StageID) {
        ensureStage(stageID)
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == window.id }
            if stages[index].focusedWindowID == window.id {
                stages[index].focusedWindowID = stages[index].members.last?.windowID
            }
        }
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].members.append(PersistentStageMember(
            windowID: window.id,
            bundleID: window.bundleID,
            title: window.title,
            frame: window.frame
        ))
        stages[index].focusedWindowID = window.id
    }

    public mutating func setMode(_ mode: WindowManagementMode, for stageID: StageID) {
        ensureStage(stageID)
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].mode = mode
    }

    public mutating func remove(windowID: WindowID) {
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == windowID }
            if stages[index].focusedWindowID == windowID {
                stages[index].focusedWindowID = stages[index].members.last?.windowID
            }
        }
    }

    public mutating func setFocusedWindow(_ windowID: WindowID, in stageID: StageID) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }),
              stages[index].members.contains(where: { $0.windowID == windowID })
        else { return }
        stages[index].focusedWindowID = windowID
    }

    public mutating func orderMembers(_ orderedWindowIDs: [WindowID], in stageID: StageID) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        let membersByID = Dictionary(uniqueKeysWithValues: stages[index].members.map { ($0.windowID, $0) })
        var seen: Set<WindowID> = []
        var ordered: [PersistentStageMember] = []
        for id in orderedWindowIDs {
            guard let member = membersByID[id], !seen.contains(id) else { continue }
            ordered.append(member)
            seen.insert(id)
        }
        ordered.append(contentsOf: stages[index].members.filter { !seen.contains($0.windowID) })
        stages[index].members = ordered
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
            if let focusedWindowID = stages[stageIndex].focusedWindowID,
               !liveWindowIDs.contains(focusedWindowID) {
                stages[stageIndex].focusedWindowID = stages[stageIndex].members.last?.windowID
            }
        }
    }

    public func memberIDs(in stageID: StageID) -> [WindowID] {
        stages.first(where: { $0.id == stageID })?.members.map(\.windowID) ?? []
    }

    mutating func mergeDisconnectedScope(_ source: PersistentStageScope) {
        if stages.allSatisfy(\.members.isEmpty) {
            activeStageID = source.activeStageID
        }
        for sourceStage in source.stages {
            ensureStage(sourceStage.id)
            guard let targetIndex = stages.firstIndex(where: { $0.id == sourceStage.id }) else { continue }
            if stages[targetIndex].members.isEmpty {
                stages[targetIndex].mode = sourceStage.mode
                stages[targetIndex].name = sourceStage.name
            }
            for member in sourceStage.members {
                remove(windowID: member.windowID)
                stages[targetIndex].members.append(member)
            }
            if let focusedWindowID = sourceStage.focusedWindowID {
                stages[targetIndex].focusedWindowID = focusedWindowID
            }
        }
    }
}

public struct PersistentStage: Equatable, Codable, Sendable {
    public var id: StageID
    public var name: String
    public var mode: WindowManagementMode
    public var focusedWindowID: WindowID?
    public var members: [PersistentStageMember]

    public init(
        id: StageID,
        name: String? = nil,
        mode: WindowManagementMode = .bsp,
        focusedWindowID: WindowID? = nil,
        members: [PersistentStageMember] = []
    ) {
        self.id = id
        self.name = name ?? "Stage \(id.rawValue)"
        self.mode = mode
        self.focusedWindowID = focusedWindowID
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case focusedWindowID
        case members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(StageID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Stage \(id.rawValue)"
        self.mode = try c.decodeIfPresent(WindowManagementMode.self, forKey: .mode) ?? .bsp
        self.focusedWindowID = try c.decodeIfPresent(WindowID.self, forKey: .focusedWindowID)
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
