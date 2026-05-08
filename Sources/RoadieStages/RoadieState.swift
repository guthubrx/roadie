import Foundation
import RoadieCore

public struct RoadieState: Equatable, Codable, Sendable {
    public private(set) var displays: [DisplayID: DisplayState]

    public init(displays: [DisplayID: DisplayState] = [:]) {
        self.displays = displays
    }

    public func display(_ id: DisplayID) -> DisplayState? {
        displays[id]
    }

    public func desktop(displayID: DisplayID, desktopID: DesktopID) -> DesktopState? {
        displays[displayID]?.desktops[desktopID]
    }

    public func stage(scope: StageScope) -> StageState? {
        desktop(displayID: scope.displayID, desktopID: scope.desktopID)?.stages[scope.stageID]
    }

    public mutating func ensureDisplay(_ id: DisplayID, defaultDesktop: DesktopID = DesktopID(rawValue: 1)) {
        guard displays[id] == nil else { return }
        displays[id] = DisplayState(id: id, currentDesktopID: defaultDesktop)
    }

    public mutating func createDesktop(_ desktopID: DesktopID, on displayID: DisplayID) throws {
        ensureDisplay(displayID)
        guard displays[displayID]?.desktops[desktopID] == nil else {
            throw RoadieStateError.desktopAlreadyExists(displayID, desktopID)
        }
        displays[displayID]?.desktops[desktopID] = DesktopState(id: desktopID)
    }

    public mutating func switchDesktop(_ desktopID: DesktopID, on displayID: DisplayID) throws {
        guard displays[displayID]?.desktops[desktopID] != nil else {
            throw RoadieStateError.unknownDesktop(displayID, desktopID)
        }
        displays[displayID]?.currentDesktopID = desktopID
    }

    public mutating func createStage(id stageID: StageID, name: String, mode: WindowManagementMode = .bsp, in displayID: DisplayID, desktopID: DesktopID) throws {
        ensureDisplay(displayID)
        if displays[displayID]?.desktops[desktopID] == nil {
            displays[displayID]?.desktops[desktopID] = DesktopState(id: desktopID)
        }
        guard displays[displayID]?.desktops[desktopID]?.stages[stageID] == nil else {
            throw RoadieStateError.stageAlreadyExists(StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID))
        }
        displays[displayID]?.desktops[desktopID]?.stages[stageID] = StageState(id: stageID, name: name, mode: mode)
    }

    public mutating func switchStage(_ stageID: StageID, in displayID: DisplayID, desktopID: DesktopID) throws {
        guard displays[displayID]?.desktops[desktopID]?.stages[stageID] != nil else {
            throw RoadieStateError.unknownStage(StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID))
        }
        displays[displayID]?.desktops[desktopID]?.activeStageID = stageID
    }

    public mutating func setMode(_ mode: WindowManagementMode, for scope: StageScope) throws {
        guard displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID] != nil else {
            throw RoadieStateError.unknownStage(scope)
        }
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.mode = mode
    }

    public mutating func setGroups(_ groups: [WindowGroup], for scope: StageScope) throws {
        guard displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID] != nil else {
            throw RoadieStateError.unknownStage(scope)
        }
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.groups = groups
    }

    public mutating func assignWindow(_ windowID: WindowID, to scope: StageScope) throws {
        guard displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID] != nil else {
            throw RoadieStateError.unknownStage(scope)
        }
        removeWindow(windowID)
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.insert(windowID)
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.focusedWindowID = windowID
    }

    public mutating func setFocusedWindow(_ windowID: WindowID, for scope: StageScope) throws {
        guard let stage = displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID],
              stage.windowIDs.contains(windowID)
        else {
            throw RoadieStateError.unknownStage(scope)
        }
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.focusedWindowID = windowID
    }

    public mutating func removeWindow(_ windowID: WindowID) {
        for displayID in Array(displays.keys) {
            guard let display = displays[displayID] else { continue }
            let desktopIDs = Array(display.desktops.keys)
            for desktopID in desktopIDs {
                guard let desktop = displays[displayID]?.desktops[desktopID] else { continue }
                let stageIDs = Array(desktop.stages.keys)
                for stageID in stageIDs {
                    displays[displayID]?.desktops[desktopID]?.stages[stageID]?.remove(windowID)
                }
            }
        }
    }

    public func activeScope(on displayID: DisplayID) -> StageScope? {
        guard let display = displays[displayID],
              let desktop = display.desktops[display.currentDesktopID]
        else { return nil }
        return StageScope(
            displayID: displayID,
            desktopID: display.currentDesktopID,
            stageID: desktop.activeStageID
        )
    }
}

