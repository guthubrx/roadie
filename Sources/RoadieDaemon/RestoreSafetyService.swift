import Foundation
import RoadieCore

public struct RestoreSafetyWindow: Codable, Equatable, Sendable {
    public var windowID: UInt32
    public var appName: String
    public var bundleID: String
    public var title: String
    public var frame: Rect
}

public struct RestoreSafetySnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var windows: [RestoreSafetyWindow]
}

public struct RestoreSafetyStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var generatedAt: Date?
    public var windowCount: Int
    public var sizeBytes: Int64
}

public struct RestoreSafetyApplyResult: Codable, Equatable, Sendable {
    public var path: String
    public var attempted: Int
    public var applied: Int
    public var failed: Int
    public var missing: Int
}

public struct RestoreSafetyRunMarker: Codable, Equatable, Sendable {
    public var pid: Int32
    public var startedAt: Date
    public var cleanExitAt: Date?
    public var snapshotPath: String

    public var cleanExit: Bool { cleanExitAt != nil }
}

public struct RestoreSafetyService {
    private let path: String
    private let markerPath: String
    private let service: SnapshotService
    private let eventLog: EventLog

    public init(
        path: String = "~/.local/state/roadies/restore.json",
        markerPath: String = "~/.local/state/roadies/restore-run.json",
        service: SnapshotService = SnapshotService(),
        eventLog: EventLog = EventLog()
    ) {
        self.path = NSString(string: path).expandingTildeInPath
        self.markerPath = NSString(string: markerPath).expandingTildeInPath
        self.service = service
        self.eventLog = eventLog
    }

    public func writeSnapshot() throws -> RestoreSafetySnapshot {
        let snapshot = service.snapshot()
        let restore = RestoreSafetySnapshot(
            generatedAt: Date(),
            windows: snapshot.windows
                .filter { $0.window.isTileCandidate && $0.scope != nil }
                .map { entry in
                    RestoreSafetyWindow(
                        windowID: entry.window.id.rawValue,
                        appName: entry.window.appName,
                        bundleID: entry.window.bundleID,
                        title: entry.window.title,
                        frame: entry.window.frame
                    )
                }
        )
        let url = URL(fileURLWithPath: path)
        try JSONPersistence.writeThrowing(restore, to: url) { encoder in
            encoder.dateEncodingStrategy = .iso8601
        }
        eventLog.append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: "restore.snapshot_written",
            scope: .restore,
            subject: AutomationSubject(kind: "snapshot", id: url.path),
            cause: .command,
            payload: [
                "path": .string(url.path),
                "window_count": .int(restore.windows.count)
            ]
        ))
        return restore
    }

    public func markRunStarted(pid: Int32) throws -> RestoreSafetyRunMarker {
        let marker = RestoreSafetyRunMarker(
            pid: pid,
            startedAt: Date(),
            cleanExitAt: nil,
            snapshotPath: path
        )
        try writeMarker(marker)
        return marker
    }

    public func markCleanExit(pid: Int32) throws -> RestoreSafetyRunMarker {
        var marker = loadMarker() ?? RestoreSafetyRunMarker(
            pid: pid,
            startedAt: Date(),
            cleanExitAt: nil,
            snapshotPath: path
        )
        marker.pid = pid
        marker.cleanExitAt = Date()
        marker.snapshotPath = path
        try writeMarker(marker)
        eventLog.append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: "restore.exit_completed",
            scope: .restore,
            subject: AutomationSubject(kind: "process", id: String(pid)),
            cause: .system,
            payload: ["snapshot_path": .string(path)]
        ))
        return marker
    }

    public func runMarker() -> RestoreSafetyRunMarker? {
        loadMarker()
    }

    public func shouldRestoreAfterProcessExit(pid: Int32) -> Bool {
        guard let marker = loadMarker(), marker.pid == pid else { return false }
        return !marker.cleanExit
    }

    public func status() -> RestoreSafetyStatus {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RestoreSafetyStatus(path: url.path, exists: false, generatedAt: nil, windowCount: 0, sizeBytes: 0)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let snapshot = try? loadSnapshot()
        return RestoreSafetyStatus(
            path: url.path,
            exists: true,
            generatedAt: snapshot?.generatedAt,
            windowCount: snapshot?.windows.count ?? 0,
            sizeBytes: size
        )
    }

    public func apply() throws -> RestoreSafetyApplyResult {
        let restore = try loadSnapshot()
        let current = service.snapshot()
        let windowsByID = Dictionary(uniqueKeysWithValues: current.windows.map { ($0.window.id.rawValue, $0.window) })
        let commands = restore.windows.compactMap { item -> ApplyCommand? in
            guard let window = windowsByID[item.windowID] else { return nil }
            return ApplyCommand(window: window, frame: item.frame)
        }
        eventLog.append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: "restore.apply_started",
            scope: .restore,
            subject: AutomationSubject(kind: "snapshot", id: path),
            cause: .command,
            payload: ["attempted": .int(commands.count)]
        ))
        let result = service.apply(ApplyPlan(commands: commands))
        let report = RestoreSafetyApplyResult(
            path: path,
            attempted: result.attempted,
            applied: result.applied,
            failed: result.failed,
            missing: restore.windows.count - commands.count
        )
        eventLog.append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: report.failed == 0 ? "restore.apply_completed" : "restore.apply_failed",
            scope: .restore,
            subject: AutomationSubject(kind: "snapshot", id: path),
            cause: .command,
            payload: [
                "attempted": .int(report.attempted),
                "applied": .int(report.applied),
                "failed": .int(report.failed),
                "missing": .int(report.missing)
            ]
        ))
        return report
    }

    private func writeMarker(_ marker: RestoreSafetyRunMarker) throws {
        let url = URL(fileURLWithPath: markerPath)
        try JSONPersistence.writeThrowing(marker, to: url) { encoder in
            encoder.dateEncodingStrategy = .iso8601
        }
    }

    private func loadMarker() -> RestoreSafetyRunMarker? {
        try? JSONPersistence.loadThrowing(
            RestoreSafetyRunMarker.self,
            from: URL(fileURLWithPath: markerPath)
        ) { decoder in
            decoder.dateDecodingStrategy = .iso8601
        }
    }

    private func loadSnapshot() throws -> RestoreSafetySnapshot {
        try JSONPersistence.loadThrowing(
            RestoreSafetySnapshot.self,
            from: URL(fileURLWithPath: path)
        ) { decoder in
            decoder.dateDecodingStrategy = .iso8601
        }
    }
}
