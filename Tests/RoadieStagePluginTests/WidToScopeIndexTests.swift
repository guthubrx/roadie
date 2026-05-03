import XCTest
@testable import RoadieStagePlugin
@testable import RoadieCore

// SPEC-021 — Tests de l'index inverse widToScope (T020, T034-T038)
// Source de vérité : StageManager.widToScope + widToStageV1
final class WidToScopeIndexTests: XCTestCase {

    // T020 — test minimal : scopeOf retourne nil pour une wid inconnue
    @MainActor
    func test_scopeOf_returns_nil_for_unknown_wid() {
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        XCTAssertNil(sm.scopeOf(wid: 9999))
        XCTAssertNil(sm.stageIDOf(wid: 9999))
    }

    // T036 — widToScope mis à jour lors d'un assign V1
    @MainActor
    func test_widToScope_updated_on_assign_v1() {
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        let wid: WindowID = 42
        let state = WindowState(cgWindowID: wid, pid: 1, bundleID: "com.test",
                                title: "Test", frame: CGRect(x: 0, y: 0, width: 200, height: 200),
                                subrole: .standard, isFloating: false)
        registry.register(state, axElement: AXUIElementCreateApplication(1))
        _ = sm.createStage(id: StageID("1"), displayName: "one")
        sm.assign(wid: wid, to: StageID("1"))
        XCTAssertEqual(sm.stageIDOf(wid: wid), StageID("1"))
    }

    // T038 — rebuildWidToScopeIndex est idempotent
    @MainActor
    func test_rebuildWidToScopeIndex_idempotent() {
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        sm.rebuildWidToScopeIndex()
        sm.rebuildWidToScopeIndex()
        // Deux reconstructions consécutives ne doivent pas planter ni se contredire.
        XCTAssertNil(sm.stageIDOf(wid: 0))
    }
}
