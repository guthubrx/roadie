import XCTest
import RoadieCore
@testable import RoadieStagePlugin

final class StagePersistenceV2Tests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("roadie-pv2-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - FlatStagePersistence

    func test_flat_save_load_delete_cycle() throws {
        let persistence = FlatStagePersistence(stagesDir: tmpDir)
        let stage = Stage(id: StageID("alpha"), displayName: "Alpha")

        try persistence.save(stage, at: .global(stage.id))
        let loaded = try persistence.loadAll()

        XCTAssertEqual(loaded.count, 1)
        let scope = StageScope.global(StageID("alpha"))
        XCTAssertNotNil(loaded[scope], "Stage alpha doit être chargé")
        XCTAssertEqual(loaded[scope]?.displayName, "Alpha")

        try persistence.delete(at: scope)
        let afterDelete = try persistence.loadAll()
        XCTAssertEqual(afterDelete.count, 0, "Stage supprimé doit disparaître du loadAll")
    }

    func test_flat_returned_scope_is_global() throws {
        let persistence = FlatStagePersistence(stagesDir: tmpDir)
        let stage = Stage(id: StageID("s1"), displayName: "S1")
        try persistence.save(stage, at: .global(stage.id))

        let loaded = try persistence.loadAll()
        let keys = Array(loaded.keys)

        XCTAssertEqual(keys.count, 1)
        XCTAssertTrue(keys[0].isGlobal, "FlatStagePersistence ne retourne que des scopes globaux")
        XCTAssertEqual(keys[0].stageID.value, "s1")
    }

    func test_flat_active_stage_round_trip() throws {
        let persistence = FlatStagePersistence(stagesDir: tmpDir)
        let scope = StageScope.global(StageID("dev"))

        try persistence.saveActiveStage(scope)
        let loaded = try persistence.loadActiveStage()

        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded!.isGlobal)
        XCTAssertEqual(loaded!.stageID.value, "dev")
    }

    func test_flat_active_stage_nil_clears() throws {
        let persistence = FlatStagePersistence(stagesDir: tmpDir)
        try persistence.saveActiveStage(.global(StageID("x")))
        try persistence.saveActiveStage(nil)
        let loaded = try persistence.loadActiveStage()
        XCTAssertNil(loaded, "saveActiveStage(nil) doit effacer le stage actif")
    }

    func test_flat_multiple_stages_coexist() throws {
        let persistence = FlatStagePersistence(stagesDir: tmpDir)
        let stages = ["1", "2", "3"].map { Stage(id: StageID($0), displayName: $0) }
        for s in stages { try persistence.save(s, at: .global(s.id)) }

        let loaded = try persistence.loadAll()
        XCTAssertEqual(loaded.count, 3)
    }

    // MARK: - NestedStagePersistence

    private let uuidA = "DISPLAY-UUID-A"
    private let uuidB = "DISPLAY-UUID-B"

    func test_nested_save_load_delete_cycle() throws {
        let persistence = NestedStagePersistence(stagesDir: tmpDir)
        let scopeA = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let stage = Stage(id: StageID("2"), displayName: "Two")

        try persistence.save(stage, at: scopeA)
        let loaded = try persistence.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertNotNil(loaded[scopeA], "Stage sous \(uuidA)/1 doit être chargé")
        XCTAssertEqual(loaded[scopeA]?.displayName, "Two")

        try persistence.delete(at: scopeA)
        XCTAssertEqual(try persistence.loadAll().count, 0)
    }

    func test_nested_two_displays_coexist() throws {
        let persistence = NestedStagePersistence(stagesDir: tmpDir)
        let scopeA = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeB = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("2"))

        try persistence.save(Stage(id: StageID("2"), displayName: "Two-A"), at: scopeA)
        try persistence.save(Stage(id: StageID("2"), displayName: "Two-B"), at: scopeB)

        let loaded = try persistence.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[scopeA]?.displayName, "Two-A")
        XCTAssertEqual(loaded[scopeB]?.displayName, "Two-B")
    }

    func test_nested_delete_a_does_not_affect_b() throws {
        let persistence = NestedStagePersistence(stagesDir: tmpDir)
        let scopeA = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeB = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("2"))

        try persistence.save(Stage(id: StageID("2"), displayName: "Two-A"), at: scopeA)
        try persistence.save(Stage(id: StageID("2"), displayName: "Two-B"), at: scopeB)

        try persistence.delete(at: scopeA)
        let remaining = try persistence.loadAll()

        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(remaining[scopeB], "scopeB doit rester intact après suppression de scopeA")
        XCTAssertNil(remaining[scopeA], "scopeA doit avoir disparu")
    }

    func test_nested_active_stage_contextual_round_trip() throws {
        let persistence = NestedStagePersistence(stagesDir: tmpDir)
        let scope = StageScope(displayUUID: uuidA, desktopID: 2, stageID: StageID("5"))
        // Save nécessite que le dossier existe (create via save d'un stage)
        try persistence.save(Stage(id: StageID("5"), displayName: "Five"), at: scope)

        try persistence.saveActiveStage(scope)
        let loaded = persistence.loadActiveStage(forDisplay: uuidA, desktop: 2)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.stageID.value, "5")
        XCTAssertEqual(loaded?.displayUUID, uuidA)
        XCTAssertEqual(loaded?.desktopID, 2)
    }

    func test_nested_same_stage_id_different_desktops_are_isolated() throws {
        let persistence = NestedStagePersistence(stagesDir: tmpDir)
        let scope1 = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("1"))
        let scope2 = StageScope(displayUUID: uuidA, desktopID: 2, stageID: StageID("1"))

        try persistence.save(Stage(id: StageID("1"), displayName: "Desktop1-Stage1"), at: scope1)
        try persistence.save(Stage(id: StageID("1"), displayName: "Desktop2-Stage1"), at: scope2)

        let loaded = try persistence.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[scope1]?.displayName, "Desktop1-Stage1")
        XCTAssertEqual(loaded[scope2]?.displayName, "Desktop2-Stage1")
    }
}
