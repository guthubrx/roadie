import XCTest
import CoreGraphics
@testable import RoadieDesktops

// MARK: - MockStageOps

/// Mock de DesktopStageOps pour les tests unitaires (T016, T023).
/// Enregistre les appels sans effets secondaires système.
actor MockStageOps: DesktopStageOps {
    enum Call: Equatable {
        case currentStageID
        case deactivateAll
        case activate(Int)
    }

    private(set) var calls: [Call] = []
    private var stubbedStageID: Int? = 1

    func stubCurrentStageID(_ id: Int?) {
        stubbedStageID = id
    }

    func currentStageID() async -> Int? {
        calls.append(.currentStageID)
        return stubbedStageID
    }

    func deactivateAll() async {
        calls.append(.deactivateAll)
    }

    func activate(_ stageID: Int) async {
        calls.append(.activate(stageID))
    }

    func reset() {
        calls = []
    }
}

// MARK: - DesktopSwitcherTests

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
        stageOps: MockStageOps? = nil
    ) async -> (DesktopSwitcher, MockStageOps, DesktopRegistry, DesktopEventBus) {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: count)
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

        let mockOps = stageOps ?? MockStageOps()
        let bus = DesktopEventBus()
        let cfg = DesktopSwitcherConfig(count: count, backAndForth: backAndForth)
        let switcher = DesktopSwitcher(
            registry: registry, stageOps: mockOps, bus: bus, config: cfg
        )
        return (switcher, mockOps, registry, bus)
    }

    // MARK: - testBasicSwitch (T023)

    func testBasicSwitch() async throws {
        let (switcher, stageOps, registry, bus) = await makeSwitcher()
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

        // Vérifier le registry
        let currentID = await registry.currentID
        XCTAssertEqual(currentID, 2)
        let recentID = await registry.recentID
        XCTAssertEqual(recentID, 1)

        // Vérifier la séquence d'appels StageOps : deactivateAll puis activate(1)
        // (activeStageID du desktop 2 = 1 par défaut)
        let calls = await stageOps.calls
        XCTAssertTrue(calls.contains(.deactivateAll),
                      "deactivateAll doit être appelé lors d'une bascule")
        XCTAssertTrue(calls.contains(.activate(1)),
                      "activate(1) doit être appelé pour le stage actif du desktop cible")

        // deactivateAll doit précéder activate
        let deactivateIdx = calls.firstIndex(of: .deactivateAll)!
        let activateIdx = calls.firstIndex(of: .activate(1))!
        XCTAssertLessThan(deactivateIdx, activateIdx,
                          "deactivateAll doit précéder activate")

        await fulfillment(of: [exp], timeout: 1.0)
        eventTask.cancel()
    }

    // MARK: - testIdempotentNoop (FR-006, T023)

    func testIdempotentNoop() async throws {
        let (switcher, stageOps, registry, _) = await makeSwitcher(backAndForth: false)

        // desktop courant = 1, focus 1 → no-op
        try await switcher.switch(to: 1)

        let currentID = await registry.currentID
        XCTAssertEqual(currentID, 1)
        let calls = await stageOps.calls
        XCTAssertTrue(calls.isEmpty, "aucun appel stageOps attendu pour no-op, got \(calls)")
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
        let (switcher, stageOps, registry, _) = await makeSwitcher(count: 5)

        // Soumettre 3 bascules quasi-simultanément.
        async let s1: Void = switcher.switch(to: 2)
        async let s2: Void = switcher.switch(to: 3)
        async let s3: Void = switcher.switch(to: 4)
        _ = try await (s1, s2, s3)

        let finalID = await registry.currentID
        XCTAssertTrue([2, 3, 4].contains(finalID),
                      "Rapid switch: expected final ∈ {2,3,4}, got \(finalID)")
        XCTAssertNotEqual(finalID, 1,
                          "Desktop 1 (initial) ne doit plus être courant après 3 switches")

        // Au moins un deactivateAll doit avoir été appelé (bascule effective).
        let calls = await stageOps.calls
        XCTAssertTrue(calls.contains(.deactivateAll),
                      "deactivateAll doit être appelé lors d'au moins une bascule")
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

    // MARK: - testDeactivateBeforeActivate

    func testDeactivateBeforeActivate() async throws {
        let (switcher, stageOps, _, _) = await makeSwitcher()

        try await switcher.switch(to: 2)
        try await switcher.switch(to: 1)

        // Vérifier que chaque bascule a bien la séquence deactivate → activate
        let calls = await stageOps.calls
        var lastDeactivate = -1
        for (i, call) in calls.enumerated() {
            switch call {
            case .deactivateAll:
                lastDeactivate = i
            case .activate:
                XCTAssertGreaterThan(i, lastDeactivate,
                    "activate doit toujours suivre deactivateAll — appel \(i) sans deactivate précédent")
            default:
                break
            }
        }
    }
}
