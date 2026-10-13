import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages

/// Session 022, lot G : constats REL-016, MIN-004, REL-017, REL-020, REL-026, REL-027.
@Suite
struct Audit022LotGTests {
    private func display(_ id: String, x: Double, width: Double = 1000, isMain: Bool = false, index: Int = 1) -> DisplaySnapshot {
        let frame = Rect(x: x, y: 0, width: width, height: 800)
        return DisplaySnapshot(id: DisplayID(rawValue: id), index: index, name: id, frame: frame, visibleFrame: frame, isMain: isMain)
    }

    private func member(_ window: WindowSnapshot) -> PersistentStageMember {
        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
    }

    // MARK: REL-020

    /// Un écran à gauche du principal contient des fenêtres visibles malgré maxX < -1000.
    @Test
    func leftDisplayWindowIsNotLegacyOffscreen() {
        let main = display("main", x: 0, isMain: true)
        let left = display("left", x: -3840, width: 3840, index: 2)
        let frame = CGRect(x: -3000, y: 100, width: 1000, height: 300)

        #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(frame, in: [left, main]))
    }

    /// L'ancienne position de masquage hors de tout écran reste détectée.
    @Test
    func legacyOffscreenFrameIsStillHidden() {
        let main = display("main", x: 0, isMain: true)
        let left = display("left", x: -3840, width: 3840, index: 2)

        #expect(HiddenWindowPlacement.isHiddenOrLegacyOffscreen(CGRect(x: -20000, y: 100, width: 300, height: 300), in: [left, main]))
        #expect(HiddenWindowPlacement.isHiddenOrLegacyOffscreen(CGRect(x: -5000, y: 100, width: 300, height: 300), in: [left, main]))
        // Position de parking actuelle : toujours masquée.
        #expect(HiddenWindowPlacement.isHiddenOrLegacyOffscreen(CGRect(x: 999, y: 100, width: 300, height: 300), in: [main]))
    }

    // MARK: REL-016 / MIN-004

