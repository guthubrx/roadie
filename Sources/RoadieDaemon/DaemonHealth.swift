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

    /// `state.failed` : audit en échec ou réparations non écrites (REL-021).
    public var failed: Bool {
        state.failed || layout.failed > 0 || health.failed
    }
}

/// Action de macOS au double-clic sur une barre de titre (SPEC-050).
public enum MacOSDoubleClickAction: Equatable, Sendable {
    case zoom
    case minimize
    case none
}

/// Réglages macOS qui déplacent ou redimensionnent les fenêtres à la place de Roadie (SPEC-049).
/// Lecture seule : Roadie ne modifie jamais ces réglages.
public struct MacOSWindowSetting: Equatable, Sendable {
    public var domain: String
    public var key: String
    /// Version majeure de macOS à partir de laquelle une clé absente vaut « activé ».
    public var enabledByDefaultSince: Int?
    public var label: String
    public var location: String

    /// Réglages vérifiés par `roadie query health`. Une clé absente prend le défaut de macOS.
    public static let all: [MacOSWindowSetting] = [
        MacOSWindowSetting(
            domain: "com.apple.WindowManager", key: "GloballyEnabled", enabledByDefaultSince: nil,
            label: "Stage Manager",
            location: tr("Réglages Système > Bureau et Dock > Stage Manager", "System Settings > Desktop & Dock > Stage Manager")
        ),
        MacOSWindowSetting(
            domain: "com.apple.WindowManager", key: "EnableTilingByEdgeDrag", enabledByDefaultSince: 15,
            label: tr("juxtaposition en glissant une fenêtre vers un bord de l'écran", "tiling by dragging a window to a screen edge"),
            location: tr("Réglages Système > Bureau et Dock > Fenêtres", "System Settings > Desktop & Dock > Windows")
        ),
        MacOSWindowSetting(
            domain: "com.apple.WindowManager", key: "EnableTopTilingByEdgeDrag", enabledByDefaultSince: 15,
            label: tr("remplissage de l'écran en glissant une fenêtre vers la barre des menus", "filling the screen by dragging a window to the menu bar"),
            location: tr("Réglages Système > Bureau et Dock > Fenêtres", "System Settings > Desktop & Dock > Windows")
        ),
        MacOSWindowSetting(
            domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop", enabledByDefaultSince: 14,
            label: tr("clic sur le fond d'écran pour afficher le bureau (« Toujours »)", "click wallpaper to reveal desktop (“Always”)"),
            location: tr("Réglages Système > Bureau et Dock > Cliquer sur le fond d'écran pour afficher le bureau", "System Settings > Desktop & Dock > Click wallpaper to reveal desktop")
        ),
    ]

    /// Domaine des préférences globales de macOS.
    public static let globalDomain = kCFPreferencesAnyApplication as String

    /// « Double-cliquer sur la barre de titre d'une fenêtre pour » (Bureau et Dock). Clé absente :
    /// ancienne préférence de réduction, sinon agrandissement, défaut de macOS. O(1).
    public static func doubleClickAction(read: (_ domain: String, _ key: String) -> Any?) -> MacOSDoubleClickAction {
        if let value = read(globalDomain, "AppleActionOnDoubleClick") as? String {
            switch value {
            case "None": return .none
            case "Minimize": return .minimize
            default: return .zoom
            }
        }
        let minimize = (read(globalDomain, "AppleMiniaturizeOnDoubleClick") as? NSNumber)?.boolValue ?? false
        return minimize ? .minimize : .zoom
    }

    /// Vrai si le réglage est actif. `value` : valeur lue, nil si la clé est absente. O(1).
    public func isEnabled(value: Any?, osMajorVersion: Int) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        guard let since = enabledByDefaultSince else { return false }
        return osMajorVersion >= since
    }
}

