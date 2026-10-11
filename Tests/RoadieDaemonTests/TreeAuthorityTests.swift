import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages
import RoadieTiler

/// Fournisseur mutable : fenêtres et focus changent entre deux snapshots ; compte les relevés.
private final class TreeProvider: SystemSnapshotProviding, @unchecked Sendable {
    let display: DisplaySnapshot
    var windowList: [WindowSnapshot]
    var focusedID: WindowID?
    private(set) var windowsCalls = 0

    init(display: DisplaySnapshot, windows: [WindowSnapshot], focusedID: WindowID? = nil) {
        self.display = display
        self.windowList = windows
        self.focusedID = focusedID
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func windows() -> [WindowSnapshot] {
        windowsCalls += 1
        return windowList
    }
    func focusedWindowID() -> WindowID? { focusedID }
    func mouseLocation() -> CGPoint? { nil }
}

/// Écrivain qui enregistre chaque lot et sa génération ; rend la frame demandée sauf réponse imposée.
private final class BatchWriter: WindowFrameWriting, @unchecked Sendable {
    var responses: [WindowID: CGRect?] = [:]
    private(set) var batches: [(updates: [WindowFrameUpdate], generation: UInt64)] = []

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        setFrames([WindowFrameUpdate(window: window, frame: frame)], generation: 0)[window.id] ?? nil
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        batches.append((updates, generation))
        var result: [WindowID: CGRect?] = [:]
        for update in updates {
            result.updateValue(responses[update.window.id] ?? update.frame, forKey: update.window.id)
        }
        return result
    }
}

private final class TreeClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_900_000_000)
}

@Suite
struct TreeAuthorityTests {
    private let display = powerDisplay("display-tree", index: 1, x: 0)
    private let a = powerWindow(1, x: 0)
    private let b = powerWindow(2, x: 400)
    private let c = powerWindow(3, x: 800)

    private var scope: StageScope {
        StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    }

    private func member(_ window: WindowSnapshot) -> PersistentStageMember {
        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
    }

