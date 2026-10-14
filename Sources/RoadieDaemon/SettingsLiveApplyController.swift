import Foundation
import RoadieCore

/// Les écritures validées des paramètres demandent une passe au tiler sans attendre AX
/// ou son filet périodique. La comparaison des domaines évite un retuilage pour une police,
/// y compris après l'édition complète du fichier (`settingID == "*"`).
@MainActor
public final class SettingsLiveApplyController {
    private let configService: ConfigReloadService
    private let center: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let stageStore: StageStore
    private let events: EventLog
    private let onLayoutChange: @MainActor (Bool) -> Void
    private let onBorderChange: @MainActor () -> Void
    private var previousConfig: RoadieConfig
    private var previousRail: RailGeometry
    private var observer: NSObjectProtocol?
    private var distributedObserver: NSObjectProtocol?

    public init(
        configService: ConfigReloadService = .shared,
        notificationCenter: NotificationCenter = .default,
        distributedNotificationCenter: NotificationCenter = DistributedNotificationCenter.default(),
        stageStore: StageStore? = nil,
        events: EventLog = EventLog(),
        onLayoutChange: @escaping @MainActor (Bool) -> Void,
        onBorderChange: @escaping @MainActor () -> Void = {}
    ) {
        self.configService = configService
        self.center = notificationCenter
        self.distributedCenter = distributedNotificationCenter
        self.stageStore = stageStore ?? SnapshotService(configService: configService).effectiveStageStore
        self.events = events
        self.onLayoutChange = onLayoutChange
        self.onBorderChange = onBorderChange
        self.previousConfig = configService.currentConfig()
        self.previousRail = RailGeometry(settings: RailSettings.load(path: configService.state.activePath ?? RoadieConfigLoader.defaultConfigPath()))
    }

    public func start() {
        guard observer == nil else { return }
        observer = observeChanges(in: center)
        distributedObserver = observeChanges(in: distributedCenter)
    }

    private func observeChanges(in center: NotificationCenter) -> NSObjectProtocol {
        center.addObserver(forName: .roadieSettingsDidChange, object: nil, queue: nil) { [weak self] note in
            guard let path = note.userInfo?["configPath"] as? String else { return }
            let settingID = note.userInfo?["settingID"] as? String ?? "*"
            // NotificationCenter peut publier pendant une écriture hors du thread principal.
            // Ne pas transporter Notification (non Sendable) ni retenir le verrou du service.
            Task { @MainActor [weak self] in
                guard self?.observer != nil else { return }
                self?.applyChange(configPath: path, settingID: settingID)
            }
        }
    }

    public func stop() {
        if let observer { center.removeObserver(observer) }
        if let distributedObserver { distributedCenter.removeObserver(distributedObserver) }
        observer = nil
        distributedObserver = nil
    }

    /// Même contrôle que le rail et les overlays : une fenêtre éditant un autre fichier
    /// ne doit pas retuiler la configuration active. Les liens symboliques sont résolus.
    func applyChange(configPath: String, settingID: String) {
        let activePath = configService.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        guard Self.resolvedPath(configPath) == Self.resolvedPath(activePath) else { return }
        let config = configService.currentConfig()
        guard configService.state.lastValidation != .failed else { return }
        let rail = RailGeometry(settings: RailSettings.load(path: activePath))
        let geometryChanged = config.tiling != previousConfig.tiling || rail != previousRail
        let layoutChanged = geometryChanged
            || config.desktops != previousConfig.desktops
            || config.stageManager != previousConfig.stageManager
            || config.exclusions != previousConfig.exclusions
            || config.windowPlacement != previousConfig.windowPlacement
            || config.rules != previousConfig.rules
            || config.focus.stageFollowsFocus != previousConfig.focus.stageFollowsFocus
        let bordersChanged = config.fx.borders != previousConfig.fx.borders
        var appliedConfig = config
        do {
            try stageStore.applyConfiguredStageNameChanges(
                from: previousConfig.stageManager.workspaces, to: config.stageManager.workspaces
            )
        } catch {
            // Un échec de persistance reste identifiable lors de la prochaine modification
            // validée ; aucune boucle de retry ou seconde notification n'est créée ici.
            appliedConfig.stageManager.workspaces = previousConfig.stageManager.workspaces
            events.append(RoadieEvent(type: "settings.stage_names_apply_failed", details: [
                "path": activePath, "error": String(describing: error)
            ]))
        }
        previousConfig = appliedConfig
        previousRail = rail
        if layoutChanged { onLayoutChange(geometryChanged) }
        if bordersChanged { onBorderChange() }
    }

    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Seules les propriétés du rail qui changent les conteneurs du tiler comptent ici.
    private struct RailGeometry: Equatable {
        var width: Double
        var autoHide: Bool
        var edgeHitWidth: Double
        var layoutMode: String
        var dynamicLeftGap: Bool

        init(settings: RailSettings) {
            width = settings.width
            autoHide = settings.autoHide
            edgeHitWidth = settings.edgeHitWidth
            layoutMode = settings.layoutMode
            dynamicLeftGap = settings.dynamicLeftGap
        }
    }
}
