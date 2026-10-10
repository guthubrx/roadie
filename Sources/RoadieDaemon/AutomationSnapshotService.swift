import Foundation
import RoadieCore
import RoadieStages

public struct AutomationSnapshotService: Sendable {
    /// Règles injectées (tests) ; nil = règles de la config courante du processus.
    private let rules: [WindowRule]?
    private let stageStore: StageStore

    public init(rules: [WindowRule]? = nil, stageStore: StageStore = StageStore()) {
        self.rules = rules
        self.stageStore = stageStore
    }

    public func snapshot(from daemonSnapshot: DaemonSnapshot, generatedAt: Date = Date()) -> RoadieStateSnapshot {
        let activeScope = activeDisplayID(in: daemonSnapshot)
            .flatMap { daemonSnapshot.state.activeScope(on: $0) }
        let rules = self.rules ?? ConfigReloadService.shared.currentConfig().rules

        return RoadieStateSnapshot(
            generatedAt: generatedAt,
            activeDisplayId: activeScope?.displayID.rawValue,
            activeDesktopId: activeScope.map { String($0.desktopID.rawValue) },
            activeStageId: activeScope?.stageID.rawValue,
            focusedWindowId: daemonSnapshot.focusedWindowID.map { String($0.rawValue) },
            displays: displaySnapshots(from: daemonSnapshot),
            desktops: desktopSnapshots(from: daemonSnapshot.state),
            stages: stageSnapshots(from: daemonSnapshot.state),
            windows: windowSnapshots(from: daemonSnapshot),
            groups: groupSnapshots(from: daemonSnapshot.state),
            rules: Self.ruleSnapshots(rules)
        )
    }

    /// Vue automation des règles, format unique partagé avec `AutomationQueryService`. O(r).
    static func ruleSnapshots(_ rules: [WindowRule]) -> [AutomationRuleSnapshot] {
        rules.map {
            AutomationRuleSnapshot(id: $0.id, enabled: $0.enabled, priority: $0.priority, description: $0.match.description)
        }
    }

    /// Display actif déterministe : celui de la fenêtre focalisée, sinon le display actif
    /// persisté, sinon le premier display (ordre du snapshot) qui a une stage active.
    // O(d + w) — d displays (bornés, < 10), w fenêtres.
    private func activeDisplayID(in snapshot: DaemonSnapshot) -> DisplayID? {
        let snapshotDisplayIDs = snapshot.displays.map(\.id)
        let stateOnlyDisplayIDs = snapshot.state.displays.values.map(\.id)
            .filter { !snapshotDisplayIDs.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let candidates = (snapshotDisplayIDs + stateOnlyDisplayIDs)
            .filter { snapshot.state.activeScope(on: $0) != nil }
        if let focusedID = snapshot.focusedWindowID,
           let displayID = snapshot.windows.first(where: { $0.window.id == focusedID })?.scope?.displayID,
           candidates.contains(displayID) {
            return displayID
        }
        if let persisted = stageStore.state().activeDisplayID, candidates.contains(persisted) {
            return persisted
        }
        return candidates.first
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
        let resolver = WindowPresentationStateResolver()
        return snapshot.windows.map { scoped in
            AutomationWindowSnapshot(
                id: String(scoped.window.id.rawValue),
                app: scoped.window.appName,
                title: scoped.window.title,
                displayId: scoped.scope?.displayID.rawValue,
                desktopId: scoped.scope.map { String($0.desktopID.rawValue) },
                stageId: scoped.scope?.stageID.rawValue,
                frame: scoped.window.frame,
                isFocused: scoped.window.id == snapshot.focusedWindowID,
                isFloating: scoped.scope == nil,
                presentationState: resolver.state(for: scoped, in: snapshot)
            )
        }
    }

    private func groupSnapshots(from state: RoadieState) -> [AutomationGroupSnapshot] {
        state.displays.values
            .flatMap { display in
                display.desktops.values.flatMap { desktop in
                    desktop.stages.values.flatMap { stage in
                        stage.groups.map { group in
                            AutomationGroupSnapshot(
                                id: group.id,
                                stageId: stage.id.rawValue,
                                memberIds: group.windowIDs.map { String($0.rawValue) },
                                activeMemberId: group.activeWindowID.map { String($0.rawValue) },
                                presentation: group.presentation
                            )
                        }
                    }
                }
            }
            .sorted { $0.id < $1.id }
    }
}

// Description lisible d'un filtre de règle (snapshot et requête automation).
extension RuleMatch {
    var description: String {
        [
            app.map { "app=\($0)" },
            appRegex.map { "app_regex=\($0)" },
            title.map { "title=\($0)" },
            titleRegex.map { "title_regex=\($0)" },
            role.map { "role=\($0)" },
            stage.map { "stage=\($0)" }
        ].compactMap(\.self).joined(separator: ",")
    }
}
