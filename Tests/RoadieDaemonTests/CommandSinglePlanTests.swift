import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

/// Écrivain espion (SPEC-017 T212, T213) : chaque écriture groupée est une application, avec sa
/// génération ; une écriture isolée (`setFrame`) est notée à part. Le journal ordonne applications
/// et focus.
final class SinglePlanWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    private(set) var batches: [(generation: UInt64, frames: [WindowID: Rect])] = []
    private(set) var singles: [WindowID] = []
    private(set) var log: [String] = []

    init(provider: PowerUserProvider) {
        self.provider = provider
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        singles.append(window.id)
        log.append("single")
        move(window.id, to: frame)
        return frame
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var frames: [WindowID: Rect] = [:]
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            frames[update.window.id] = Rect(update.frame)
            results[update.window.id] = update.frame
            move(update.window.id, to: update.frame)
        }
        batches.append((generation, frames))
        log.append("apply")
        return results
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        log.append("focus")
        provider.focusedID = window.id
        return true
    }

    private func move(_ id: WindowID, to frame: CGRect) {
        provider.snapshots = provider.snapshots.map {
            guard $0.id == id else { return $0 }
            var updated = $0
            updated.frame = Rect(frame)
            return updated
        }
    }

    /// Plan unique : aucune écriture isolée, une seule application qui écrit exactement `written`,
    /// dans une génération ouverte par la commande (après `before`), puis le focus.
    func expectSinglePlan(
        writing written: Set<WindowID>,
        frames expected: [WindowID: Rect] = [:],
        generationAfter before: UInt64,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(singles.isEmpty, "écritures isolées : \(singles)", sourceLocation: sourceLocation)
        #expect(batches.count == 1, "applications : \(batches.map(\.frames))", sourceLocation: sourceLocation)
        guard let batch = batches.first else { return }
        #expect(Set(batch.frames.keys) == written, sourceLocation: sourceLocation)
        #expect(batch.generation > before, sourceLocation: sourceLocation)
        for (id, frame) in expected {
            #expect(batch.frames[id] == frame, "fenêtre \(id.rawValue)", sourceLocation: sourceLocation)
        }
        if let focus = log.lastIndex(of: "focus") {
            #expect(focus > (log.firstIndex(of: "apply") ?? .max), "focus avant l'application", sourceLocation: sourceLocation)
        }
    }
}

