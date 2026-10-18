import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// SPEC-047 : une fenêtre flotte dans sa stage (épinglage de portée `stage`).
@Suite(.serialized)
struct Spec047FloatingWindowTests {
    private let main = powerDisplay("display-main", index: 1, x: 0)

    private func fixture(
        _ name: String,
        windows: [WindowSnapshot],
        focused: WindowID?
    ) -> (service: SnapshotService, store: StageStore, actions: WindowContextActions, events: String) {
        let provider = PowerUserProvider(displays: [main], windows: windows)
        provider.focusedID = focused
        let store = StageStore(path: tempPath("spec047-\(name)"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: windows.map(member)),
                PersistentStage(id: StageID(rawValue: "2"))
            ])
        ], activeDisplayID: main.id))
        let eventPath = tempPath("spec047-\(name)-events")
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let actions = WindowContextActions(snapshotService: service, stageStore: store, eventLog: EventLog(path: eventPath))
        return (service, store, actions, eventPath)
    }

    private func member(_ window: WindowSnapshot) -> PersistentStageMember {
        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
    }

    private func scope(_ stage: String) -> StageScope {
        StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: stage))
    }

    @Test
    func stagePinIsVisibleOnlyInItsHomeStage() {
        let pin = PersistentWindowPin(
            windowID: WindowID(rawValue: 1),
            homeScope: scope("1"),
            pinScope: .stage,
            bundleID: "app",
            title: "t",
            lastFrame: Rect(x: 0, y: 0, width: 10, height: 10)
        )
        #expect(pin.visibility(in: scope("1")).shouldBeVisible)
        let other = pin.visibility(in: scope("2"))
        #expect(!other.shouldBeVisible)
        #expect(other.reason == .outOfScope)
    }

    /// Fenêtre flottante de la stage 1 avec un cadre donné ; la stage active est `active`.
    private func maintainerFixture(
        _ name: String,
        floatingFrame: Rect,
        lastFrame: Rect,
        neighbour: WindowSnapshot? = nil,
        active: String
    ) -> (maintainer: LayoutMaintainer, writer: PowerUserWriter, floating: WindowSnapshot) {
        let floating = WindowSnapshot(
            id: WindowID(rawValue: 10), pid: 10, appName: "Float", bundleID: "app.float", title: "Float",
            frame: floatingFrame, isOnScreen: true, isTileCandidate: true
        )
        let members = [floating, neighbour].compactMap { $0 }.map(member)
        let store = StageStore(path: tempPath("spec047-maintainer-\(name)"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: active), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: members),
                    PersistentStage(id: StageID(rawValue: "2"))
                ])
            ],
            windowPins: [
                PersistentWindowPin(
                    windowID: floating.id, homeScope: scope("1"), pinScope: .stage,
                    bundleID: floating.bundleID, title: floating.title, lastFrame: lastFrame
                )
            ],
            activeDisplayID: main.id
        ))
        let windows = [floating, neighbour].compactMap { $0 }
        let provider = PowerUserProvider(displays: [main], windows: windows)
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        return (LayoutMaintainer(service: service), writer, floating)
    }

    private var parkedFrame: Rect {
        Rect(
            x: main.visibleFrame.x - 299,
            y: main.visibleFrame.y + main.visibleFrame.height - 1,
            width: 300,
            height: 240
        )
    }

    @Test
    func floatingWindowIsHiddenWhenAnotherStageIsActive() {
        let visible = Rect(x: 150, y: 120, width: 300, height: 240)
        let f = maintainerFixture("hide", floatingFrame: visible, lastFrame: visible, active: "2")

        _ = f.maintainer.tick()

        let written = f.writer.frames[f.floating.id]
        #expect(written != nil)
        #expect(written.map { HiddenWindowPlacement.isHidden($0.cgRect, in: [main]) } == true)
    }

    @Test
    func floatingWindowReturnsToItsLastFrameInItsStage() {
        let visible = Rect(x: 150, y: 120, width: 300, height: 240)
        let f = maintainerFixture("restore", floatingFrame: parkedFrame, lastFrame: visible, active: "1")

        _ = f.maintainer.tick()

        #expect(f.writer.frames[f.floating.id] == visible)
    }

    @Test
    func floatingWindowIsNotPlacedByTheTilerWhileItsNeighbourIs() {
        let visible = Rect(x: 150, y: 120, width: 300, height: 240)
        let neighbour = powerWindow(11, x: 900)
        let f = maintainerFixture("tiler", floatingFrame: visible, lastFrame: visible, neighbour: neighbour, active: "1")

        _ = f.maintainer.tick()

        #expect(f.writer.frames[f.floating.id] == nil)
        #expect(f.writer.frames[neighbour.id] != nil)
    }

    @Test
    func floatingStateSurvivesReloadingTheStateFile() {
        let path = tempPath("spec047-reload")
        let pin = PersistentWindowPin(
            windowID: WindowID(rawValue: 7), homeScope: scope("1"), pinScope: .stage,
            bundleID: "app", title: "t", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10)
        )
        StageStore(path: path).save(PersistentStageState(windowPins: [pin], activeDisplayID: main.id))

        let reloaded = StageStore(path: path)
        #expect(reloaded.loadFailure == nil)
        #expect(reloaded.state().pin(for: pin.windowID)?.pinScope == .stage)
    }

    /// Une version antérieure (portées `desktop` et `all_desktops` seulement) lit encore le fichier :
    /// la fenêtre flottante y devient un pin de desktop, sans rejet de tout `stages.json`.
    @Test
    func earlierVersionReadsFloatingWindowAsDesktopPin() throws {
        struct LegacyPin: Decodable {
            enum Scope: String, Decodable { case desktop, allDesktops = "all_desktops" }
            let windowID: WindowID
            let pinScope: Scope
        }
        let pin = PersistentWindowPin(
            windowID: WindowID(rawValue: 7), homeScope: scope("1"), pinScope: .stage,
            bundleID: "app", title: "t", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10)
        )
        let data = try JSONEncoder().encode(pin)
        #expect(try JSONDecoder().decode(LegacyPin.self, from: data).pinScope == .desktop)
    }

    @Test
    func stagePinScopeRoundTripsAsStage() throws {
        let pin = PersistentWindowPin(
            windowID: WindowID(rawValue: 7),
            homeScope: scope("1"),
            pinScope: .stage,
            bundleID: "app",
            title: "t",
            lastFrame: Rect(x: 0, y: 0, width: 10, height: 10)
        )
        let data = try JSONEncoder().encode(pin)
        #expect(String(decoding: data, as: UTF8.self).contains("\"floatingInStage\":true"))
        #expect(try JSONDecoder().decode(PersistentWindowPin.self, from: data) == pin)
        var desktop = pin
        desktop.pinScope = .desktop
        let desktopData = try JSONEncoder().encode(desktop)
        #expect(!String(decoding: desktopData, as: UTF8.self).contains("floatingInStage"))
        #expect(try JSONDecoder().decode(PersistentWindowPin.self, from: desktopData) == desktop)
    }

    @Test
    func toggleFloatsTiledWindowThenReturnsItToTiling() {
        let floating = powerWindow(1, x: 100)
        let neighbour = powerWindow(2, x: 600)
        let f = fixture("toggle", windows: [floating, neighbour], focused: floating.id)
        let before = f.service.snapshot()
        #expect(before.state.stage(scope: scope("1"))?.windowIDs.contains(floating.id) == true)

        let first = f.actions.toggleFloating(windowID: nil)
        #expect(first.changed)
        #expect(f.store.state().pin(for: floating.id)?.pinScope == .stage)
        #expect(f.store.state().pin(for: floating.id)?.homeScope.stageID == StageID(rawValue: "1"))
        let afterFloat = f.service.snapshot()
        #expect(afterFloat.state.stage(scope: scope("1"))?.windowIDs.contains(floating.id) == false)
        #expect(afterFloat.state.stage(scope: scope("1"))?.windowIDs.contains(neighbour.id) == true)
        let entry = afterFloat.windows.first { $0.window.id == floating.id }
        #expect(entry.map { LayoutMaintainer.ruleFloatingState(of: $0, in: afterFloat.state) } == true)

        let second = f.actions.toggleFloating(windowID: nil)
        #expect(second.changed)
        #expect(f.store.state().pin(for: floating.id) == nil)
        let afterTile = f.service.snapshot()
        #expect(afterTile.state.stage(scope: scope("1"))?.windowIDs.contains(floating.id) == true)
        #expect(f.store.state().stageScope(for: floating.id)?.stageID == StageID(rawValue: "1"))
        let events = (try? String(contentsOfFile: f.events, encoding: .utf8)) ?? ""
        #expect(events.contains("window.pin_added"))
    }

    @Test
    func toggleRemovesExistingDesktopPin() {
        let window = powerWindow(1, x: 100)
        let f = fixture("desktop-pin", windows: [window], focused: window.id)
        _ = f.service.snapshot()
        _ = f.actions.execute(WindowContextAction(windowID: window.id, kind: .pinDesktop, targetID: "pin", sourceScope: nil))
        #expect(f.store.state().pin(for: window.id)?.pinScope == .desktop)

        let result = f.actions.toggleFloating(windowID: nil)
        #expect(result.changed)
        #expect(f.store.state().pin(for: window.id) == nil)
    }

    @Test
    func toggleWithoutManagedWindowChangesNothing() {
        let f = fixture("no-window", windows: [], focused: nil)
        _ = f.service.snapshot()
        let before = f.store.state()

        let result = f.actions.toggleFloating(windowID: nil)
        #expect(!result.changed)
        #expect(result.outcome == .noOp)
        #expect(f.store.state().windowPins == before.windowPins)
    }

    @Test
    func menuActionFloatsSelectedWindowInItsStage() {
        let window = powerWindow(1, x: 100)
        let other = powerWindow(2, x: 600)
        let f = fixture("menu", windows: [window, other], focused: other.id)
        _ = f.service.snapshot()

        let result = f.actions.execute(WindowContextAction(
            windowID: window.id,
            kind: .floatStage,
            targetID: WindowContextActionKind.floatStage.rawValue,
            sourceScope: nil
        ))
        #expect(result.changed)
        #expect(f.store.state().pin(for: window.id)?.pinScope == .stage)
        #expect(f.store.state().pin(for: other.id) == nil)
    }
}
