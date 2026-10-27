import CoreGraphics
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 102 : barre déplaçable, place retenue, écran choisi.
@Suite(.serialized)
struct Spec102PlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func bottomStaysTheHistoricalPlaceWithTheListAbove() {
        let layout = SearchBarLayout.make(bounds: screen, suggestions: 4, messageLines: 0)
        #expect(layout.bar.minY == 48)
        #expect(layout.bar.midX == 800)
        let panel = try! #require(layout.panel)
        #expect(panel.minY > layout.bar.maxY)
    }

    @Test func topAndCenterOpenTheListBelowTheBar() throws {
        for placement in [SearchBarPlacement.top, .center] {
            let layout = SearchBarLayout.makeRich(bounds: screen, heights: [20, 40, 40, 40], selected: 1, placement: placement)
            let panel = try #require(layout.panel)
            #expect(panel.maxY < layout.bar.minY)
            #expect(panel.minY >= 8)
            // Première ligne collée à la barre.
            #expect(layout.suggestionRows.first!.maxY > layout.suggestionRows.last!.maxY)
        }
        #expect(SearchBarPlacement(setting: "top") == .top)
        #expect(SearchBarPlacement(setting: "inconnu") == .bottom)
    }

    @Test func aDraggedPlaceIsRelativeToTheScreenAndStaysInside() {
        let placement = SearchBarPlacement.custom(center: CGPoint(x: 400, y: 750), in: screen)
        #expect(placement == .custom(x: 0.25, y: 0.75))
        #expect(placement.listBelow)
        let bar = placement.bar(in: screen, width: 640, height: 40)
        #expect(bar.midX == 400 && bar.midY == 750)
        // Un autre écran garde la même place relative.
        let other = CGRect(x: 1600, y: 0, width: 800, height: 500)
        #expect(placement.bar(in: other, width: 640, height: 40).midY == 375)
        // Trop au bord : la barre reste dans l'écran.
        let edge = SearchBarPlacement.custom(x: 1, y: 0).bar(in: screen, width: 640, height: 40)
        #expect(edge.maxX == 1600 && edge.minY == 0)
        #expect(!SearchBarPlacement.custom(x: 0.5, y: 0.2).listBelow)
    }

    @Test func theSavedPlaceSurvivesAndCanBeForgotten() {
        let path = NSTemporaryDirectory() + "roadie-102-\(UUID().uuidString).json"
        let store = LauncherPositionStore(path: path)
        #expect(store.load() == nil)
        store.save(.custom(x: 0.3, y: 0.8))
        #expect(store.load() == .custom(x: 0.3, y: 0.8))
        store.save(nil)
        #expect(store.load() == nil)
    }

    @Test func barScreenFollowsTheSetting() {
        let left = CGRect(x: 0, y: 0, width: 1600, height: 1000), right = CGRect(x: 1600, y: 0, width: 1920, height: 1080)
        let focused = CGRect(x: 1700, y: 100, width: 800, height: 600)
        #expect(TargetModeRuntimeController.barScreen("main", focused: focused, screens: [left, right]) == left)
        #expect(TargetModeRuntimeController.barScreen("active", focused: focused, screens: [left, right]) == right)
        #expect(TargetModeRuntimeController.barScreen("active", focused: nil, screens: [left, right]) == nil)
        #expect(TargetModeRuntimeController.barScreen("mouse", focused: focused, screens: [left, right]) == nil)
    }

    @Test func dragEventsAreInTheSearchMask() {
        let mask = TargetSearchDismissal.eventMask(search: true)
        #expect(mask & CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) != 0)
        #expect(mask & CGEventMask(1 << CGEventType.leftMouseUp.rawValue) != 0)
        #expect(TargetSearchDismissal.eventMask(search: false) & CGEventMask(1 << CGEventType.leftMouseUp.rawValue) == 0)
    }
}
