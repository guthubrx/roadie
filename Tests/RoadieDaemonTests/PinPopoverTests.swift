import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct PinPopoverTests {
    @Test
    func placementWorksForPinnedAndUnpinnedManagedWindows() {
        let window = powerWindow(10, x: 100)
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let pin = PersistentWindowPin(
            windowID: window.id,
            homeScope: scope,
            pinScope: .desktop,
            bundleID: window.bundleID,
            title: window.title,
            lastFrame: window.frame
        )
        let settings = PinPopoverSettings(enabled: true, buttonSize: 14, titlebarHeight: 36, leadingExclusion: 84)

        let eligible = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope, pin: pin),
            activeScope: scope,
            settings: settings
        )
        let disabled = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope, pin: pin),
            activeScope: scope,
            settings: PinPopoverSettings(enabled: false)
        )
        let unpinnedVisible = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope),
            activeScope: scope,
            settings: settings
        )
        let unpinnedHiddenByConfig = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope),
            activeScope: scope,
            settings: PinPopoverSettings(enabled: true, showOnUnpinned: false)
        )

        #expect(eligible.reason == .eligible)
        #expect(eligible.buttonFrame?.width == 14)
        #expect(disabled.reason == .disabled)
        #expect(unpinnedVisible.reason == .eligible)
        #expect(unpinnedVisible.buttonFrame?.width == 14)
        #expect(unpinnedHiddenByConfig.reason == .notPinned)
    }

    @Test
    func placementIgnoresUnmanagedOrTransientWindows() {
        let transient = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "Panel",
            bundleID: "panel",
            title: "Panel",
            frame: Rect(x: 10, y: 10, width: 300, height: 200),
            isOnScreen: true,
            isTileCandidate: false
        )

        let unmanaged = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: powerWindow(11, x: 100), scope: nil),
            activeScope: nil,
            settings: PinPopoverSettings(enabled: true)
        )
        let nonTileable = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: transient, scope: nil),
            activeScope: nil,
            settings: PinPopoverSettings(enabled: true)
        )

        #expect(unmanaged.reason == .notManaged)
        #expect(unmanaged.buttonFrame == nil)
        #expect(nonTileable.reason == .notManaged)
        #expect(nonTileable.buttonFrame == nil)
    }

    @Test
    func collapsedPlacementUsesProxyFrameInsteadOfButton() {
        let window = powerWindow(10, x: 100)
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let pin = PersistentWindowPin(
            windowID: window.id,
            homeScope: scope,
            pinScope: .desktop,
            bundleID: window.bundleID,
            title: window.title,
            lastFrame: window.frame
        )
        let presentation = PinPresentationState(
            windowID: window.id,
            presentation: .collapsed,
            restoreFrame: window.frame,
            proxyFrame: Rect(x: 100, y: 0, width: 180, height: 28)
        )

        let placement = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope, pin: pin, pinPresentation: presentation),
            activeScope: scope,
            settings: PinPopoverSettings(enabled: true)
        )

        #expect(placement.reason == .collapsed)
        #expect(placement.buttonFrame == nil)
        #expect(placement.proxyFrame == CGRect(x: 100, y: 0, width: 180, height: 28))
    }

    @Test
    func placementOmitsPinnedWindowWhenTitlebarHasNoSafeSlot() {
        let window = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "Tiny",
            bundleID: "tiny",
            title: "Tiny",
            frame: Rect(x: 10, y: 10, width: 80, height: 40),
            isOnScreen: true,
            isTileCandidate: true
        )
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let pin = PersistentWindowPin(
            windowID: window.id,
            homeScope: scope,
            pinScope: .desktop,
            bundleID: window.bundleID,
            title: window.title,
            lastFrame: window.frame
        )

        let placement = PinPopoverController.placement(
            for: ScopedWindowSnapshot(window: window, scope: scope, pin: pin),
            activeScope: scope,
            settings: PinPopoverSettings(enabled: true, buttonSize: 18, leadingExclusion: 84, trailingExclusion: 16)
        )

        #expect(placement.reason == .notVisible)
        #expect(placement.buttonFrame == nil)
    }

    @Test
    func menuModelIncludesPinCollapseAndDestinations() {
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let pin = PersistentWindowPin(
            windowID: WindowID(rawValue: 10),
            homeScope: scope,
            pinScope: .desktop,
            bundleID: "app",
            title: "Doc",
            lastFrame: Rect(x: 0, y: 0, width: 200, height: 100)
        )

        let model = PinPopoverController.menuModel(
            windowID: WindowID(rawValue: 10),
            pin: pin,
            presentation: nil,
            destinations: [
                WindowDestination(kind: .stage, id: "2", label: "Stage 2", isCurrent: false),
                WindowDestination(kind: .desktop, id: "2", label: "Desktop 2", isCurrent: false)
            ],
            settings: PinPopoverSettings(enabled: true, collapseEnabled: true)
        )

        #expect(model.sections.map(\.title).contains("Fenêtre"))
        #expect(model.sections.flatMap(\.items).contains { $0.title == "Replier la fenêtre" })
        #expect(model.sections.first(where: { $0.title == "Envoyer vers stage" })?.items.first?.title == "Stage 2")
        #expect(model.sections.first(where: { $0.title == "Envoyer vers desktop" })?.items.first?.title == "Desktop 2")
    }

    @Test
    func windowActionBuiltByPinPopoverExecutesThroughWindowContextActions() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let window = powerWindow(10, x: 100)
        let store = StageStore(path: tempPath("pin-popover-window-action"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"))
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()

        let action = PinPopoverController.contextAction(
            for: .window(.stage, "2"),
            windowID: window.id,
            sourceScope: nil
        )
        let result = action.map {
            WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true }).execute($0)
        }

        var state = store.state()

        #expect(action == WindowContextAction(windowID: window.id, kind: .stage, targetID: "2", sourceScope: nil))
        #expect(result?.changed == true)
        #expect(state.scope(displayID: display.id).memberIDs(in: StageID(rawValue: "2")) == [window.id])
    }

    @Test
    func menuModelShowsRestoreForCollapsedPins() {
        let windowID = WindowID(rawValue: 10)
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let pin = PersistentWindowPin(
            windowID: windowID,
            homeScope: scope,
            pinScope: .desktop,
            bundleID: "app",
            title: "Doc",
            lastFrame: Rect(x: 0, y: 0, width: 200, height: 100)
        )
        let presentation = PinPresentationState(windowID: windowID, presentation: .collapsed)

        let model = PinPopoverController.menuModel(
            windowID: windowID,
            pin: pin,
            presentation: presentation,
            destinations: [],
            settings: PinPopoverSettings(enabled: true, collapseEnabled: true)
        )

        #expect(model.sections.flatMap(\.items).contains { $0.title == "Déplier la fenêtre" })
        #expect(model.sections.flatMap(\.items).contains { $0.title == "Retirer le pin" })
    }

    @Test
    func menuModelReflectsDesktopAndAllDesktopPinScopes() {
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let desktopPin = PersistentWindowPin(
            windowID: WindowID(rawValue: 10),
            homeScope: scope,
            pinScope: .desktop,
            bundleID: "app",
            title: "Doc",
            lastFrame: Rect(x: 0, y: 0, width: 200, height: 100)
        )
        var allDesktopPin = desktopPin
        allDesktopPin.pinScope = .allDesktops

        let desktopModel = PinPopoverController.menuModel(
            windowID: desktopPin.windowID,
            pin: desktopPin,
            presentation: nil,
            destinations: [],
            settings: PinPopoverSettings(enabled: true)
        )
        let allDesktopModel = PinPopoverController.menuModel(
            windowID: allDesktopPin.windowID,
            pin: allDesktopPin,
            presentation: nil,
            destinations: [],
            settings: PinPopoverSettings(enabled: true)
        )

        #expect(desktopModel.sections.flatMap(\.items).contains { $0.title == "Pin actuel : ce desktop" })
        #expect(desktopModel.sections.flatMap(\.items).contains { $0.title == "Pin sur tous les desktops" })
        #expect(allDesktopModel.sections.flatMap(\.items).contains { $0.title == "Pin actuel : tous les desktops" })
        #expect(allDesktopModel.sections.flatMap(\.items).contains { $0.title == "Pin sur ce desktop" })
    }

    @Test
    func collapsedPresentationStoresRestoreFrameAndProxyWithoutResizingAppFrame() {
        let window = powerWindow(10, x: 100)

        let presentation = PinPopoverController.collapsedPresentation(
            for: window,
            settings: PinPopoverSettings(enabled: true, proxyHeight: 28, proxyMinWidth: 160)
        )

        #expect(presentation.presentation == .collapsed)
        #expect(presentation.restoreFrame == window.frame)
        #expect(presentation.proxyFrame?.height == 28)
        #expect(presentation.proxyFrame?.width == 300)
        #expect(window.frame.width == 300)
    }

    @Test
    func proxyTitleUsesWindowTitleAndFallsBackToAppName() {
        let titled = powerWindow(10, x: 100, app: "App")
        let untitled = WindowSnapshot(
            id: WindowID(rawValue: 11),
            pid: 11,
            appName: "FallbackApp",
            bundleID: "fallback",
            title: " ",
            frame: Rect(x: 0, y: 0, width: 300, height: 200),
            isOnScreen: true,
            isTileCandidate: true
        )

        #expect(PinPopoverController.proxyTitle(for: titled) == "Window 10")
        #expect(PinPopoverController.proxyTitle(for: untitled) == "FallbackApp")
    }

    @Test
    func nonPinnedWindowHasNoPresentationAndNoMenuCollapseAction() {
        let model = PinPopoverController.menuModel(
            windowID: WindowID(rawValue: 10),
            pin: nil,
            presentation: nil,
            destinations: [],
            settings: PinPopoverSettings(enabled: true, collapseEnabled: true)
        )

        #expect(model.sections.flatMap(\.items).contains { $0.title == "Replier la fenêtre" } == false)
        #expect(model.sections.flatMap(\.items).contains { $0.title == "Pin sur ce desktop" })
    }

    @Test
    func menuSectionsKeepStableOrderForFuturePinModes() {
        let model = PinPopoverController.menuModel(
            windowID: WindowID(rawValue: 10),
            pin: nil,
            presentation: nil,
            destinations: [
                WindowDestination(kind: .stage, id: "2", label: "Stage 2", isCurrent: false),
                WindowDestination(kind: .desktop, id: "2", label: "Desktop 2", isCurrent: false),
                WindowDestination(kind: .display, id: "display-2", label: "Ecran 2", isCurrent: false)
            ],
            settings: PinPopoverSettings(enabled: true)
        )

        #expect(model.sections.map(\.title) == [
            "Fenêtre",
            "Envoyer vers stage",
            "Envoyer vers desktop",
            "Envoyer vers écran"
        ])
    }
}
