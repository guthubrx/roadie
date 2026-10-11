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

    private struct Fixture {
        let store: StageStore
        let service: SnapshotService
        let engine: DropPreviewEngine
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
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: LayoutIntentStore(path: tempPreviewPath()),
            stageStore: store,
            events: EventLog(path: tempPreviewPath())
        )
        return Fixture(store: store, service: service, engine: DropPreviewEngine(service: service))
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
