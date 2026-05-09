import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct QueryCommandTests {
    @Test
    func queryStateAndWindowsExposeStablePayloads() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let service = AutomationQueryService(service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)))

        let state = service.query("state")
        let windows = service.query("windows")

        #expect(state.kind == "state")
        #expect(windows.kind == "windows")
        if case .array(let rows) = windows.data {
            #expect(rows.count == 1)
        } else {
            Issue.record("windows query did not return an array")
        }
    }

    @Test
    func queryDisplaysDesktopsStagesGroupsAndRulesExposePayloads() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let store = StageStore(path: tempPath("query-groups"))
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = snapshotService.snapshot()
        _ = WindowGroupCommandService(service: snapshotService, store: store).create(
            id: "pair",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        )
        let query = AutomationQueryService(service: snapshotService, configPath: try fixturePath())

        #expect(query.query("displays").kind == "displays")
        #expect(query.query("desktops").kind == "desktops")
        #expect(query.query("stages").kind == "stages")
        #expect(query.query("groups").kind == "groups")
        #expect(query.query("rules").kind == "rules")
    }

    @Test
    func queryConfigReloadExposesState() {
        let service = AutomationQueryService()
        let result = service.query("config_reload")

        #expect(result.kind == "config_reload")
        if case .object(let object) = result.data {
            #expect(object["lastValidation"] != nil)
        } else {
            Issue.record("config_reload query did not return an object")
        }
    }

    @Test
    func queryPerformanceIsReadOnlyAndExposesRecentInteractions() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("query-performance-stages"))
        let performancePath = tempPath("query-performance")
        let performanceStore = PerformanceStore(path: performancePath, maxInteractions: 10)
        performanceStore.append(PerformanceInteraction(type: .stageSwitch, durationMs: 42))
        let service = AutomationQueryService(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store),
            performanceStore: performanceStore
        )

        let result = service.query("performance")

        #expect(result.kind == "performance")
        #expect(store.state().scopes.isEmpty)
        if case .object(let object) = result.data {
            #expect(object["recent_interactions"] != nil)
        } else {
            Issue.record("performance query did not return an object")
        }
        try? FileManager.default.removeItem(atPath: performancePath)
    }

    @Test
    func performanceTextFormattersExposeSummaryRecentAndThresholds() {
        let snapshot = PerformanceSnapshot(
            retention: PerformanceRetention(storagePath: "/tmp/performance.json", maxInteractions: 100),
            recentInteractions: [
                PerformanceInteraction(
                    type: .stageSwitch,
                    durationMs: 42,
                    steps: [PerformanceStep(name: .layoutApply, durationMs: 12)],
                    skippedFrameMoves: 2
                )
            ],
            summaryByType: [PerformanceSummary(type: .stageSwitch, count: 1, medianMs: 42, p95Ms: 42, slowCount: 0)],
            thresholds: [PerformanceThreshold(interactionType: .stageSwitch, limitMs: 150, percentileTarget: 95)]
        )

        let summary = TextFormatter.performanceSummary(snapshot)
        let recent = TextFormatter.performanceRecent(snapshot)
        let thresholds = TextFormatter.performanceThresholds(snapshot)

        #expect(summary.contains("stage_switch"))
        #expect(summary.contains("MEDIAN_MS"))
        #expect(recent.contains("layout_apply"))
        #expect(thresholds.contains("frame_tolerance_points=2.0"))
        #expect(thresholds.contains("retention_max_interactions=100"))
    }
}
