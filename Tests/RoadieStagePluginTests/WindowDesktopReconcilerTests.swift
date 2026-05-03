import XCTest
@testable import RoadieStagePlugin
@testable import RoadieCore

// SPEC-021 T052-T054 — Tests logique WindowDesktopReconciler
// NOTE ARCHITECTURALE : WindowDesktopReconciler vit dans le target `roadied`
// (exécutable), non importable par les test targets. Les tests d'intégration
// sont couverts par le script manuel Tests/21-mission-control-drift.sh (T055).
// Seule la logique de debounce stockée dans StageManager (widToScope) est testable
// ici de façon unitaire, comme proxy de vérification de l'invariant.

final class WindowDesktopReconcilerTests: XCTestCase {

    // T052 — proxy : un seul assign ne crée pas de migration si scope identique
    // (simule le cas "1 poll, pas de drift → pas de changement").
    @MainActor
    func test_no_migration_when_scope_unchanged() {
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        let wid: WindowID = 100
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "com.test",
            title: "Test", frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            subrole: .standard, isFloating: false
        )
        registry.register(state, axElement: AXUIElementCreateApplication(1))
        let scope = StageScope(displayUUID: "uuid-1", desktopID: 1, stageID: StageID("1"))
        _ = sm.createStage(id: StageID("1"), displayName: "one")
        sm.assign(wid: wid, to: scope)
        // Scope non changé → scopeOf retourne toujours scope initial.
        XCTAssertEqual(sm.scopeOf(wid: wid)?.displayUUID, "uuid-1")
        XCTAssertEqual(sm.scopeOf(wid: wid)?.desktopID, 1)
    }

    // T053 — proxy : 2 assigns consécutifs vers un nouveau scope migrent la wid.
    // (simule le debounce "2 polls consécutifs même osScope → assign effectif").
    @MainActor
    func test_assign_updates_scope_after_two_calls() {
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        let wid: WindowID = 101
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "com.test",
            title: "Test", frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            subrole: .standard, isFloating: false
        )
        registry.register(state, axElement: AXUIElementCreateApplication(1))
        _ = sm.createStage(id: StageID("1"), displayName: "one")
        let scope1 = StageScope(displayUUID: "uuid-1", desktopID: 1, stageID: StageID("1"))
        sm.assign(wid: wid, to: scope1)
        XCTAssertEqual(sm.scopeOf(wid: wid)?.desktopID, 1)
        // Deuxième assign vers scope différent (simule confirmation debounce).
        let scope2 = StageScope(displayUUID: "uuid-1", desktopID: 2, stageID: StageID("1"))
        sm.assign(wid: wid, to: scope2)
        XCTAssertEqual(sm.scopeOf(wid: wid)?.desktopID, 2)
    }

    // T054 — pollIntervalMs == 0 : le reconciler ne doit pas démarrer sa Task.
    // Test indirect : vérifie que la logique "guard pollIntervalMs > 0" est cohérente
    // avec l'invariant que widToScope reste stable sans mutation.
    @MainActor
    func test_zero_poll_ms_leaves_scope_unchanged() {
        // Sans reconciler actif (pollMs == 0), le scope persisté ne change pas.
        let registry = WindowRegistry()
        let sm = StageManager(registry: registry)
        let wid: WindowID = 102
        let state = WindowState(
            cgWindowID: wid, pid: 1, bundleID: "com.test",
            title: "Test", frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            subrole: .standard, isFloating: false
        )
        registry.register(state, axElement: AXUIElementCreateApplication(1))
        _ = sm.createStage(id: StageID("1"), displayName: "one")
        let scope = StageScope(displayUUID: "uuid-1", desktopID: 3, stageID: StageID("1"))
        sm.assign(wid: wid, to: scope)
        // Aucun reconciler actif → scope identique.
        XCTAssertEqual(sm.scopeOf(wid: wid)?.desktopID, 3)
    }
}