@Suite
struct CommandSinglePlanTests {
    private let displayID = DisplayID(rawValue: "display-main")
    private let stage1 = StageID(rawValue: "1")
    private let stage2 = StageID(rawValue: "2")
    private let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0))

    private func service(
        _ provider: PowerUserProvider, _ writer: SinglePlanWriter, _ store: StageStore, _ name: String,
        config: RoadieConfig? = nil, applications: TreeScopeApplicationCenter = .shared
    ) -> SnapshotService {
        SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: config ?? self.config,
            intentStore: LayoutIntentStore(path: tempPath("\(name)-intents")),
            stageStore: store,
            events: EventLog(path: tempPath("\(name)-service-events")),
            treeScopeApplications: applications
        )
    }

    /// Stage 1 visible (fenêtre 1), stage 2 cachée (fenêtres 2 et 3, frames mémorisées périmées).
    private func twoStageState(mode: WindowManagementMode, memorized: Rect) -> (PersistentStageState, [WindowSnapshot]) {
        let current = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let first = powerWindow(2, x: 999, y: 799, width: 300, height: 300)
        let second = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let tree: (BSPTree, BSPTree)? = mode.usesTreeEngine
            ? (.leaf(current.id), .split(orientation: .vertical, ratio: 0.5, first: .leaf(first.id), second: .leaf(second.id)))
            : nil
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, mode: mode, focusedWindowID: current.id, members: [treeMember(current)], bspTree: tree?.0),
                PersistentStage(id: stage2, mode: mode, focusedWindowID: first.id, members: [first, second].map {
                    PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: memorized)
                }, bspTree: tree?.1),
            ]),
        ], activeDisplayID: displayID)
        return (state, [current, first, second])
    }

    @Test
    func treeStageSwitchHidesAndLaysOutInOneApplicationThenFocuses() {
        let (state, windows) = twoStageState(mode: .spatialBsp, memorized: Rect(x: 100, y: 100, width: 300, height: 300))
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath("single-plan-stage-tree"))
        store.save(state)
        let before = PlacementGeneration.shared.current

        let result = StageCommandService(service: service(provider, writer, store, "single-plan-stage-tree"), store: store, events: EventLog(path: tempPath("single-plan-stage-tree-events")))
            .switchTo("2", displayID: displayID)

        #expect(result.changed)
        writer.expectSinglePlan(
            writing: [windows[0].id, windows[1].id, windows[2].id],
            frames: [windows[1].id: Rect(x: 0, y: 0, width: 500, height: 800), windows[2].id: Rect(x: 500, y: 0, width: 500, height: 800)],
            generationAfter: before
        )
        #expect(writer.log.last == "focus")
    }

    /// Audit TEST-003 (T219) : une commande à plan unique publie son application d'arbre au
    /// centre de son service (celui du maintainer en production), une fois par scope à arbre,
    /// avec la génération de l'application groupée.
    @Test
    func treeStageSwitchPublishesItsApplicationToTheServiceCenter() {
        let (state, windows) = twoStageState(mode: .spatialBsp, memorized: Rect(x: 100, y: 100, width: 300, height: 300))
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath("single-plan-stage-publish"))
        store.save(state)
        let applications = TreeScopeApplicationCenter()
        let published = PublishedApplications()
        applications.setHandler { published.append($0) }

        _ = StageCommandService(
            service: service(provider, writer, store, "single-plan-stage-publish", applications: applications),
            store: store,
            events: EventLog(path: tempPath("single-plan-stage-publish-events"))
        ).switchTo("2", displayID: displayID)

        let received = published.values
        #expect(received.count == 1)
        #expect(received.first?.scope.displayID == displayID)
        #expect(received.first?.scope.stageID == stage2)
        #expect(received.first?.generation == writer.batches.first?.generation)
        #expect(Set(received.first?.windowIDs ?? []) == [windows[1].id, windows[2].id])
    }

    @Test
    func restoringStageSwitchWritesNoIntermediateMemorizedFrame() {
        let memorized = Rect(x: 100, y: 100, width: 300, height: 300)
        let (state, windows) = twoStageState(mode: .bsp, memorized: memorized)
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath("single-plan-stage-bsp"))
        store.save(state)
        let before = PlacementGeneration.shared.current

        _ = StageCommandService(service: service(provider, writer, store, "single-plan-stage-bsp", config: RoadieConfig()), store: store, events: EventLog(path: tempPath("single-plan-stage-bsp-events")))
            .switchTo("2", displayID: displayID)

        writer.expectSinglePlan(writing: [windows[0].id, windows[1].id, windows[2].id], generationAfter: before)
        // Les frames mémorisées servent au calcul de la disposition, jamais d'écriture intermédiaire.
        #expect(writer.batches.first?.frames.values.contains(memorized) == false)
    }

    @Test
    func treeDesktopSwitchHidesAndLaysOutInOneApplication() {
        let current = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let target = powerWindow(2, x: 999, y: 100, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [current, target])
        provider.focusedID = current.id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath("single-plan-desktop"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stages: [
                PersistentStage(id: stage1, mode: .spatialBsp, members: [treeMember(current)], bspTree: .leaf(current.id)),
            ]),
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 2), stages: [
                PersistentStage(id: stage1, mode: .spatialBsp, focusedWindowID: target.id, members: [treeMember(target)], bspTree: .leaf(target.id)),
            ]),
        ], activeDisplayID: displayID))
        let before = PlacementGeneration.shared.current

        let result = DesktopCommandService(service: service(provider, writer, store, "single-plan-desktop"), store: store, events: EventLog(path: tempPath("single-plan-desktop-events")))
            .focus(DesktopID(rawValue: 2))

        #expect(result.changed)
        writer.expectSinglePlan(writing: [current.id, target.id], frames: [target.id: Rect(x: 0, y: 0, width: 1000, height: 800)], generationAfter: before)
    }

    @Test
    func treeBookmarkFocusHidesAndLaysOutInOneApplication() {
        let (state, windows) = twoStageState(mode: .spatialBsp, memorized: Rect(x: 100, y: 100, width: 300, height: 300))
        var withBookmark = state
        withBookmark.windowBookmarks = [PersistentWindowBookmark(
            name: "work",
            windowID: windows[2].id,
            scope: StageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stageID: stage2),
            bundleID: windows[2].bundleID,
            title: windows[2].title,
            frame: windows[2].frame
        )]
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath("single-plan-bookmark"))
        store.save(withBookmark)
        let before = PlacementGeneration.shared.current

        let result = WindowBookmarkCommandService(service: service(provider, writer, store, "single-plan-bookmark"), store: store, events: EventLog(path: tempPath("single-plan-bookmark-events")))
            .focus("work")

        #expect(result.changed)
        writer.expectSinglePlan(
            writing: [windows[0].id, windows[1].id, windows[2].id],
            frames: [windows[1].id: Rect(x: 0, y: 0, width: 500, height: 800), windows[2].id: Rect(x: 500, y: 0, width: 500, height: 800)],
            generationAfter: before
        )
    }

    /// Deux écrans à arbre : 1 et 2 sur l'écran principal, 3 sur l'écran de droite.
    private func twoDisplayTrees(_ name: String) -> (PowerUserProvider, SinglePlanWriter, StageStore, [WindowSnapshot], [DisplaySnapshot]) {
        let displays = [powerDisplay("display-main", index: 1, x: 0), powerDisplay("display-side", index: 2, x: 1000)]
        let remaining = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let moved = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let target = powerWindow(3, x: 1000, y: 0, width: 1000, height: 800)
        let provider = PowerUserProvider(displays: displays, windows: [remaining, moved, target])
        provider.focusedID = moved.id
        let writer = SinglePlanWriter(provider: provider)
        let store = StageStore(path: tempPath(name))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displays[0].id, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, mode: .spatialBsp, focusedWindowID: moved.id, members: [remaining, moved].map(treeMember),
                                bspTree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(remaining.id), second: .leaf(moved.id))),
            ]),
            PersistentStageScope(displayID: displays[1].id, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, mode: .spatialBsp, members: [treeMember(target)], bspTree: .leaf(target.id)),
            ]),
        ], activeDisplayID: displays[0].id))
        return (provider, writer, store, [remaining, moved, target], displays)
    }

    @Test
    func windowDisplaySendWritesSourceAndTargetInOneApplication() {
        let (provider, writer, store, windows, displays) = twoDisplayTrees("single-plan-display")
        let before = PlacementGeneration.shared.current

        let result = WindowCommandService(service: service(provider, writer, store, "single-plan-display"), stageStore: store, events: EventLog(path: tempPath("single-plan-display-events")))
            .sendToDisplay(2)

        #expect(result.changed)
        // Pas de déplacement initial isolé : la fenêtre transférée entre dans le plan des deux écrans.
        writer.expectSinglePlan(writing: [windows[0].id, windows[1].id, windows[2].id], frames: [windows[0].id: Rect(x: 0, y: 0, width: 1000, height: 800)], generationAfter: before)
        let movedFrame = writer.batches.first?.frames[windows[1].id]?.cgRect ?? .zero
        #expect(displays[1].frame.cgRect.contains(CGPoint(x: movedFrame.midX, y: movedFrame.midY)))
    }

    @Test
    func treeDropAcrossScopesWritesSourceAndTargetInOneApplication() {
        let (provider, writer, store, windows, displays) = twoDisplayTrees("single-plan-drop")
        let before = PlacementGeneration.shared.current

        let result = StageCommandService(service: service(provider, writer, store, "single-plan-drop"), store: store, events: EventLog(path: tempPath("single-plan-drop-events")))
            .place(windowID: windows[1].id, displayID: displays[1].id, orderedWindowIDs: [windows[1].id, windows[2].id])

        #expect(result.changed)
        writer.expectSinglePlan(
            writing: [windows[0].id, windows[1].id, windows[2].id],
            frames: [
                windows[0].id: Rect(x: 0, y: 0, width: 1000, height: 800),
                windows[1].id: Rect(x: 1000, y: 0, width: 500, height: 800),
                windows[2].id: Rect(x: 1500, y: 0, width: 500, height: 800),
            ],
            generationAfter: before
        )
    }

    /// T220 : la voisine est choisie sur les frames projetées de l'arbre. La fenêtre 2 déborde de sa
    /// feuille (haute de 240 pt) sur toute la hauteur : sur les frames physiques, elle serait la
    /// voisine de droite de 1 ; dans l'arbre, c'est 3 (feuille basse, plus haute et plus proche).
    @Test
    func treeDirectionalFocusUsesProjectedTreeFrames() {
        let fixture = TreeFixture("single-plan-focus", tree: .split(
            orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w1),
            second: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))
        ))
        fixture.provider.snapshots = fixture.provider.snapshots.map {
            guard $0.id == TreeFixture.w2 else { return $0 }
            var overflowing = $0
            overflowing.frame = Rect(x: 500, y: 0, width: 500, height: 800)
            return overflowing
        }

        let result = fixture.windowCommands().focus(.right)

        #expect(result.changed)
        #expect(fixture.writer.focused.last == TreeFixture.w3)
        #expect(fixture.writer.frameHistory.isEmpty)
    }

    @Test
    func physicalDirectionalFocusKeepsPhysicalFramesOutsideTreeModes() {
        let fixture = TreeFixture("single-plan-focus-bsp", mode: .bsp, tree: .split(
            orientation: .vertical, ratio: 0.5, first: .leaf(TreeFixture.w1),
            second: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(TreeFixture.w2), second: .leaf(TreeFixture.w3))
        ))
        fixture.provider.snapshots = fixture.provider.snapshots.map {
            guard $0.id == TreeFixture.w2 else { return $0 }
            var overflowing = $0
            overflowing.frame = Rect(x: 500, y: 0, width: 500, height: 800)
            return overflowing
        }

        _ = fixture.windowCommands().focus(.right)

        #expect(fixture.writer.focused.last == TreeFixture.w2)
    }
}

