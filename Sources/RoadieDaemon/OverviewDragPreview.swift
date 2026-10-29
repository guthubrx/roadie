import Foundation
import RoadieCore

/// Ce que produira le dépôt en cours (SPEC-071). Sert à la fois à l’aperçu en direct et à l’action.
enum OverviewDropIntent: Equatable {
    /// Bureau posé à la place `target` d’un écran (même écran : renumérotation ; autre écran : insertion).
    case desktop(source: OverviewDesktopID, display: DisplayID, target: DesktopID)
    /// Stage insérée devant `before` (nil = en dernier) dans un bureau existant.
    case stage(source: StageScope, display: DisplayID, desktop: DesktopID, before: StageID?)
    /// Stage qui crée un nouveau bureau, après le dernier de l’écran.
    case stageToNewDesktop(source: StageScope, display: DisplayID)
    /// Fenêtre qui rejoint une stage existante.
    case window(WindowID, target: StageScope)
    /// Fenêtre qui crée une nouvelle stage dans un bureau existant.
    case windowToNewStage(WindowID, display: DisplayID, desktop: DesktopID)
    /// Fenêtre qui crée un nouveau bureau (et sa stage), après le dernier de l’écran.
    case windowToNewDesktop(WindowID, display: DisplayID)
}

/// Identifiants réservés à l’aperçu des contenants créés ; jamais écrits dans l’état.
enum OverviewPreviewIDs {
    static let newStage = StageID(rawValue: "overview-preview-new-stage")
    static func newDesktop(on display: DisplayID, after model: OverviewModel) -> OverviewDesktopID {
        let highest = model.displays.first { $0.id == display }?.desktops.map(\.id.desktopID.rawValue).max() ?? 0
        return OverviewDesktopID(displayID: display, desktopID: DesktopID(rawValue: highest + 1))
    }
}

extension WindowSwitcherEntry {
    func moved(to scope: StageScope) -> WindowSwitcherEntry {
        WindowSwitcherEntry(window: window, scope: scope, displayName: displayName, desktopName: desktopName, stageName: stageName,
                            isMinimized: isMinimized, isHidden: isHidden, isFullscreen: isFullscreen,
                            isAvailable: isAvailable, visibilityKnown: visibilityKnown)
    }
}

extension OverviewDesktop {
    /// Même bureau sous un autre numéro : seul le nom affiché change, l’identité reste celle d’origine
    /// pour que l’aperçu suive l’élément à sa nouvelle place.
    func renumbered(_ number: Int) -> OverviewDesktop {
        let label = name.range(of: " · ").map { String(name[$0.lowerBound...]) } ?? ""
        return OverviewDesktop(id: id, name: tr("Bureau", "Desktop") + " \(number)\(label)", isActive: isActive, stages: stages)
    }
}

extension OverviewModel {
    /// Vue d’ensemble telle qu’elle sera après le dépôt. Les éléments déplacés gardent leur identité
    /// (fenêtre, bureau d’origine) ; seuls places, numéros affichés et stages d’accueil changent. O(w + s + b).
    func previewing(_ intent: OverviewDropIntent) -> OverviewModel {
        var copy = self
        switch intent {
        case .desktop(let source, let display, let target):
            copy.previewDesktop(source, to: display, target)
        case .stage(let source, let display, let desktop, let before):
            guard let stage = copy.removeStage(source) else { return self }
            copy.insert(stage, display: display, desktop: desktop, before: before)
        case .stageToNewDesktop(let source, let display):
            guard let stage = copy.removeStage(source) else { return self }
            copy.appendNewDesktop(on: display, stage: stage)
        case .window(let id, let target):
            guard let entry = copy.removeEntry(id) else { return self }
            copy.updateStage(target) { $0.entries.append(entry.moved(to: target)) }
        case .windowToNewStage(let id, let display, let desktop):
            guard let entry = copy.removeEntry(id) else { return self }
            let scope = StageScope(displayID: display, desktopID: desktop, stageID: OverviewPreviewIDs.newStage)
            copy.insert(OverviewStage(scope: scope, name: tr("Nouvelle stage", "New stage"), entries: [entry.moved(to: scope)], isActive: false),
                        display: display, desktop: desktop, before: nil)
        case .windowToNewDesktop(let id, let display):
            guard let entry = copy.removeEntry(id) else { return self }
            let desktop = OverviewPreviewIDs.newDesktop(on: display, after: copy)
            let scope = StageScope(displayID: display, desktopID: desktop.desktopID, stageID: OverviewPreviewIDs.newStage)
            copy.appendNewDesktop(on: display, stage: OverviewStage(scope: scope, name: tr("Nouvelle stage", "New stage"), entries: [entry.moved(to: scope)], isActive: false))
        }
        return copy
    }

