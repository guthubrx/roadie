import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// Lot H de l'audit v14 (session 022) : aperçu de dépôt, rail, menu de titre, focus souris.
@Suite
struct Audit022LotHTests {
    // MARK: - PERF-003 : géométrie de groupe en une passe

    /// Ancienne version récursive (copie de suffixe et fusion à chaque niveau), gardée comme référence.
    private static func recursivePlanGroup(_ ids: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = ids.first else { return [:] }
        guard ids.count > 1 else { return [first: rect.integral] }
        let parts = DropGroupGeometry.split(rect, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: ids.count - 1)
        var placements = [first: parts.first.integral]
        placements.merge(recursivePlanGroup(Array(ids.dropFirst()), in: parts.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        return placements
    }

    @Test(arguments: [0, 1, 2, 3, 10, 100])
    func perf003PlanGroupMatchesRecursiveVersion(count: Int) {
        let ids = (0..<count).map { WindowID(rawValue: UInt32($0 + 1)) }
        let rects = [CGRect(x: 0, y: 0, width: 1000, height: 500), CGRect(x: 13.3, y: -964, width: 3840.7, height: 2160.2)]
        for rect in rects {
            for horizontal in [true, false] {
                for gap: CGFloat in [0, 10, 7.5] {
                    #expect(DropGroupGeometry.planGroup(ids, in: rect, horizontal: horizontal, gap: gap)
                        == Self.recursivePlanGroup(ids, in: rect, horizontal: horizontal, gap: gap))
                }
            }
        }
    }

    @Test
    func perf003RepeatedIdentifierKeepsFirstPlacement() {
        let ids = [1, 2, 1, 3, 2].map { WindowID(rawValue: $0) }
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 500)
        #expect(DropGroupGeometry.planGroup(ids, in: rect, horizontal: true, gap: 10)
            == Self.recursivePlanGroup(ids, in: rect, horizontal: true, gap: 10))
    }

    /// Chemin structurel complet (mode bsp) : résultat figé, calculé sur l'ancienne version.
    @Test
    func perf003StructuralPreviewKeepsPlacements() throws {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "lot-h-display"), index: 1, name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true
        )
        let left = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 495, height: 500))
        let topRight = lotHWindow(2, frame: Rect(x: 505, y: 0, width: 495, height: 245))
        let bottomRight = lotHWindow(3, frame: Rect(x: 505, y: 255, width: 495, height: 245))
        let windows = [left, topRight, bottomRight]
        let store = StageStore(path: lotHTempPath())
        store.save(PersistentStageState(
            scopes: [PersistentStageScope(displayID: display.id, stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .bsp, members: windows.map {
                    PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                }),
            ])],
            activeDisplayID: display.id
        ))
        let provider = PowerUserProvider(displays: [display], windows: windows)
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: LayoutIntentStore(path: lotHTempPath()),
            stageStore: store,
            events: EventLog(path: lotHTempPath())
        )

        let candidate = try #require(DropPreviewEngine(service: service).candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 50, y: 250)))

        #expect(candidate.operation == .insertLeft)
        #expect(candidate.placements[bottomRight.id] == Rect(x: 0, y: 0, width: 495, height: 245))
        #expect(candidate.placements[left.id] == Rect(x: 0, y: 255, width: 495, height: 245))
        #expect(candidate.placements[topRight.id] == Rect(x: 505, y: 0, width: 495, height: 500))
    }

    // MARK: - REL-019 : la fenêtre vue au premier plan, pas la plus petite

    @Test
    func rel019FocusPicksFrontWindowOverSmallerHiddenOne() {
        let big = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))
        let small = lotHWindow(2, frame: Rect(x: 100, y: 100, width: 200, height: 150))
        let snapshot = lotHSnapshot([big, small])

        #expect(FocusFollowsMousePicker.targetWindow(at: CGPoint(x: 150, y: 150), in: snapshot)?.window.id == big.id)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 150, y: 150), in: snapshot)?.window.id == big.id)
    }

    @Test
    func rel019UnmanagedFrontWindowBlocksWindowsBehind() {
        let panel = lotHWindow(9, frame: Rect(x: 0, y: 0, width: 400, height: 400), tileCandidate: false)
        let managed = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))
        var snapshot = lotHSnapshot([managed])
        snapshot.windows.insert(ScopedWindowSnapshot(window: panel, scope: nil), at: 0)

        #expect(FocusFollowsMousePicker.targetWindow(at: CGPoint(x: 150, y: 150), in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 150, y: 150), in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.targetWindow(at: CGPoint(x: 600, y: 150), in: snapshot)?.window.id == managed.id)
    }

    @Test
    func rel019OffscreenWindowDoesNotBlock() {
        var hidden = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))
        hidden.isOnScreen = false
        let visible = lotHWindow(2, frame: Rect(x: 100, y: 100, width: 200, height: 150))
        let snapshot = lotHSnapshot([hidden, visible])

        #expect(FocusFollowsMousePicker.targetWindow(at: CGPoint(x: 150, y: 150), in: snapshot)?.window.id == visible.id)
    }

    @Test
    func rel019DragStartIgnoresTitlebarCoveredByAnotherWindow() {
        let big = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))
        let small = lotHWindow(2, frame: Rect(x: 100, y: 100, width: 200, height: 150))
        let covered = lotHSnapshot([big, small])
        let uncovered = lotHSnapshot([small, big])

        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: CGPoint(x: 150, y: 110), in: covered) == nil)
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: CGPoint(x: 150, y: 110), in: uncovered)?.window.id == small.id)
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: CGPoint(x: 400, y: 20), in: covered)?.window.id == big.id)
    }

    // MARK: - REL-022 : dépôt entre deux rails

    @Test
    func rel022RailDropComparesDisplayAndStage() {
        let first = DisplayID(rawValue: "first")
        let second = DisplayID(rawValue: "second")
        let one = StageID(rawValue: "1")
        let two = StageID(rawValue: "2")

        #expect(RailController.railDropMovesWindow(sourceDisplayID: first, sourceStageID: one, targetDisplayID: second, targetStageID: one))
        #expect(RailController.railDropMovesWindow(sourceDisplayID: first, sourceStageID: one, targetDisplayID: second, targetStageID: two))
        #expect(RailController.railDropMovesWindow(sourceDisplayID: first, sourceStageID: one, targetDisplayID: first, targetStageID: two))
        #expect(!RailController.railDropMovesWindow(sourceDisplayID: first, sourceStageID: one, targetDisplayID: first, targetStageID: one))
    }

    // MARK: - PERF-006 : menu de titre désactivé

    @Test @MainActor
    func perf006DisabledMenuSkipsSnapshot() {
        let provider = CountingProvider(windows: [lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))])
        let controller = titlebarController(provider: provider, enabled: false)

        #expect(controller.handleRightMouseDown(at: CGPoint(x: 100, y: 100), source: "test") == false)
        #expect(provider.windowsCalls == 0)
        #expect(provider.displaysCalls == 0)
    }

    @Test @MainActor
    func perf006EnabledMenuStillReadsSnapshot() {
        let provider = CountingProvider(windows: [])
        let controller = titlebarController(provider: provider, enabled: true)

        #expect(controller.handleRightMouseDown(at: CGPoint(x: 100, y: 100), source: "test") == false)
        #expect(provider.windowsCalls > 0)
    }

    // MARK: - DUP-001 : une seule exécution journalisée pour toutes les familles de menu

    @Test @MainActor
    func dup001EveryMenuFamilyLogsTheSameFailureEvent() {
        let eventsPath = lotHTempPath()
        let controller = titlebarController(provider: CountingProvider(windows: []), enabled: true, eventsPath: eventsPath)
        let scope = StageScope(displayID: DisplayID(rawValue: "display-main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

        for (kind, targetID) in [(WindowContextActionKind.pinDesktop, "pin_desktop"), (.stage, "2"), (.desktopStage, "2:3")] {
            controller.executeAndLog(WindowContextAction(windowID: WindowID(rawValue: 7), kind: kind, targetID: targetID, sourceScope: scope))
        }

        let logged = lotHEvents(eventsPath)
        #expect(logged.map(\.type) == Array(repeating: "titlebar_context_menu.failed", count: 3))
        #expect(logged.map { $0.details["kind"] } == ["pin_desktop", "stage", "desktop_stage"])
        #expect(logged.map { $0.details["targetID"] } == ["pin_desktop", "2", "2:3"])
        for event in logged {
            #expect(event.scope == scope)
            #expect(event.details["windowID"] == "7")
            #expect(event.details["result"] == "failed")
            #expect(event.details["message"] == "window disappeared")
        }
    }

    @Test @MainActor
    func dup001SuccessfulActionLogsActionEvent() throws {
        let display = powerDisplay()
        let window = lotHWindow(1, frame: Rect(x: 0, y: 0, width: 800, height: 600))
        let store = StageStore(path: lotHTempPath())
        store.save(PersistentStageState(
            scopes: [PersistentStageScope(displayID: display.id, stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ])],
            activeDisplayID: display.id
        ))
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: lotHTempPath()),
            stageStore: store,
            events: EventLog(path: lotHTempPath())
        )
        let actions = WindowContextActions(snapshotService: service, stageStore: store, eventLog: EventLog(path: lotHTempPath()), stageLabelsVisible: { false })
        let eventsPath = lotHTempPath()
        let controller = TitlebarContextMenuController(snapshotService: service, actions: actions, configLoader: { RoadieConfig() }, events: EventLog(path: eventsPath))
        let snapshot = service.snapshot()
        let scope = try #require(snapshot.windows.first { $0.window.id == window.id }?.scope)
        let destination = try #require(actions.destinations(for: window.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))
            .first { $0.kind == .stage && !$0.isCurrent })

        controller.executeAndLog(WindowContextAction(windowID: window.id, kind: .stage, targetID: destination.id, sourceScope: scope))

        let logged = lotHEvents(eventsPath)
        #expect(logged.map(\.type) == ["titlebar_context_menu.action"])
        #expect(logged.first?.details["result"] == "changed")
        #expect(logged.first?.details["kind"] == "stage")
        #expect(logged.first?.details["targetID"] == destination.id)
    }
}

