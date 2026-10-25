import Foundation
import RoadieCore

/// Une stage nommée est unique dans tout Roadie, tous écrans et bureaux confondus (SPEC-067).
/// Les noms générés (« Stage N ») ne comptent pas : ils désignent des stages anonymes.
enum StageNameUniqueness {
    /// Clé de comparaison : espaces de bord ignorés, sans distinction de casse.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension PersistentStageState {
    /// Clés des noms portés par les stages nommées, hors un bureau (et hors une stage) donnés. O(S).
    func namedStageKeys(excludingDisplay displayID: DisplayID? = nil, desktop desktopID: DesktopID? = nil,
                        stage stageID: StageID? = nil) -> Set<String> {
        var keys = Set<String>()
        for scope in scopes {
            let sameDesktop = scope.displayID == displayID && scope.desktopID == desktopID
            for stage in scope.stages where StagePresentationOrder.isNamed(stage) {
                if sameDesktop, stageID == nil || stage.id == stageID { continue }
                keys.insert(StageNameUniqueness.key(stage.name))
            }
        }
        return keys
    }

    /// Doublons existants : une copie sur un écran branché passe avant une copie d'écran absent (ses
    /// membres mémorisés peuvent être fermés depuis longtemps), puis la copie qui a le plus de fenêtres
    /// garde le nom ; les autres copies occupées deviennent « Nom 2 », « Nom 3 »… ; les copies vides
    /// redeviennent anonymes. À égalité, le plus petit numéro de bureau, écran actif d'abord. Aucune
    /// stage n'est supprimée et aucune fenêtre ne change de stage. `liveDisplays` vide : aucun écran
    /// n'est privilégié. Renvoie le nombre de stages modifiées. O(S log S).
    mutating func makeStageNamesUnique(liveDisplays: Set<DisplayID> = []) -> Int {
        struct Copy { let scope: Int; let stage: Int; let members: Int; let desktop: Int; let activeDisplay: Bool; let live: Bool }
        var groups: [String: [Copy]] = [:]
        var order: [String] = []
        for (scopeIndex, scope) in scopes.enumerated() {
            for (stageIndex, stage) in scope.stages.enumerated() where StagePresentationOrder.isNamed(stage) {
                let key = StageNameUniqueness.key(stage.name)
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(Copy(scope: scopeIndex, stage: stageIndex, members: stage.members.count,
                                                     desktop: scope.desktopID.rawValue, activeDisplay: scope.displayID == activeDisplayID,
                                                     live: liveDisplays.contains(scope.displayID)))
            }
        }
        var taken = Set(order)
        var changed = 0
        for key in order {
            guard let copies = groups[key], copies.count > 1 else { continue }
            let ranked = copies.sorted { a, b in
                if a.live != b.live { return a.live }
                if a.members != b.members { return a.members > b.members }
                if a.desktop != b.desktop { return a.desktop < b.desktop }
                if a.activeDisplay != b.activeDisplay { return a.activeDisplay }
                return (a.scope, a.stage) < (b.scope, b.stage)
            }
            let base = scopes[ranked[0].scope].stages[ranked[0].stage].name.trimmingCharacters(in: .whitespacesAndNewlines)
            var suffix = 2
            for copy in ranked.dropFirst() {
                if copy.members > 0 {
                    while taken.contains(StageNameUniqueness.key("\(base) \(suffix)")) { suffix += 1 }
                    scopes[copy.scope].stages[copy.stage].name = "\(base) \(suffix)"
                    taken.insert(StageNameUniqueness.key("\(base) \(suffix)"))
                } else {
                    let id = scopes[copy.scope].stages[copy.stage].id
                    scopes[copy.scope].stages[copy.stage].name = "Stage \(id.rawValue)"
                }
                changed += 1
            }
        }
        return changed
    }

    /// Nombre de noms portés par plus d'une stage. O(S).
    var duplicateStageNameCount: Int {
        var counts: [String: Int] = [:]
        for scope in scopes {
            for stage in scope.stages where StagePresentationOrder.isNamed(stage) {
                counts[StageNameUniqueness.key(stage.name), default: 0] += 1
            }
        }
        return counts.values.filter { $0 > 1 }.count
    }
}
