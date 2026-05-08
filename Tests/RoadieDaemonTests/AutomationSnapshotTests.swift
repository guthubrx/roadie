import Foundation
import Testing
import RoadieCore

@Suite
struct AutomationSnapshotTests {
    @Test
    func spec002StateSnapshotRoundTrips() throws {
        let snapshot = RoadieStateSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_777_777_777),
            activeDisplayId: "display-main",
            activeDesktopId: "desktop-1",
            activeStageId: "stage-dev",
            focusedWindowId: "window-terminal",
            displays: [
                AutomationDisplaySnapshot(
                    id: "display-main",
                    name: "Built-in Display",
                    frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
                    activeDesktopId: "desktop-1"
                )
            ],
            desktops: [
                AutomationDesktopSnapshot(id: "desktop-1", displayId: "display-main", label: "dev", activeStageId: "stage-dev")
            ],
            stages: [
                AutomationStageSnapshot(
                    id: "stage-dev",
                    desktopId: "desktop-1",
                    name: "dev",
                    mode: "bsp",
                    windowIds: ["window-terminal"],
                    focusedWindowId: "window-terminal"
                )
            ],
            windows: [
                AutomationWindowSnapshot(
                    id: "window-terminal",
                    app: "Terminal",
                    title: "roadie",
                    displayId: "display-main",
                    desktopId: "desktop-1",
                    stageId: "stage-dev",
                    frame: Rect(x: 10, y: 20, width: 800, height: 600),
                    isFocused: true
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RoadieStateSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.windows.first?.stageId == "stage-dev")
    }

    @Test
    func spec002SnapshotFixtureDecodes() throws {
        let url = Bundle.module.url(forResource: "Spec002Snapshot", withExtension: "json")
        let fixtureURL = try #require(url)
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(RoadieStateSnapshot.self, from: data)

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.activeDisplayId == "display-main")
        #expect(snapshot.windows.contains { $0.id == snapshot.focusedWindowId })
        #expect(snapshot.stages.contains { $0.id == snapshot.activeStageId })
    }
}
