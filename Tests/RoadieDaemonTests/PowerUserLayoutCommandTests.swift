import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

@Suite
struct PowerUserLayoutCommandTests {
    @Test
    func layoutFlattenAndSplitReturnCommandResults() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        // Config explicite (`bsp`) : la config réelle de la machine peut choisir l'arbre.
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig())
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let flatten = commands.flatten()
        let split = commands.split("horizontal")

        #expect(flatten.message.contains("layout flatten"))
        #expect(split.message.contains("layout split horizontal"))
    }

    @Test
    func layoutSplitVerticalStacksWindowsTopToBottom() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0, y: 0, width: 300, height: 300),
            powerWindow(2, x: 350, y: 0, width: 300, height: 300),
            powerWindow(3, x: 700, y: 0, width: 300, height: 300),
        ])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsInner: 4))
        )
        _ = service.snapshot()

        let result = LayoutCommandService(service: service).split("vertical")

        #expect(result.changed)
        #expect(writer.frames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 1000, height: 264))
        #expect(writer.frames[WindowID(rawValue: 2)] == Rect(x: 0, y: 268, width: 1000, height: 264))
        #expect(writer.frames[WindowID(rawValue: 3)] == Rect(x: 0, y: 536, width: 1000, height: 264))
    }

    // MARK: - Mode arbre (SPEC-017 R12, T090, T091, T095)
    //
    // Les commandes mutent l'arbre persisté puis l'appliquent par `applyTreeScope` : exactement une
    // écriture par fenêtre déplacée, à la frame de l'arbre muté (T204).

    @Test
    func treeMoveSwapsLeavesInOneApplicationWithoutCommandHold() {
        let fixture = TreeFixture("tree-move")

        let result = fixture.windowCommands().move(.right)

        // Depuis 1 (gauche), la voisine de droite la plus proche du centre est 3 (en bas à droite).
        #expect(result.changed)
        #expect(fixture.tree() == .split(orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w3),
                                         second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w1))))
        #expect(!fixture.activity.isActive())
        fixture.expectOneWrite([TreeFixture.w1: TreeFixture.bottomRight, TreeFixture.w3: TreeFixture.left])
        #expect(fixture.events().contains("\"strategy\":\"tree\""))
    }

    @Test
    func treeWarpReinsertsByCuttingNeighborLeafShape() {
        let fixture = TreeFixture("tree-warp")

        let result = fixture.windowCommands().warp(.right)

        // 1 est retirée : 2 et 3 occupent tout l'écran ; la feuille de 3 (1000x400) est large,
        // donc coupée en colonnes, 1 du côté droit.
        #expect(result.changed)
        #expect(fixture.tree() == .split(orientation: .horizontal, ratio: 0.5, first: .leaf(TreeFixture.w2),
                                         second: .split(orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w3), second: .leaf(TreeFixture.w1))))
        #expect(!fixture.activity.isActive())
        fixture.expectOneWrite([TreeFixture.w2: Rect(x: 0, y: 0, width: 1000, height: 399)])
    }

    @Test
    func treeResizePushesDesignatedEdgeThenPullsOppositeFence() {
        let fixture = TreeFixture("tree-resize")
        let commands = fixture.windowCommands()

        // Bord droit de 1 : frontière poussée de 80 pt vers la droite.
        #expect(commands.resize(.right).changed)
        #expect(fixture.rootRatio().map { abs($0 - 0.58) < 0.0001 } == true)
        // Pas de frontière à gauche de 1 : la frontière opposée (droite) est tirée vers l'intérieur.
        #expect(commands.resize(.left).changed)
        #expect(fixture.rootRatio().map { abs($0 - 0.5) < 0.0001 } == true)
        #expect(!fixture.activity.isActive())
        for history in fixture.writer.frameHistory.values {
            #expect(history.count <= 2)
        }
    }

    @Test
    func treeBalanceResetsEveryRatioInOneApplication() {
        let fixture = TreeFixture("tree-balance", tree: .split(
            orientation: .vertical, ratio: 0.7, first: .leaf(TreeFixture.w1),
            second: .split(orientation: .horizontal, ratio: 0.2, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))
        ))

        let result = LayoutCommandService(service: fixture.service).balance()

        #expect(result.changed)
        #expect(fixture.tree() == TreeFixture.baseTree)
        fixture.expectOneWrite([TreeFixture.w1: TreeFixture.left, TreeFixture.w2: TreeFixture.topRight, TreeFixture.w3: TreeFixture.bottomRight])
    }

    @Test
    func treeFlattenEqualsBalance() {
        let fixture = TreeFixture("tree-flatten", tree: .split(
            orientation: .vertical, ratio: 0.3, first: .leaf(TreeFixture.w1),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))
        ))

        #expect(LayoutCommandService(service: fixture.service).flatten().changed)
        #expect(fixture.tree() == TreeFixture.baseTree)
        fixture.expectOneWrite([TreeFixture.w1: TreeFixture.left, TreeFixture.w2: TreeFixture.topRight, TreeFixture.w3: TreeFixture.bottomRight])
    }

    @Test
    func treeToggleSplitFlipsParentSplitOfActiveWindow() {
        let fixture = TreeFixture("tree-toggle-split", focused: TreeFixture.w2)

        let result = LayoutCommandService(service: fixture.service).toggleSplit()

        #expect(result.changed)
        #expect(fixture.tree() == .split(orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w1),
                                         second: .split(orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))))
        fixture.expectOneWrite([TreeFixture.w2: Rect(x: 500, y: 0, width: 250, height: 800)])
    }

    @Test
    func treeSplitVerticalStacksParentSplit() {
        let fixture = TreeFixture("tree-split")

        // Vocabulaire Roadie : `vertical` = fenêtres empilées.
        #expect(LayoutCommandService(service: fixture.service).split("vertical").changed)
        #expect(fixture.tree() == .split(orientation: .horizontal, ratio: 0.5, first: .leaf(TreeFixture.w1),
                                         second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))))
    }

    @Test
    func treeModeRefusesInsertJoinAndWidthWithFailureExitCode() {
        let fixture = TreeFixture("tree-refusals")
        let layout = LayoutCommandService(service: fixture.service)
        let width = WidthAdjustmentService(service: fixture.service, config: fixture.service.effectiveConfig, events: EventLog(path: tempPath("tree-refusal-width")))

        let results = [
            (layout.insert(.left).message, layout.insert(.left).changed),
            (layout.join(with: .right).message, layout.join(with: .right).changed),
            (width.apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .presetNext)).message, false),
        ]

        for (message, changed) in results {
            #expect(!changed)
            #expect(message.contains("unavailable in tree mode"))
            #expect(CLICommandRouter.actionExitCode(changed: changed, message: message) == 1)
        }
        #expect(fixture.tree() == TreeFixture.baseTree)
        #expect(fixture.writer.frameHistory.isEmpty)
    }

    @Test
    func toggleSplitRequiresTreeMode() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0, y: 0, width: 495, height: 500),
            powerWindow(2, x: 505, y: 0, width: 495, height: 500),
        ])
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp))
        )
        _ = service.snapshot()

        let result = LayoutCommandService(service: service).toggleSplit()

        #expect(!result.changed)
        #expect(result.message.contains("requires spatialBsp"))
    }

    /// L'alias `mutableBsp` passe par le moteur à arbre ; seule la stage de l'écran actif change.
    @Test
    func toggleSplitUsesFocusedDisplayTreeAndMutableBspAlias() {
        let leftDisplay = powerDisplay("left-display", index: 1, x: 0)
        let rightDisplay = powerDisplay("right-display", index: 2, x: 1100)
        let leftDisplayWindow = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let rightLeft = powerWindow(2, x: 1100, y: 0, width: 500, height: 800)
        let rightRight = powerWindow(3, x: 1600, y: 0, width: 500, height: 800)
        let provider = PowerUserProvider(displays: [leftDisplay, rightDisplay], windows: [leftDisplayWindow, rightLeft, rightRight])
        provider.focusedID = rightRight.id
        let leftTree = BSPTree.leaf(leftDisplayWindow.id)
        let rightTree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(rightLeft.id), second: .leaf(rightRight.id))
        let store = StageStore(path: tempPath("layout-toggle-focused-display"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: leftDisplay.id, stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, focusedWindowID: leftDisplayWindow.id,
                                    members: [leftDisplayWindow].map(treeMember), bspTree: leftTree),
                ]),
                PersistentStageScope(displayID: rightDisplay.id, stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, focusedWindowID: rightRight.id,
                                    members: [rightLeft, rightRight].map(treeMember), bspTree: rightTree),
                ]),
            ],
            activeDisplayID: rightDisplay.id
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0)),
            intentStore: LayoutIntentStore(path: tempPath("layout-toggle-focused-display-intents")),
            stageStore: store
        )

        let result = LayoutCommandService(service: service).toggleSplit()

        let rightScope = StageScope(displayID: rightDisplay.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let leftScope = StageScope(displayID: leftDisplay.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        #expect(result.changed)
        #expect(store.state().bspTree(for: rightScope) == .split(orientation: .horizontal, ratio: 0.5, first: .leaf(rightLeft.id), second: .leaf(rightRight.id)))
        #expect(store.state().bspTree(for: leftScope) == leftTree)
    }

    @Test
    func layoutInsertAndZoomParentApplyFrames() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        // Config explicite (`bsp`) : la config réelle de la machine peut choisir l'arbre.
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig())
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let insert = commands.insert(.right)
        let zoom = commands.zoomParent()

        #expect(insert.message.contains("layout insert right"))
        #expect(zoom.message.contains("layout zoom-parent"))
        #expect(!writer.frames.isEmpty)
    }
}

