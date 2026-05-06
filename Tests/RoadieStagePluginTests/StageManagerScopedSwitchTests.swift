import XCTest
import RoadieCore
@testable import RoadieStagePlugin

// SPEC-022 — Tests unitaires du refactor currentStageID stored→computed (T016/T017)
// et du comportement switchTo scopé (T026/T027).

@MainActor
final class StageManagerScopedSwitchTests: XCTestCase {

    private var mockRegistry: WindowRegistry!
    private var manager: StageManager!
    private var inMemPersistence: InMemoryStagePersistenceV2!

    private let uuidA = "UUID-SPEC022-A"
    private let uuidB = "UUID-SPEC022-B"

    override func setUp() {
        super.setUp()
        mockRegistry = WindowRegistry()
        inMemPersistence = InMemoryStagePersistenceV2()
        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: NSTemporaryDirectory() + "roadie-022-\(UUID().uuidString)",
            layoutHooks: nil
        )
        manager.setMode(.perDisplay, persistence: inMemPersistence)
    }

    // MARK: - T016 : currentStageID est dérivé de activeStageByDesktop

    /// currentStageID retourne la valeur de activeStageByDesktop pour currentDesktopKey.
    func test_currentStageID_derives_from_activeStageByDesktop() {
        let key = DesktopKey(displayUUID: uuidA, desktopID: 1)
        manager.setCurrentDesktopKey(key)
        let scope = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        _ = manager.createStage(id: StageID("2"), displayName: "S2", scope: scope)

        // Injecter directement dans activeStageByDesktop via le setter de currentStageID.
        manager.currentStageID = StageID("2")

        XCTAssertEqual(manager.currentStageID, StageID("2"),
                       "currentStageID doit retourner la valeur injectée dans activeStageByDesktop")
        XCTAssertEqual(manager.activeStageByDesktop[key], StageID("2"),
                       "activeStageByDesktop[currentDesktopKey] doit être la source de vérité")
    }

    // MARK: - T017 : setter de currentStageID met à jour activeStageByDesktop

    /// Assigner via currentStageID = X doit muter activeStageByDesktop[currentDesktopKey].
    func test_currentStageID_setter_updates_activeStageByDesktop() {
        let keyA = DesktopKey(displayUUID: uuidA, desktopID: 1)
        let keyB = DesktopKey(displayUUID: uuidB, desktopID: 1)
        manager.setCurrentDesktopKey(keyA)

        manager.currentStageID = StageID("3")

        XCTAssertEqual(manager.activeStageByDesktop[keyA], StageID("3"),
                       "Le setter de currentStageID doit muter activeStageByDesktop pour keyA")
        XCTAssertNil(manager.activeStageByDesktop[keyB],
                     "Le setter ne doit pas toucher au scope keyB")
    }

    // MARK: - T017-bis : currentStageID nil-setter retire la clé du dict

    func test_currentStageID_setter_nil_removes_key() {
        let key = DesktopKey(displayUUID: uuidA, desktopID: 1)
        manager.setCurrentDesktopKey(key)
        manager.currentStageID = StageID("1")
        XCTAssertNotNil(manager.activeStageByDesktop[key])

        manager.currentStageID = nil
        XCTAssertNil(manager.activeStageByDesktop[key],
                     "Setter nil doit retirer la clé de activeStageByDesktop")
    }

    // MARK: - T026 : switchTo(scopeB) ne touche pas scopeA (display A courant)

    /// Click sur stage 3 du display B ne change pas le stage actif du display A courant.
    func test_switchTo_scoped_does_not_affect_other_scope() throws {
        let keyA = DesktopKey(displayUUID: uuidA, desktopID: 1)
        let keyB = DesktopKey(displayUUID: uuidB, desktopID: 1)
        let scopeA2 = StageScope(displayUUID: uuidA, desktopID: 1, stageID: StageID("2"))
        let scopeB1 = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("1"))
        let scopeB3 = StageScope(displayUUID: uuidB, desktopID: 1, stageID: StageID("3"))

        _ = manager.createStage(id: StageID("2"), displayName: "A-Stage2", scope: scopeA2)
        _ = manager.createStage(id: StageID("1"), displayName: "B-Stage1", scope: scopeB1)
        _ = manager.createStage(id: StageID("3"), displayName: "B-Stage3", scope: scopeB3)

        // Initialiser B sur stage 1 : setCurrentDesktopKey(keyB) puis switcher vers "1".
        manager.setCurrentDesktopKey(keyB)
        manager.currentStageID = StageID("1")

        // Scope courant = display A, stage 2.
        manager.setCurrentDesktopKey(keyA)
        manager.currentStageID = StageID("2")

        // Switcher sur stage 3 du display B (scope distant).
        manager.switchTo(stageID: StageID("3"), scope: scopeB3)

        XCTAssertEqual(manager.activeStageByDesktop[keyB], StageID("3"),
                       "Display B doit basculer sur stage 3")
        XCTAssertEqual(manager.currentStageID, StageID("2"),
                       "currentStageID (display A courant) ne doit pas changer")
        XCTAssertEqual(manager.activeStageByDesktop[keyA], StageID("2"),
                       "activeStageByDesktop[keyA] ne doit pas être affecté")
    }

    // MARK: - T027 : switchTo(scope) persiste dans _active.toml du bon scope

    func test_switchTo_scoped_persists_to_correct_active_toml() throws {
        let scopeB2_stage3 = StageScope(displayUUID: uuidB, desktopID: 2, stageID: StageID("3"))

        _ = manager.createStage(id: StageID("3"), displayName: "B-D2-Stage3",
                                scope: scopeB2_stage3)
        manager.setCurrentDesktopKey(DesktopKey(displayUUID: uuidA, desktopID: 1))

        manager.switchTo(stageID: StageID("3"), scope: scopeB2_stage3)

        // Vérifier que inMemPersistence a capturé le bon scope.
        let saved = try inMemPersistence.loadActiveStage()
        XCTAssertEqual(saved?.displayUUID, uuidB, "Active stage persisté sur le bon display")
        XCTAssertEqual(saved?.desktopID, 2, "Active stage persisté sur le bon desktop")
        XCTAssertEqual(saved?.stageID, StageID("3"), "Active stage persisté avec le bon stageID")
    }
}
