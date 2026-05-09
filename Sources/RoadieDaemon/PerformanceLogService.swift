import Foundation
import RoadieCore

public struct PerformanceThresholds: Codable, Equatable, Sendable {
    public var stageSwitchP95Ms: Int
    public var desktopSwitchP95Ms: Int
    public var altTabActivationP90Ms: Int
    public var note: String

    public init(
        stageSwitchP95Ms: Int = 150,
        desktopSwitchP95Ms: Int = 200,
        altTabActivationP90Ms: Int = 250,
        note: String = "Read-only thresholds. This build does not instrument hot focus/border paths."
    ) {
        self.stageSwitchP95Ms = stageSwitchP95Ms
        self.desktopSwitchP95Ms = desktopSwitchP95Ms
        self.altTabActivationP90Ms = altTabActivationP90Ms
        self.note = note
    }
}

public struct PerformanceSummaryRow: Codable, Equatable, Sendable {
    public var eventType: String
    public var count: Int
    public var firstSeen: Date?
    public var lastSeen: Date?
}

public struct PerformanceSummaryReport: Codable, Equatable, Sendable {
    public var source: String
    public var sampleCount: Int
    public var rows: [PerformanceSummaryRow]
    public var thresholds: PerformanceThresholds
}

public struct PerformanceRecentEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var type: String
    public var scope: String?
    public var subject: String?
}

public struct PerformanceLogService: Sendable {
    private let eventLog: EventLog
    private let thresholdsValue: PerformanceThresholds

    public init(eventLog: EventLog = EventLog(), thresholds: PerformanceThresholds = PerformanceThresholds()) {
        self.eventLog = eventLog
        self.thresholdsValue = thresholds
    }

    public func summary(limit: Int = 500) -> PerformanceSummaryReport {
        let events = eventLog.envelopes(limit: max(1, limit)).filter(Self.isInteractionEvent)
        let grouped = Dictionary(grouping: events, by: \.type)
        let rows = grouped.map { type, events in
            let dates = events.map(\.timestamp).sorted()
            return PerformanceSummaryRow(
                eventType: type,
                count: events.count,
                firstSeen: dates.first,
                lastSeen: dates.last
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.eventType < rhs.eventType
        }
        return PerformanceSummaryReport(
            source: "events.jsonl",
            sampleCount: events.count,
            rows: rows,
            thresholds: thresholdsValue
        )
    }

    public func recent(limit: Int = 20) -> [PerformanceRecentEvent] {
        eventLog.envelopes(limit: max(1, limit))
            .filter(Self.isInteractionEvent)
            .suffix(max(1, limit))
            .map { event in
                PerformanceRecentEvent(
                    timestamp: event.timestamp,
                    type: event.type,
                    scope: event.scope?.rawValue,
                    subject: event.subject.map { "\($0.kind):\($0.id)" }
                )
            }
    }

    public func thresholds() -> PerformanceThresholds {
        thresholdsValue
    }

    private static func isInteractionEvent(_ event: RoadieEventEnvelope) -> Bool {
        let prefixes = [
            "command.",
            "display.",
            "desktop.",
            "stage.",
            "window.",
            "layout.",
            "rail_"
        ]
        return prefixes.contains { event.type.hasPrefix($0) }
    }
}
