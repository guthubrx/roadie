import Foundation
import RoadieAX
import RoadieCore

public struct RestoreSafetyResult: Codable, Equatable, Sendable {
    public var restored: Int
    public var failed: Int
    public var snapshotPath: String
    public var message: String

    public init(restored: Int, failed: Int, snapshotPath: String, message: String) {
        self.restored = restored
        self.failed = failed
        self.snapshotPath = snapshotPath
        self.message = message
    }
}

public struct RestoreSafetyService {
    private let service: SnapshotService
    private let frameWriter: any WindowFrameWriting
    private let path: String
    private let eventLog: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        frameWriter: any WindowFrameWriting = AXWindowFrameWriter(),
        path: String = Self.defaultPath(),
        eventLog: EventLog = EventLog()
    ) {
        self.service = service
        self.frameWriter = frameWriter
        self.path = NSString(string: path).expandingTildeInPath
        self.eventLog = eventLog
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-restore-\(ProcessInfo.processInfo.processIdentifier).json"
        }
        return "~/.local/state/roadies/restore-safety.json"
    }

    public func capture() -> RestoreSafetySnapshot {
        capture(from: service.snapshot())
    }

    @discardableResult
    public func captureAndSave() -> Bool {
        save(capture())
    }

    public func capture(from snapshot: DaemonSnapshot) -> RestoreSafetySnapshot {
        let activeDisplayID = snapshot.displays.first { display in
            snapshot.state.activeScope(on: display.id) != nil
        }?.id.rawValue
        let activeScope = snapshot.displays.compactMap { snapshot.state.activeScope(on: $0.id) }.first
        let windows = snapshot.windows.compactMap { entry -> RestoreWindowState? in
            guard entry.scope != nil || entry.window.isTileCandidate else { return nil }
            let visible = snapshot.displays.first { display in
                display.visibleFrame.cgRect.intersects(entry.window.frame.cgRect)
            }?.visibleFrame ?? snapshot.displays.first?.visibleFrame ?? entry.window.frame
            return RestoreWindowState(
                windowID: entry.window.id.rawValue,
                identity: WindowIdentityService.identity(for: entry.window),
                frame: entry.window.frame,
                visibleFrame: visible,
                wasManaged: entry.scope != nil,
                wasHiddenByRoadie: !entry.window.isOnScreen,
                stageScope: entry.scope?.description,
                groupID: nil
            )
        }
        return RestoreSafetySnapshot(
            daemonPID: ProcessInfo.processInfo.processIdentifier,
            windows: windows,
            activeDisplayID: activeDisplayID,
            activeDesktop: activeScope.map { String($0.desktopID.rawValue) },
            activeStage: activeScope?.stageID.rawValue
        )
    }

    @discardableResult
    public func save(_ snapshot: RestoreSafetySnapshot) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let existing = load(), semanticFingerprint(existing) == semanticFingerprint(snapshot) {
                return true
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            eventLog.append(envelope("restore.snapshot_written", payload: ["windows": .int(snapshot.windows.count)]))
            return true
        } catch {
            eventLog.append(envelope("restore.snapshot_failed", payload: ["error": .string(String(describing: error))]))
            return false
        }
    }

    public func load() -> RestoreSafetySnapshot? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RestoreSafetySnapshot.self, from: data)
    }

    public func restoreFromDisk() -> RestoreSafetyResult {
        guard let snapshot = load() else {
            return RestoreSafetyResult(restored: 0, failed: 0, snapshotPath: path, message: "restore: no snapshot")
        }
        return restore(snapshot)
    }

    public func restore(_ snapshot: RestoreSafetySnapshot) -> RestoreSafetyResult {
        let live = service.snapshot()
        var restored = 0
        var failed = 0
        let windowsByID = Dictionary(uniqueKeysWithValues: live.windows.map { ($0.window.id.rawValue, $0.window) })
        let identityMatches = WindowIdentityService().match(saved: snapshot.windows, live: live.windows.map(\.window), threshold: 0.75)
        for (saved, match) in zip(snapshot.windows, identityMatches) {
            let matchedID = saved.windowID.flatMap { windowsByID[$0] == nil ? nil : $0 } ?? match.liveWindowID
            guard let id = matchedID, let window = windowsByID[id] else {
                failed += 1
                continue
            }
            let target = visibleFrame(for: saved, liveDisplays: live.displays)
            if frameWriter.setFrame(target.cgRect, of: window) != nil {
                restored += 1
            } else {
                failed += 1
            }
        }
        eventLog.append(envelope("restore.applied", payload: [
            "restored": .int(restored),
            "failed": .int(failed),
            "identityMatches": .int(identityMatches.filter(\.accepted).count)
        ]))
        return RestoreSafetyResult(
            restored: restored,
            failed: failed,
            snapshotPath: path,
            message: "restore: restored=\(restored) failed=\(failed)"
        )
    }

    public func restoreIfDaemonMissing(pid: Int32?, isAlive: (Int32) -> Bool) -> RestoreSafetyResult {
        guard let pid, !isAlive(pid) else {
            return RestoreSafetyResult(restored: 0, failed: 0, snapshotPath: path, message: "restore watcher: daemon alive")
        }
        eventLog.append(envelope("restore.crash_detected", payload: ["pid": .int(Int(pid))]))
        let result = restoreFromDisk()
        eventLog.append(envelope("restore.crash_completed", payload: [
            "restored": .int(result.restored),
            "failed": .int(result.failed)
        ]))
        return result
    }

    private func visibleFrame(for saved: RestoreWindowState, liveDisplays: [DisplaySnapshot]) -> Rect {
        if liveDisplays.contains(where: { $0.visibleFrame.cgRect.intersects(saved.frame.cgRect) }) {
            return saved.frame
        }
        return liveDisplays.first?.visibleFrame ?? saved.visibleFrame
    }

    private func semanticFingerprint(_ snapshot: RestoreSafetySnapshot) -> RestoreSafetySnapshot {
        var stable = snapshot
        stable.createdAt = Date(timeIntervalSince1970: 0)
        stable.windows = stable.windows
            .map { window in
                var stableWindow = window
                stableWindow.identity.title = ""
                stableWindow.identity.createdAt = nil
                return stableWindow
            }
            .sorted { lhs, rhs in
                let lhsKey = "\(lhs.stageScope ?? "")/\(lhs.windowID ?? 0)/\(lhs.identity.bundleID ?? lhs.identity.appName)"
                let rhsKey = "\(rhs.stageScope ?? "")/\(rhs.windowID ?? 0)/\(rhs.identity.bundleID ?? rhs.identity.appName)"
                return lhsKey < rhsKey
            }
        return stable
    }

    private func envelope(_ type: String, payload: [String: AutomationPayload]) -> RoadieEventEnvelope {
        RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: type,
            scope: .restore,
            subject: AutomationSubject(kind: "restore", id: path),
            cause: .restore,
            payload: payload
        )
    }
}