    private func desktopFixture(windowDesktop: Int, currentDesktop: Int = 1, targetMode: WindowManagementMode = .bsp) -> (SnapshotService, StageStore, PowerUserWriter, WindowSnapshot, DisplayID) {
        let displaySnapshot = powerDisplay("display-main")
        let window = powerWindow(1, x: windowDesktop == currentDesktop ? 100 : 999)
        let provider = PowerUserProvider(displays: [displaySnapshot], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("lot-g-desktop"))
        let scope1 = windowDesktop == 1
            ? PersistentStageScope(displayID: displaySnapshot.id, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: window.id, members: [member(window)]),
            ])
            : PersistentStageScope(displayID: displaySnapshot.id, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: targetMode),
            ])
        let scope2 = windowDesktop == 2
            ? PersistentStageScope(displayID: displaySnapshot.id, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: window.id, members: [member(window)]),
            ])
            : PersistentStageScope(displayID: displaySnapshot.id, desktopID: DesktopID(rawValue: 2))
        store.save(PersistentStageState(
            scopes: [scope1, scope2],
            desktopSelections: [PersistentDesktopSelection(displayID: displaySnapshot.id, currentDesktopID: DesktopID(rawValue: currentDesktop))],
            activeDisplayID: displaySnapshot.id
        ))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        return (service, store, writer, window, displaySnapshot.id)
    }

    /// Envoyer la fenêtre active vers son bureau actuel ne la masque pas et ne change rien.
    @Test
    func assignActiveWindowToCurrentDesktopDoesNothing() {
        let (service, store, writer, window, display) = desktopFixture(windowDesktop: 1)

        let result = DesktopCommandService(service: service, store: store).assignActiveWindow(to: DesktopID(rawValue: 1))

        #expect(!result.changed)
        #expect(result.message.contains("already on target desktop"))
        #expect(writer.frames.isEmpty)
        #expect(store.state().stageScope(for: window.id)?.desktopID == DesktopID(rawValue: 1))
        #expect(store.state().scopes.flatMap { $0.stages.flatMap { $0.members.map(\.windowID) } } == [window.id])
        #expect(store.state().stageScope(for: window.id)?.displayID == display)
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// Déplacer vers un autre bureau masque toujours la fenêtre (comportement conservé après extraction).
    @Test
    func assignActiveWindowToOtherDesktopStillHidesWindow() {
        let (service, store, writer, window, _) = desktopFixture(windowDesktop: 1)

        let result = DesktopCommandService(service: service, store: store).assignActiveWindow(to: DesktopID(rawValue: 2))

        #expect(result.changed)
        #expect(result.message.contains("hidden=true"))
        #expect(writer.frames[window.id].map { $0.x >= 999 } == true)
        #expect(store.state().stageScope(for: window.id)?.desktopID == DesktopID(rawValue: 2))
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// Une fenêtre d'un bureau masqué envoyée vers le bureau affiché n'est pas masquée.
    @Test
    func assignWindowToDisplayedDesktopDoesNotHideIt() {
        let (service, store, writer, window, display) = desktopFixture(windowDesktop: 2, currentDesktop: 1)

        let result = DesktopCommandService(service: service, store: store)
            .assign(windowID: window.id, to: DesktopID(rawValue: 1), displayID: display)

        #expect(result.message.contains("hidden=false"))
        #expect(store.state().stageScope(for: window.id)?.desktopID == DesktopID(rawValue: 1))
        // Inconditionnel (R1-09) : une fenêtre garée reçoit toujours un cadre visible.
        let frame = writer.frames[window.id]
        #expect(frame != nil)
        #expect(frame.map { !HiddenWindowPlacement.isHidden($0.cgRect, in: [powerDisplay("display-main")]) } == true)
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// R1-09 : stage cible en mode `float` (aucune disposition ne donne de cadre) : la fenêtre garée
    /// est replacée explicitement dans la zone visible de l'écran.
    @Test
    func assignParkedWindowToDisplayedFloatDesktopRestoresVisibleFrame() throws {
        let (service, store, writer, window, display) = desktopFixture(windowDesktop: 2, currentDesktop: 1, targetMode: .float)
        let displays = [powerDisplay("display-main")]

        let result = DesktopCommandService(service: service, store: store)
            .assign(windowID: window.id, to: DesktopID(rawValue: 1), displayID: display)

        #expect(result.message.contains("hidden=false"))
        #expect(result.changed)
        let frame = try #require(writer.frames[window.id])
        #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(frame.cgRect, in: displays))
        #expect(displays[0].visibleFrame.cgRect.contains(frame.cgRect))
        #expect(frame.width == window.frame.width && frame.height == window.frame.height)
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// Décision pure : cadre mémorisé visible conservé, sinon taille courante centrée, nil si non garée.
    @Test
    func visibleRestoreFrameDecision() {
        let main = powerDisplay("display-main")
        let parked = CGRect(x: 999, y: 100, width: 300, height: 300)

        #expect(DesktopCommandService.visibleRestoreFrame(current: CGRect(x: 100, y: 100, width: 300, height: 300), remembered: nil, on: main, among: [main]) == nil)
        let remembered = CGRect(x: 200, y: 150, width: 400, height: 300)
        #expect(DesktopCommandService.visibleRestoreFrame(current: parked, remembered: remembered, on: main, among: [main]) == remembered)
        let centered = DesktopCommandService.visibleRestoreFrame(current: parked, remembered: parked, on: main, among: [main])
        #expect(centered == CGRect(x: 350, y: 250, width: 300, height: 300))
        let huge = DesktopCommandService.visibleRestoreFrame(current: CGRect(x: 999, y: 0, width: 5000, height: 5000), remembered: nil, on: main, among: [main])
        #expect(huge == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    // MARK: REL-017

    private func parkedStage(_ id: String, name: String, desktop: Int, window: UInt32, origin originID: DisplayID, host hostID: DisplayID) -> PersistentStage {
        PersistentStage(
            id: StageID(rawValue: id),
            name: name,
            parkingState: .parked,
            origin: StageOrigin(
                logicalDisplayID: LogicalDisplayID(displayID: originID),
                displayID: originID,
                desktopID: DesktopID(rawValue: desktop),
                stageID: StageID(rawValue: name.lowercased()),
                position: 1,
                nameAtParking: name,
                parkedAt: Date(timeIntervalSince1970: 100)
            ),
            hostDisplayID: hostID,
            members: [member(powerWindow(window, x: 0))]
        )
    }

    /// Deux stages garés du même écran mais de bureaux différents reviennent chacun dans leur bureau.
    @Test
    func reconnectRestoresStagesIntoTheirOwnDesktops() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external")
        let logicalID = LogicalDisplayID(displayID: externalID)
        let fingerprint = DisplayFingerprint(
            nameKey: "external", sizeKey: "1000x800", visibleSizeKey: "1000x800", positionKey: "1000:0",
            mainHint: false, previousDisplayID: externalID
        )
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host"),
                    parkedStage("parked-external-docs", name: "Docs", desktop: 1, window: 10, origin: externalID, host: hostID),
                    parkedStage("parked-external-mail", name: "Mail", desktop: 2, window: 11, origin: externalID, host: hostID),
                ]),
                PersistentStageScope(displayID: externalID, logicalDisplayID: logicalID, lastKnownDisplayFingerprint: fingerprint),
            ],
            activeDisplayID: hostID
        )

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [powerDisplay("built-in", index: 1, x: 0), powerDisplay("external", index: 2, x: 1000)],
            windows: [],
            now: Date(timeIntervalSince1970: 200)
        )

        func restored(_ desktop: Int) -> [String] {
            state.scopes
                .first { $0.displayID == externalID && $0.desktopID == DesktopID(rawValue: desktop) }?
                .stages.filter { $0.parkingState == .restored }.map(\.name) ?? []
        }
        #expect(report.kind == .restore)
        #expect(report.restoredStageCount == 2)
        #expect(restored(1) == ["Docs"])
        #expect(restored(2) == ["Mail"])
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.contains { $0.parkingState == .parked } == false)
    }

    // MARK: REL-026 / REL-027

    private func widthFixture(focus: UInt32) -> (SnapshotService, PowerUserWriter, StageStore) {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let w1 = powerWindow(1, x: 0, width: 300)
        let w2 = powerWindow(2, x: 400, width: 600)
        let w3 = powerWindow(3, x: 1000, width: 300)
        let w4 = powerWindow(4, x: 1400, width: 500)
        let provider = PowerUserProvider(displays: [main, side], windows: [w1, w2, w3, w4])
        provider.focusedID = WindowID(rawValue: focus)
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("lot-g-width"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [member(w1), member(w2)]),
                ]),
                PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [member(w3), member(w4)]),
                ]),
            ],
            // Le daemon a déjà fait suivre l'écran actif au focus (sinon le snapshot ignore ce focus).
            activeDisplayID: focus >= 3 ? side.id : main.id
        ))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        return (service, writer, store)
    }

    /// Focus sur le second écran : seule la fenêtre focalisée de cet écran change.
    @Test
    func widthTargetsFocusedWindowOnSecondDisplay() {
        let (service, writer, store) = widthFixture(focus: 4)

        let result = WidthAdjustmentService(service: service, config: RoadieConfig(), events: EventLog(path: tempPath("lot-g-width-events")))
            .apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .explicitRatio, targetRatio: 0.4))

        #expect(result.changed)
        #expect(writer.frames[WindowID(rawValue: 4)]?.width == 400)
        #expect(Set(writer.frames.keys) == [WindowID(rawValue: 4)])
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// `--all` agit sur toutes les fenêtres de l'écran de la fenêtre focalisée, pas du premier écran.
    @Test
    func widthAllWindowsUsesFocusedDisplay() {
        let (service, writer, store) = widthFixture(focus: 3)

        _ = WidthAdjustmentService(service: service, config: RoadieConfig(), events: EventLog(path: tempPath("lot-g-width-all-events")))
            .apply(WidthAdjustmentIntent(scope: .allWindows, mode: .explicitRatio, targetRatio: 0.5))

        #expect(Set(writer.frames.keys) == [WindowID(rawValue: 3), WindowID(rawValue: 4)])
        #expect(writer.frames[WindowID(rawValue: 3)]?.width == 500)
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// Le réglage relatif part de la largeur de la fenêtre active (600), pas de la première entrée (300).
    @Test
    func relativeWidthStartsFromFocusedWindow() {
        let (service, writer, store) = widthFixture(focus: 2)

        _ = WidthAdjustmentService(service: service, config: RoadieConfig(), events: EventLog(path: tempPath("lot-g-width-nudge-events")))
            .apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .nudge, delta: 0.05))

        #expect(writer.frames[WindowID(rawValue: 2)]?.width == 650)
        try? FileManager.default.removeItem(at: store.fileURL)
    }

    /// Le preset suivant se calcule depuis la largeur active : 600/1000 = 0.6, premier preset au-delà.
    @Test
    func presetNextStartsFromFocusedWindow() {
        let config = RoadieConfig()
        let (service, writer, store) = widthFixture(focus: 2)
        let expected = config.widthAdjustment.presets.first(where: { $0 > 0.61 }) ?? config.widthAdjustment.presets.last ?? 0.6

        let result = WidthAdjustmentService(service: service, config: config, events: EventLog(path: tempPath("lot-g-width-preset-events")))
            .apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .presetNext))

        #expect(result.ratio == min(max(expected, config.widthAdjustment.minimumRatio), config.widthAdjustment.maximumRatio))
        try? FileManager.default.removeItem(at: store.fileURL)
    }
}
