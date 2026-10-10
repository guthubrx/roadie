import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

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
        #expect(snapshot.windows.allSatisfy { $0.presentationState == .normal })
    }

    @Test
    func automationSnapshotExposesWindowPresentationState() {
        let display = powerDisplay()
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let window = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        // Une fenêtre tilée seule n'est pas « agrandie » (SPEC-016 FR-027) : une voisine est nécessaire.
        let sibling = powerWindow(2, x: 100, y: 100, width: 300, height: 300)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [ScopedWindowSnapshot(window: window, scope: scope), ScopedWindowSnapshot(window: sibling, scope: scope)],
            state: RoadieState(),
            focusedWindowID: window.id
        )

        let automation = AutomationSnapshotService().snapshot(from: snapshot)

        #expect(automation.windows.first?.presentationState == .maximized)
    }

    @Test
    func automationSnapshotUsesFocusedWindowDisplayAndConfiguredRules() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 2000)
        let desktop = DesktopID(rawValue: 1)
        let stage = StageID(rawValue: "1")
        var state = RoadieState()
        for display in [main, side] {
            state.ensureDisplay(display.id)
        }
        let window = powerWindow(5, x: 2100)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [main, side],
            windows: [ScopedWindowSnapshot(window: window, scope: StageScope(displayID: side.id, desktopID: desktop, stageID: stage))],
            state: state,
            focusedWindowID: window.id
        )
        let service = AutomationSnapshotService(
            rules: [WindowRule(id: "terminal", match: RuleMatch(app: "Terminal"))],
            stageStore: StageStore(path: tempPath("automation-active-display"))
        )

        let automation = service.snapshot(from: snapshot)

        #expect(automation.activeDisplayId == side.id.rawValue)
        #expect(automation.rules.map(\.id) == ["terminal"])
        #expect(automation.rules.first?.description == "app=Terminal")
    }
}
