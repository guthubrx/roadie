import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec097PreviousWindowTests {
    private func targets(_ ids: [UInt32]) -> [String: RoadieTarget] {
        Dictionary(uniqueKeysWithValues: ids.map { id in
            ("window:\(id)", RoadieTarget(id: "window:\(id)", kind: .window, title: "w\(id)", source: .roadie, actions: [.focus]))
        })
    }

    @Test func backIsTheWindowBeforeTheActiveOne() {
        let previous = TargetModeRuntimeController.previousWindow(
            recent: [WindowID(rawValue: 638), WindowID(rawValue: 67718)], focused: WindowID(rawValue: 638), targets: targets([638, 67718]))
        #expect(previous?.id == "window:67718")
    }

    @Test func unknownOrMissingFocusNeverProposesTheCurrentWindow() {
        // Constat du 27 octobre : la fenêtre active lue n'était pas une cible, « Revenir » montrait T3 (638).
        let all = targets([638, 67718])
        let history = [WindowID(rawValue: 638), WindowID(rawValue: 67718)]
        for focused in [nil, WindowID(rawValue: 999)] {
            #expect(TargetModeRuntimeController.previousWindow(recent: history, focused: focused, targets: all)?.id == "window:67718")
        }
        // Une fenêtre récente sans cible est sautée.
        #expect(TargetModeRuntimeController.previousWindow(
            recent: [WindowID(rawValue: 5), WindowID(rawValue: 638), WindowID(rawValue: 67718)], focused: nil, targets: all)?.id == "window:67718")
        #expect(TargetModeRuntimeController.previousWindow(recent: [WindowID(rawValue: 638)], focused: nil, targets: all) == nil)
    }
}
