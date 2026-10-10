import CoreGraphics
import Darwin
import Foundation
import RoadieAX
import RoadieCore

public enum DaemonHealthLevel: String, Codable, Sendable {
    case ok
    case warn
    case fail
}

public struct DaemonHealthCheck: Equatable, Codable, Sendable {
    public var level: DaemonHealthLevel
    public var name: String
    public var message: String

    public init(level: DaemonHealthLevel, name: String, message: String) {
        self.level = level
        self.name = name
        self.message = message
    }
}

public struct DaemonHealthReport: Equatable, Codable, Sendable {
    public var checks: [DaemonHealthCheck]

    public init(checks: [DaemonHealthCheck]) {
        self.checks = checks
    }

    public var failed: Bool {
        checks.contains { $0.level == .fail }
    }
}

public struct DaemonHealReport: Equatable, Codable, Sendable {
    public var parking: DisplayParkingReport
    public var state: StateHealReport
    public var layout: ApplyResult
    public var health: DaemonHealthReport

    public init(
        parking: DisplayParkingReport = DisplayParkingReport(kind: .noop, reason: .alreadyStable),
        state: StateHealReport,
        layout: ApplyResult,
        health: DaemonHealthReport
    ) {
        self.parking = parking
        self.state = state
        self.layout = layout
        self.health = health
    }

    public var failed: Bool {
        state.audit.failed || layout.failed > 0 || health.failed
    }
}

