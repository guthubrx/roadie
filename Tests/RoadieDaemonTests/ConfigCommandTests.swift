import Testing
import RoadieDaemon

@Suite
struct ConfigCommandTests {
    @Test
    func configReloadResultEncodesSnakeCaseJSON() throws {
        let result = ConfigReloadResult(
            status: .failedKeepingPrevious,
            path: "/tmp/roadies.toml",
            error: "invalid",
            activeVersion: "bytes:1:2"
        )

        let json = try SnapshotEncoding.json(result, pretty: false)

        #expect(json.contains("\"status\":\"failed_keeping_previous\""))
        #expect(json.contains("\"active_version\":\"bytes:1:2\""))
        #expect(json.contains("\"error\":\"invalid\""))
    }
}