/// T216 : relâchement d'un glisser, avec ou sans dépôt reconnu.
@Suite
struct WindowDragReleaseTests {
    @Test
    func releaseWithoutDropEndsDragImmediatelyWithoutGrace() {
        let path = tempPath("drag-release-no-drop")
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let now = Date(timeIntervalSince1970: 1_000)
        producer.markActive(windowID: WindowID(rawValue: 1), now: now)

        producer.release(now: now.addingTimeInterval(0.1))

        #expect(!consumer.isActive(now: now.addingTimeInterval(0.11)))
        #expect(consumer.lastDrop() == nil)
    }

    @Test
    func recognizedDropKeepsGraceAndLeavesProofAcrossProcesses() {
        let path = tempPath("drag-release-drop")
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let now = Date(timeIntervalSince1970: 1_000)
        producer.markActive(windowID: WindowID(rawValue: 7), now: now)

        producer.finish(now: now.addingTimeInterval(0.1), droppedWindowID: WindowID(rawValue: 7))

        let drop = consumer.lastDrop(now: now.addingTimeInterval(0.2))
        #expect(drop?.windowID == WindowID(rawValue: 7))
        #expect(drop.map { abs($0.at.timeIntervalSince(now.addingTimeInterval(0.1))) < 0.001 } == true)
        #expect(consumer.isActive(now: now.addingTimeInterval(0.2)))
        #expect(!consumer.isActive(now: now.addingTimeInterval(0.2), includingReleaseGrace: false))
    }