public struct DaemonHealthService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let events: EventLog
    private let pidFilePath: String
    private let statusPath: String
    private let componentRegistry: () -> [(component: String, pid: Int32, startedAt: Date)]

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        events: EventLog = EventLog(),
        pidFilePath: String = "\(NSHomeDirectory())/.roadies/roadied.pid",
        statusPath: String = DaemonStatus.defaultPath,
        componentRegistry: @escaping () -> [(component: String, pid: Int32, startedAt: Date)] = ComponentLockFile.registry
    ) {
        self.service = service
        self.stageStore = stageStore
        self.events = events
        self.pidFilePath = pidFilePath
        self.statusPath = statusPath
        self.componentRegistry = componentRegistry
    }

    public func run() -> DaemonHealthReport {
        let selfTest = SelfTestService(service: service, stageStore: stageStore).run()
        let audit = StateAuditService(service: service, stageStore: stageStore).run()
        var checks = [pidCheck()]
        if let statusCheck = statusCheck() {
            checks.append(statusCheck)
        }
        checks.append(DaemonHealthCheck(
            level: selfTest.failed ? .fail : .ok,
            name: "self-test",
            message: "failed=\(selfTest.failed)"
        ))
        checks.append(DaemonHealthCheck(
            level: audit.failed ? .fail : .ok,
            name: "state-audit",
            message: "failed=\(audit.failed)"
        ))
        return DaemonHealthReport(checks: checks)
    }

    public func heal() -> DaemonHealReport {
        let parkingReport = applyParkingTransition(snapshot: service.snapshot())
        appendParkingEvent(parkingReport)

        let stateReport = StateAuditService(service: service, stageStore: stageStore).heal()
        let snapshot = service.snapshot()
        let layoutResult = service.apply(service.applyPlan(from: snapshot))
        let healthReport = run()
        return DaemonHealReport(parking: parkingReport, state: stateReport, layout: layoutResult, health: healthReport)
    }

    /// Heal léger au changement d'écran : un seul snapshot, transition de parking, sauvegarde
    /// si l'état change. Le tick suivant du tiler applique la disposition. Le heal complet
    /// (`heal()`) prend plusieurs snapshots et purge les membres absents, ce qu'il faut éviter
    /// pendant qu'un écran se reconfigure (fenêtres transitoirement invisibles pour AX).
    public func healDisplayChange() -> DisplayParkingReport {
        let report = applyParkingTransition(snapshot: service.snapshot())
        appendParkingEvent(report)
        return report
    }

    /// Transition de parking appliquée sur l'état relu sous verrou (SPEC-016 FR-013) ; le
    /// snapshot (AX) est pris avant, hors verrou. `mutate` n'écrit rien si l'état est inchangé.
    private func applyParkingTransition(snapshot: DaemonSnapshot) -> DisplayParkingReport {
        stageStore.mutate { state in
            DisplayParkingService().transition(
                state: &state,
                liveDisplays: snapshot.displays,
                windows: snapshot.windows.map(\.window)
            )
        }
    }

    private func appendParkingEvent(_ report: DisplayParkingReport) {
        let eventType: String
        switch report.kind {
        case .park:
            eventType = "display.parking_started"
        case .restore:
            eventType = "display.parking_restored"
        case .ambiguous:
            eventType = "display.parking_ambiguous"
        case .noop:
            eventType = "display.parking_noop"
        }
        var details: [String: String] = [
            "reason": report.reason.rawValue,
            "parkedStageCount": String(report.parkedStageCount),
            "restoredStageCount": String(report.restoredStageCount),
            "skippedStageCount": String(report.skippedStageCount)
        ]
        if let originDisplayID = report.originDisplayID {
            details["originDisplayID"] = originDisplayID.rawValue
        }
        if let originLogicalDisplayID = report.originLogicalDisplayID {
            details["originLogicalDisplayID"] = originLogicalDisplayID.rawValue
        }
        if let hostDisplayID = report.hostDisplayID {
            details["hostDisplayID"] = hostDisplayID.rawValue
        }
        if let restoredDisplayID = report.restoredDisplayID {
            details["restoredDisplayID"] = restoredDisplayID.rawValue
        }
        if !report.candidateDisplayIDs.isEmpty {
            details["candidateDisplayIDs"] = report.candidateDisplayIDs.map(\.rawValue).joined(separator: ",")
        }
        if let confidence = report.confidence {
            details["confidence"] = String(format: "%.3f", confidence)
        }
        events.append(RoadieEvent(type: eventType, details: details))
    }

    /// Relit `daemon-status.json` (contrat SPEC-016). Jamais `.fail` : l'absence du fichier ou
    /// un battement ancien signale un daemon arrêté ou d'une version antérieure.
    private func statusCheck() -> DaemonHealthCheck? {
        guard let status = DaemonStatus.load(from: statusPath) else { return nil }
        let alive = status.isAlive()
        return DaemonHealthCheck(
            level: alive ? .ok : .warn,
            name: "daemon-status",
            message: "pid=\(status.pid) mode=\(status.mode) alive=\(alive) accessibility=\(status.accessibilityTrusted) config_valid=\(status.config.valid)"
        )
    }

    private func pidCheck() -> DaemonHealthCheck {
        guard let raw = try? String(contentsOfFile: pidFilePath).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(raw)
        else {
            let components = componentRegistry()
            if !components.isEmpty {
                return DaemonHealthCheck(
                    level: .ok,
                    name: "components",
                    message: "running=\(components.count) names=\(components.map(\.component).joined(separator: ","))"
                )
            }
            return DaemonHealthCheck(level: .warn, name: "pidfile", message: "missing")
        }

        let running = ProcessLiveness.isAlive(pid)
        return DaemonHealthCheck(
            level: running ? .ok : .fail,
            name: "process",
            message: "pid=\(pid) running=\(running)"
        )
    }
}

/// Version de Roadie, partagée par `roadied --version`, `roadie --version` et `daemon-status.json`.
public enum RoadieVersion {
    public static let current = "0.3.0"
}

/// État publié par le daemon dans `~/.roadies/daemon-status.json`
/// (contrat `specs/016-roadie-stabilization/contracts/daemon-status.md`).
public struct DaemonStatus: Codable, Equatable, Sendable {
    public struct ConfigState: Codable, Equatable, Sendable {
        public var valid: Bool
        public var path: String
        public var error: String?

        public init(valid: Bool, path: String, error: String?) {
            self.valid = valid
            self.path = path
            self.error = error
        }
    }

