import XCTest
import RoadieCore
@testable import RoadieStagePlugin

final class StageTests: XCTestCase {
    func test_stage_serialization_round_trip() throws {
        var stage = Stage(id: StageID("dev"), displayName: "Development")
        stage.memberWindows = [
            StageMember(cgWindowID: 100, bundleID: "com.apple.Terminal",
                       titleHint: "~/code", savedFrame: SavedRect(CGRect(x: 0, y: 0, width: 100, height: 200)))
        ]
        let encoder = JSONEncoder()
        let data = try encoder.encode(stage)
        let decoded = try JSONDecoder().decode(Stage.self, from: data)
        XCTAssertEqual(decoded.id, stage.id)
        XCTAssertEqual(decoded.displayName, stage.displayName)
        XCTAssertEqual(decoded.memberWindows.count, 1)
        XCTAssertEqual(decoded.memberWindows[0].bundleID, "com.apple.Terminal")
        XCTAssertEqual(decoded.memberWindows[0].savedFrame?.cgRect, CGRect(x: 0, y: 0, width: 100, height: 200))
    }

    func test_saved_rect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 400)
        let saved = SavedRect(rect)
        XCTAssertEqual(saved.cgRect, rect)
    }
}
