import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct ControlCommandTests {
    @Test
    func controlStatusJSONEncodesContractFields() throws {
        let state = ControlCenterState(
            daemonStatus: .running,
            configPath: "/tmp/roadies.toml",
            configStatus: .valid,
            activeDesktop: "1",
            activeStage: "dev",
            windowCount: 2
        )

        let json = try SnapshotEncoding.json(state, pretty: false)

        #expect(json.contains("\"daemonStatus\":\"running\""))
        #expect(json.contains("\"configStatus\":\"valid\""))
        #expect(json.contains("\"activeDesktop\":\"1\""))
        #expect(json.contains("\"activeStage\":\"dev\""))
        #expect(json.contains("\"windowCount\":2"))
    }
}
