import XCTest
import RoadieCore
@testable import RoadieStagePlugin

// MARK: - MockDesktopPersistence

/// Simule le comportement de DesktopBackedStagePersistence pour les tests unitaires.
/// Lit/écrit un tableau de Stage en mémoire — aucune dépendance vers RoadieDesktops.
final class MockDesktopPersistence: StagePersistence, @unchecked Sendable {
    var storedStages: [Stage] = []
    var activeStageID: StageID?
    var lastDesktopID: Int = 1
    var requiresPhysicalDirSwap: Bool { false }

    func saveStage(_ stage: Stage) {
        if let idx = storedStages.firstIndex(where: { $0.id == stage.id }) {
            storedStages[idx] = stage
        } else {
            storedStages.append(stage)
        }
    }
    func deleteStage(_ id: StageID) {
        storedStages.removeAll { $0.id == id }
    }
    func saveActiveStage(_ stageID: StageID?) {
        activeStageID = stageID
    }
    func loadStages() -> [Stage] { storedStages }
    func loadActiveStage() -> StageID? { activeStageID }
    func setDesktopID(_ id: Int) { lastDesktopID = id }
}

// MARK: - StageManagerWithPersistenceTests

/// Tests de cohérence : StageManager + persistence injectée (simule mode V2).
/// Vérifie que les opérations sur StageManager passent bien par la persistence
/// et que reload(forDesktop:) recharge depuis la source de vérité.
@MainActor
final class StageManagerWithPersistenceTests: XCTestCase {

    private var mockPersistence: MockDesktopPersistence!
    private var manager: StageManager!
    private var mockRegistry: WindowRegistry!

