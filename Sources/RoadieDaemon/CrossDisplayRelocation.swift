import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

/// Fenêtres d'une stage ou d'un bureau arrivés sur un autre écran sans y être affichés (SPEC-070).
/// Elles rejoignent le coin de masquage de cet écran ; leurs cadres de retour sont recentrés dans sa
/// zone utile, écrits après l'application car le relevé du plan réécrit les cadres des membres
/// (même règle que REL-023). Une fenêtre absente du relevé garde seulement son cadre recentré. O(w + m).
func relocateHiddenWindows(
    _ ids: Set<WindowID>,
    to displayID: DisplayID,
    service: SnapshotService,
    store: StageStore,
    events: EventLog,
    cause: String
) -> (moved: Int, failed: Int) {
    guard !ids.isEmpty else { return (0, 0) }
    let generation = PlacementGeneration.shared.next()
    let snapshot = service.snapshot()
    guard let display = snapshot.displays.first(where: { $0.id == displayID }) else { return (0, ids.count) }
    var placement = CommandPlacement(layoutScopes: [])
    for entry in snapshot.windows where ids.contains(entry.window.id) {
        placement.hiding[entry.window.id] = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
    }
    let result = service.applyCommandPlacement(placement, cause: cause, generation: generation, events: events).result
    let area = display.visibleFrame.cgRect
    try? store.mutateChecked { state in
        for scopeIndex in state.scopes.indices where state.scopes[scopeIndex].displayID == displayID {
            for stageIndex in state.scopes[scopeIndex].stages.indices {
                for memberIndex in state.scopes[scopeIndex].stages[stageIndex].members.indices {
                    let member = state.scopes[scopeIndex].stages[stageIndex].members[memberIndex]
                    guard ids.contains(member.windowID) else { continue }
                    let frame = member.frame.cgRect
                    let width = min(frame.width, area.width), height = min(frame.height, area.height)
                    state.scopes[scopeIndex].stages[stageIndex].members[memberIndex].frame =
                        Rect(CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height).integral)
                }
            }
        }
    }
    return (placement.hiding.count, result.failed)
}
