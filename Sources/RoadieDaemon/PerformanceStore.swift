import Foundation
import RoadieCore

public struct PerformanceStore: Sendable {
    private let url: URL
    private let maxInteractions: Int
    private let config: PerformanceConfig

    public init(
        path: String = Self.defaultPath(),
        maxInteractions: Int? = nil,
        config: PerformanceConfig = (try? RoadieConfigLoader.load().performance) ?? PerformanceConfig()
    ) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.config = config
        self.maxInteractions = max(1, maxInteractions ?? config.maxInteractions)
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-performance-\(ProcessInfo.processInfo.processIdentifier).json"
        }
        return "~/.local/state/roadies/performance.json"
    }

    public func load() -> [PerformanceInteraction] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(PerformanceSnapshot.self, from: data) {
            return Array(snapshot.recentInteractions.suffix(maxInteractions))
        }
        if let interactions = try? decoder.decode([PerformanceInteraction].self, from: data) {
            return Array(interactions.suffix(maxInteractions))
        }
        return []
    }

    public func save(_ interactions: [PerformanceInteraction]) {
        let retained = Array(interactions.suffix(maxInteractions))
        let snapshot = snapshot(from: retained)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            fputs("roadie: failed to write performance store: \(error)\n", stderr)
        }
    }

    public func append(_ interaction: PerformanceInteraction) {
        var interactions = load()
        interactions.append(interaction)
        save(interactions)
    }

    public func snapshot(limit: Int? = nil) -> PerformanceSnapshot {
        let interactions = load()
        let retained = limit.map { Array(interactions.suffix(max(1, $0))) } ?? interactions
        return snapshot(from: retained)
    }

    private func snapshot(from interactions: [PerformanceInteraction]) -> PerformanceSnapshot {
        let sorted = interactions.sorted { $0.startedAt < $1.startedAt }
        let breaches = sorted.compactMap(\.thresholdBreach)
        return PerformanceSnapshot(
            retention: PerformanceRetention(storagePath: url.path, maxInteractions: maxInteractions),
            recentInteractions: sorted,
            summaryByType: sorted.performanceSummaries(thresholds: config.thresholds),
            slowestRecent: Array(sorted.sorted { $0.durationMs > $1.durationMs }.prefix(5)),
            thresholdBreaches: breaches,
            thresholds: config.thresholds,
            frameEquivalence: FrameEquivalencePolicy(defaultTolerancePoints: config.frameTolerancePoints)
        )
    }
}
