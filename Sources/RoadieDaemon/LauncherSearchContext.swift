import AppKit
import Foundation
import RoadieAX
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
    /// Stages, bureaux et écrans proposés comme destinations (SPEC-074).
    var destinations: [LauncherDestination] = []
    /// Bureau affiché de l'écran actif : là où « Nouvelle stage » crée la stage.
    var newStageHome = (DisplayID(rawValue: "none"), DesktopID(rawValue: 1))
    /// Exécute un verbe ; appelé après la fermeture de la barre.
    var perform: @MainActor (LauncherAction) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    /// Stage active du bureau affiché : la destination de ⌥ Retour (SPEC-075).
    var activeStage: StageScope?
    /// Identité de cette stage pour le classement appris (SPEC-076) : `stage:<nom>` ou `scope:<place>`.
    var rankingContext: String?
    /// Objet dont la barre montre tout de suite les verbes (Capslock + Maj + F) ; nil : la liste.
    var initialSubject: LauncherSubject?
    /// État de tuilage d'une fenêtre, pour ses verbes de flottement.
    var tiling: @MainActor (WindowID) -> LauncherTilingState? = { _ in nil }
    /// ⌃ Retour : le texte tapé sur le web ; appelé après la fermeture de la barre.
    var webSearch: @MainActor (String) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }

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

    /// Destinations proposées : stages visibles au rail (nommées ou occupées), bureaux occupés, nommés
    /// ou affichés, puis écrans ; écrans dans leur ordre, bureaux par numéro. O(S + d).
    static func destinations(state: PersistentStageState, displays: [DisplaySnapshot],
                             stageNames: [StageScope: String]) -> [LauncherDestination] {
        var stages: [LauncherDestination] = [], desktops: [LauncherDestination] = [], screens: [LauncherDestination] = []
        for display in displays.sorted(by: { $0.index < $1.index }) {
            let current = state.currentDesktopID(for: display.id)
            let scopes = state.scopes.filter { $0.displayID == display.id }.sorted { $0.desktopID < $1.desktopID }
            for scope in scopes {
                let label = state.label(displayID: display.id, desktopID: scope.desktopID)
                let occupied = scope.stages.contains { !$0.members.isEmpty }
                if occupied || label != nil || scope.desktopID == current {
                    desktops.append(LauncherDestination(kind: .desktop(display.id, scope.desktopID),
                                                        title: "Bureau \(scope.desktopID.rawValue)" + (label.map { " · \($0)" } ?? ""),
                                                        detail: display.name))
                }
                for stage in scope.stages {
                    let key = StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stage.id)
                    guard let name = stageNames[key] else { continue }
                    stages.append(LauncherDestination(kind: .stage(key), title: name,
                                                      detail: "bureau \(scope.desktopID.rawValue) · \(display.name)"))
                }
            }
            screens.append(LauncherDestination(kind: .display(display.id), title: display.name, detail: "écran"))
        }
        return stages + desktops + screens
    }
}

/// Recherche web de ⌃ Retour (SPEC-075), reprise par le repli de la session 077.
extension LauncherSearchContext {
    /// Stage nommée : son nom, unique dans tout Roadie et stable quand elle change de bureau.
    /// Stage anonyme : sa place. O(1).
    static func rankingContext(_ scope: StageScope, name: String?) -> String {
        let folded = name.map(LauncherMatch.fold) ?? ""
        return folded.isEmpty ? "scope:\(scope.description)" : "stage:\(folded)"
    }
}

enum LauncherWeb {
    /// `{query}` remplacé par le texte encodé ; nil si l'adresse obtenue est invalide. O(q).
    static func searchURL(_ template: String, query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard template.contains("{query}"),
              let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }
}
