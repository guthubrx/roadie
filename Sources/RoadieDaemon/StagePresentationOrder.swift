import Foundation
import RoadieCore

/// Projection commune du rail et des destinations (SPEC-029). L'ordre persistant et les IDs restent
/// intacts ; seuls les membres réellement représentés et les stages nommées composent l'ordre visible.
struct StagePresentationOrder {
    let visibleStages: [PersistentStage]
    let emptyStageIDs: [StageID]

    init(scope: PersistentStageScope, liveWindowIDs: Set<WindowID>, now: Date = Date()) {
        let representedStages = scope.stages.compactMap { stage -> PersistentStage? in
            let represented = RailController.railDisplayStage(stage, liveWindowIDs: liveWindowIDs, now: now)
            let named = Self.isNamed(stage) && (stage.parkingState != .parked || !stage.members.isEmpty)
            guard !represented.members.isEmpty || named else { return nil }
            return represented
        }
        // Partition stable : les destinations et le rail partagent les mêmes rangs. O(s).
        visibleStages = representedStages.filter { !$0.members.isEmpty }
            + representedStages.filter { $0.members.isEmpty }
        // Un membre absent du relevé n'est pas une place libre : ne jamais y mélanger une nouvelle
        // fenêtre. Les stages nommées ont déjà leur carte et ne sont pas le dépôt « prochaine vide ».
        emptyStageIDs = scope.stages.filter {
            $0.parkingState != .parked && $0.members.isEmpty && !Self.isNamed($0)
        }.map(\.id)
    }

    var visibleStageIDs: [StageID] { visibleStages.map(\.id) }

    func stageID(at position: Int, allowingEmptySlots: Bool = false) -> StageID? {
        guard position > 0 else { return nil }
        let ordered = visibleStageIDs + (allowingEmptySlots ? emptyStageIDs : [])
        guard ordered.indices.contains(position - 1) else { return nil }
        return ordered[position - 1]
    }

    static func isNamed(_ stage: PersistentStage) -> Bool {
        let name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedNames = [stage.id.rawValue, stage.origin?.stageID.rawValue].compactMap { $0 }.map { "Stage \($0)" }
        return !name.isEmpty && !generatedNames.contains(name)
    }

    static func name(_ stage: PersistentStage, position: Int) -> String {
        isNamed(stage) ? stage.name.trimmingCharacters(in: .whitespacesAndNewlines) : "Stage \(position)"
    }

    static func menuLabel(_ stage: PersistentStage, position: Int) -> String {
        isNamed(stage) ? "\(position) · \(name(stage, position: position))" : name(stage, position: position)
    }
}
