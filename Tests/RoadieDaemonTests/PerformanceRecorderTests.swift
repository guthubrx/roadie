import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PerformanceRecorderTests {
    @Test
    func recorderPersistsInteractionWithTotalStep() {
        let path = tempPath("performance-recorder")
        let store = PerformanceStore(path: path, maxInteractions: 10)
        let recorder = PerformanceRecorder(store: store, events: EventLog(path: tempPath("performance-events")))
        let session = recorder.start(.stageSwitch, targetContext: PerformanceTargetContext(displayID: "display-a", stageID: "2"))

        let interaction = recorder.complete(
            session,
            steps: [
                PerformanceStep(name: .stateUpdate, durationMs: 4),
                PerformanceStep(name: .layoutApply, durationMs: 8),
            ],
            completedAt: session.startedAt.addingTimeInterval(0.020)
        )

        #expect(interaction.type == .stageSwitch)
        #expect(interaction.steps.contains { $0.name == .total })
        #expect(store.load().count == 1)
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test
    func recorderMarksThresholdBreachWithDominantStep() {
        let path = tempPath("performance-threshold")
        let config = PerformanceConfig(stageSwitchMs: 10)
        let store = PerformanceStore(path: path, maxInteractions: 10, config: config)
        let recorder = PerformanceRecorder(store: store, events: EventLog(path: tempPath("performance-threshold-events")), config: config)
        let session = recorder.start(.stageSwitch)

        let interaction = recorder.complete(
            session,
            steps: [
                PerformanceStep(name: .hidePrevious, durationMs: 8),
                PerformanceStep(name: .layoutApply, durationMs: 20),
            ],
            completedAt: session.startedAt.addingTimeInterval(0.040)
        )

        #expect(interaction.thresholdBreach?.dominantStep == .layoutApply)
        #expect(store.snapshot().thresholdBreaches.count == 1)
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test
    func recorderSummaryComputesMedianP95AndSlowCount() {
        let path = tempPath("performance-summary")
        let config = PerformanceConfig(stageSwitchMs: 50)
        let store = PerformanceStore(path: path, maxInteractions: 10, config: config)
        store.save([
            PerformanceInteraction(type: .stageSwitch, durationMs: 10),
            PerformanceInteraction(type: .stageSwitch, durationMs: 50),
            PerformanceInteraction(type: .stageSwitch, durationMs: 90),
        ])

        let summary = store.snapshot().summaryByType.first
        #expect(summary?.medianMs == 50)
        #expect(summary?.slowCount == 1)
        #expect(summary?.p95Ms == 90)
        try? FileManager.default.removeItem(atPath: path)
    }
}
