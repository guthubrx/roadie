import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite
struct TargetModeRuntimeControllerTests {
    @Test
    func commandRoundTripsThroughDistributedNotificationPayload() throws {
        let command = TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "all",
            "includeAppTargets": "true",
            "duration": "10"
        ])

        let parsed = try #require(TargetModeRuntimeCommand(userInfo: command.userInfo))

        #expect(parsed.name == "targets.interactive")
        #expect(parsed.string("source") == "all")
        #expect(parsed.bool("includeAppTargets"))
        #expect(parsed.double("duration") == 10)
    }

    @Test
    func commandRejectsMissingCommandName() {
        #expect(TargetModeRuntimeCommand(userInfo: ["source": "all"]) == nil)
    }

    @Test
    func gridFocusPickerPrefersTopmostWindowContainingCellCenter() {
        let large = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 100,
            appName: "Large",
            bundleID: "large",
            title: "Large",
            frame: Rect(x: 100, y: 100, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let small = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 20),
            pid: 200,
            appName: "Small",
            bundleID: "small",
            title: "Small",
            frame: Rect(x: 140, y: 140, width: 80, height: 80),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [large, small],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 120, y: 120, width: 140, height: 140), in: snapshot)

        #expect(target?.window.id == large.window.id)
    }

    @Test
    func gridFocusPickerFallsBackToTopmostIntersectingWindowWhenCenterIsEmpty() {
        let top = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 30),
            pid: 300,
            appName: "Top",
            bundleID: "top",
            title: "Top",
            frame: Rect(x: 100, y: 100, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let bottom = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 40),
            pid: 400,
            appName: "Bottom",
            bundleID: "bottom",
            title: "Bottom",
            frame: Rect(x: 110, y: 110, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [top, bottom],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 90, y: 90, width: 130, height: 60), in: snapshot)

        #expect(target?.window.id == top.window.id)
    }

    // TEST-002 / REL-003 : la lettre validée active la cible de la liste affichée (filtrée), pas
    // celle qui porte la même lettre dans une liste reconstruite sans les options.
    @Test @MainActor
    func interactiveLetterActivatesTargetOfDisplayedFilteredList() throws {
        let service = targetModeService(name: "rel003-filtered", displays: [powerDisplay()])
        let presenter = SpyTargetModeOverlayPresenter()
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)

        controller.handle(TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "roadie",
            "filter": "firefox",
            "action": "inspect",
        ]))
        let shown = try #require(presenter.interactiveState?.report.targets.first)
        let activate = try #require(presenter.interactiveActivate)
        let unfiltered = TargetHintService(service: service).list(TargetQueryOptions(source: .all))

        #expect(unfiltered.targets.first { $0.label == shown.label }?.id != shown.id)
        #expect(activate(shown.label.lowercased()).target?.id == shown.id)
        #expect(activate("ZZZ").error == "unknown_target")
    }

    // TEST-002 / REL-004 : après une flèche vers l'écran 2, la grille affichée est celle de l'écran 2.
    @Test @MainActor
    func gridFollowsDisplaySelectedByArrows() throws {
        let service = targetModeService(name: "rel004-grid", displays: [
            powerDisplay("display-1", index: 1, x: 0),
            powerDisplay("display-2", index: 2, x: 1000),
        ])
        let presenter = SpyTargetModeOverlayPresenter()
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)

        controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: [
            "display": "1",
            "scope": "display",
        ]))
        let stateProvider = try #require(presenter.gridStateProvider)

        #expect(stateProvider(nil, "").report.targets.first?.scope.displayId == "display-1")
        #expect(stateProvider(1, "").report.targets.first?.scope.displayId == "display-1")
        #expect(stateProvider(2, "").report.targets.first?.scope.displayId == "display-2")
        #expect(stateProvider(2, "").report.targets.first?.frame?.x ?? 0 >= 1000)
    }

    // TEST-002 / REL-004 (contre-revue R1-16) : la lettre validée après une flèche vers l'écran 2 clique
    // au centre de la case affichée sur l'écran 2, puis la session se termine.
    @Test @MainActor
    func gridActivationClicksShownCellOfSelectedDisplayThenFinishes() throws {
        let service = targetModeService(name: "rel004-grid-click", displays: [
            powerDisplay("display-1", index: 1, x: 0),
            powerDisplay("display-2", index: 2, x: 1000),
        ])
        let eventPath = tempPath("rel004-grid-click-events")
        let presenter = SpyTargetModeOverlayPresenter()
        var posted: [CGEvent] = []
        // Événements souris réellement construits par `TargetGridService.perform`, interceptés avant
        // l'envoi au système.
        let controller = TargetModeRuntimeController(
            service: service,
            events: EventLog(path: eventPath),
            presenter: presenter,
            gridPostEvent: { posted.append($0) }
        )

        controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: [
            "display": "1",
            "scope": "display",
        ]))
        let stateProvider = try #require(presenter.gridStateProvider)
        let activate = try #require(presenter.gridActivate)
        let onFinish = try #require(presenter.gridFinish)
        let shown = try #require(stateProvider(2, "").report.targets.first)
        let shownFrame = try #require(shown.frame).cgRect
        let path = try #require(shown.id.split(separator: "/").last.map(String.init))

        let result = activate(2, path)
        onFinish(result)

        #expect(result.changed)
        #expect(posted.map(\.type) == [.leftMouseDown, .leftMouseUp])
        // La case affichée est arrondie au point entier (`integral`), le clic vise le centre exact :
        // écart inférieur à un point, toujours dans la case affichée.
        #expect(posted.allSatisfy { shownFrame.contains($0.location) })
        #expect(posted.allSatisfy { abs($0.location.x - shownFrame.midX) < 1 && abs($0.location.y - shownFrame.midY) < 1 })
        #expect(posted.allSatisfy { $0.location.x >= 1000 })
        let finished = EventLog(path: eventPath).tail(limit: 5).filter { $0.contains("target_mode.finished") }
        #expect(finished.count == 1)
        #expect(finished.first?.contains("grid.interactive") == true)
    }
}

