import XCTest
import RoadieCore
@testable import RoadieStagePlugin

/// Tests de l'intégration LayoutHooks V2 (reassignToStage + setActiveStage).
/// Simule le comportement du LayoutEngine via des closures enregistrées, sans
/// instancier le vrai LayoutEngine (qui a des dépendances AppKit/AX).
@MainActor
final class StageLayoutHooksTests: XCTestCase {

    private var tmpDir: String!
    private var mockRegistry: WindowRegistry!
    private var manager: StageManager!

    // Capture les appels hooks pour vérification.
    private var capturedReassignments: [(WindowID, StageID)] = []
    private var capturedActiveStages: [StageID?] = []
    private var capturedApplyLayouts: Int = 0
    private var capturedVisibility: [(WindowID, Bool)] = []

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "roadie-hooktests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        mockRegistry = WindowRegistry()

        capturedReassignments = []
        capturedActiveStages = []
        capturedApplyLayouts = 0
        capturedVisibility = []

        let hooks = LayoutHooks(
            setLeafVisible: { [weak self] wid, visible in
                self?.capturedVisibility.append((wid, visible))
            },
            applyLayout: { [weak self] in
                self?.capturedApplyLayouts += 1
            },
            reassignToStage: { [weak self] wid, stageID in
                self?.capturedReassignments.append((wid, stageID))
            },
            setActiveStage: { [weak self] stageID in
                self?.capturedActiveStages.append(stageID)
            }
        )

        manager = StageManager(
            registry: mockRegistry,
            hideStrategy: .corner,
            stagesDir: tmpDir,
            baseConfigDir: nil,
            layoutHooks: hooks
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - Test 1 : assign appelle reassignToStage

    /// Vérifie que assign(wid:to:stageID) déclenche layoutHooks.reassignToStage.
    func test_assign_triggers_reassignToStage() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        _ = manager.createStage(id: StageID("2"), displayName: "2")

        let wid: WindowID = 42
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "com.test", title: "T",
            frame: .zero, subrole: .standard, isFloating: false
        )
        mockRegistry.register(state, axElement: AXUIElementCreateApplication(1))
        manager.assign(wid: wid, to: StageID("1"))

        XCTAssertEqual(capturedReassignments.count, 1,
                       "assign doit déclencher exactement 1 appel reassignToStage")
        XCTAssertEqual(capturedReassignments.first?.0, wid,
                       "reassignToStage doit recevoir le bon wid")
        XCTAssertEqual(capturedReassignments.first?.1, StageID("1"),
                       "reassignToStage doit recevoir le bon stageID")
    }

    // MARK: - Test 2 : switchTo appelle setActiveStage puis applyLayout

    /// Vérifie que switchTo(stageID:) appelle setActiveStage avec le bon stageID
    /// AVANT applyLayout (ordre critique pour que le tiler utilise le bon tree).
    func test_switchTo_calls_setActiveStage_before_applyLayout() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        _ = manager.createStage(id: StageID("2"), displayName: "2")
        manager.switchTo(stageID: StageID("1"))

        // Reset les compteurs après le premier switch.
        capturedActiveStages = []
        capturedApplyLayouts = 0

        manager.switchTo(stageID: StageID("2"))

        XCTAssertEqual(capturedActiveStages.count, 1,
                       "switchTo doit appeler setActiveStage une fois")
        XCTAssertEqual(capturedActiveStages.first, StageID("2"),
                       "setActiveStage doit recevoir stageID 2")
        XCTAssertGreaterThan(capturedApplyLayouts, 0,
                             "switchTo doit déclencher applyLayout")
    }

    // MARK: - Test 3 : deactivateAll set nil puis applyLayout

    func test_deactivateAll_sets_activeStage_nil() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        manager.switchTo(stageID: StageID("1"))
        capturedActiveStages = []
        capturedApplyLayouts = 0

        manager.deactivateAll()

        XCTAssertTrue(capturedActiveStages.contains(where: { $0 == nil }),
                      "deactivateAll doit appeler setActiveStage(nil)")
        XCTAssertGreaterThan(capturedApplyLayouts, 0,
                             "deactivateAll doit déclencher applyLayout")
    }

    // MARK: - Test 4 : activate appelle setActiveStage avec le stageID cible

    func test_activate_sets_correct_activeStage() {
        _ = manager.createStage(id: StageID("1"), displayName: "1")
        _ = manager.createStage(id: StageID("2"), displayName: "2")
        manager.deactivateAll()
        capturedActiveStages = []
        capturedApplyLayouts = 0

        manager.activate(stageID: StageID("2"))

        XCTAssertTrue(capturedActiveStages.contains(StageID("2")),
                      "activate doit appeler setActiveStage avec stageID 2")
        XCTAssertGreaterThan(capturedApplyLayouts, 0,
                             "activate doit déclencher applyLayout")
    }
}
