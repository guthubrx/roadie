import Foundation
import RoadieCore

public struct LayoutPersistenceV2Report: Codable, Equatable, Sendable {
    public var matches: [WindowIdentityMatch]
    public var applied: Bool
    public var restored: Int
    public var failed: Int

    public init(matches: [WindowIdentityMatch], applied: Bool, restored: Int = 0, failed: Int = 0) {
        self.matches = matches
        self.applied = applied
        self.restored = restored
        self.failed = failed
    }
}

public struct LayoutPersistenceV2Service {
    private let service: SnapshotService
    private let restore: RestoreSafetyService
    private let identity: WindowIdentityService
    private let config: RoadieConfig
    private let events: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        restore: RestoreSafetyService = RestoreSafetyService(),
        identity: WindowIdentityService = WindowIdentityService(),
        config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig(),
        events: EventLog = EventLog()
    ) {
        self.service = service
        self.restore = restore
        self.identity = identity
        self.config = config
        self.events = events
    }

    public func dryRun() -> LayoutPersistenceV2Report {
        guard let snapshot = restore.load() else {
            return LayoutPersistenceV2Report(matches: [], applied: false)
        }
        let live = service.snapshot(followExternalFocus: false, persistState: false).windows.map(\.window)
        return LayoutPersistenceV2Report(
            matches: identity.match(saved: snapshot.windows, live: live, threshold: config.layoutPersistence.minimumMatchScore),
            applied: false
        )
    }

    public func apply() -> LayoutPersistenceV2Report {
        guard let snapshot = restore.load() else {
            return LayoutPersistenceV2Report(matches: [], applied: false)
        }
        events.append(envelope("layout_identity.restore_started", payload: ["windows": .int(snapshot.windows.count)]))
        let live = service.snapshot().windows.map(\.window)
        let matches = identity.match(saved: snapshot.windows, live: live, threshold: config.layoutPersistence.minimumMatchScore)
        let result = restore.restore(snapshot)
        let conflicts = matches.filter { !$0.accepted && $0.reason == "ambiguous" }.count
        if conflicts > 0 {
            events.append(envelope("layout_identity.conflict_detected", payload: ["conflicts": .int(conflicts)]))
        }
        events.append(envelope(result.restored > 0 ? "layout_identity.restore_applied" : "layout_identity.restore_skipped", payload: [
            "restored": .int(result.restored),
            "failed": .int(result.failed)
        ]))
        return LayoutPersistenceV2Report(matches: matches, applied: result.restored > 0, restored: result.restored, failed: result.failed)
    }

    private func envelope(_ type: String, payload: [String: AutomationPayload]) -> RoadieEventEnvelope {
        RoadieEventEnvelope(
            id: "layout_identity_\(UUID().uuidString)",
            type: type,
            scope: .layout,
            subject: AutomationSubject(kind: "layout_identity", id: "restore-v2"),
            cause: .restore,
            payload: payload
        )
    }
}