    private func store(
        mode: WindowManagementMode = .spatialBsp,
        members: [WindowSnapshot],
        tree: BSPTree?,
        focused: WindowID? = nil,
        path: String = tempPath("tree-authority-stages")
    ) -> StageStore {
        let store = StageStore(path: path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: mode, focusedWindowID: focused, members: members.map(member), bspTree: tree)
                ])
            ],
            activeDisplayID: display.id
        ))
        return store
    }

    private func service(
        provider: TreeProvider,
        store: StageStore,
        writer: BatchWriter = BatchWriter(),
        intents: LayoutIntentStore = LayoutIntentStore(path: tempPath("tree-authority-intents")),
        events: EventLog = EventLog(path: tempPath("tree-authority-events")),
        clock: TreeClock = TreeClock(),
        registry: WrittenFrameRegistry = WrittenFrameRegistry(),
        persist: Bool = true
    ) -> SnapshotService {
        SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0)),
            intentStore: intents,
            stageStore: store,
            events: events,
            persistStateChanges: persist,
            userInput: UserInputActivity(),
            clock: { clock.now },
            frameRegistry: registry
        )
    }

    private func targets(_ service: SnapshotService, _ snapshot: DaemonSnapshot) -> [WindowID: CGRect] {
        service.layoutPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: service.orderedWindowIDs(in: scope, from: snapshot)
        ).placements
    }

    private func eventTypes(_ events: EventLog) -> [String] {
        events.tail(limit: 200).compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["type"] as? String
        }
    }

    // MARK: - T080 : l'arbre fait foi, seul le marqueur de zoom reste

    @Test
    func treeModeIgnoresAutoAndCommandIntentsButHonoursZoomMarker() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let provider = TreeProvider(display: display, windows: [a, b])
        let intents = LayoutIntentStore(path: tempPath("tree-intents"))
        let service = service(provider: provider, store: store(members: [a, b], tree: tree), intents: intents)
        let skewed: [WindowID: Rect] = [a.id: Rect(x: 0, y: 0, width: 700, height: 800), b.id: Rect(x: 700, y: 0, width: 300, height: 800)]

        for source in [LayoutIntent.Source.auto, .command] {
            intents.save(LayoutIntent(scope: scope, windowIDs: [a.id, b.id], placements: skewed, source: source))
            let frames = Dictionary(uniqueKeysWithValues: service.applyPlan(from: service.snapshot()).commands.map { ($0.window.id, $0.frame) })
            #expect(frames[a.id] == Rect(x: 0, y: 0, width: 500, height: 800))
            #expect(frames[b.id] == Rect(x: 500, y: 0, width: 500, height: 800))
        }

        intents.save(LayoutIntent(
            scope: scope,
            windowIDs: [a.id, b.id],
            placements: [a.id: display.visibleFrame, b.id: Rect(x: 999, y: 799, width: 300, height: 300)],
            source: .command,
            zoomedWindowID: a.id
        ))
        let zoomed = Dictionary(uniqueKeysWithValues: service.applyPlan(from: service.snapshot()).commands.map { ($0.window.id, $0.frame) })
        #expect(zoomed[a.id] == display.visibleFrame)
        #expect(zoomed[b.id] == Rect(x: 999, y: 799, width: 300, height: 300))
    }

    @Test
    func treeModePersistsNoAutomaticIntent() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let left = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let intents = LayoutIntentStore(path: tempPath("tree-no-auto-intents"))
        let service = service(provider: TreeProvider(display: display, windows: [left, right]), store: store(members: [left, right], tree: tree), intents: intents)
        let snapshot = service.snapshot()

        #expect(!service.saveCurrentLayoutIntentIfValid(scope: scope, from: snapshot))
        service.saveLayoutIntent(scope: scope, windowIDs: [a.id, b.id], placements: [a.id: left.frame, b.id: right.frame])
        #expect(intents.intent(for: scope) == nil)

        service.saveLayoutIntent(scope: scope, windowIDs: [a.id], placements: [a.id: display.visibleFrame], source: .auto, zoomedWindowID: a.id)
        #expect(intents.intent(for: scope)?.zoomedWindowID == a.id)
    }

    @Test
    func legacyMutableStageIsLaidOutFromTheTreeNotFromGeometry() {
        // Stage non migrée : `mutableBsp` passe par le moteur à arbre, la géométrie observée ne compte pas.
        let wide = powerWindow(1, x: 0, y: 0, width: 700, height: 800)
        let narrow = powerWindow(2, x: 700, y: 0, width: 300, height: 800)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let service = service(provider: TreeProvider(display: display, windows: [wide, narrow]), store: store(mode: .mutableBsp, members: [wide, narrow], tree: tree))
        let snapshot = service.snapshot()

        #expect(targets(service, snapshot) == [a.id: CGRect(x: 0, y: 0, width: 500, height: 800), b.id: CGRect(x: 500, y: 0, width: 500, height: 800)])
    }

    // MARK: - T081 : une réconciliation par passe, feuille gardée pendant la grâce

    @Test
    func newWindowSplitsActiveLeafAlongItsDominantDimension() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let stages = store(members: [a, b], tree: tree, focused: b.id)
        let provider = TreeProvider(display: display, windows: [a, b, c], focusedID: c.id)
        let service = service(provider: provider, store: stages)

        let snapshot = service.snapshot()

        // La feuille de b (500 x 800) est haute : coupe en deux rangées, b en haut, c en bas.
        let expected = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id),
                                     second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(b.id), second: .leaf(c.id)))
        #expect(stages.state().bspTree(for: scope) == expected)
        #expect(targets(service, snapshot)[c.id] == CGRect(x: 500, y: 400, width: 500, height: 400))

        // Passe suivante sans changement : l'arbre ne bouge plus.
        _ = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == expected)
    }

    @Test
    func absentMemberKeepsItsLeafBeyondFortyFiveSecondsAndReturnsToItsPlace() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id),
                                 second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(b.id), second: .leaf(c.id)))
        let stages = store(members: [a, b, c], tree: tree)
        let provider = TreeProvider(display: display, windows: [a, c])
        let clock = TreeClock()
        let service = service(provider: provider, store: stages, clock: clock)

        let absent = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == tree)
        // Pendant l'absence : c reprend toute la colonne de droite (arbre projeté).
        #expect(targets(service, absent)[c.id] == CGRect(x: 500, y: 0, width: 500, height: 800))

        clock.now += 60
        _ = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == tree)

        provider.windowList = [a, b, c]
        clock.now += 1
        let back = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == tree)
        let frames = targets(service, back)
        #expect(frames[b.id] == CGRect(x: 500, y: 0, width: 500, height: 399))   // couture de barre de titre
        #expect(frames[c.id] == CGRect(x: 500, y: 400, width: 500, height: 400))
    }

    @Test
    func resizeDuringNeighbourAbsenceSurvivesItsReturn() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id),
                                 second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(b.id), second: .leaf(c.id)))
        let stages = store(members: [a, b, c], tree: tree)
        let provider = TreeProvider(display: display, windows: [a, c])
        let service = service(provider: provider, store: stages)
        _ = service.snapshot()

        // Geste pendant l'absence de b : la frontière visible a | c passe à 600.
        let container = display.visibleFrame.cgRect
        stages.mutate { state in
            let full = state.bspTree(for: scope) ?? .empty
            state.setBSPTree(
                full.adjustingFence(of: a.id, edge: .right, to: CGRect(x: 0, y: 0, width: 600, height: 800), in: container, excluding: [b.id]),
                for: scope
            )
        }

        provider.windowList = [a, b, c]
        let back = service.snapshot()
        let frames = targets(service, back)
        #expect(frames[a.id] == CGRect(x: 0, y: 0, width: 600, height: 800))
        #expect(frames[b.id] == CGRect(x: 600, y: 0, width: 400, height: 399))
        #expect(frames[c.id] == CGRect(x: 600, y: 400, width: 400, height: 400))
    }

    @Test
    func confirmedDestructionRemovesTheLeafWithoutWaitingForThePurge() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let stages = store(members: [a, b], tree: tree)
        let provider = TreeProvider(display: display, windows: [a, b])
        let service = service(provider: provider, store: stages)
        _ = service.snapshot()

        // Notification reçue alors que la liste CoreGraphics montre encore b : feuille retirée, pas réinsérée.
        service.noteWindowDestroyed(b.id)
        _ = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == .leaf(a.id))

        provider.windowList = [a]
        _ = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == .leaf(a.id))
        // Le membre reste dans sa grâce ; seule la feuille est partie.
        #expect(stages.state().scopes.flatMap(\.stages).flatMap(\.members).contains { $0.windowID == b.id })
    }

    @Test
    func nativeFullscreenWindowKeepsItsLeafAndIsNotPlaced() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        var fullscreen = b
        fullscreen.role = "AXWindow"
        fullscreen.subrole = "AXStandardWindow"
        fullscreen.furniture = WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true, isNativeFullscreen: true)
        let stages = store(members: [a, b], tree: tree)
        let provider = TreeProvider(display: display, windows: [a, fullscreen])
        let service = service(provider: provider, store: stages)

        let snapshot = service.snapshot()
        #expect(stages.state().bspTree(for: scope) == tree)
        #expect(targets(service, snapshot) == [a.id: display.visibleFrame.cgRect])
    }

    // MARK: - T082 : migration une seule fois par processus producteur

    @Test
    func legacyModesAreMigratedOnceByTheFirstProducerSnapshot() throws {
        let path = tempPath("tree-migration-stages")
        let left = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let stages = store(mode: .mutableBsp, members: [left, right], tree: nil, path: path)
        let events = EventLog(path: tempPath("tree-migration-events"))
        let provider = TreeProvider(display: display, windows: [left, right])
        defer { try? FileManager.default.removeItem(atPath: path + ".pre-017") }

        _ = service(provider: provider, store: stages, events: events, persist: false).producerSnapshot(cycle: 0.5)
        #expect(stages.state().scopes.first?.stages.first?.mode == .mutableBsp)

        let producer = service(provider: provider, store: stages, events: events)
        _ = producer.snapshot()
        #expect(stages.state().scopes.first?.stages.first?.mode == .mutableBsp)

        _ = producer.producerSnapshot(cycle: 0.5)
        let migrated = try #require(stages.state().scopes.first?.stages.first)
        #expect(migrated.mode == .spatialBsp)
        #expect(migrated.bspTree == .split(orientation: .vertical, ratio: 0.5, first: .leaf(left.id), second: .leaf(right.id)))
        #expect(FileManager.default.fileExists(atPath: path + ".pre-017"))

        // Une stage repassée en `mutableBsp` n'est plus migrée par ce processus.
        stages.mutate { state in state.scopes[0].stages[0].mode = .mutableBsp }
        _ = producer.producerSnapshot(cycle: 0.5)
        _ = service(provider: provider, store: stages, events: events).producerSnapshot(cycle: 0.5)
        #expect(stages.state().scopes.first?.stages.first?.mode == .mutableBsp)
        #expect(eventTypes(events).filter { $0 == "state_migrated" }.count == 1)
    }

    // MARK: - T083 : application d'un scope en une écriture, snapshot republié

    @Test
    func applyTreeScopeWritesOnceWithItsGenerationAndRepublishesReadBackFrames() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let provider = TreeProvider(display: display, windows: [a, b])
        let writer = BatchWriter()
        let clock = TreeClock()
        let events = EventLog(path: tempPath("tree-apply-events"))
        let service = service(provider: provider, store: store(members: [a, b], tree: tree), writer: writer, events: events, clock: clock)
        let refused = CGRect(x: 500, y: 0, width: 480, height: 800)
        writer.responses[b.id] = refused

        let tick = service.applyTreeScope(scope, cause: "command:test", generation: 42)

        #expect(provider.windowsCalls == 1)
        #expect(writer.batches.count == 1)
        #expect(writer.batches.first?.generation == 42)
        #expect(Set(writer.batches.first?.updates.map(\.window.id) ?? []) == [a.id, b.id])
        #expect(tick.commands == 2)
        #expect(tick.applied == 1)
        #expect(tick.clamped == 1)
        #expect(service.treeScopeAppliedAt(scope) == clock.now)
        #expect(eventTypes(events).contains("layout_apply"))

        // Lecteurs : snapshot republié avec les frames relues, sans nouveau relevé.
        let shared = service.sharedSnapshot()
        #expect(provider.windowsCalls == 1)
        #expect(shared.windows.first { $0.window.id == a.id }?.window.frame == Rect(x: 0, y: 0, width: 500, height: 800))
        #expect(shared.windows.first { $0.window.id == b.id }?.window.frame == Rect(refused))
    }

    @Test
    func failedWriteInvalidatesTheSharedSnapshot() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let provider = TreeProvider(display: display, windows: [a, b])
        let writer = BatchWriter()
        writer.responses[b.id] = .some(nil)
        let service = service(provider: provider, store: store(members: [a, b], tree: tree), writer: writer)

        let tick = service.applyTreeScope(scope, cause: "command:test", generation: 7)
        #expect(tick.failed == 1)
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 2)
    }

    @Test
    func applyTreeScopeIgnoresNonTreeAndInactiveScopes() {
        let provider = TreeProvider(display: display, windows: [a, b])
        let writer = BatchWriter()
        let service = service(provider: provider, store: store(mode: .bsp, members: [a, b], tree: nil), writer: writer)

        #expect(service.applyTreeScope(scope, cause: "command:test", generation: 1).commands == 0)
        let inactive = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "9"))
        #expect(service.applyTreeScope(inactive, cause: "command:test", generation: 1).commands == 0)
        #expect(writer.batches.isEmpty)
    }

    @Test
    func treeContainerIsTheLayoutContainerWithOuterGaps() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let service = SnapshotService(
            provider: TreeProvider(display: display, windows: [a, b]),
            frameWriter: BatchWriter(),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 8, gapsInner: 0)),
            railSettings: RailSettings.load(raw: ""),
            intentStore: LayoutIntentStore(path: tempPath("tree-container-intents")),
            stageStore: store(members: [a, b], tree: tree),
            events: EventLog(path: tempPath("tree-container-events")),
            frameRegistry: WrittenFrameRegistry()
        )
        let snapshot = service.snapshot()
        let container = try #require(service.treeContainer(for: scope, in: snapshot))

        #expect(container == CGRect(x: 8, y: 8, width: 984, height: 784))
        #expect(targets(service, snapshot)[a.id]?.minX == container.minX)
        #expect(targets(service, snapshot)[b.id]?.maxX == container.maxX)
    }

    @Test
    func singleToleranceDecidesSuccessAndRewrite() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a.id), second: .leaf(b.id))
        let target = CGRect(x: 500, y: 0, width: 500, height: 800)
        let terminal = CGRect(x: 500, y: 0, width: 490, height: 795)   // arrondi à la cellule
        var placedB = b
        placedB.frame = Rect(terminal)
        let placedA = powerWindow(1, x: 0, y: 0, width: 501, height: 800)   // à 1 pt : rien à refaire
        let registry = WrittenFrameRegistry()
        let writer = BatchWriter()
        writer.responses[b.id] = terminal
        let service = service(provider: TreeProvider(display: display, windows: [placedA, placedB]), store: store(members: [a, b], tree: tree), writer: writer, registry: registry)

        // 10 pt d'écart : plus de seuil « réussi » à 48 pt.
        let first = service.apply(ApplyPlan(commands: [ApplyCommand(window: placedB, frame: Rect(target))]), generation: 3)
        #expect(first.items.map(\.status) == [.clamped])
        #expect(service.applyPlan(from: service.snapshot()).commands.map(\.window.id) == [b.id])

        // Frame acceptée pour cette même cible : réussie, et plus jamais redemandée.
        registry.record(windowID: b.id.rawValue, requested: target, readBack: terminal, generation: 3, at: Date())
        registry.accept(windowID: b.id.rawValue, frame: terminal)
        let second = service.apply(ApplyPlan(commands: [ApplyCommand(window: placedB, frame: Rect(target))]), generation: 3)
        #expect(second.items.map(\.status) == [.applied])
        #expect(service.applyPlan(from: service.snapshot()).commands.isEmpty)
    }
}