// MARK: - Aides

private final class CountingProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let windowsValue: [WindowSnapshot]
    private var windowsCount = 0
    private var displaysCount = 0

    init(windows: [WindowSnapshot]) {
        self.windowsValue = windows
    }

    var windowsCalls: Int { lock.withLock { windowsCount } }
    var displaysCalls: Int { lock.withLock { displaysCount } }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }

    func displays() -> [DisplaySnapshot] {
        lock.withLock { displaysCount += 1 }
        return [powerDisplay()]
    }

    func windows() -> [WindowSnapshot] {
        lock.withLock { windowsCount += 1 }
        return windowsValue
    }
}

@MainActor
private func titlebarController(provider: CountingProvider, enabled: Bool, eventsPath: String = lotHTempPath()) -> TitlebarContextMenuController {
    let store = StageStore(path: lotHTempPath())
    let service = SnapshotService(
        provider: provider,
        frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
        config: RoadieConfig(),
        intentStore: LayoutIntentStore(path: lotHTempPath()),
        stageStore: store,
        events: EventLog(path: lotHTempPath())
    )
    var config = RoadieConfig()
    config.experimental.titlebarContextMenu.enabled = enabled
    return TitlebarContextMenuController(
        snapshotService: service,
        actions: WindowContextActions(snapshotService: service, stageStore: store, eventLog: EventLog(path: lotHTempPath()), stageLabelsVisible: { false }),
        configLoader: { config },
        events: EventLog(path: eventsPath)
    )
}

