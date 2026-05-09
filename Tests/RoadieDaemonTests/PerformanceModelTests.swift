import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PerformanceModelTests {
    @Test
    func performanceModelsEncodeAndSummarizeRecentInteractions() throws {
        let interactions = [
            PerformanceInteraction(type: .stageSwitch, durationMs: 20),
            PerformanceInteraction(type: .stageSwitch, durationMs: 40),
            PerformanceInteraction(type: .stageSwitch, durationMs: 80),
        ]
        let summaries = interactions.performanceSummaries(thresholds: [
            PerformanceThreshold(interactionType: .stageSwitch, limitMs: 50, percentileTarget: 95)
        ])

        #expect(summaries.count == 1)
        #expect(summaries[0].count == 3)
        #expect(summaries[0].slowCount == 1)
        #expect(summaries[0].medianMs == 40)

        let snapshot = PerformanceSnapshot(
            retention: PerformanceRetention(storagePath: "/tmp/performance.json", maxInteractions: 100),
            recentInteractions: interactions,
            summaryByType: summaries,
            thresholds: [PerformanceThreshold(interactionType: .stageSwitch, limitMs: 50, percentileTarget: 95)]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PerformanceSnapshot.self, from: data)

        #expect(decoded.recentInteractions.count == 3)
        #expect(decoded.summaryByType.first?.type == .stageSwitch)
    }

    @Test
    func performanceStoreKeepsBoundedFifoHistory() {
        let path = tempPath("performance-store")
        let store = PerformanceStore(path: path, maxInteractions: 2, config: PerformanceConfig(maxInteractions: 2))

        store.append(PerformanceInteraction(id: "one", type: .stageSwitch))
        store.append(PerformanceInteraction(id: "two", type: .desktopSwitch))
        store.append(PerformanceInteraction(id: "three", type: .altTabActivation))

        let interactions = store.load()
        #expect(interactions.map(\.id) == ["two", "three"])
        try? FileManager.default.removeItem(atPath: path)
    }
}
