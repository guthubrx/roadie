import Darwin
import Foundation

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

public struct DaemonHealthService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let pidFilePath: String

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        pidFilePath: String = "\(NSHomeDirectory())/.roadies/roadied.pid"
    ) {
        self.service = service
        self.stageStore = stageStore
        self.pidFilePath = pidFilePath
    }

    public func run() -> DaemonHealthReport {
        let selfTest = SelfTestService(service: service, stageStore: stageStore).run()
        let audit = StateAuditService(service: service, stageStore: stageStore).run()
        var checks = [pidCheck()]
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

    private func pidCheck() -> DaemonHealthCheck {
        guard let raw = try? String(contentsOfFile: pidFilePath).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(raw)
        else {
            return DaemonHealthCheck(level: .warn, name: "pidfile", message: "missing")
        }

        let running = kill(pid, 0) == 0
        return DaemonHealthCheck(
            level: running ? .ok : .fail,
            name: "process",
            message: "pid=\(pid) running=\(running)"
        )
    }
}
