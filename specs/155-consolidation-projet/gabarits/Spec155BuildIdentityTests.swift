import Foundation
import Testing
@testable import RoadieDaemon

@Suite struct Spec155BuildIdentityTests {
    private func plist(_ entries: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie155-\(UUID().uuidString).plist")
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0).write(to: url)
        return url
    }

    @Test func commitIsReadFromInfoPlist() throws {
        let url = try plist(["RoadieBuildCommit": "0b7de36b"])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(RoadieVersion.buildCommit(infoPlist: url) == "0b7de36b")
    }

    @Test func missingKeyEmptyValueAndMissingFileGiveNoCommit() throws {
        let withoutKey = try plist(["CFBundleName": "Roadie"])
        let emptyValue = try plist(["RoadieBuildCommit": ""])
        defer {
            try? FileManager.default.removeItem(at: withoutKey)
            try? FileManager.default.removeItem(at: emptyValue)
        }
        #expect(RoadieVersion.buildCommit(infoPlist: withoutKey) == nil)
        #expect(RoadieVersion.buildCommit(infoPlist: emptyValue) == nil)
        #expect(RoadieVersion.buildCommit(infoPlist: URL(fileURLWithPath: "/nonexistent/roadie155/Info.plist")) == nil)
    }

    @Test func displayAddsTheCommitInParentheses() {
        #expect(RoadieVersion.display(commit: "0b7de36b-dirty") == "\(RoadieVersion.current) (0b7de36b-dirty)")
        #expect(RoadieVersion.display(commit: nil) == RoadieVersion.current)
    }

    @Test func statusCarriesTheCommitAndStillReadsOlderFiles() throws {
        let moment = Date(timeIntervalSince1970: 0)
        let status = DaemonStatus(
            pid: 1, mode: "bsp", startedAt: moment, updatedAt: moment,
            accessibilityTrusted: true, screenRecordingGranted: true,
            config: DaemonStatus.ConfigState(valid: true, path: "/tmp/roadies.toml", error: nil),
            buildCommit: "0b7de36b"
        )
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(DaemonStatus.self, from: data).buildCommit == "0b7de36b")

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "buildCommit")
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DaemonStatus.self, from: older).buildCommit == nil)
    }
}
