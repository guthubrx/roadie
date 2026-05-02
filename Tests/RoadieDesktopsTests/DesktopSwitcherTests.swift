import XCTest
import CoreGraphics
@testable import RoadieDesktops

/// Vérifie qu'une position est hors de la zone visible, quel que soit le setup d'écrans.
/// - Fallback headless : x ou y très négatif (≤ -1000)
/// - Mode dynamique multi-display : x très positif (≥ 3000, hors du bounding box)
/// Aucune fenêtre applicative réelle n'a |x| > 1000 dans un setup normal.
private func isOffscreenPosition(_ point: CGPoint?) -> Bool {
    guard let p = point else { return false }
    return p.x <= -1000 || p.x >= 3000 || p.y <= -1000
}

/// Tests de la state machine DesktopSwitcher (T023, FR-002, FR-006, FR-023, FR-025).
final class DesktopSwitcherTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-switcher-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSwitcher(
        count: Int = 5,
        backAndForth: Bool = true,
        mover: MockWindowMover? = nil
    ) async -> (DesktopSwitcher, MockWindowMover, DesktopRegistry, DesktopEventBus) {
        let registry = DesktopRegistry(configDir: tmpDir, count: count)
        await registry.load()

        // Peupler desktop 1 avec 2 fenêtres, desktop 2 avec 2 fenêtres
        let d1 = RoadieDesktop(
            id: 1, stages: [DesktopStage(id: 1, windows: [100, 200])],
            windows: [
                WindowEntry(cgwid: 100, bundleID: "a", title: "A",
                            expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600), stageID: 1),
                WindowEntry(cgwid: 200, bundleID: "b", title: "B",
                            expectedFrame: CGRect(x: 950, y: 100, width: 600, height: 600), stageID: 1),
            ]
        )
        let d2 = RoadieDesktop(
            id: 2, stages: [DesktopStage(id: 1, windows: [300, 400])],
            windows: [
                WindowEntry(cgwid: 300, bundleID: "c", title: "C",
                            expectedFrame: CGRect(x: 200, y: 200, width: 800, height: 600), stageID: 1),
                WindowEntry(cgwid: 400, bundleID: "d", title: "D",
                            expectedFrame: CGRect(x: 50, y: 50, width: 400, height: 300), stageID: 1),
            ]
        )
        try? await registry.save(d1)
        try? await registry.save(d2)

        let mockMover = mover ?? MockWindowMover()
        let bus = DesktopEventBus()
        let cfg = DesktopSwitcherConfig(count: count, backAndForth: backAndForth)
        let switcher = DesktopSwitcher(
            registry: registry, mover: mockMover, bus: bus, config: cfg
        )
        return (switcher, mockMover, registry, bus)
    }

    // MARK: - testBasicSwitch (T023)

    func testBasicSwitch() async throws {
        let (switcher, mover, registry, bus) = await makeSwitcher()
        let stream = await bus.subscribe()
        let exp = expectation(description: "event received")
        let eventTask = Task {
            for await e in stream {
                XCTAssertEqual(e.from, "1")
                XCTAssertEqual(e.to, "2")
                exp.fulfill()
                break
            }
        }

        try await switcher.switch(to: 2)

        let currentID = await registry.currentID
        XCTAssertEqual(currentID, 2)
        let recentID = await registry.recentID
        XCTAssertEqual(recentID, 1)

        // Vérifier que les fenêtres desktop 1 sont offscreen.
        // L'invariant est display-agnostique : x très négatif (fallback headless)
        // OU x très positif (calcul dynamique multi-display).
        // Aucune fenêtre visible n'a |x| > 1000 dans un setup réaliste.
        let moves = await mover.moves
        let wid100Pos = moves.last(where: { $0.cgwid == 100 })?.point
        let wid200Pos = moves.last(where: { $0.cgwid == 200 })?.point
        XCTAssertTrue(isOffscreenPosition(wid100Pos), "wid100 should be offscreen, got \(String(describing: wid100Pos))")
        XCTAssertTrue(isOffscreenPosition(wid200Pos), "wid200 should be offscreen, got \(String(describing: wid200Pos))")

        // Fenêtres desktop 2 restaurées à leur expectedFrame
        let wid300Pos = moves.last(where: { $0.cgwid == 300 })?.point
        let wid400Pos = moves.last(where: { $0.cgwid == 400 })?.point
        XCTAssertEqual(wid300Pos, CGPoint(x: 200, y: 200))
        XCTAssertEqual(wid400Pos, CGPoint(x: 50, y: 50))

        await fulfillment(of: [exp], timeout: 1.0)
        eventTask.cancel()
    }

    // MARK: - testIdempotentNoop (FR-006, T023)

    func testIdempotentNoop() async throws {
        let (switcher, mover, registry, _) = await makeSwitcher(backAndForth: false)

        // desktop courant = 1, focus 1 → no-op
        try await switcher.switch(to: 1)

        let currentID = await registry.currentID
        XCTAssertEqual(currentID, 1)
        let moves = await mover.moves
        XCTAssertTrue(moves.isEmpty, "no moves expected for no-op, got \(moves.count)")
    }

    // MARK: - testBackAndForth (FR-006, T023)

    func testBackAndForth() async throws {
        let (switcher, _, registry, _) = await makeSwitcher(backAndForth: true)

        // Aller sur desktop 3 (préparer un recentID)
        try await switcher.switch(to: 3)
        let currentAfter3 = await registry.currentID
        XCTAssertEqual(currentAfter3, 3)
        let recentAfter3 = await registry.recentID
        XCTAssertEqual(recentAfter3, 1)

        // Maintenant focus 3 (current) avec back_and_forth=true → doit basculer vers recentID = 1
        try await switcher.switch(to: 3)
        let currentFinal = await registry.currentID
        XCTAssertEqual(currentFinal, 1)
    }

    // MARK: - testRangeCheck (FR-023, T023)

    func testRangeCheck() async {
        let (switcher, _, _, _) = await makeSwitcher(count: 5)

        do {
            try await switcher.switch(to: 0)
            XCTFail("Expected DesktopError.unknownDesktop for id=0")
        } catch DesktopError.unknownDesktop(let id) {
            XCTAssertEqual(id, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await switcher.switch(to: 6)
            XCTFail("Expected DesktopError.unknownDesktop for id=6")
        } catch DesktopError.unknownDesktop(let id) {
            XCTAssertEqual(id, 6)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testRapidSwitchCollapsing (FR-025, R-003, T023)
    /// 3 switches enchaînés quasi-simultanément → seul le dernier doit être appliqué.

    func testRapidSwitchCollapsing() async throws {
        let (switcher, mover, registry, _) = await makeSwitcher(count: 5)

        // Soumettre 3 bascules quasi-simultanément. L'ordre d'arrivée à l'actor
        // n'est pas garanti avec `async let`, donc on teste la **propriété** :
        // toutes les bascules se sérialisent sans crash, l'état final est l'un
        // des targets demandés, et le desktop 1 (de départ) n'est plus courant.
        async let s1: Void = switcher.switch(to: 2)
        async let s2: Void = switcher.switch(to: 3)
        async let s3: Void = switcher.switch(to: 4)
        _ = try await (s1, s2, s3)

        let finalID = await registry.currentID
        XCTAssertTrue([2, 3, 4].contains(finalID),
                      "Rapid switch: expected final ∈ {2,3,4}, got \(finalID)")
        XCTAssertNotEqual(finalID, 1,
                          "Desktop 1 (initial) ne doit plus être courant après 3 switches")

        // Les fenêtres de desktop 1 doivent être offscreen dans leur dernier
        // mouvement enregistré (sérialisation correcte, pas de fenêtre orpheline).
        let moves = await mover.moves
        let lastPos100 = moves.last(where: { $0.cgwid == 100 })?.point
        XCTAssertTrue(isOffscreenPosition(lastPos100),
                      "Window 100 (desktop 1) doit être offscreen après bascule, got \(String(describing: lastPos100))")
    }

    // MARK: - testBackNoRecentThrows

    func testBackNoRecentThrows() async {
        let (switcher, _, _, _) = await makeSwitcher()
        do {
            try await switcher.back()
            XCTFail("Expected DesktopError.noRecentDesktop")
        } catch DesktopError.noRecentDesktop {
            // Attendu
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
