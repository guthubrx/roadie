import AppKit
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec070CrossDisplayStateTests {
    private let a = DisplayID(rawValue: "A")
    private let b = DisplayID(rawValue: "B")
    private func d(_ raw: Int) -> DesktopID { DesktopID(rawValue: raw) }
    private func s(_ raw: String) -> StageID { StageID(rawValue: raw) }
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app", title: "w\(id)", frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }
    private func name(_ state: PersistentStageState, _ display: DisplayID, _ desktop: Int) -> String? {
        state.scopes.first { $0.displayID == display && $0.desktopID == d(desktop) }?.stages.first?.name
    }

    @Test func aDesktopBecomesADesktopOfTheOtherDisplay() throws {
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("1"), name: "A1")]),
            PersistentStageScope(displayID: a, desktopID: d(2), stages: [PersistentStage(id: s("1"), name: "A2", members: [member(9)])]),
            PersistentStageScope(displayID: a, desktopID: d(3), stages: [PersistentStage(id: s("1"), name: "A3")]),
            PersistentStageScope(displayID: b, desktopID: d(1), stages: [PersistentStage(id: s("1"), name: "B1")]),
        ], desktopSelections: [
            PersistentDesktopSelection(displayID: a, currentDesktopID: d(3), lastDesktopID: d(2)),
            PersistentDesktopSelection(displayID: b, currentDesktopID: d(1)),
        ], desktopLabels: [PersistentDesktopLabel(displayID: a, desktopID: d(2), label: "Projet")],
           windowPins: [PersistentWindowPin(windowID: WindowID(rawValue: 9), homeScope: StageScope(displayID: a, desktopID: d(2), stageID: s("1")),
                                            pinScope: .desktop, bundleID: "app", title: "w9", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10))])

        let moved = state.moveDesktop(d(2), from: a, to: b, position: d(1))
        let result = try #require(moved)

        #expect(result.windows == [WindowID(rawValue: 9)])
        #expect(name(state, b, 1) == "A2")
        #expect(name(state, b, 2) == "B1")
        #expect(name(state, a, 1) == "A1")
        #expect(name(state, a, 2) == "A3")
        #expect(state.currentDesktopID(for: b) == d(2))
        #expect(state.currentDesktopID(for: a) == d(2))
        #expect(state.lastDesktopID(for: a) == nil)
        #expect(state.label(displayID: b, desktopID: d(1)) == "Projet")
        #expect(state.windowPins[0].homeScope == StageScope(displayID: b, desktopID: d(1), stageID: s("1")))
    }

    @Test func aJustConnectedDisplayKeepsItsDisplayedDesktop() throws {
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("1"), name: "A1")]),
            PersistentStageScope(displayID: a, desktopID: d(2), stages: [PersistentStage(id: s("1"), name: "A2")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1))])

        let moved = state.moveDesktop(d(2), from: a, to: b, position: d(1))
        #expect(moved != nil)

        #expect(name(state, b, 1) == "A2")
        #expect(state.currentDesktopID(for: b) == d(2))
    }

    @Test func aStageMovesToAPlaceOnTheOtherDisplay() {
        let store = StageStore(path: tempPath("spec070-stage"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Un"), PersistentStage(id: s("2"), name: "Deux", members: [member(4)])]),
            PersistentStageScope(displayID: b, desktopID: d(3), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Trois"), PersistentStage(id: s("5"), name: "Cinq")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1)),
                               PersistentDesktopSelection(displayID: b, currentDesktopID: d(1))]))
        let provider = PowerUserProvider(windows: [])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec070-events")))

        let result = commands.moveStage(s("2"), displayID: a, from: d(1), to: d(3), before: s("5"), targetDisplay: b)

        #expect(result.changed)
        let state = store.state()
        #expect(state.scopes.first { $0.displayID == a && $0.desktopID == d(1) }?.stages.map(\.name) == ["Un"])
        let target = state.scopes.first { $0.displayID == b && $0.desktopID == d(3) }
        #expect(target?.stages.map(\.name) == ["Trois", "Deux", "Cinq"])
        #expect(target?.stages.first { $0.name == "Deux" }?.members.map(\.windowID) == [WindowID(rawValue: 4)])
        #expect(target?.activeStageID == s("1"))
    }
}

@MainActor
struct Spec070CrossDisplayDragTests {
    private func canvas() -> OverviewCanvas {
        let layout: [(UInt32, String, Int, String)] = [(1, "A", 1, "a"), (2, "A", 2, "b"), (3, "B", 1, "c"), (4, "B", 2, "d")]
        let entries = layout.map { id, display, desktop, stage in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: id), pid: 1, appName: "App", bundleID: "fixture", title: "F\(id)",
                                                       frame: Rect(x: 0, y: 0, width: 900, height: 600), isOnScreen: true, isTileCandidate: true),
                                scope: StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage)),
                                stageName: stage.uppercased())
        }
        let displays = ["A", "B"].enumerated().map { index, id in
            DisplaySnapshot(id: DisplayID(rawValue: id), index: index, name: id, frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
                            visibleFrame: Rect(x: 0, y: 0, width: 1728, height: 1080), isMain: index == 0)
        }
        let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        var config = OverviewConfig()
        config.loupe = false
        canvas.config = config
        canvas.model = OverviewModel(entries: entries, displays: displays, state: PersistentStageState())
        canvas.viewport = CGSize(width: 1600, height: 1000)
        canvas.rebuild()
        return canvas
    }

    @Test func dropsReachTheOtherDisplay() throws {
        let canvas = canvas()
        let b = DisplayID(rawValue: "B")
        let bDesktops = canvas.plan.desktops.filter { $0.desktop.id.displayID == b }
        try #require(bDesktops.count == 2)
        let source = OverviewDesktopID(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 2))
        // Au-dessus du premier bureau de B : il devient le bureau 1 de B.
        let top = CGPoint(x: bDesktops[0].frame.midX, y: bDesktops[0].frame.minY + 2)
        #expect(canvas.dropSlot(source: source, point: top)?.display == b)
        #expect(canvas.dropSlot(source: source, point: top)?.target == DesktopID(rawValue: 1))
        // Après le dernier bureau de B : numéro suivant.
        let bottom = CGPoint(x: bDesktops[1].frame.midX, y: bDesktops[1].frame.maxY - 2)
        #expect(canvas.dropSlot(source: source, point: bottom)?.target == DesktopID(rawValue: 3))

        let cardC = try #require(canvas.plan.cards.first { $0.entry.id == WindowID(rawValue: 3) })
        let stage = canvas.stageSlot(source: StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "a")),
                                     point: CGPoint(x: cardC.frame.minX - 2, y: cardC.frame.minY + 20))
        #expect(stage?.display == b && stage?.desktop == DesktopID(rawValue: 1) && stage?.before == StageID(rawValue: "c"))

        let entry = try #require(canvas.plan.cards.first { $0.entry.id == WindowID(rawValue: 1) }).entry
        #expect(canvas.windowTarget(for: entry, point: CGPoint(x: cardC.frame.midX, y: cardC.frame.midY))?.displayID == b)
    }
}
