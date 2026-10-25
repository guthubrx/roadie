import Foundation
import Testing
import AppKit
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec067StageNamesTests {
    private let a = DisplayID(rawValue: "display-main")
    private let b = DisplayID(rawValue: "display-other")
    private func d(_ raw: Int) -> DesktopID { DesktopID(rawValue: raw) }
    private func s(_ raw: String) -> StageID { StageID(rawValue: raw) }
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app", title: "w\(id)", frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }
    private func names(_ state: PersistentStageState, _ display: DisplayID, _ desktop: Int) -> [String] {
        state.scopes.first { $0.displayID == display && $0.desktopID == d(desktop) }?.stages.map(\.name) ?? []
    }

    @Test func duplicatesKeepTheOccupiedCopyAndNeverLoseWindows() {
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("2"), name: "Perso"), PersistentStage(id: s("1"), name: "Work")]),
            PersistentStageScope(displayID: a, desktopID: d(2), stages: [PersistentStage(id: s("2"), name: "Perso", members: [member(1), member(2)])]),
            PersistentStageScope(displayID: b, desktopID: d(1), stages: [PersistentStage(id: s("9"), name: "perso ", members: [member(3)]),
                                                                       PersistentStage(id: s("1"), name: "Work")]),
        ], activeDisplayID: b)

        let changed = state.makeStageNamesUnique()

        #expect(changed == 3)
        #expect(names(state, a, 2) == ["Perso"])
        #expect(names(state, b, 1) == ["Perso 2", "Work"])
        #expect(names(state, a, 1) == ["Stage 2", "Stage 1"])
        #expect(state.duplicateStageNameCount == 0)
        #expect(state.scopes.flatMap { $0.stages.flatMap(\.members) }.count == 3)
        #expect(state.makeStageNamesUnique() == 0)
    }

    @Test func aConnectedDisplayKeepsTheNameBeforeAnAbsentOne() {
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: b, desktopID: d(1), stages: [PersistentStage(id: s("3"), name: "Com", members: [member(1), member(2), member(3)])]),
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("3"), name: "Com", members: [member(4)])]),
        ])
        #expect(state.makeStageNamesUnique(liveDisplays: [a]) == 1)
        #expect(names(state, a, 1) == ["Com"])
        #expect(names(state, b, 1) == ["Com 2"])
    }

    @Test func configuredWorkspaceNamesOnlyOneStage() {
        let config = StageManagerConfig(workspaces: [StageDefinition(id: "1", displayName: "Work"), StageDefinition(id: "2", displayName: "Perso")])
        var scope = PersistentStageScope(displayID: a, desktopID: d(3), stages: [])
        scope.applyConfiguredStages(config, takenNames: [StageNameUniqueness.key("Work")])
        #expect(scope.stages.map(\.id) == [s("1"), s("2")])
        #expect(scope.stages.map(\.name) == ["Stage 1", "Perso"])
    }

    @Test func renameToANameUsedElsewhereIsRefused() {
        let store = StageStore(path: tempPath("spec067-rename"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("1"), name: "Work"), PersistentStage(id: s("2"))]),
            PersistentStageScope(displayID: b, desktopID: d(4), stages: [PersistentStage(id: s("1"), name: "Perso")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1))]))
        let service = SnapshotService(provider: PowerUserProvider(windows: []), frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
                                      config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec067-events")))

        #expect(commands.rename("2", to: " perso", displayID: a).outcome == .failed)
        #expect(commands.rename("1", to: "Work", displayID: a).changed)
        #expect(commands.rename("2", to: "Lecture", displayID: a).changed)
        #expect(names(store.state(), a, 1) == ["Work", "Lecture"])
    }

    @Test func stageMovesToAPlaceOfAnotherDesktopWithItsName() {
        let store = StageStore(path: tempPath("spec067-move"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Work"), PersistentStage(id: s("3"), name: "Com", members: [member(5)])]),
            PersistentStageScope(displayID: a, desktopID: d(2), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Un"), PersistentStage(id: s("3"), name: "Trois"), PersistentStage(id: s("4"), name: "Quatre")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1))],
           windowPins: [PersistentWindowPin(windowID: WindowID(rawValue: 5), homeScope: StageScope(displayID: a, desktopID: d(1), stageID: s("3")),
                                            pinScope: .stage, bundleID: "app", title: "w5", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10))]))
        let service = SnapshotService(provider: PowerUserProvider(windows: []), frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
                                      config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec067-move-events")))

        let result = commands.moveStage(s("3"), displayID: a, from: d(1), to: d(2), before: s("4"))

        #expect(result.changed)
        let state = store.state()
        #expect(names(state, a, 1) == ["Work"])
        // Identifiant 3 déjà pris par une stage nommée : la stage arrivante change d'identifiant, pas de nom.
        #expect(names(state, a, 2) == ["Un", "Trois", "Com", "Quatre"])
        let moved = state.scopes.first { $0.desktopID == d(2) }?.stages.first { $0.name == "Com" }
        #expect(moved?.members.map(\.windowID) == [WindowID(rawValue: 5)])
        #expect(state.windowPins.first?.homeScope == StageScope(displayID: a, desktopID: d(2), stageID: moved?.id ?? s("?")))
        #expect(state.scopes.first { $0.desktopID == d(2) }?.activeStageID == s("1"))

        // Même bureau : réordonnancement seul, puis dépôt sans effet à sa propre place.
        #expect(commands.moveStage(s("4"), displayID: a, from: d(2), to: d(2), before: s("1")).changed)
        #expect(names(store.state(), a, 2) == ["Quatre", "Un", "Trois", "Com"])
        #expect(commands.moveStage(s("4"), displayID: a, from: d(2), to: d(2), before: s("1")).outcome == .noOp)
    }
}

