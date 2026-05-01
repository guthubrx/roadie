import XCTest
import RoadieCore
@testable import RoadieTiler

final class TilerRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TilerRegistry.reset()
    }

    override func tearDown() {
        TilerRegistry.reset()
        super.tearDown()
    }

    func test_make_returns_nil_for_unregistered_strategy() {
        XCTAssertNil(TilerRegistry.make(.bsp))
        XCTAssertNil(TilerRegistry.make("papillon"))
    }

    func test_register_then_make_returns_instance() {
        BSPTiler.register()
        let tiler = TilerRegistry.make(.bsp)
        XCTAssertNotNil(tiler)
        XCTAssertTrue(tiler is BSPTiler)
    }

    func test_available_strategies_sorted() {
        BSPTiler.register()
        MasterStackTiler.register()
        let avail = TilerRegistry.availableStrategies.map(\.rawValue)
        XCTAssertEqual(avail, ["bsp", "masterStack"])
    }

    func test_register_third_party_strategy() {
        // Démontre l'isolation : on peut enregistrer un tiler arbitraire
        // sans modifier TilerRegistry, TilerStrategy ou LayoutEngine.
        TilerRegistry.register("papillon") { BSPTiler() }   // factory simulée
        XCTAssertNotNil(TilerRegistry.make("papillon"))
        XCTAssertTrue(TilerRegistry.availableStrategies.contains("papillon"))
    }

    func test_register_idempotent() {
        BSPTiler.register()
        BSPTiler.register()   // deuxième appel
        XCTAssertEqual(TilerRegistry.availableStrategies.count, 1)
    }

    func test_strategy_string_literal() {
        let s: TilerStrategy = "papillon"
        XCTAssertEqual(s.rawValue, "papillon")
    }

    func test_strategy_codable_round_trip() throws {
        let original: TilerStrategy = .bsp
        let data = try JSONEncoder().encode(original)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertEqual(json, "\"bsp\"")
        let decoded = try JSONDecoder().decode(TilerStrategy.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
