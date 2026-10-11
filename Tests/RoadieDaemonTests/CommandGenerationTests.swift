import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
@testable import RoadieDaemon

/// Écrivain qui tient le registre comme l'écrivain AX réel : chaque écriture groupée est inscrite
/// avec sa génération, ce qui fait jouer le budget A13 (SPEC-017 T223).
final class RegistryWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let registry: WrittenFrameRegistry
    private(set) var batches: [(generation: UInt64, frames: [WindowID: Rect])] = []

    init(provider: PowerUserProvider, registry: WrittenFrameRegistry) {
        self.provider = provider
        self.registry = registry
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        var frames: [WindowID: Rect] = [:]
        for update in updates {
            registry.record(windowID: update.window.id.rawValue, requested: update.frame, readBack: update.frame, generation: generation, at: Date())
            frames[update.window.id] = Rect(update.frame)
            results[update.window.id] = update.frame
            provider.snapshots = provider.snapshots.map {
                guard $0.id == update.window.id else { return $0 }
                var moved = $0
                moved.frame = Rect(update.frame)
                return moved
            }
        }
        batches.append((generation, frames))
        return results
    }

    func focus(_ window: WindowSnapshot) -> Bool { true }
}

/// Commandes qui ouvrent leur propre génération (SPEC-017 A13, T223) : sans cela, leurs écritures
/// s'ajoutent au budget de la génération précédente et la 3e est refusée sans écriture.
@Suite
struct CommandGenerationTests {
    @Test
    func threeWidthNextInARowWriteThreeTimesInBsp() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 0, y: 0, width: 300, height: 800)])
        let registry = WrittenFrameRegistry()
        let writer = RegistryWriter(provider: provider, registry: registry)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp)),
            intentStore: LayoutIntentStore(path: tempPath("width-gen-intents")),
            stageStore: StageStore(path: tempPath("width-gen-stage")),
            events: EventLog(path: tempPath("width-gen-service-events")),
            frameRegistry: registry
        )
        let width = WidthAdjustmentService(service: service, config: RoadieConfig(), events: EventLog(path: tempPath("width-gen-events")))

        let results = (0..<3).map { _ in width.apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .presetNext)) }

        #expect(results.allSatisfy { $0.changed }, "\(results.map(\.message))")
        #expect(writer.batches.count == 3, "écritures : \(writer.batches.map(\.frames))")
        #expect(Set(writer.batches.map(\.generation)).count == 3, "une génération par commande")
    }

    @Test
    func menuDesktopStageAssignmentIsOneApplicationInAnOpenedGeneration() {
        let displayID = DisplayID(rawValue: "display-main")
        let moved = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let staying = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let stage1 = StageID(rawValue: "1")
        let stage2 = StageID(rawValue: "2")
        let store = StageStore(path: tempPath("menu-assign-stage"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stage1, stages: [
                PersistentStage(
                    id: stage1, mode: .spatialBsp, focusedWindowID: moved.id,
                    members: [treeMember(moved), treeMember(staying)],
                    bspTree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(moved.id), second: .leaf(staying.id))
                ),
            ]),
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 2), activeStageID: stage1, stages: [
                PersistentStage(id: stage1, mode: .spatialBsp),
                PersistentStage(id: stage2, name: "Later", mode: .spatialBsp),
            ]),
        ], activeDisplayID: displayID))
        let provider = PowerUserProvider(windows: [moved, staying])
        let writer = SinglePlanWriter(provider: provider)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0)),
            intentStore: LayoutIntentStore(path: tempPath("menu-assign-intents")),
            stageStore: store,
            events: EventLog(path: tempPath("menu-assign-service-events"))
        )
        _ = service.snapshot()
        let before = PlacementGeneration.shared.current

        let result = WindowContextActions(snapshotService: service, stageStore: store, eventLog: EventLog(path: tempPath("menu-assign-events")), stageLabelsVisible: { true })
            .execute(WindowContextAction(windowID: moved.id, kind: .desktopStage, targetID: "2:2", sourceScope: nil))

        #expect(result.changed)
        writer.expectSinglePlan(
            writing: [moved.id, staying.id],
            frames: [staying.id: Rect(x: 0, y: 0, width: 1000, height: 800)],
            generationAfter: before
        )
    }
}
