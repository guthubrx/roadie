import XCTest
import RoadieCore
@testable import RoadieStagePlugin

/// Tests T033 — StageManager scoped au desktop courant (FR-009, US2).
/// Vérifie que list/focus ne concernent que les stages du desktop actif.
@MainActor
final class StageManagerDesktopScopeTests: XCTestCase {

    private var tmpDir: String!
    private var manager: StageManager!
    private var mockRegistry: WindowRegistry!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "roadie-stage-scope-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        mockRegistry = WindowRegistry()
        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: "\(tmpDir!)/desktops/1/stages",
            baseConfigDir: tmpDir,
            layoutHooks: nil
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - Setup helpers

    /// Prépare 2 desktops avec stages distincts.
    /// Desktop 1 : stages A et B. Desktop 2 : stages C et D.
    private func populateTwoDesktops() {
        // Desktop 1 : stages A et B (stagesDir est déjà desktop 1)
        _ = manager.createStage(id: StageID("A"), displayName: "Alpha")
        _ = manager.createStage(id: StageID("B"), displayName: "Beta")

        // Basculer vers desktop 2 et créer C, D
        manager.reload(forDesktop: 2)
        _ = manager.createStage(id: StageID("C"), displayName: "Charlie")
        _ = manager.createStage(id: StageID("D"), displayName: "Delta")

        // Revenir sur desktop 1 comme état initial des tests
        manager.reload(forDesktop: 1)
    }

    // MARK: - Test 1 : currentDesktop=1 → list retourne {A, B}

    func test_list_on_desktop1_returns_A_and_B() {
        populateTwoDesktops()

        // On est sur desktop 1 après populateTwoDesktops
        let stageIDs = Set(manager.stages.keys.map { $0.value })
        XCTAssertEqual(stageIDs, ["A", "B"],
                       "Desktop 1 doit avoir stages A et B, pas C ou D")
        XCTAssertFalse(stageIDs.contains("C"), "C appartient au desktop 2")
        XCTAssertFalse(stageIDs.contains("D"), "D appartient au desktop 2")
    }

    // MARK: - Test 2 : reload(forDesktop: 2) → list retourne {C, D}

    func test_reload_to_desktop2_shows_C_and_D() {
        populateTwoDesktops()

        manager.reload(forDesktop: 2)
        let stageIDs = Set(manager.stages.keys.map { $0.value })
        XCTAssertEqual(stageIDs, ["C", "D"],
                       "Desktop 2 doit avoir stages C et D")
        XCTAssertFalse(stageIDs.contains("A"), "A appartient au desktop 1")
    }

    // MARK: - Test 3 : focus stage A sur desktop 1 → persisté après round-trip

    func test_active_stage_persisted_across_desktop_switch() {
        populateTwoDesktops()

        // On est sur desktop 1, focus A
        manager.switchTo(stageID: StageID("A"))
        XCTAssertEqual(manager.currentStageID?.value, "A")

        // Basculer desktop 2 (A doit être sauvegardé)
        manager.reload(forDesktop: 2)
        XCTAssertNil(manager.currentStageID, "Aucun stage actif sur desktop 2 initialement")

        // Retourner desktop 1 → A doit être restauré
        manager.reload(forDesktop: 1)
        XCTAssertEqual(manager.currentStageID?.value, "A",
                       "Stage A doit rester actif sur desktop 1 après round-trip")
    }

    // MARK: - Test 4 : isolation — create sur desktop 1 n'affecte pas desktop 2

    func test_create_on_desktop1_isolated_from_desktop2() {
        // Partir de zéro
        _ = manager.createStage(id: StageID("X"), displayName: "Xray")

        // Desktop 2 ne doit pas voir X
        manager.reload(forDesktop: 2)
        let stageIDs = Set(manager.stages.keys.map { $0.value })
        XCTAssertFalse(stageIDs.contains("X"),
                       "Stage X (desktop 1) ne doit pas apparaître sur desktop 2")
    }

    // MARK: - Test 5 : delete sur desktop 1 n'affecte pas desktop 2

    func test_delete_on_desktop1_isolated_from_desktop2() {
        populateTwoDesktops()

        // Supprimer B sur desktop 1
        manager.deleteStage(id: StageID("B"))
        let d1IDs = Set(manager.stages.keys.map { $0.value })
        XCTAssertFalse(d1IDs.contains("B"), "B supprimé sur desktop 1")

        // Desktop 2 doit toujours avoir C et D
        manager.reload(forDesktop: 2)
        let d2IDs = Set(manager.stages.keys.map { $0.value })
        XCTAssertTrue(d2IDs.contains("C"))
        XCTAssertTrue(d2IDs.contains("D"))
    }
}
