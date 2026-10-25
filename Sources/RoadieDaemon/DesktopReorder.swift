import Foundation
import RoadieCore

/// Réordonnancement des bureaux d'un écran (SPEC-066), comme Mission Control : le bureau déplacé
/// prend le numéro de sa nouvelle place et ceux d'entre les deux glissent d'un cran. Tout ce qui
/// appartient à un bureau suit son contenu : stages, sélection et historique, nom, épinglages,
/// signets, origine des stages garées, protection de focus et intentions de disposition.
enum DesktopReorder {
    /// Ancien numéro → nouveau, pour les seuls bureaux renumérotés ; vide si `from == to`. O(|to - from|).
    static func mapping(from: DesktopID, to: DesktopID) -> [DesktopID: DesktopID] {
        guard from != to else { return [:] }
        var result = [from: to]
        let shifted = from < to ? Array(from.rawValue + 1 ... to.rawValue) : Array(to.rawValue ..< from.rawValue)
        for raw in shifted {
            result[DesktopID(rawValue: raw)] = DesktopID(rawValue: from < to ? raw - 1 : raw + 1)
        }
        return result
    }

    static func remap(_ scope: StageScope, on displayID: DisplayID, _ mapping: [DesktopID: DesktopID]) -> StageScope {
        guard scope.displayID == displayID, let desktopID = mapping[scope.desktopID] else { return scope }
        return StageScope(displayID: displayID, desktopID: desktopID, stageID: scope.stageID)
    }

    /// Intentions réindexées sur leur nouveau scope : un zoom ou une disposition suit son bureau. O(i).
    static func remap(intents: inout [String: LayoutIntent], on displayID: DisplayID, _ mapping: [DesktopID: DesktopID]) {
        var result: [String: LayoutIntent] = [:]
        for (key, intent) in intents {
            var moved = intent
            moved.scope = remap(intent.scope, on: displayID, mapping)
            result[moved.scope == intent.scope ? key : moved.scope.description] = moved
        }
        intents = result
    }
}

extension PersistentStageState {
    /// Applique la correspondance à un écran, en une seule mutation. O(s + p + b), s = scopes et stages.
    mutating func renumberDesktops(on displayID: DisplayID, _ mapping: [DesktopID: DesktopID]) {
        guard !mapping.isEmpty else { return }
        func moved(_ id: DesktopID) -> DesktopID { mapping[id] ?? id }
        for index in scopes.indices where scopes[index].displayID == displayID {
            scopes[index].desktopID = moved(scopes[index].desktopID)
        }
        for scopeIndex in scopes.indices {
            for stageIndex in scopes[scopeIndex].stages.indices {
                guard let origin = scopes[scopeIndex].stages[stageIndex].origin, origin.displayID == displayID else { continue }
                scopes[scopeIndex].stages[stageIndex].origin?.desktopID = moved(origin.desktopID)
            }
        }
        for index in desktopSelections.indices where desktopSelections[index].displayID == displayID {
            desktopSelections[index].currentDesktopID = moved(desktopSelections[index].currentDesktopID)
            desktopSelections[index].lastDesktopID = desktopSelections[index].lastDesktopID.map(moved)
        }
        for index in desktopLabels.indices where desktopLabels[index].displayID == displayID {
            desktopLabels[index].desktopID = moved(desktopLabels[index].desktopID)
        }
        for index in windowPins.indices {
            windowPins[index].homeScope = DesktopReorder.remap(windowPins[index].homeScope, on: displayID, mapping)
        }
        for index in windowBookmarks.indices {
            windowBookmarks[index].scope = DesktopReorder.remap(windowBookmarks[index].scope, on: displayID, mapping)
        }
        if commandFocusProtection?.displayID == displayID, let protection = commandFocusProtection {
            commandFocusProtection?.desktopID = moved(protection.desktopID)
        }
    }
}