    /// Glisser par la barre de titre de 1, relâché hors de tout écran : aucun candidat, aucun dépôt,
    /// le glisser cesse tout de suite et la session de geste n'est pas consommée.
    @Test @MainActor
    func mouseUpWithoutCandidateReleasesWithoutGraceOrDrop() {
        let fixture = TreeFixture("drag-release-controller")
        let activity = WindowDragActivity(path: tempPath("drag-release-controller-activity"))
        let controller = WindowDragReorderController(
            preview: DropPreviewController(engine: DropPreviewEngine(service: fixture.service)),
            commandService: StageCommandService(service: fixture.service, store: fixture.store, events: EventLog(path: tempPath("drag-release-controller-events"))),
            events: EventLog(path: tempPath("drag-release-controller-drag-events")),
            userInput: UserInputActivity(monitoring: true),
            dragActivity: activity
        )
        let nsPoint = { (point: CGPoint) in RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin }

        controller.handleMouseDown(at: nsPoint(CGPoint(x: 100, y: 10)))
        controller.handleMouseDragged(to: nsPoint(CGPoint(x: 160, y: 40)))
        #expect(activity.isActive(includingReleaseGrace: false))
        controller.handleMouseUp(at: nsPoint(CGPoint(x: -50_000, y: -50_000)))

        #expect(!activity.isActive())
        #expect(activity.lastDrop() == nil)
        #expect(fixture.writer.frameHistory.isEmpty)
    }
}

/// Applications d'arbre reçues par un centre de test (le handler peut être appelé hors du test).
private final class PublishedApplications: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [TreeScopeApplication] = []

    func append(_ application: TreeScopeApplication) { lock.withLock { received.append(application) } }
    var values: [TreeScopeApplication] { lock.withLock { received } }
}
