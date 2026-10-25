import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec066DesktopReorderTests {
    private let main = DisplayID(rawValue: "display-main")
    private let other = DisplayID(rawValue: "display-other")

    private func d(_ raw: Int) -> DesktopID { DesktopID(rawValue: raw) }
    private func scope(_ display: DisplayID, _ desktop: Int, _ stage: String = "1") -> StageScope {
        StageScope(displayID: display, desktopID: d(desktop), stageID: StageID(rawValue: stage))
    }

    @Test func mappingRotatesOnlyTheRangeBetweenSourceAndTarget() {
        #expect(DesktopReorder.mapping(from: d(2), to: d(1)) == [d(2): d(1), d(1): d(2)])
        #expect(DesktopReorder.mapping(from: d(1), to: d(3)) == [d(1): d(3), d(2): d(1), d(3): d(2)])
        #expect(DesktopReorder.mapping(from: d(5), to: d(2)) == [d(5): d(2), d(2): d(3), d(3): d(4), d(4): d(5)])
        #expect(DesktopReorder.mapping(from: d(3), to: d(3)).isEmpty)
    }

    @Test func everythingOwnedByADesktopFollowsItsContent() {
        let parked = PersistentStage(id: StageID(rawValue: "9"), name: "Garée", origin: StageOrigin(
            logicalDisplayID: LogicalDisplayID(rawValue: "logical"), displayID: main, desktopID: d(2),
            stageID: StageID(rawValue: "1"), position: 1, nameAtParking: "Garée", parkedAt: Date()))
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: main, desktopID: d(1), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Un")]),
                PersistentStageScope(displayID: main, desktopID: d(2), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Deux"), parked]),
                PersistentStageScope(displayID: main, desktopID: d(3), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Trois")]),
                PersistentStageScope(displayID: other, desktopID: d(2), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Ailleurs")]),
            ],
            desktopSelections: [
                PersistentDesktopSelection(displayID: main, currentDesktopID: d(2), lastDesktopID: d(1)),
                PersistentDesktopSelection(displayID: other, currentDesktopID: d(2), lastDesktopID: d(1)),
            ],
            desktopLabels: [PersistentDesktopLabel(displayID: main, desktopID: d(2), label: "Travail")],
            windowPins: [PersistentWindowPin(windowID: WindowID(rawValue: 7), homeScope: scope(main, 2), pinScope: .desktop,
                                             bundleID: "a", title: "a", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10))],
            windowBookmarks: [PersistentWindowBookmark(name: "b", windowID: WindowID(rawValue: 8), scope: scope(main, 1),
                                                       bundleID: "b", title: "b", frame: Rect(x: 0, y: 0, width: 10, height: 10))],
            commandFocusProtection: CommandFocusProtection(displayID: main, desktopID: d(2), stageID: StageID(rawValue: "1"),
                                                           windowID: nil, expiresAt: Date())
        )

        state.renumberDesktops(on: main, DesktopReorder.mapping(from: d(2), to: d(1)))

        func name(_ display: DisplayID, _ desktop: Int) -> String? {
            state.scopes.first { $0.displayID == display && $0.desktopID == d(desktop) }?.stages.first?.name
        }
        #expect(name(main, 1) == "Deux")
        #expect(name(main, 2) == "Un")
        #expect(name(main, 3) == "Trois")
        #expect(name(other, 2) == "Ailleurs")
        #expect(state.desktopSelections[0].currentDesktopID == d(1))
        #expect(state.desktopSelections[0].lastDesktopID == d(2))
        #expect(state.desktopSelections[1].currentDesktopID == d(2))
        #expect(state.label(displayID: main, desktopID: d(1)) == "Travail")
        #expect(state.windowPins[0].homeScope == scope(main, 1))
        #expect(state.windowBookmarks[0].scope == scope(main, 2))
        #expect(state.commandFocusProtection?.desktopID == d(1))
        let movedParked = state.scopes.first { $0.desktopID == d(1) && $0.displayID == main }?.stages.last
        #expect(movedParked?.origin?.desktopID == d(1))
    }

    @Test func intentsAreRekeyedOnTheirNewScope() {
        let moved = LayoutIntent(scope: scope(main, 2), windowIDs: [WindowID(rawValue: 1)], placements: [:], zoomedWindowID: WindowID(rawValue: 1))
        let untouched = LayoutIntent(scope: scope(other, 2), windowIDs: [], placements: [:])
        var intents = [moved.scope.description: moved, untouched.scope.description: untouched]

        DesktopReorder.remap(intents: &intents, on: main, DesktopReorder.mapping(from: d(2), to: d(1)))

        #expect(intents.count == 2)
        #expect(intents[scope(main, 1).description]?.zoomedWindowID == WindowID(rawValue: 1))
        #expect(intents[scope(main, 1).description]?.scope == scope(main, 1))
        #expect(intents[scope(main, 2).description] == nil)
        #expect(intents[scope(other, 2).description] == untouched)
    }

    @Test func commandRenumbersStateAndIntentsTogether() throws {
        let store = StageStore(path: tempPath("spec066-stages"))
        let intents = LayoutIntentStore(path: tempPath("spec066-intents"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main, desktopID: d(1), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Un")]),
            PersistentStageScope(displayID: main, desktopID: d(2), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Deux")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: main, currentDesktopID: d(1))]))
        intents.save(LayoutIntent(scope: scope(main, 2), windowIDs: [], placements: [:]))
        let service = SnapshotService(provider: PowerUserProvider(windows: []), frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
                                      config: RoadieConfig(), intentStore: intents, stageStore: store)
        let commands = DesktopCommandService(service: service, store: store, events: EventLog(path: tempPath("spec066-events")))

        let result = commands.move(d(2), to: d(1), displayID: main)

        #expect(result.changed)
        let state = store.state()
        #expect(state.scopes.first { $0.desktopID == d(1) }?.stages.first?.name == "Deux")
        #expect(state.currentDesktopID(for: main) == d(2))
        #expect(intents.intent(for: scope(main, 1)) != nil)
        #expect(intents.intent(for: scope(main, 2)) == nil)
        #expect(commands.move(d(1), to: d(1), displayID: main).outcome == .noOp)
        #expect(commands.move(d(1), to: d(40), displayID: main).outcome == .failed)
    }
}