public struct DaemonHealthService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let events: EventLog
    private let pidFilePath: String
    private let statusPath: String
    private let componentRegistry: () -> [(component: String, pid: Int32, startedAt: Date)]
    private let readPreference: (_ domain: String, _ key: String) -> Any?
    private let osMajorVersion: Int

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        events: EventLog = EventLog(),
        pidFilePath: String = "\(NSHomeDirectory())/.roadies/roadied.pid",
        statusPath: String = DaemonStatus.defaultPath,
        componentRegistry: @escaping () -> [(component: String, pid: Int32, startedAt: Date)] = ComponentLockFile.registry,
        readPreference: @escaping (_ domain: String, _ key: String) -> Any? = { domain, key in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        },
        osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) {
        self.readPreference = readPreference
        self.osMajorVersion = osMajorVersion
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
        checks.append(Self.macOSWindowSettingsCheck(
            read: readPreference, osMajorVersion: osMajorVersion,
            roadieDoubleClickMaximize: service.effectiveConfig.experimental.titlebarContextMenu.doubleClickMaximize
        ))
        return DaemonHealthReport(checks: checks)
    }

    /// Réglages macOS qui déplacent les fenêtres (SPEC-049) : `warn` si l'un est actif, jamais `fail`.
    /// O(r), r = nombre de réglages vérifiés.
    public static func macOSWindowSettingsCheck(
        read: (_ domain: String, _ key: String) -> Any?,
        osMajorVersion: Int,
        roadieDoubleClickMaximize: Bool = false
    ) -> DaemonHealthCheck {
        var active = MacOSWindowSetting.all.filter {
            $0.isEnabled(value: read($0.domain, $0.key), osMajorVersion: osMajorVersion)
        }
        // SPEC-050 : le double-clic Roadie n'agit que si macOS ne fait rien de ce double-clic.
        if roadieDoubleClickMaximize, MacOSWindowSetting.doubleClickAction(read: read) != .none {
            active.append(MacOSWindowSetting(
                domain: MacOSWindowSetting.globalDomain, key: "AppleActionOnDoubleClick", enabledByDefaultSince: nil,
                label: tr("action de macOS au double-clic sur la barre de titre, à régler sur « Ne rien faire »", "macOS action on title bar double-click, to set to “Do Nothing”"),
                location: tr("Réglages Système > Bureau et Dock > Double-cliquer sur la barre de titre d'une fenêtre pour", "System Settings > Desktop & Dock > Double-click a window's title bar to")
            ))
        }
        guard !active.isEmpty else {
            return DaemonHealthCheck(level: .ok, name: "macos-window-settings", message: tr("aucun réglage macOS en conflit", "no conflicting macOS setting"))
        }
        let details = active.map { "\($0.label) (\($0.location))" }.joined(separator: " ; ")
        return DaemonHealthCheck(
            level: .warn,
            name: "macos-window-settings",
            message: tr("réglages macOS qui déplacent les fenêtres à la place de Roadie, à désactiver : \(details)", "macOS settings that move windows instead of Roadie, to turn off: \(details)")
        )
    }

    public func heal() -> DaemonHealReport {
        // Génération ouverte à l'entrée de la commande (A13, T223).
        let generation = PlacementGeneration.shared.next()
        let parkingReport = applyParkingTransition(snapshot: service.snapshot())
        appendParkingEvent(parkingReport)

        let stateReport = StateAuditService(service: service, stageStore: stageStore).heal()
        let snapshot = service.snapshot()
        let layoutResult = service.apply(service.applyPlan(from: snapshot, generation: generation), generation: generation)
        let healthReport = run()
        return DaemonHealReport(parking: parkingReport, state: stateReport, layout: layoutResult, health: healthReport)
    }

    /// Heal léger au changement d'écran : un seul snapshot, transition de parking, sauvegarde
    /// si l'état change. Le tick suivant du tiler applique la disposition. Le heal complet
    /// (`heal()`) prend plusieurs snapshots et purge les membres absents, ce qu'il faut éviter
    /// pendant qu'un écran se reconfigure (fenêtres transitoirement invisibles pour AX).
    public func healDisplayChange(snapshot: DaemonSnapshot? = nil) -> DisplayParkingReport {
        let report = applyParkingTransition(snapshot: snapshot ?? service.snapshot())
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
    public static let current = "0.11.0"
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
