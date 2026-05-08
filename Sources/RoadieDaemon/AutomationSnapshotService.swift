import Foundation
import RoadieCore
import RoadieStages

public struct AutomationSnapshotService: Sendable {
    public init() {}

    public func snapshot(from daemonSnapshot: DaemonSnapshot, generatedAt: Date = Date()) -> RoadieStateSnapshot {
        let activeDisplayID = daemonSnapshot.state.displays.values
            .first { display in
                daemonSnapshot.state.activeScope(on: display.id) != nil
            }?
            .id
            .rawValue
        let activeScope = activeDisplayID
            .map(DisplayID.init(rawValue:))
            .flatMap { daemonSnapshot.state.activeScope(on: $0) }

        return RoadieStateSnapshot(
            generatedAt: generatedAt,
            activeDisplayId: activeScope?.displayID.rawValue ?? activeDisplayID,
            activeDesktopId: activeScope.map { String($0.desktopID.rawValue) },
            activeStageId: activeScope?.stageID.rawValue,
            focusedWindowId: daemonSnapshot.focusedWindowID.map { String($0.rawValue) },
            displays: displaySnapshots(from: daemonSnapshot),
            desktops: desktopSnapshots(from: daemonSnapshot.state),
            stages: stageSnapshots(from: daemonSnapshot.state),
            windows: windowSnapshots(from: daemonSnapshot),
            groups: [],
            rules: []
        )
    }

    private func displaySnapshots(from snapshot: DaemonSnapshot) -> [AutomationDisplaySnapshot] {
        snapshot.displays.map { display in
            AutomationDisplaySnapshot(
                id: display.id.rawValue,
                name: display.name,
                frame: display.frame,
                activeDesktopId: snapshot.state.display(display.id).map { String($0.currentDesktopID.rawValue) }
            )
        }
    }

    private func desktopSnapshots(from state: RoadieState) -> [AutomationDesktopSnapshot] {
        state.displays.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .flatMap { display in
                display.desktops.values
                    .sorted { $0.id < $1.id }
                    .map { desktop in
                        AutomationDesktopSnapshot(
                            id: String(desktop.id.rawValue),
                            displayId: display.id.rawValue,
                            label: desktop.label,
                            activeStageId: desktop.activeStageID.rawValue
                        )
                    }
            }
    }

    private func stageSnapshots(from state: RoadieState) -> [AutomationStageSnapshot] {
        state.displays.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .flatMap { display in
                display.desktops.values
                    .sorted { $0.id < $1.id }
                    .flatMap { desktop in
                        desktop.stages.values
                            .sorted { $0.id < $1.id }
                            .map { stage in
                                AutomationStageSnapshot(
                                    id: stage.id.rawValue,
                                    desktopId: String(desktop.id.rawValue),
                                    name: stage.name,
                                    mode: stage.mode.rawValue,
                                    windowIds: stage.windowIDs.map { String($0.rawValue) },
                                    focusedWindowId: stage.focusedWindowID.map { String($0.rawValue) }
                                )
                            }
                    }
            }
    }

    private func windowSnapshots(from snapshot: DaemonSnapshot) -> [AutomationWindowSnapshot] {
        snapshot.windows.map { scoped in
            AutomationWindowSnapshot(
                id: String(scoped.window.id.rawValue),
                app: scoped.window.appName,
                title: scoped.window.title,
                displayId: scoped.scope?.displayID.rawValue,
                desktopId: scoped.scope.map { String($0.desktopID.rawValue) },
                stageId: scoped.scope?.stageID.rawValue,
                frame: scoped.window.frame,
                isFocused: scoped.window.id == snapshot.focusedWindowID,
                isFloating: scoped.scope == nil
            )
        }
    }
}