public struct DisplayState: Equatable, Codable, Sendable {
    public let id: DisplayID
    public var currentDesktopID: DesktopID
    public var desktops: [DesktopID: DesktopState]

    public init(id: DisplayID, currentDesktopID: DesktopID) {
        self.id = id
        self.currentDesktopID = currentDesktopID
        self.desktops = [
            currentDesktopID: DesktopState(id: currentDesktopID)
        ]
    }
}

public struct DesktopState: Equatable, Codable, Sendable {
    public let id: DesktopID
    public var label: String?
    public var activeStageID: StageID
    public var stages: [StageID: StageState]

    public init(id: DesktopID, label: String? = nil, activeStageID: StageID = StageID(rawValue: "1")) {
        self.id = id
        self.label = label
        self.activeStageID = activeStageID
        self.stages = [
            activeStageID: StageState(id: activeStageID, name: "Stage \(activeStageID.rawValue)")
        ]
    }
}

public struct StageState: Equatable, Codable, Sendable {
    public let id: StageID
    public var name: String
    public var mode: WindowManagementMode
    public private(set) var windowIDs: [WindowID]
    public var focusedWindowID: WindowID?
    public var groups: [WindowGroup]

    public init(id: StageID, name: String, mode: WindowManagementMode = .bsp, windowIDs: [WindowID] = [], groups: [WindowGroup] = []) {
        self.id = id
        self.name = name
        self.mode = mode
        self.windowIDs = []
        self.focusedWindowID = nil
        self.groups = groups
        for windowID in windowIDs {
            insert(windowID)
        }
    }

    public mutating func insert(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
        windowIDs.append(windowID)
    }

    public mutating func remove(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
        groups = groups.compactMap { group in
            var updated = group
            updated.remove(windowID)
            return updated.windowIDs.count >= 2 ? updated : nil
        }
        if focusedWindowID == windowID {
            focusedWindowID = windowIDs.last
        }
    }
}

public struct WindowGroup: Equatable, Codable, Sendable {
    public var id: String
    public var windowIDs: [WindowID]
    public var activeWindowID: WindowID?
    public var presentation: String

    public init(id: String, windowIDs: [WindowID] = [], activeWindowID: WindowID? = nil, presentation: String = "tabbed") {
        self.id = id
        self.windowIDs = []
        self.activeWindowID = activeWindowID
        self.presentation = presentation
        for windowID in windowIDs {
            add(windowID)
        }
        if self.activeWindowID == nil {
            self.activeWindowID = self.windowIDs.first
        }
    }

    public mutating func add(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
        windowIDs.append(windowID)
        if activeWindowID == nil {
            activeWindowID = windowID
        }
    }

    public mutating func remove(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
        if activeWindowID == windowID {
            activeWindowID = windowIDs.first
        }
    }

    public mutating func focus(_ windowID: WindowID) -> Bool {
        guard windowIDs.contains(windowID) else { return false }
        activeWindowID = windowID
        return true
    }
}

public enum RoadieStateError: Error, Equatable, CustomStringConvertible {
    case desktopAlreadyExists(DisplayID, DesktopID)
    case unknownDesktop(DisplayID, DesktopID)
    case stageAlreadyExists(StageScope)
    case unknownStage(StageScope)

    public var description: String {
        switch self {
        case .desktopAlreadyExists(let displayID, let desktopID):
            return "desktop \(desktopID) already exists on display \(displayID)"
        case .unknownDesktop(let displayID, let desktopID):
            return "desktop \(desktopID) does not exist on display \(displayID)"
        case .stageAlreadyExists(let scope):
            return "stage already exists at \(scope)"
        case .unknownStage(let scope):
            return "stage does not exist at \(scope)"
        }
    }
}
