import CoreGraphics
import Foundation
import RoadieAX
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

    /// Écrit la dernière frame visible de chaque fenêtre gérée (FR-037). Une fenêtre masquée
    /// prend la frame de son membre de stage (ou celle du snapshot précédent) : le snapshot ne
    /// contient jamais de position masquée. Aucune écriture si le contenu n'a pas changé.
    // O(n + m), n = fenêtres live, m = membres de stage.
    public func writeSnapshot() throws -> RestoreSafetySnapshot {
        let snapshot = service.snapshot()
        let previous = try? loadSnapshot()
        let memberFrames = Self.visibleMemberFrames(service.effectiveStageStore.state(), displays: snapshot.displays)
        let previousFrames = Self.visibleFrames(of: previous, displays: snapshot.displays)
        let windows = snapshot.windows
            .filter { $0.window.isTileCandidate && $0.scope != nil }
            .compactMap { entry -> RestoreSafetyWindow? in
                var frame = entry.window.frame
                if HiddenWindowPlacement.isHidden(frame.cgRect, in: snapshot.displays) {
                    guard let visible = memberFrames[entry.window.id.rawValue] ?? previousFrames[entry.window.id.rawValue] else {
                        return nil
                    }
                    frame = visible
                }
                return RestoreSafetyWindow(
                    windowID: entry.window.id.rawValue,
                    appName: entry.window.appName,
                    bundleID: entry.window.bundleID,
                    title: entry.window.title,
                    frame: frame
                )
            }
        if let previous, previous.windows == windows {
            return previous
        }
        let restore = RestoreSafetySnapshot(generatedAt: Date(), windows: windows)
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

    /// Ramène chaque fenêtre masquée à sa dernière frame visible connue : union des membres de
    /// stage (prioritaires, plus récents) et du snapshot de restauration. Une fenêtre sans frame
    /// connue est centrée sur l'écran principal ; une frame dont l'écran a disparu est replacée
    /// sur l'écran principal. Utilisé à l'arrêt, après un crash et par `roadie restore unhide-all`.
    // O(n + m), n = fenêtres live, m = membres de stage.
    public func unhideAll() -> RestoreSafetyApplyResult {
        let current = service.snapshot(followFocus: false)
        let displays = current.displays
        let memberFrames = Self.visibleMemberFrames(service.effectiveStageStore.state(), displays: displays)
        let savedFrames = Self.visibleFrames(of: try? loadSnapshot(), displays: displays)
        var unknown = 0
        let commands = current.windows.compactMap { entry -> ApplyCommand? in
            let window = entry.window
            guard HiddenWindowPlacement.isHidden(window.frame.cgRect, in: displays) else { return nil }
            let known = memberFrames[window.id.rawValue] ?? savedFrames[window.id.rawValue]
            if known == nil { unknown += 1 }
            return ApplyCommand(window: window, frame: Self.onScreen(known ?? window.frame, displays: displays))
        }
        let result = service.apply(ApplyPlan(commands: commands))
        let report = RestoreSafetyApplyResult(
            path: path,
            attempted: result.attempted,
            applied: result.applied,
            failed: result.failed,
            missing: unknown
        )
        eventLog.append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: report.failed == 0 ? "restore.unhide_all_completed" : "restore.unhide_all_failed",
            scope: .restore,
            subject: AutomationSubject(kind: "snapshot", id: path),
            cause: .command,
            payload: [
                "attempted": .int(report.attempted),
                "applied": .int(report.applied),
                "failed": .int(report.failed),
                "unknown_frame": .int(report.missing)
            ]
        ))
        return report
    }

    /// Démarrage d'une instance (sous son verrou d'instance, avant le tiler) : si l'exécution
    /// précédente ne s'est pas arrêtée proprement, ses fenêtres masquées sont d'abord restaurées,
    /// puis le marqueur passe à `pid`. Le verrou de reprise sérialise ce couple avec
    /// `recoverAfterProcessExit` : un redémarrage rapide ne peut pas écraser le marqueur entre la
    /// lecture et la restauration du watcher précédent, et la restauration n'est jamais perdue.
    public func startRun(pid: Int32) throws -> RestoreSafetyApplyResult? {
        try FileLock.withLock(path: recoveryLockPath) {
            var recovery: RestoreSafetyApplyResult?
            if let marker = loadMarker(), !marker.cleanExit, marker.pid != pid {
                recovery = unhideAll()
            }
            _ = try markRunStarted(pid: pid)
            return recovery
        }
    }

    /// Arrêt propre : restaure les fenêtres masquées puis marque l'arrêt propre, seulement si
    /// la restauration a réussi. Sinon le marqueur reste « non propre » et le watcher (ou le
    /// prochain démarrage) retente.
    public func finishRun(pid: Int32) -> RestoreSafetyApplyResult {
        let result = unhideAll()
        guard result.failed == 0 else { return result }
        do {
            _ = try markCleanExit(pid: pid)
        } catch {
            fputs("roadied: restore safety clean exit failed: \(error)\n", stderr)
        }
        return result
    }

    /// Watcher : restaure si `pid` a disparu sans arrêt propre. Renvoie nil si rien à faire
    /// (arrêt propre, ou marqueur déjà repris par une nouvelle instance).
    public func recoverAfterProcessExit(pid: Int32) throws -> RestoreSafetyApplyResult? {
        try FileLock.withLock(path: recoveryLockPath) {
            guard var marker = loadMarker(), marker.pid == pid, !marker.cleanExit else { return nil }
            let result = unhideAll()
            if result.failed == 0 {
                marker.cleanExitAt = Date()
                try writeMarker(marker)
            }
            return result
        }
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
        let windowsByID = Dictionary(current.windows.map { ($0.window.id.rawValue, $0.window) }, uniquingKeysWith: { first, _ in first })
        let commands = restore.windows.compactMap { item -> ApplyCommand? in
            guard let window = windowsByID[item.windowID] else { return nil }
            return ApplyCommand(window: window, frame: Self.onScreen(item.frame, displays: current.displays))
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

    /// Verrou distinct de celui de `JSONPersistence` (`<marqueur>.lock`), non réentrant.
    private var recoveryLockPath: String { "\(markerPath).recovery.lock" }

    /// Dernière frame visible de chaque membre de stage (toutes stages confondues). O(m).
    static func visibleMemberFrames(_ state: PersistentStageState, displays: [DisplaySnapshot]) -> [UInt32: Rect] {
        var frames: [UInt32: Rect] = [:]
        for scope in state.scopes {
            for stage in scope.stages {
                for member in stage.members where frames[member.windowID.rawValue] == nil {
                    guard !HiddenWindowPlacement.isHidden(member.frame.cgRect, in: displays) else { continue }
                    frames[member.windowID.rawValue] = member.frame
                }
            }
        }
        return frames
    }

    private static func visibleFrames(of snapshot: RestoreSafetySnapshot?, displays: [DisplaySnapshot]) -> [UInt32: Rect] {
        var frames: [UInt32: Rect] = [:]
        for window in snapshot?.windows ?? [] where frames[window.windowID] == nil {
            guard !HiddenWindowPlacement.isHidden(window.frame.cgRect, in: displays) else { continue }
            frames[window.windowID] = window.frame
        }
        return frames
    }

    /// Garde la frame si son centre tombe sur un écran présent ; sinon la centre sur l'écran
    /// principal, réduite à sa zone visible. O(d), d = nombre d'écrans.
    static func onScreen(_ frame: Rect, displays: [DisplaySnapshot]) -> Rect {
        let center = CGPoint(x: frame.cgRect.midX, y: frame.cgRect.midY)
        guard !displays.contains(where: { $0.visibleFrame.cgRect.contains(center) }),
              let host = displays.first(where: \.isMain) ?? displays.first
        else { return frame }
        let visible = host.visibleFrame.cgRect
        let width = min(frame.width, Double(visible.width))
        let height = min(frame.height, Double(visible.height))
        return Rect(
            x: (Double(visible.midX) - width / 2).rounded(),
            y: (Double(visible.midY) - height / 2).rounded(),
            width: width,
            height: height
        )
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