    private mutating func previewDesktop(_ source: OverviewDesktopID, to display: DisplayID, _ target: DesktopID) {
        guard let from = displays.firstIndex(where: { $0.id == source.displayID }),
              let index = displays[from].desktops.firstIndex(where: { $0.id == source }) else { return }
        if display == source.displayID {
            let mapping = DesktopReorder.mapping(from: source.desktopID, to: target)
            displays[from].desktops = displays[from].desktops
                .map { desktop in (desktop, (mapping[desktop.id.desktopID] ?? desktop.id.desktopID).rawValue) }
                .sorted { $0.1 < $1.1 }
                .map { $0.0.renumbered($0.1) }
            return
        }
        guard let to = displays.firstIndex(where: { $0.id == display }) else { return }
        let moving = displays[from].desktops.remove(at: index)
        displays[from].desktops = displays[from].desktops.map { desktop in
            desktop.id.desktopID > source.desktopID ? desktop.renumbered(desktop.id.desktopID.rawValue - 1) : desktop
        }
        var arrivals = displays[to].desktops.map { desktop in
            desktop.id.desktopID >= target ? desktop.renumbered(desktop.id.desktopID.rawValue + 1) : desktop
        }
        let position = arrivals.firstIndex { $0.id.desktopID >= target } ?? arrivals.count
        arrivals.insert(moving.renumbered(target.rawValue), at: position)
        displays[to].desktops = arrivals
    }

    private mutating func removeStage(_ scope: StageScope) -> OverviewStage? {
        for d in displays.indices {
            for b in displays[d].desktops.indices {
                if let s = displays[d].desktops[b].stages.firstIndex(where: { $0.scope == scope }) {
                    return displays[d].desktops[b].stages.remove(at: s)
                }
            }
        }
        return nil
    }

    private mutating func removeEntry(_ id: WindowID) -> WindowSwitcherEntry? {
        for d in displays.indices {
            for b in displays[d].desktops.indices {
                for s in displays[d].desktops[b].stages.indices {
                    if let e = displays[d].desktops[b].stages[s].entries.firstIndex(where: { $0.id == id }) {
                        return displays[d].desktops[b].stages[s].entries.remove(at: e)
                    }
                }
            }
        }
        return nil
    }

    private mutating func insert(_ stage: OverviewStage, display: DisplayID, desktop: DesktopID, before: StageID?) {
        guard let d = displays.firstIndex(where: { $0.id == display }),
              let b = displays[d].desktops.firstIndex(where: { $0.id.desktopID == desktop }) else { return }
        let stages = displays[d].desktops[b].stages
        let index = before.flatMap { id in stages.firstIndex { $0.scope.stageID == id } } ?? stages.count
        displays[d].desktops[b].stages.insert(stage, at: index)
    }

    private mutating func updateStage(_ scope: StageScope, _ body: (inout OverviewStage) -> Void) {
        for d in displays.indices where displays[d].id == scope.displayID {
            for b in displays[d].desktops.indices where displays[d].desktops[b].id.desktopID == scope.desktopID {
                for s in displays[d].desktops[b].stages.indices where displays[d].desktops[b].stages[s].scope == scope {
                    body(&displays[d].desktops[b].stages[s])
                }
            }
        }
    }

    private mutating func appendNewDesktop(on display: DisplayID, stage: OverviewStage) {
        guard let d = displays.firstIndex(where: { $0.id == display }) else { return }
        let id = OverviewPreviewIDs.newDesktop(on: display, after: self)
        displays[d].desktops.append(OverviewDesktop(id: id, name: tr("Nouveau bureau", "New desktop"), isActive: false, stages: [stage]))
    }
}
