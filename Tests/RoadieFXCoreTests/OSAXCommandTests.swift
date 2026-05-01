import XCTest
@testable import RoadieFXCore

final class OSAXCommandTests: XCTestCase {
    func testNoopJSON() {
        let cmd = OSAXCommand.noop
        let line = cmd.toJSONLine()
        XCTAssertTrue(line.contains("\"cmd\""))
        XCTAssertTrue(line.contains("noop"))
        XCTAssertTrue(line.hasSuffix("\n"))
    }

    func testSetAlphaJSON() throws {
        let cmd = OSAXCommand.setAlpha(wid: 12345, alpha: 0.7)
        let line = cmd.toJSONLine()
        let dict = try parseJSONLine(line)
        XCTAssertEqual(dict["cmd"] as? String, "set_alpha")
        XCTAssertEqual(dict["wid"] as? Int, 12345)
        XCTAssertEqual(dict["alpha"] as? Double ?? 0.0, 0.7, accuracy: 0.001)
    }

    func testSetTransformJSON() throws {
        let cmd = OSAXCommand.setTransform(wid: 99, scale: 0.95, tx: 10, ty: 0)
        let line = cmd.toJSONLine()
        let dict = try parseJSONLine(line)
        XCTAssertEqual(dict["cmd"] as? String, "set_transform")
        XCTAssertEqual(dict["scale"] as? Double ?? 0.0, 0.95, accuracy: 0.001)
        XCTAssertEqual(dict["tx"] as? Double ?? 0.0, 10, accuracy: 0.001)
    }

    private func parseJSONLine(_ line: String) throws -> [String: Any] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testMoveWindowToSpaceJSON() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let cmd = OSAXCommand.moveWindowToSpace(wid: 42, spaceUUID: uuid)
        let line = cmd.toJSONLine()
        XCTAssertTrue(line.contains("move_window_to_space"))
        XCTAssertTrue(line.contains(uuid))
    }

    func testResultParsingOK() {
        let r = OSAXResult(jsonLine: "{\"status\":\"ok\"}")
        XCTAssertEqual(r, .ok)
    }

    func testResultParsingError() {
        let r = OSAXResult(jsonLine: "{\"status\":\"error\",\"code\":\"wid_not_found\"}")
        guard case .error(let code, _) = r else {
            XCTFail("expected error"); return
        }
        XCTAssertEqual(code, "wid_not_found")
    }

    func testResultParsingErrorWithMessage() {
        let r = OSAXResult(jsonLine: "{\"status\":\"error\",\"code\":\"oops\",\"message\":\"details\"}")
        guard case .error(_, let msg) = r else {
            XCTFail("expected error"); return
        }
        XCTAssertEqual(msg, "details")
    }

    func testResultParsingMalformed() {
        XCTAssertNil(OSAXResult(jsonLine: "garbage"))
        XCTAssertNil(OSAXResult(jsonLine: ""))
    }

    func testEquality() {
        XCTAssertEqual(OSAXCommand.noop, OSAXCommand.noop)
        XCTAssertEqual(OSAXCommand.setAlpha(wid: 1, alpha: 0.5),
                       OSAXCommand.setAlpha(wid: 1, alpha: 0.5))
        XCTAssertNotEqual(OSAXCommand.setAlpha(wid: 1, alpha: 0.5),
                          OSAXCommand.setAlpha(wid: 2, alpha: 0.5))
    }
}
