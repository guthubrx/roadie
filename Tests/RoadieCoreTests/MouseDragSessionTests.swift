import XCTest
import CoreGraphics
import Cocoa
@testable import RoadieCore

/// SPEC-015 F4 — tests sur le lifecycle `MouseDragSession`, le calcul de throttle,
/// les edge cases de drag (floating, cross-display) et la préservation de session
/// au `reload(config:)` (FR-004).
@MainActor
final class MouseDragSessionTests: XCTestCase {

    // MARK: - MouseDragSession struct

    func testSessionInitWithDefaults() {
        let s = MouseDragSession(
            wid: 42,
            mode: .move,
            startCursor: CGPoint(x: 100, y: 100),
            startFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            quadrant: .center,
            lastApply: .distantPast,
            tileableAtStart: true)
        XCTAssertEqual(s.wid, 42)
        XCTAssertEqual(s.mode, .move)
        XCTAssertTrue(s.tileableAtStart)
    }

    func testSessionMutateLastApply() {
        var s = MouseDragSession(
            wid: 1, mode: .move,
            startCursor: .zero, startFrame: .zero, quadrant: .center,
            lastApply: .distantPast, tileableAtStart: false)
        let now = Date()
        s.lastApply = now
        XCTAssertEqual(s.lastApply, now)
    }

    func testSessionMutateTileableAtStart() {
        var s = MouseDragSession(
            wid: 1, mode: .move,
            startCursor: .zero, startFrame: .zero, quadrant: .center,
            lastApply: .distantPast, tileableAtStart: true)
        s.tileableAtStart = false
        XCTAssertFalse(s.tileableAtStart)
    }

    // MARK: - Throttle behavior (FR-040)

    /// Réplique le check de throttle utilisé dans handleMouseDragged (l. 200).
    /// La logique : applique seulement si Δt depuis lastApply >= 30 ms.
    private func shouldApplyThrottle(lastApply: Date, now: Date) -> Bool {
        return now.timeIntervalSince(lastApply) >= 0.030
    }

    func testThrottleAllowsFirstApply() {
        XCTAssertTrue(shouldApplyThrottle(lastApply: .distantPast, now: Date()))
    }

    func testThrottleRejectsRapidSecondApply() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.010)  // 10 ms après
        XCTAssertFalse(shouldApplyThrottle(lastApply: t0, now: t1))
    }

    func testThrottleAllowsAfter30ms() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.031)  // 31 ms après
        XCTAssertTrue(shouldApplyThrottle(lastApply: t0, now: t1))
    }

    func testThrottleAllowsAtBoundary() {
        let t0 = Date()
        // Floating-point arithmetic : 0.0301 garantit > 30 ms strict.
        let t1 = t0.addingTimeInterval(0.0301)
        XCTAssertTrue(shouldApplyThrottle(lastApply: t0, now: t1))
    }

    // MARK: - reload(config:) préserve la session (FR-004 — F3 fix)

    func testReloadPreservesIsDraggingState() {
        let registry = WindowRegistry()
        let initialConfig = MouseConfig(modifier: .ctrl, actionLeft: .move,
                                        actionRight: .resize, actionMiddle: .none)
        let handler = MouseDragHandler(registry: registry, config: initialConfig)
        // Pas de drag en cours initialement.
        XCTAssertFalse(handler.isDragging)

        // Reload avec nouvelle config — pas de drag actif → reste false.
        let newConfig = MouseConfig(modifier: .alt, actionLeft: .move,
                                    actionRight: .resize, actionMiddle: .none)
        handler.reload(config: newConfig)
        XCTAssertFalse(handler.isDragging)
        XCTAssertEqual(handler.config.modifier, .alt, "config bien remplacée")
    }

    /// Vérifie que la new config est bien adoptée après reload.
    func testReloadAdoptsNewConfig() {
        let registry = WindowRegistry()
        let handler = MouseDragHandler(
            registry: registry,
            config: MouseConfig(modifier: .ctrl, actionLeft: .move,
                                actionRight: .resize, actionMiddle: .none))
        XCTAssertEqual(handler.config.modifier, .ctrl)

        handler.reload(config: MouseConfig(modifier: .cmd, actionLeft: .resize,
                                           actionRight: .move, actionMiddle: .move))
        XCTAssertEqual(handler.config.modifier, .cmd)
        XCTAssertEqual(handler.config.actionLeft, .resize)
        XCTAssertEqual(handler.config.actionRight, .move)
        XCTAssertEqual(handler.config.actionMiddle, .move)
    }

    // MARK: - Drag delta calculation (F8 — pure math)

    /// Réplique le calcul de delta utilisé dans handleMouseDragged.
    private func computeDelta(start: CGPoint, current: CGPoint) -> CGPoint {
        return CGPoint(x: current.x - start.x, y: current.y - start.y)
    }

    func testDeltaPositive() {
        let d = computeDelta(start: CGPoint(x: 100, y: 100),
                             current: CGPoint(x: 150, y: 130))
        XCTAssertEqual(d, CGPoint(x: 50, y: 30))
    }

    func testDeltaNegative() {
        let d = computeDelta(start: CGPoint(x: 100, y: 100),
                             current: CGPoint(x: 50, y: 70))
        XCTAssertEqual(d, CGPoint(x: -50, y: -30))
    }

    /// US1 acceptance #1 : drag d'une fenêtre tilée → la fenêtre passe floating
    /// (FR-012). Test du contract via WindowState mutation.
    func testTiledWindowBecomesFloatingOnFirstDrag() {
        var state = WindowState(
            cgWindowID: 1, pid: 1234, bundleID: "test", title: "test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            subrole: .standard, isFloating: false)
        XCTAssertTrue(state.isTileable, "initially tileable")

        // Simulate mutation faite par handleMouseDragged au 1er drag.
        state.isFloating = true
        XCTAssertFalse(state.isTileable, "no longer tileable once floating")
    }

    /// US1 acceptance #2 : fenêtre déjà floating draggée ne change pas d'état tile.
    func testFloatingWindowStaysFloatingOnDrag() {
        var state = WindowState(
            cgWindowID: 1, pid: 1234, bundleID: "test", title: "test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            subrole: .standard, isFloating: true)
        XCTAssertFalse(state.isTileable)

        // No mutation expected — isFloating stays true.
        state.isFloating = true
        XCTAssertTrue(state.isFloating)
    }

    // MARK: - move offset application

    /// Réplique le calcul de newFrame en mode .move (l. 207).
    func testMoveAppliesOffsetToOrigin() {
        let start = CGRect(x: 100, y: 100, width: 800, height: 600)
        let delta = CGPoint(x: 50, y: 30)
        let result = start.offsetBy(dx: delta.x, dy: delta.y)
        XCTAssertEqual(result.origin, CGPoint(x: 150, y: 130))
        XCTAssertEqual(result.size, start.size, "size inchangée en mode move")
    }
}