private func lotHWindow(_ id: UInt32, frame: Rect, tileCandidate: Bool = true) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id), pid: Int32(id + 100), appName: "App\(id)", bundleID: "app.\(id)",
        title: "w\(id)", frame: frame, isOnScreen: true, isTileCandidate: tileCandidate
    )
}

/// Snapshot d'une stage active ; l'ordre des fenêtres est l'ordre CoreGraphics (devant d'abord).
private func lotHSnapshot(_ windows: [WindowSnapshot]) -> DaemonSnapshot {
    let display = DisplayID(rawValue: "lot-h")
    let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    var state = RoadieState()
    state.ensureDisplay(display)
    try? state.createStage(id: scope.stageID, name: "Active", in: display, desktopID: scope.desktopID)
    try? state.switchStage(scope.stageID, in: display, desktopID: scope.desktopID)
    for window in windows {
        try? state.assignWindow(window.id, to: scope)
    }
    return DaemonSnapshot(
        permissions: PermissionSnapshot(accessibilityTrusted: true),
        displays: [],
        windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope) },
        state: state
    )
}

private func lotHEvents(_ path: String) -> [RoadieEvent] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return EventLog(path: path).tail(limit: 50).compactMap { try? decoder.decode(RoadieEvent.self, from: Data($0.utf8)) }
}

private func lotHTempPath() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("roadie-lot-h-\(UUID().uuidString).json").path
}
