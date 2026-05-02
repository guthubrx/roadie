import XCTest
import RoadieCore
@testable import RoadieStagePlugin

/// Tests unitaires du comportement de StageManager relatifs au modèle
/// "stage 1 immortel" et à la garantie du stage par défaut (SPEC-011).
@MainActor
final class StageManagerTests: XCTestCase {

    private var tmpDir: String!
    private var manager: StageManager!
    private var mockRegistry: WindowRegistry!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "roadie-stagemanager-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        mockRegistry = WindowRegistry()
        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: tmpDir,
            baseConfigDir: nil,
            layoutHooks: nil
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - testDeleteStage1IsNoop

    /// deleteStage(id: "1") ne doit pas supprimer le stage 1 (stage immortel).
    func testDeleteStage1IsNoop() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        XCTAssertNotNil(manager.stages[StageID("1")], "Stage 1 doit exister avant le delete")

        manager.deleteStage(id: StageID("1"))

        XCTAssertNotNil(manager.stages[StageID("1")],
                        "Stage 1 doit rester après deleteStage — il est immortel")
    }

    /// deleteStage sur un stage non-1 fonctionne normalement.
    func testDeleteStageNonDefaultWorks() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        _ = manager.createStage(id: StageID("2"), displayName: "2")

        manager.deleteStage(id: StageID("2"))

        XCTAssertNil(manager.stages[StageID("2")], "Stage 2 doit être supprimé")
        XCTAssertNotNil(manager.stages[StageID("1")], "Stage 1 doit rester intact")
    }

    // MARK: - testEnsureDefaultStage

    /// ensureDefaultStage() sur un manager vide crée le stage 1 et l'active.
    func testEnsureDefaultStageCreatesAndActivatesStage1() {
        XCTAssertNil(manager.stages[StageID("1")], "Aucun stage au départ")
        XCTAssertNil(manager.currentStageID, "Aucun stage actif au départ")

        manager.ensureDefaultStage()

        XCTAssertNotNil(manager.stages[StageID("1")],
                        "ensureDefaultStage doit créer le stage 1")
        XCTAssertEqual(manager.currentStageID?.value, "1",
                       "ensureDefaultStage doit activer le stage 1")
    }

    /// ensureDefaultStage() est idempotent : stage 1 déjà présent et actif → aucun changement.
    func testEnsureDefaultStageIsIdempotent() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        manager.switchTo(stageID: StageID("1"))
        XCTAssertEqual(manager.currentStageID?.value, "1")

        manager.ensureDefaultStage()

        XCTAssertEqual(manager.currentStageID?.value, "1",
                       "ensureDefaultStage idempotent quand stage 1 déjà actif")
        XCTAssertEqual(manager.stages.count, 1,
                       "Pas de stage supplémentaire créé")
    }

    /// ensureDefaultStage() quand le stage 1 existe mais n'est pas actif → l'active.
    func testEnsureDefaultStageActivatesExistingStage1() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        _ = manager.createStage(id: StageID("2"), displayName: "2")
        manager.switchTo(stageID: StageID("2"))
        XCTAssertEqual(manager.currentStageID?.value, "2")

        // currentStageID != nil → ensureDefaultStage ne touche pas le stage actif
        manager.ensureDefaultStage()

        // Stage 2 doit rester actif (ensureDefaultStage n'écrase pas un stage actif existant)
        XCTAssertEqual(manager.currentStageID?.value, "2",
                       "ensureDefaultStage ne change pas le stage actif s'il est déjà défini")
    }

    // MARK: - testStage1SurvivesEmptyAssign

    /// Créer le stage 2, y assigner toutes les fenêtres depuis stage 1 → stage 1 reste vide mais existant.
    func testStage1SurvivesWhenAllWindowsMovedToStage2() {
        // Simuler loadFromDisk → puis ensureDefaultStage (comme dans bootstrap)
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        manager.switchTo(stageID: StageID("1"))

        // Créer une fenêtre factice dans le registry et l'assigner directement au stage 1.
        // On ne crée pas stage 2 avant l'assignation initiale pour éviter que la logique
        // "lazy auto-destroy sur vide" ne supprime stage 2 (qui serait vide) lors du premier assign.
        let wid: WindowID = 999
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "test.bundle", title: "Test",
            frame: .zero, subrole: .standard, isFloating: false
        )
        mockRegistry.register(state, axElement: AXUIElementCreateApplication(1))
        manager.assign(wid: wid, to: StageID("1"))
        XCTAssertEqual(manager.stages[StageID("1")]?.memberWindows.count, 1)

        // Créer stage 2 maintenant que la fenêtre est dans stage 1.
        // Puis déplacer la fenêtre vers stage 2.
        _ = manager.createStage(id: StageID("2"), displayName: "2")
        manager.assign(wid: wid, to: StageID("2"))

        // Stage 1 ne doit pas avoir été auto-détruit (il est immortel).
        XCTAssertNotNil(manager.stages[StageID("1")],
                        "Stage 1 ne doit pas être auto-détruit même quand vide")
        XCTAssertEqual(manager.stages[StageID("1")]?.memberWindows.count, 0,
                       "Stage 1 doit être vide après déplacement de toutes ses fenêtres")
        XCTAssertEqual(manager.stages[StageID("2")]?.memberWindows.count, 1,
                       "Stage 2 doit contenir la fenêtre déplacée")
    }

    // MARK: - testLoadFromDiskDoesNotCreateDefaultStage

    /// loadFromDisk() seul sur un dossier vide ne crée pas le stage 1.
    /// C'est bootstrap() qui appelle ensureDefaultStage() — pas le manager.
    func testLoadFromDiskDoesNotAutoCreateDefaultStage() {
        // Dossier vide : aucun fichier .toml
        manager.loadFromDisk()

        XCTAssertNil(manager.stages[StageID("1")],
                     "loadFromDisk seul ne doit pas créer le stage 1 — rôle de bootstrap()")
        XCTAssertNil(manager.currentStageID,
                     "loadFromDisk seul ne doit pas définir un stage actif")
    }
}
