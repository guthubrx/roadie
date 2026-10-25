import AppKit
import Foundation
import RoadieCore

/// Ce que la barre de recherche reçoit pour jouer le rôle de lanceur (SPEC-073).
struct LauncherSearchContext {
    var apps: [LauncherApp]
    /// État affiché à côté de chaque application, par identifiant.
    var details: [String: String]
    var ranking: LauncherRanking
    /// Rafraîchit l'index des applications et rappelle avec le nouveau, sur le fil principal.
    var refreshApps: (@escaping @MainActor @Sendable ([LauncherApp]) -> Void) -> Void
    /// Va à la fenêtre de l'application ou l'ouvre ; appelé après la fermeture de la barre.
    var launch: @MainActor (LauncherApp) -> TargetActionResult
    /// Mémorise un choix : clé de classement, requête tapée.
    var recordVisit: @MainActor (String, String) -> Void

    /// Sans lanceur : la barre garde le seul mode recherche (tests, configuration désactivée).
    static var disabled: LauncherSearchContext { LauncherSearchContext(
        apps: [], details: [:], ranking: LauncherRanking(), refreshApps: { _ in },
        launch: { _ in TargetActionResult(changed: false, message: "launcher_disabled") }, recordVisit: { _, _ in }) }
}

/// Décisions du lanceur sur l'état de Roadie, sans effet de bord.
enum LauncherPlacement {
    /// Fenêtre à rejoindre pour une application déjà ouverte : celle qui a le focus dans une stage
    /// affichée, puis une fenêtre d'une stage affichée, puis la fenêtre qui avait le focus dans sa
    /// stage, puis la première. O(w), w fenêtres de l'application.
    static func preferredWindow(_ entries: [WindowSwitcherEntry], state: PersistentStageState) -> WindowSwitcherEntry? {
        func stage(_ scope: StageScope) -> PersistentStage? {
            state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages.first { $0.id == scope.stageID }
        }
        func shown(_ scope: StageScope) -> Bool {
            state.currentDesktopID(for: scope.displayID) == scope.desktopID
                && state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?.activeStageID == scope.stageID
        }
        func focused(_ entry: WindowSwitcherEntry) -> Bool { entry.scope.flatMap(stage)?.focusedWindowID == entry.id }
        let managed = entries.filter { $0.scope != nil }
        return managed.first { shown($0.scope!) && focused($0) }
            ?? managed.first { shown($0.scope!) }
            ?? managed.first(where: focused)
            ?? managed.first
            ?? entries.first
    }

    /// État de chaque application : ouverte ou non, et stage et bureau de sa fenêtre la plus
    /// pertinente, avec les noms du rail. O(m), m membres des stages.
    static func details(runningBundleIDs: Set<String>, state: PersistentStageState, stageNames: [StageScope: String]) -> [String: String] {
        var locations: [String: (shown: Bool, text: String)] = [:]
        for scope in state.scopes {
            let current = state.currentDesktopID(for: scope.displayID) == scope.desktopID
            for stage in scope.stages {
                let key = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                guard let name = stageNames[key] else { continue }
                for member in stage.members where member.confirmedClosedAt == nil && runningBundleIDs.contains(member.bundleID) {
                    let shown = current && scope.activeStageID == stage.id
                    if let known = locations[member.bundleID], known.shown || !shown { continue }
                    locations[member.bundleID] = (shown, "\(name) · bureau \(scope.desktopID.rawValue)")
                }
            }
        }
        var result: [String: String] = [:]
        for bundleID in runningBundleIDs {
            result[bundleID] = LauncherList.detail(running: true, location: locations[bundleID]?.text)
        }
        return result
    }
}