@MainActor
private func targetModeService(name: String, displays: [DisplaySnapshot]) -> SnapshotService {
    let displayID = displays[0].id
    let stageID = StageID(rawValue: "1")
    let first = powerWindow(1, x: 100, app: "iTerm")
    let second = powerWindow(2, x: 500, app: "Firefox")
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: [
        PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
            PersistentStage(id: stageID, members: [
                PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
            ]),
        ]),
    ], activeDisplayID: displayID))
    let provider = PowerUserProvider(displays: displays, windows: [first, second])
    let config = RoadieConfig(experimental: ExperimentalConfig(
        targetMode: TargetModeConfig(overlayEnabled: true),
        targetGrid: TargetGridConfig(enabled: true)
    ))
    return SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: config, stageStore: store)
}

/// Présentation espionne : conserve la liste affichée et les fermetures, sans overlay réel.
@MainActor
private final class SpyTargetModeOverlayPresenter: TargetModeOverlayPresenting {
    var interactiveState: TargetOverlayState?
    var interactiveActivate: (@MainActor (String) -> TargetActionResult)?
    var gridStateProvider: (@MainActor (Int?, String) -> TargetOverlayState)?
    var gridActivate: (@MainActor (Int?, String) -> TargetActionResult)?
    var gridFinish: (@MainActor (TargetActionResult) -> Void)?

    func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        interactiveState = state
        interactiveActivate = activate
        return nil
    }

    func startGridInteractive(
        initialPath: String,
        duration: TimeInterval,
        config: TargetGridConfig,
        displayIndex: Int?,
        stateProvider: @escaping @MainActor (Int?, String) -> TargetOverlayState,
        activate: @escaping @MainActor (Int?, String) -> TargetActionResult,
        focusAt: @escaping @MainActor (CGRect) -> Void,
        displayNeighbor: @escaping @MainActor (Int?, TargetGridArrowDirection) -> Int?,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        gridStateProvider = stateProvider
        gridActivate = activate
        gridFinish = onFinish
        return nil
    }

    func startSearch(
        targets: [RoadieTarget],
        alphabet: String,
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        nil
    }
}