func treeMember(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
}

/// Stage à arbre de 3 fenêtres sur un écran 1000x800 sans marges (SPEC-017 T095) : 1 à gauche,
/// 2 en haut à droite, 3 en bas à droite, chacune déjà à sa frame dans l'arbre de départ.
struct TreeFixture {
    static let w1 = WindowID(rawValue: 1)
    static let w2 = WindowID(rawValue: 2)
    static let w3 = WindowID(rawValue: 3)
    static let left = Rect(x: 0, y: 0, width: 500, height: 800)
    static let topRight = Rect(x: 500, y: 0, width: 500, height: 399)
    static let bottomRight = Rect(x: 500, y: 400, width: 500, height: 400)
    static let baseTree = BSPTree.split(
        orientation: .vertical, ratio: 0.5, first: .leaf(w1),
        second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(w2), second: .leaf(w3))
    )

    let provider: PowerUserProvider
    let writer: PowerUserWriter
    let store: StageStore
    let service: SnapshotService
    let activity: LayoutCommandActivity
    let eventPath: String
    let scope = StageScope(displayID: DisplayID(rawValue: "display-main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

    init(_ name: String, mode: WindowManagementMode = .spatialBsp, tree: BSPTree = Self.baseTree, focused: WindowID = Self.w1) {
        // Fenêtres posées aux frames de `tree` : une commande qui change l'arbre doit les écrire (T204).
        let placed = tree.place(in: CGRect(x: 0, y: 0, width: 1000, height: 800), innerGap: 0)
        let windows = [(Self.w1, Self.left), (Self.w2, Self.topRight), (Self.w3, Self.bottomRight)].map { id, base in
            let frame = placed[id].map { Rect($0) } ?? base
            return powerWindow(id.rawValue, x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        }
        provider = PowerUserProvider(windows: windows)
        provider.focusedID = focused
        writer = PowerUserWriter(provider: provider)
        store = StageStore(path: tempPath(name))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: scope.displayID, stages: [
                    PersistentStage(id: scope.stageID, mode: mode, focusedWindowID: focused, members: windows.map(treeMember), bspTree: tree),
                ]),
            ],
            activeDisplayID: scope.displayID
        ))
        eventPath = tempPath("\(name)-events")
        service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0)),
            intentStore: LayoutIntentStore(path: tempPath("\(name)-intents")),
            stageStore: store,
            events: EventLog(path: tempPath("\(name)-service-events"))
        )
        activity = LayoutCommandActivity(path: tempPath("\(name)-activity"), enabled: true)
    }

    func windowCommands() -> WindowCommandService {
        WindowCommandService(service: service, stageStore: store, events: EventLog(path: eventPath), commandActivity: activity)
    }

    func tree() -> BSPTree? {
        store.state().bspTree(for: scope)
    }

    func rootRatio() -> Double? {
        guard case .split(_, let ratio, _, _) = tree() else { return nil }
        return ratio
    }

    func events() -> String {
        (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
    }

    /// Une seule application (FR-012, T204) : exactement une écriture par fenêtre attendue, à sa
    /// frame d'arbre, et aucune autre fenêtre écrite plus d'une fois. Échoue si rien n'est écrit.
    func expectOneWrite(_ expected: [WindowID: Rect], sourceLocation: SourceLocation = #_sourceLocation) {
        for (id, frame) in expected {
            #expect(writer.frameHistory[id] == [frame], "fenêtre \(id.rawValue)", sourceLocation: sourceLocation)
        }
        for (id, history) in writer.frameHistory {
            #expect(history.count <= 1, "fenêtre \(id.rawValue) : \(history)", sourceLocation: sourceLocation)
        }
    }
}
