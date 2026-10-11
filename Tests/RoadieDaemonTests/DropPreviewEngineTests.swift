import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

private final class DropPreviewProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let displaysValue: [DisplaySnapshot]
    private let windowsValue: [WindowSnapshot]

    init(displays: [DisplaySnapshot], windows: [WindowSnapshot]) {
        self.displaysValue = displays
        self.windowsValue = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        displaysValue
    }

    func windows() -> [WindowSnapshot] {
        windowsValue
    }
}

/// Aperçu et dépôt sur l'arbre projeté (SPEC-017 R12, T092, T095). Les anciens tests `mutableBsp`
/// (reflow local, frame de départ du glisser) sont remplacés : l'arbre fait foi, la frame
/// transitoire de la fenêtre glissée et les frames mémorisées n'entrent plus dans le calcul.
@Suite
struct DropPreviewEngineTests {
    private static let display = DisplaySnapshot(
        id: DisplayID(rawValue: "display-a"),
        index: 1,
        name: "A",
        frame: Rect(x: 0, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
        isMain: true
    )
    private static let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    private static let internalDisplay = DisplaySnapshot(
        id: DisplayID(rawValue: "drop-internal"), index: 1, name: "Mac",
        frame: Rect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950), isMain: true
    )
    private static let externalDisplay = DisplaySnapshot(
        id: DisplayID(rawValue: "drop-external"), index: 2, name: "LG",
        frame: Rect(x: 1512, y: -964, width: 3840, height: 2160),
        visibleFrame: Rect(x: 1512, y: -934, width: 3840, height: 2130), isMain: false
    )
    private static let sourceScope = StageScope(displayID: internalDisplay.id, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "1"))
    private static let destinationScope = StageScope(displayID: externalDisplay.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    private let source = previewWindow(41, title: "source", frame: internalDisplay.visibleFrame)
    private let destination = previewWindow(42, title: "destination", frame: externalDisplay.visibleFrame)

    private struct Fixture {
        let store: StageStore
        let service: SnapshotService
        let engine: DropPreviewEngine
        let provider: PowerUserProvider
        let writer: PowerUserWriter
    }

    private func fixture(windows: [WindowSnapshot], tree: BSPTree) -> Fixture {
        let store = StageStore(path: tempPreviewPath())
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: Self.display.id, stages: [
                    PersistentStage(
                        id: Self.scope.stageID,
                        mode: .spatialBsp,
                        members: windows.map {
                            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                        },
                        bspTree: tree
                    ),
                ]),
            ],
            activeDisplayID: Self.display.id
        ))
        let provider = PowerUserProvider(displays: [Self.display], windows: windows)
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: LayoutIntentStore(path: tempPreviewPath()),
            stageStore: store,
            events: EventLog(path: tempPreviewPath())
        )
        return Fixture(store: store, service: service, engine: DropPreviewEngine(service: service), provider: provider, writer: writer)
    }

    private func crossDisplayFixture(destinationHasWindow: Bool = true, destinationMode: WindowManagementMode = .spatialBsp) -> Fixture {
        let member = { (window: WindowSnapshot) in
            PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
        }
        let store = StageStore(path: tempPreviewPath())
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: Self.internalDisplay.id, desktopID: Self.sourceScope.desktopID, stages: [
                    PersistentStage(id: Self.sourceScope.stageID, mode: .spatialBsp, members: [member(source)], bspTree: .leaf(source.id))
                ]),
                PersistentStageScope(displayID: Self.externalDisplay.id, stages: [
                    PersistentStage(id: Self.destinationScope.stageID, mode: destinationMode,
                                    members: destinationHasWindow ? [member(destination)] : [],
                                    bspTree: destinationHasWindow ? .leaf(destination.id) : .empty)
                ])
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: Self.internalDisplay.id, currentDesktopID: Self.sourceScope.desktopID)],
            activeDisplayID: Self.internalDisplay.id
        ))
        let provider = PowerUserProvider(displays: [Self.internalDisplay, Self.externalDisplay], windows: destinationHasWindow ? [source, destination] : [source])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 20, gapsInner: 10, smartGapsSolo: true)),
            railSettings: RailSettings.load(raw: ""),
            intentStore: LayoutIntentStore(path: tempPreviewPath()),
            stageStore: store,
            events: EventLog(path: tempPreviewPath())
        )
        return Fixture(store: store, service: service, engine: DropPreviewEngine(service: service), provider: provider, writer: writer)
    }

    private let left = previewWindow(1, title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500))
    private let topRight = previewWindow(2, title: "top-right", frame: Rect(x: 505, y: 0, width: 495, height: 245))
    private let bottomRight = previewWindow(3, title: "bottom-right", frame: Rect(x: 505, y: 255, width: 495, height: 245))
    private var threeTree: BSPTree {
        .split(orientation: .vertical, ratio: 0.5, first: .leaf(left.id),
               second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(topRight.id), second: .leaf(bottomRight.id)))
    }

    @Test
    func treeDropOnBottomEdgeInsertsBelowTarget() {
        let right = previewWindow(2, title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500))
        let setup = fixture(windows: [left, right], tree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(left.id), second: .leaf(right.id)))

        let candidate = setup.engine.candidate(sourceWindowID: right.id, atAXPoint: CGPoint(x: 250, y: 420))

        #expect(candidate?.operation == .insertDown)
        #expect(candidate?.targetWindowID == left.id)
        #expect(candidate?.frame == CGRect(x: 0, y: 255, width: 1000, height: 245))
        #expect(candidate?.placements[left.id] == Rect(x: 0, y: 0, width: 1000, height: 245))
        #expect(candidate?.placements[right.id] == Rect(x: 0, y: 255, width: 1000, height: 245))
    }

    @Test
    func treeDropIgnoresTransientDraggedFrameAndRefillsFreedSpace() {
        let dragged = previewWindow(3, title: "bottom-right", frame: Rect(x: 1900, y: 1700, width: 395, height: 220))
        let setup = fixture(windows: [left, topRight, dragged], tree: threeTree)

        let candidate = setup.engine.candidate(sourceWindowID: dragged.id, atAXPoint: CGPoint(x: 250, y: 420))

        // 3 quitte la droite : 2 reprend toute la colonne ; 3 coupe la feuille de 1 en rangées.
        #expect(candidate?.operation == .insertDown)
        #expect(candidate?.placements[left.id] == Rect(x: 0, y: 0, width: 495, height: 245))
        #expect(candidate?.placements[dragged.id] == Rect(x: 0, y: 255, width: 495, height: 245))
        #expect(candidate?.placements[topRight.id] == Rect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func treeDropAtCenterSwapsLeaves() {
        let setup = fixture(windows: [left, topRight, bottomRight], tree: threeTree)

        let candidate = setup.engine.candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 250, y: 250))

        #expect(candidate?.operation == .swap)
        #expect(candidate?.placements[bottomRight.id] == left.frame)
        #expect(candidate?.placements[left.id] == bottomRight.frame)
        #expect(candidate?.placements[topRight.id] == topRight.frame)
    }

    @Test
    func treePreviewPersistsNothing() throws {
        let setup = fixture(windows: [left, topRight, bottomRight], tree: threeTree)
        // Contexte figé au début du glisser (son snapshot peut écrire l'état des membres) ; les
        // aperçus qui suivent n'écrivent rien.
        let context = setup.engine.makeContext()
        let before = try Data(contentsOf: setup.store.fileURL)

        _ = setup.engine.candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 250, y: 420), context: context)
        _ = setup.engine.candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 250, y: 250), context: context)

        #expect(try Data(contentsOf: setup.store.fileURL) == before)
        #expect(setup.store.state().bspTree(for: Self.scope) == threeTree)
    }

    @Test
    func treeDropAppliesCandidateMutationToPersistedTree() {
        let setup = fixture(windows: [left, topRight, bottomRight], tree: threeTree)
        guard let candidate = setup.engine.candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 250, y: 420)) else {
            Issue.record("aucun candidat")
            return
        }

        let result = StageCommandService(service: setup.service, store: setup.store).place(
            windowID: candidate.sourceWindowID,
            displayID: candidate.displayID,
            orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements,
            treeMutation: candidate.treeMutation
        )

        let expected = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(left.id), second: .leaf(bottomRight.id)),
            second: .leaf(topRight.id)
        )
        #expect(result.changed)
        #expect(setup.store.state().bspTree(for: Self.scope) == expected)
        #expect(setup.store.state().scopes.first?.stages.first?.members.map { $0.windowID } == expected.windowIDs)
    }

    @Test
    func crossDisplayCenterInsertsWithFutureSmartGaps() throws {
        let setup = crossDisplayFixture()
        let context = setup.engine.makeContext()
        #expect(context.snapshot.windows.first { $0.window.id == source.id }?.scope == Self.sourceScope)

        let candidate = try #require(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: context))

        #expect(candidate.operation == .insertRight)
        #expect(candidate.targetWindowID == destination.id)
        #expect(candidate.displayID == Self.externalDisplay.id)
        #expect(candidate.scope == Self.destinationScope)
        #expect(candidate.frame == CGRect(x: 3437, y: -914, width: 1895, height: 2090))
        #expect(candidate.placements[destination.id] == Rect(x: 1532, y: -914, width: 1895, height: 2090))
        #expect(candidate.orderedWindowIDs == [destination.id, source.id])
    }

    @Test(arguments: [DropPreviewOperation.insertLeft, .insertRight, .insertUp, .insertDown])
    func crossDisplayEdgesApplyThePreviewedTree(operation: DropPreviewOperation) throws {
        let setup = crossDisplayFixture()
        let point: CGPoint
        let expectedFrame: CGRect
        switch operation {
        case .insertLeft:
            point = CGPoint(x: 1700, y: -244)
            expectedFrame = CGRect(x: 1532, y: -914, width: 1895, height: 2090)
        case .insertRight:
            point = CGPoint(x: 5200, y: -244)
            expectedFrame = CGRect(x: 3437, y: -914, width: 1895, height: 2090)
        case .insertUp:
            point = CGPoint(x: 3432, y: -850)
            expectedFrame = CGRect(x: 1532, y: -914, width: 3800, height: 1040)
        case .insertDown:
            point = CGPoint(x: 3432, y: 1050)
            expectedFrame = CGRect(x: 1532, y: 136, width: 3800, height: 1040)
        default:
            Issue.record("bord attendu")
            return
        }
        let candidate = try #require(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: point))
        #expect(candidate.operation == operation)
        #expect(candidate.frame == expectedFrame)
        let mutation = try #require(candidate.treeMutation)
        let expectedTree = mutation(.leaf(destination.id))

        let result = StageCommandService(service: setup.service, store: setup.store).place(
            windowID: candidate.sourceWindowID, displayID: candidate.displayID,
            orderedWindowIDs: candidate.orderedWindowIDs, placements: candidate.placements,
            treeMutation: candidate.treeMutation
        )

        #expect(result.changed)
        #expect(setup.store.state().bspTree(for: Self.sourceScope) == .empty)
        #expect(setup.store.state().bspTree(for: Self.destinationScope) == expectedTree)
        #expect(expectedTree.windowIDs.filter { $0 == source.id }.count == 1)
        #expect(setup.store.state().stageScope(for: source.id) == Self.destinationScope)
        for (id, frame) in candidate.placements { #expect(setup.writer.frames[id] == frame) }
    }

    @Test
    func crossDisplayEmptyTreePreviewsItsFirstPlacement() throws {
        let setup = crossDisplayFixture(destinationHasWindow: false)
        let context = setup.engine.makeContext()
        #expect(context.snapshot.state.stage(scope: Self.destinationScope)?.mode == .spatialBsp)
        let before = try Data(contentsOf: setup.store.fileURL)

        let candidate = try #require(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: context))

        #expect(candidate.operation == .append)
        #expect(candidate.targetWindowID == nil)
        #expect(candidate.scope == Self.destinationScope)
        #expect(candidate.frame == Self.externalDisplay.visibleFrame.cgRect)
        #expect(candidate.placements == [source.id: Self.externalDisplay.visibleFrame])
        #expect(candidate.orderedWindowIDs == [source.id])
        #expect(try Data(contentsOf: setup.store.fileURL) == before)
        let result = StageCommandService(service: setup.service, store: setup.store).place(
            windowID: source.id, displayID: candidate.displayID, orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements, treeMutation: candidate.treeMutation
        )

        #expect(result.changed)
        #expect(setup.store.state().bspTree(for: Self.sourceScope) == .empty)
        #expect(setup.store.state().bspTree(for: Self.destinationScope) == .leaf(source.id))
        #expect(setup.writer.frames[source.id] == Rect(candidate.frame))
    }

    @Test
    func crossDisplayEmptyProjectionKeepsHistoricalLeafOnDrop() throws {
        let setup = crossDisplayFixture(destinationHasWindow: false)
        var state = setup.store.state()
        let scopeIndex = try #require(state.scopes.firstIndex { $0.displayID == Self.externalDisplay.id })
        state.scopes[scopeIndex].stages[0].members = [
            PersistentStageMember(windowID: destination.id, bundleID: destination.bundleID, title: destination.title, frame: destination.frame)
        ]
        state.scopes[scopeIndex].stages[0].bspTree = .leaf(destination.id)
        setup.store.save(state)
        let context = setup.engine.makeContext()
        #expect(context.persistedStateBeforeSnapshot.bspTree(for: Self.destinationScope) == .leaf(destination.id))
        #expect(context.snapshot.state.stage(scope: Self.destinationScope)?.mode == .spatialBsp)
        #expect(!context.snapshot.windows.contains { $0.scope == Self.destinationScope })
        let before = try Data(contentsOf: setup.store.fileURL)

        let candidate = try #require(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: context))

        #expect(candidate.operation == .append)
        #expect(candidate.targetWindowID == nil)
        #expect(candidate.placements == [source.id: Self.externalDisplay.visibleFrame])
        #expect(candidate.frame == Self.externalDisplay.visibleFrame.cgRect)
        #expect(candidate.orderedWindowIDs == [destination.id, source.id])
        #expect(try Data(contentsOf: setup.store.fileURL) == before)
        let result = StageCommandService(service: setup.service, store: setup.store).place(
            windowID: source.id, displayID: candidate.displayID, orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements, treeMutation: candidate.treeMutation
        )

        #expect(result.changed)
        #expect(setup.store.state().bspTree(for: Self.sourceScope) == .empty)
        #expect(setup.store.state().bspTree(for: Self.destinationScope) == .split(
            orientation: .vertical, ratio: 0.5, first: .leaf(destination.id), second: .leaf(source.id)
        ))
        #expect(setup.store.state().stageScope(for: destination.id) == Self.destinationScope)
        #expect(setup.writer.frames[source.id] == Rect(candidate.frame))
        #expect(setup.writer.frames[destination.id] == nil)
    }

    @Test
    func crossDisplayPreviewUsesFrozenContextAndPersistsNothing() throws {
        let setup = crossDisplayFixture()
        let context = setup.engine.makeContext()
        let before = try Data(contentsOf: setup.store.fileURL)
        let point = CGPoint(x: 3432, y: -244)
        let candidate = try #require(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: point, context: context))
        setup.provider.snapshots = []

        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: point, context: context) == candidate)
        #expect(try Data(contentsOf: setup.store.fileURL) == before)
        #expect(setup.store.state().bspTree(for: Self.sourceScope) == .leaf(source.id))
        #expect(setup.store.state().bspTree(for: Self.destinationScope) == .leaf(destination.id))
        #expect(setup.writer.frames.isEmpty)
    }

    @Test
    func crossDisplayPreviewRequiresAnEligibleSourceOnItsActiveDesktop() throws {
        let setup = crossDisplayFixture()
        let context = setup.engine.makeContext()
        let sourceIndex = try #require(context.snapshot.windows.firstIndex { $0.window.id == source.id })
        var inactive = context
        try inactive.snapshot.state.createDesktop(DesktopID(rawValue: 3), on: Self.internalDisplay.id)
        try inactive.snapshot.state.switchDesktop(DesktopID(rawValue: 3), on: Self.internalDisplay.id)
        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: inactive) == nil)
        var floating = context
        floating.snapshot.windows[sourceIndex].window.isTileCandidate = false
        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: floating) == nil)
        var fixed = context
        fixed.snapshot.windows[sourceIndex].window.furniture?.isResizable = false
        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), context: fixed) == nil)
    }

    @Test
    func crossDisplayPreviewRejectsFloatDestinationAndPointsOutsideDisplays() {
        let floating = crossDisplayFixture(destinationMode: .float)
        #expect(floating.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244)) == nil)
        let emptyFloating = crossDisplayFixture(destinationHasWindow: false, destinationMode: .float)
        #expect(emptyFloating.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244)) == nil)
        let setup = crossDisplayFixture()
        let context = setup.engine.makeContext()
        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: -20, y: -1200), context: context) == nil)
        #expect(setup.engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 3432, y: -244), displayID: Self.internalDisplay.id, context: context) == nil)
    }

    @Test
    func sameScopeDropOutsideProjectedWindowsCancels() {
        let setup = fixture(windows: [left, topRight, bottomRight], tree: threeTree)
        // Le pointeur est dans l'écran mais dans le gap entre les deux colonnes.
        #expect(setup.engine.candidate(sourceWindowID: bottomRight.id, atAXPoint: CGPoint(x: 500, y: 250)) == nil)
    }

    @Test
    func sameScopeEmptyProjectionCancels() {
        let setup = fixture(windows: [left], tree: .leaf(WindowID(rawValue: 99)))
        let context = setup.engine.makeContext()
        #expect(setup.engine.candidate(sourceWindowID: left.id, atAXPoint: CGPoint(x: 250, y: 250), context: context) == nil)
    }
}

private func previewWindow(_ rawID: UInt32, title: String, frame: Rect) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: rawID),
        pid: Int32(rawID + 10),
        appName: "App\(rawID)",
        bundleID: "app.\(rawID)",
        title: title,
        frame: frame,
        isOnScreen: true,
        isTileCandidate: true,
        subrole: "AXStandardWindow",
        role: "AXWindow",
        furniture: WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, hasMinimizeButton: true, isResizable: true)
    )
}

private func tempPreviewPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("roadie-drop-preview-\(UUID().uuidString).json")
        .path
}
