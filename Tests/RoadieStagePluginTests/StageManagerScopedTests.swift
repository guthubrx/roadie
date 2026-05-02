import XCTest
import RoadieCore
@testable import RoadieStagePlugin

// MARK: - InMemoryStagePersistenceV2

/// Persistence V2 entièrement en mémoire pour les tests unitaires scopés.
/// Garantit l'isolation des tests sans I/O disque.
final class InMemoryStagePersistenceV2: StagePersistenceV2, @unchecked Sendable {
    private var store: [StageScope: Stage] = [:]
    private var activeScope: StageScope?

    func loadAll() throws -> [StageScope: Stage] { store }

    func save(_ stage: Stage, at scope: StageScope) throws {
        store[scope] = stage
    }

    func delete(at scope: StageScope) throws {
        store.removeValue(forKey: scope)
    }

    func saveActiveStage(_ scope: StageScope?) throws {
        activeScope = scope
    }

    func loadActiveStage() throws -> StageScope? { activeScope }
}

// MARK: - StageManagerScopedTests

/// Tests US1 SPEC-018 Phase 3 : isolation cross-display.
/// Vérifie au niveau StageManager que deux scopes distincts sont étanches.
@MainActor
final class StageManagerScopedTests: XCTestCase {

    private var mockRegistry: WindowRegistry!
    private var manager: StageManager!
    private var inMemPersistence: InMemoryStagePersistenceV2!

    private let uuidA = "UUID-DISPLAY-A"
    private let uuidB = "UUID-DISPLAY-B"

    override func setUp() {
        super.setUp()
        mockRegistry = WindowRegistry()
        inMemPersistence = InMemoryStagePersistenceV2()
        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: NSTemporaryDirectory() + "roadie-scoped-\(UUID().uuidString)",
            layoutHooks: nil
        )
        manager.setMode(.perDisplay, persistence: inMemPersistence)
    }

    // MARK: - T024-A : même stageID, scopes distincts → coexistent

    /// Créer "Stage 2" sur Display A ne pollue pas Display B.
    func testCoexistSameStageIDDifferentDisplays() throws {
        let scopeA = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeB = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("2"))

        _ = manager.createStage(id: StageID("2"), displayName: "On A", scope: scopeA)
        _ = manager.createStage(id: StageID("2"), displayName: "On B", scope: scopeB)

        XCTAssertEqual(manager.stagesV2.count, 2,
                       "Deux scopes distincts = deux entrées indépendantes")
        XCTAssertEqual(manager.stagesV2[scopeA]?.displayName, "On A")
        XCTAssertEqual(manager.stagesV2[scopeB]?.displayName, "On B")
    }

    // MARK: - T024-B : filtre par display

    /// `stages(in: .display(uuidA))` ne retourne que les stages de Display A.
    func testFilterByDisplay() throws {
        let s1A = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("1"))
        let s2A = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let s1B = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("1"))

        _ = manager.createStage(id: StageID("1"), displayName: "A-1", scope: s1A)
        _ = manager.createStage(id: StageID("2"), displayName: "A-2", scope: s2A)
        _ = manager.createStage(id: StageID("1"), displayName: "B-1", scope: s1B)

        let filtered = manager.stages(in: .display(uuidA))
        XCTAssertEqual(filtered.count, 2, "Display A a 2 stages")
        XCTAssertTrue(filtered.allSatisfy { $0.displayName.hasPrefix("A-") },
                      "Tous les stages filtrés appartiennent à Display A")
    }

    // MARK: - T024-C : lookup par scope retourne le bon displayName (isolation lecture)

    /// Deux stages avec le même ID mais des scopes différents ont des noms distincts.
    /// Vérifie que la lookup par scope exact retourne toujours le bon stage.
    func testLookupByExactScopeReturnsCorrectName() throws {
        let scopeA = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeB = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("2"))

        _ = manager.createStage(id: StageID("2"), displayName: "Name-A", scope: scopeA)
        _ = manager.createStage(id: StageID("2"), displayName: "Name-B", scope: scopeB)

        // La lookup exacte doit retourner le bon nom pour chaque scope.
        let stagesA = manager.stages(in: .exact(scopeA))
        let stagesB = manager.stages(in: .exact(scopeB))

        XCTAssertEqual(stagesA.count, 1, "Un seul stage pour le scope A exact")
        XCTAssertEqual(stagesB.count, 1, "Un seul stage pour le scope B exact")
        XCTAssertEqual(stagesA.first?.displayName, "Name-A",
                       "Scope A exact retourne le stage A")
        XCTAssertEqual(stagesB.first?.displayName, "Name-B",
                       "Scope B exact retourne le stage B — pas de pollution croisée")
    }

    // MARK: - T024-D : stage 1 immortel par scope

    /// `deleteStage(scope:)` avec stageID "1" est un no-op (stage immortel).
    func testDeleteStage1ImmortalPerScope() throws {
        let scope1A = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("1"))
        _ = manager.createStage(id: StageID("1"), displayName: "Default A", scope: scope1A)

        manager.deleteStage(scope: scope1A)

        XCTAssertNotNil(manager.stagesV2[scope1A],
                        "Stage 1 immortel : deleteStage(scope:) est no-op pour stageID=1")
    }

    // MARK: - T024-E : assign crée lazy dans le scope V2

    /// `createStage(scope:)` persiste dans inMemPersistence, loadAll() retrouve le stage.
    func testCreateStagePersistsInV2() throws {
        let scope = StageScope(displayUUID: uuidA, desktopID: 2, stageID: StageID("3"))
        _ = manager.createStage(id: StageID("3"), displayName: "Work", scope: scope)

        let all = try inMemPersistence.loadAll()
        XCTAssertEqual(all[scope]?.displayName, "Work",
                       "createStage(scope:) persiste dans StagePersistenceV2")
    }

    // MARK: - T024-F : deux desktops sur le même display sont isolés

    /// Desktop 1 et Desktop 2 sur le même display ne se mélangent pas.
    func testSameDisplayDifferentDesktopsIsolated() throws {
        let scopeD1 = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeD2 = StageScope(displayUUID: uuidA, desktopID: 2, stageID: StageID("2"))

        _ = manager.createStage(id: StageID("2"), displayName: "Desktop1-Stage2", scope: scopeD1)
        _ = manager.createStage(id: StageID("2"), displayName: "Desktop2-Stage2", scope: scopeD2)

        let filteredD1 = manager.stages(in: .displayDesktop(uuidA, 1))
        let filteredD2 = manager.stages(in: .displayDesktop(uuidA, 2))

        XCTAssertEqual(filteredD1.count, 1)
        XCTAssertEqual(filteredD1.first?.displayName, "Desktop1-Stage2")
        XCTAssertEqual(filteredD2.count, 1)
        XCTAssertEqual(filteredD2.first?.displayName, "Desktop2-Stage2")
    }
}