    public static let defaultPath = "\(NSHomeDirectory())/.roadies/daemon-status.json"
    /// Battement de cœur : `updatedAt` est réécrit au plus toutes les 30 s (SC-004).
    public static let heartbeatInterval: TimeInterval = 30
    /// Au-delà, le daemon est considéré arrêté.
    public static let staleAfter: TimeInterval = 90

    public var version: Int
    public var pid: Int32
    public var mode: String
    public var roadieVersion: String
    public var startedAt: Date
    public var updatedAt: Date
    public var accessibilityTrusted: Bool
    public var screenRecordingGranted: Bool
    public var config: ConfigState
    public var socketPath: String

    public init(
        pid: Int32,
        mode: String,
        startedAt: Date,
        updatedAt: Date,
        accessibilityTrusted: Bool,
        screenRecordingGranted: Bool,
        config: ConfigState,
        socketPath: String = "\(NSHomeDirectory())/.roadies/roadied.sock",
        roadieVersion: String = RoadieVersion.current
    ) {
        self.version = 1
        self.pid = pid
        self.mode = mode
        self.roadieVersion = roadieVersion
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.accessibilityTrusted = accessibilityTrusted
        self.screenRecordingGranted = screenRecordingGranted
        self.config = config
        self.socketPath = socketPath
    }

    /// Vrai si le process vit et que le battement a moins de 90 s.
    public func isAlive(now: Date = Date()) -> Bool {
        let running = ProcessLiveness.isAlive(pid)
        return running && now.timeIntervalSince(updatedAt) <= Self.staleAfter
    }

    /// Réécriture nécessaire si le contenu change hors `updatedAt`, ou si le battement est dû.
    public func needsRewrite(comparedTo previous: DaemonStatus?) -> Bool {
        guard var previous else { return true }
        if updatedAt.timeIntervalSince(previous.updatedAt) >= Self.heartbeatInterval { return true }
        previous.updatedAt = updatedAt
        return previous != self
    }

    public static func load(from path: String = defaultPath) -> DaemonStatus? {
        try? JSONPersistence.loadThrowing(DaemonStatus.self, from: URL(fileURLWithPath: path)) { decoder in
            decoder.dateDecodingStrategy = .iso8601
        }
    }

    public func write(to path: String = defaultPath) throws {
        try JSONPersistence.writeThrowing(self, to: URL(fileURLWithPath: path)) { encoder in
            encoder.dateEncodingStrategy = .iso8601
        }
    }
}

/// Publie `daemon-status.json` depuis le daemon (`run` ou `tiler`). `publish()` est appelé
/// au démarrage puis périodiquement : les sondes sont peu coûteuses (permission AX, preflight
/// capture d'écran, stat de la config) et le fichier n'est écrit qu'en cas de changement ou
/// de battement dû.
public final class DaemonStatusPublisher {
    private let path: String
    private let mode: String
    private let startedAt: Date
    private let configService: ConfigReloadService
    private var lastWritten: DaemonStatus?

    public init(
        mode: String,
        path: String = DaemonStatus.defaultPath,
        startedAt: Date = Date(),
        configService: ConfigReloadService = .shared
    ) {
        self.mode = mode
        self.path = path
        self.startedAt = startedAt
        self.configService = configService
    }

    @discardableResult
    public func publish(now: Date = Date()) -> Bool {
        _ = configService.currentConfig()
        let configState = configService.state
        let status = DaemonStatus(
            pid: ProcessInfo.processInfo.processIdentifier,
            mode: mode,
            startedAt: startedAt,
            updatedAt: now,
            accessibilityTrusted: AXPermissions.snapshot(prompt: false).accessibilityTrusted,
            screenRecordingGranted: CGPreflightScreenCaptureAccess(),
            config: DaemonStatus.ConfigState(
                valid: configState.lastError == nil,
                path: configState.activePath ?? RoadieConfigLoader.defaultConfigPath(),
                error: configState.lastError
            )
        )
        guard status.needsRewrite(comparedTo: lastWritten) else { return false }
        do {
            try status.write(to: path)
            lastWritten = status
            return true
        } catch {
            fputs("roadied: daemon status not written: \(error)\n", stderr)
            return false
        }
    }
}
