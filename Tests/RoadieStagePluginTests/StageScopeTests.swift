import XCTest
import RoadieCore
@testable import RoadieStagePlugin

final class StageScopeTests: XCTestCase {

    // MARK: - Hashable

    func test_hashable_equal_scopes_have_same_hash() {
        let a = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("2"))
        let b = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("2"))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_different_display_uuid_not_equal() {
        let a = StageScope(displayUUID: "AAA", desktopID: 1, stageID: StageID("1"))
        let b = StageScope(displayUUID: "BBB", desktopID: 1, stageID: StageID("1"))
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_different_desktop_id_not_equal() {
        let a = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("1"))
        let b = StageScope(displayUUID: "ABC", desktopID: 2, stageID: StageID("1"))
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_different_stage_id_not_equal() {
        let a = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("1"))
        let b = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("2"))
        XCTAssertNotEqual(a, b)
    }

    func test_usable_as_dictionary_key() {
        let scope = StageScope(displayUUID: "XYZ", desktopID: 3, stageID: StageID("5"))
        var dict: [StageScope: String] = [:]
        dict[scope] = "hello"
        XCTAssertEqual(dict[scope], "hello")
    }

    // MARK: - Codable

    func test_codable_round_trip() throws {
        let original = StageScope(displayUUID: "DEADBEEF", desktopID: 4, stageID: StageID("7"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StageScope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.displayUUID, "DEADBEEF")
        XCTAssertEqual(decoded.desktopID, 4)
        XCTAssertEqual(decoded.stageID.value, "7")
    }

    func test_codable_round_trip_global_sentinel() throws {
        let original = StageScope.global(StageID("1"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StageScope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isGlobal)
    }

    // MARK: - global sentinel

    func test_global_sentinel_has_empty_display_uuid() {
        let scope = StageScope.global(StageID("1"))
        XCTAssertEqual(scope.displayUUID, "")
        XCTAssertEqual(scope.desktopID, 0)
        XCTAssertTrue(scope.isGlobal)
    }

    func test_normal_scope_is_not_global() {
        let scope = StageScope(displayUUID: "ABC", desktopID: 1, stageID: StageID("2"))
        XCTAssertFalse(scope.isGlobal)
    }

    func test_global_sentinels_with_same_stage_are_equal() {
        let a = StageScope.global(StageID("3"))
        let b = StageScope.global(StageID("3"))
        XCTAssertEqual(a, b)
    }

    func test_global_sentinels_with_different_stages_are_not_equal() {
        let a = StageScope.global(StageID("1"))
        let b = StageScope.global(StageID("2"))
        XCTAssertNotEqual(a, b)
    }
}