    override func setUp() {
        super.setUp()
        mockRegistry = WindowRegistry()
        mockPersistence = MockDesktopPersistence()

        // Prépeupler la persistence avec desktop 1 : stage 1 + 2 fenêtres.
        var stage1 = Stage(id: StageID("1"), displayName: "1")
        stage1.memberWindows = [
            StageMember(cgWindowID: 100, bundleID: "com.apple.Terminal",
                        titleHint: "Terminal", savedFrame: nil),
            StageMember(cgWindowID: 200, bundleID: "com.apple.Safari",
                        titleHint: "Safari", savedFrame: nil)
        ]
        mockPersistence.storedStages = [stage1]
        mockPersistence.activeStageID = StageID("1")

        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: "~/.config/roadies",
            baseConfigDir: "~/.config/roadies",
            persistence: mockPersistence,
            layoutHooks: nil
        )
    }

    // MARK: - Test 1 : loadFromDisk() lit depuis la persistence injectée

    /// Garantit que loadFromDisk() lit depuis la persistence injectée,
    /// pas depuis des fichiers TOML.
    func test_loadFromDisk_reads_from_injected_persistence() {
        manager.loadFromDisk()

        XCTAssertEqual(manager.stages.count, 1,
                       "Un stage chargé depuis la persistence")
        XCTAssertNotNil(manager.stages[StageID("1")],
                        "Stage 1 chargé depuis la persistence")
        XCTAssertEqual(manager.stages[StageID("1")]?.memberWindows.count, 2,
                       "Stage 1 doit avoir 2 fenêtres issues de la persistence")
        XCTAssertEqual(manager.currentStageID?.value, "1",
                       "Stage actif restauré depuis la persistence")
    }

    // MARK: - Test 2 : assign() persiste via la persistence injectée

    /// Vérifie que assign(wid:to:) met à jour la persistence (saveStage appelé).
    func test_assign_persists_through_injected_persistence() {
        manager.loadFromDisk()

        // Enregistrer une 3e fenêtre dans le registry.
        let wid: WindowID = 300
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "com.apple.Notes", title: "Notes",
            frame: .zero, subrole: .standard, isFloating: false
        )
        mockRegistry.register(state, axElement: AXUIElementCreateApplication(1))

        manager.assign(wid: wid, to: StageID("1"))

        // La persistence doit avoir été mise à jour.
        let persisted = mockPersistence.storedStages.first { $0.id == StageID("1") }
        XCTAssertNotNil(persisted, "Stage 1 doit exister dans la persistence")
        XCTAssertEqual(persisted?.memberWindows.count, 3,
                       "Stage 1 doit avoir 3 fenêtres après assign")
        XCTAssertTrue(persisted?.memberWindows.contains { $0.cgWindowID == 300 } ?? false,
                      "wid 300 doit être présent dans la persistence")
    }

    // MARK: - Test 3 : reload(forDesktop:) appelle setDesktopID

    /// Vérifie que reload(forDesktop:) délègue bien à setDesktopID sur la persistence.
    func test_reload_forDesktop_calls_setDesktopID() {
        manager.loadFromDisk()
        XCTAssertEqual(mockPersistence.lastDesktopID, 1)

        // Préparer la persistence pour desktop 2 (vide, sera créé avec stage 1 vide).
        // On ne modifie pas storedStages — MockDesktopPersistence retourne le même store
        // pour tous les IDs (simulation simplifiée).
        manager.reload(forDesktop: 2)

        XCTAssertEqual(mockPersistence.lastDesktopID, 2,
                       "setDesktopID(2) doit être appelé lors de reload(forDesktop: 2)")
    }

    // MARK: - Test 4 : cohérence — windows dans DesktopRegistry → visibles dans StageManager

    /// Simule le scénario du bug : DesktopRegistry a 4 fenêtres en stage 1,
    /// StageManager rechargé dessus doit les voir.
    func test_coherence_desktop_windows_visible_in_stage_manager() {
        // Préparer la persistence avec 4 fenêtres.
        var stageWith4 = Stage(id: StageID("1"), displayName: "1")
        stageWith4.memberWindows = [
            StageMember(cgWindowID: 10, bundleID: "a", titleHint: "W1"),
            StageMember(cgWindowID: 20, bundleID: "b", titleHint: "W2"),
            StageMember(cgWindowID: 30, bundleID: "c", titleHint: "W3"),
            StageMember(cgWindowID: 40, bundleID: "d", titleHint: "W4")
        ]
        mockPersistence.storedStages = [stageWith4]
        mockPersistence.activeStageID = StageID("1")

        manager.loadFromDisk()

        let stage = manager.stages[StageID("1")]
        XCTAssertNotNil(stage, "Stage 1 doit exister")
        XCTAssertEqual(stage?.memberWindows.count, 4,
                       "Stage 1 doit afficher 4 fenêtres — cohérence desktop/stage rétablie")

        // Vérifier que currentStageID est bien "1".
        XCTAssertEqual(manager.currentStageID?.value, "1",
                       "Stage actif doit être 1")
    }

    // MARK: - Test 5 : createStage persiste via la persistence

    func test_createStage_persists_through_injected_persistence() {
        manager.loadFromDisk()
        _ = manager.createStage(id: StageID("2"), displayName: "Dev")

        let persisted = mockPersistence.storedStages.first { $0.id == StageID("2") }
        XCTAssertNotNil(persisted,
                        "createStage doit persister le nouveau stage via la persistence injectée")
        XCTAssertEqual(persisted?.displayName, "Dev")
    }

    // MARK: - Test 6 : deleteStage persiste via la persistence

    func test_deleteStage_removes_from_injected_persistence() {
        manager.loadFromDisk()
        _ = manager.createStage(id: StageID("2"), displayName: "Tmp")
        XCTAssertNotNil(mockPersistence.storedStages.first { $0.id == StageID("2") })

        manager.deleteStage(id: StageID("2"))

        XCTAssertNil(mockPersistence.storedStages.first { $0.id == StageID("2") },
                     "deleteStage doit retirer le stage de la persistence injectée")
    }
}