@MainActor
struct Spec067OverviewDragTests {
    private let display = DisplayID(rawValue: "A")
    private func scope(_ desktop: Int, _ stage: String) -> StageScope {
        StageScope(displayID: display, desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage))
    }

    private func canvas() -> (OverviewCanvas, NSWindow) {
        let layout: [(UInt32, Int, String)] = [(1, 1, "a"), (2, 1, "a"), (3, 1, "b"), (4, 2, "c")]
        let entries = layout.map { id, desktop, stage in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: id), pid: 1, appName: "App", bundleID: "fixture", title: "F\(id)",
                                                       frame: Rect(x: 0, y: 0, width: 900, height: 600), isOnScreen: true, isTileCandidate: true),
                                scope: scope(desktop, stage), stageName: stage.uppercased())
        }
        let screen = DisplaySnapshot(id: display, index: 0, name: "A", frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
                                     visibleFrame: Rect(x: 0, y: 0, width: 1728, height: 1080), isMain: true)
        let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1400, height: 1000))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1400, height: 1000), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        var config = OverviewConfig()
        config.loupe = false
        canvas.config = config
        canvas.model = OverviewModel(entries: entries, displays: [screen], state: PersistentStageState())
        canvas.viewport = CGSize(width: 1400, height: 1000)
        canvas.rebuild()
        return (canvas, window)
    }

    private func card(_ canvas: OverviewCanvas, _ id: UInt32) throws -> OverviewLayout.Card {
        try #require(canvas.plan.cards.first { $0.entry.id == WindowID(rawValue: id) })
    }

    @Test func stageGapsGiveThePlaceInTheTargetDesktop() throws {
        let (canvas, _) = canvas()
        let a1 = try card(canvas, 1), b = try card(canvas, 3), c = try card(canvas, 4)
        func left(_ card: OverviewLayout.Card) -> CGPoint { CGPoint(x: card.frame.minX - 2, y: card.frame.minY + 20) }
        func right(_ card: OverviewLayout.Card) -> CGPoint { CGPoint(x: card.frame.maxX + 2, y: card.frame.minY + 20) }
        // Espaces voisins de la stage déplacée : rien ne changerait.
        #expect(canvas.stageSlot(source: scope(1, "a"), point: left(b)) == nil)
        #expect(canvas.stageSlot(source: scope(1, "a"), point: left(a1)) == nil)
        // Après la dernière stage du même bureau.
        let end = canvas.stageSlot(source: scope(1, "a"), point: right(b))
        #expect(end?.desktop == DesktopID(rawValue: 1) && end?.before == nil)
        // Devant la première stage.
        #expect(canvas.stageSlot(source: scope(1, "b"), point: left(a1))?.before == StageID(rawValue: "a"))
        // Autre bureau du même écran.
        let other = canvas.stageSlot(source: scope(1, "a"), point: left(c))
        #expect(other?.desktop == DesktopID(rawValue: 2) && other?.before == StageID(rawValue: "c"))
    }

    @Test func windowTargetsAnotherStageOnly() throws {
        let (canvas, _) = canvas()
        let a2 = try card(canvas, 2), c = try card(canvas, 4)
        let entry = canvas.plan.cards[0].entry
        #expect(canvas.windowTarget(for: entry, point: CGPoint(x: c.frame.midX, y: c.frame.midY)) == scope(2, "c"))
        #expect(canvas.windowTarget(for: entry, point: CGPoint(x: a2.frame.midX, y: a2.frame.midY)) == nil)
        let chip = try #require(canvas.stageChipFrame(for: c))
        #expect(c.frame.contains(CGPoint(x: chip.midX, y: chip.midY)))
    }

    /// Régression 071 : la carte visée bouge dans l’aperçu ; lâcher sur le fantôme de la fenêtre, là où
    /// l’ancienne disposition était vide, doit la faire rejoindre la stage, pas créer une stage.
    @Test func droppingOnTheGhostKeepsTheTargetStage() throws {
        let (canvas, window) = canvas()
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        var drops: [OverviewDropIntent] = []
        canvas.onDrop = { drops.append($0) }
        func send(_ type: NSEvent.EventType, _ point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        let source = try card(canvas, 1), target = try card(canvas, 4)
        let start = CGPoint(x: source.frame.midX, y: source.frame.midY)
        try send(.leftMouseDown, start)
        try send(.leftMouseDragged, CGPoint(x: start.x + 30, y: start.y))
        try send(.leftMouseDragged, CGPoint(x: target.frame.midX, y: target.frame.midY))
        let ghost = try #require(canvas.displayedPlan.cards.first { $0.entry.id == WindowID(rawValue: 1) }?.frame)
        // Dans la disposition d’avant le geste, cet endroit n’est sur aucune carte.
        #expect(!canvas.plan.cards.contains { $0.frame.contains(CGPoint(x: ghost.midX, y: ghost.midY)) })
        try send(.leftMouseDragged, CGPoint(x: ghost.midX, y: ghost.midY))
        try send(.leftMouseUp, CGPoint(x: ghost.midX, y: ghost.midY))
        #expect(drops == [.window(WindowID(rawValue: 1), target: scope(2, "c"))])
    }

    @Test func nativeClickOpensAndDragMovesTheWindow() throws {
        let (canvas, window) = canvas()
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        var opened: [WindowID] = []
        var drops: [OverviewDropIntent] = []
        canvas.onOpen = { opened.append($0.id) }
        canvas.onDrop = { drops.append($0) }
        let source = try card(canvas, 1), target = try card(canvas, 4)
        func send(_ type: NSEvent.EventType, _ point: CGPoint) throws {
            let location = canvas.convert(point, to: nil)
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        let start = CGPoint(x: source.frame.midX, y: source.frame.midY)
        try send(.leftMouseDown, start)
        try send(.leftMouseUp, start)
        #expect(opened == [WindowID(rawValue: 1)])
        let end = CGPoint(x: target.frame.midX, y: target.frame.midY)
        try send(.leftMouseDown, start)
        try send(.leftMouseDragged, CGPoint(x: start.x + 30, y: start.y))
        try send(.leftMouseDragged, end)
        try send(.leftMouseUp, end)
        #expect(opened.count == 1)
        #expect(drops == [.window(WindowID(rawValue: 1), target: scope(2, "c"))])
    }
}
