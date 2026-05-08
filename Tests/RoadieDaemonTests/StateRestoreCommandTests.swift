import Testing
import Foundation
import RoadieCore
import RoadieDaemon

@Suite
struct StateRestoreCommandTests {
    @Test
    func restoreV2ReportEncodesForCLI() throws {
        let report = LayoutPersistenceV2Report(matches: [
            WindowIdentityMatch(savedWindowID: 1, liveWindowID: 2, score: 0.9, accepted: true, reason: "identity")
        ], applied: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(report), as: UTF8.self)

        #expect(json.contains("\"applied\":false"))
        #expect(json.contains("\"liveWindowID\":2"))
    }
}
