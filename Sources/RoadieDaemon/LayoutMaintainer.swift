import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler

public struct MaintenanceTick: Equatable, Codable, Sendable {
    public var commands: Int
    public var applied: Int
    public var clamped: Int
    public var failed: Int
    public var accessibilityDenied: Bool
    public var manualResizeDetected: Bool

    public init(
        commands: Int,
        applied: Int,
        clamped: Int,
        failed: Int,
        accessibilityDenied: Bool = false,
        manualResizeDetected: Bool = false
    ) {
        self.commands = commands
        self.applied = applied
        self.clamped = clamped
        self.failed = failed
        self.accessibilityDenied = accessibilityDenied
        self.manualResizeDetected = manualResizeDetected
    }
}

public final class LayoutMaintainer {
    private var service: SnapshotService
    private let events: EventLog
    /// Cycle du filet de sécurité, seulement pour la durée de vie du snapshot publié (FR-023).
    /// Aucune attente n'en dépend : les durées de `LayoutTolerance` sont absolues (SPEC-017 R5).
    private let intervalSeconds: TimeInterval
    private let now: () -> Date
    private let staticRuleEngine: WindowRuleEngine?
    /// Configuration active du processus, rechargée par `roadie config reload` (REL-014).
    private let configService: ConfigReloadService
    /// Session 132 : place des fenêtres flottantes.
    private let floatingPlacement = FloatingPlacement()
    private let store: StageStore
    private let dragActivity: WindowDragActivity
    private let commandActivity: LayoutCommandActivity
    /// Vrai tant qu'un bouton de souris est enfoncé (FR-010). Injectable pour les tests.
    private let mouseButtonsPressed: () -> Bool
    /// Vrai pendant Mission Control (SPEC-062). Injectable pour les tests.
    private let missionControlActive: () -> Bool
    /// Dernière détection de Mission Control et début de la pause en cours.
    private var missionControlLastSeen: Date?
    private var missionControlPausedAt: Date?
    /// Maintien de l'aperçu actif du lanceur (SPEC-078) ; injectable par les tests.
    private let previewHold: LayoutPreviewHold
    private var previewPausedAt: Date?
    /// Délai après la dernière détection : l'animation de fermeture rapporte encore des cadres réduits.
    static let missionControlSettle: TimeInterval = 0.4
    /// Mémoire des frames écrites : écho, réponse de l'application, refus (R6, A4, A14).
    private let writtenFrames: WrittenFrameRegistry
    /// Génération de placement globale (A13).
    private let generations: PlacementGeneration
    /// Session de geste terminée, consommée une seule fois (A17). Injectable pour les tests.
    private let takeGesture: () -> GestureSession?
    /// Une session au plus : plafond absolu 2 s, dont 300 ms d'observation hors garde.
    /// Les pas de 50 ms utilisent l'ordonnanceur existant ; aucune boucle ni état persisté.
    private struct PendingGesture {
        let session: GestureSession
        let windowID: WindowID
        let pid: pid_t
        let scope: StageScope
        let expiresAt: Date
        var observationRemaining: TimeInterval = 0.3
        var lastObservationAt: Date?
        var pollAt: Date
    }
    private var pendingGesture: PendingGesture?
    /// Type du bureau courant d'un écran : vrai = bureau utilisateur, nil = sonde indisponible (A19).
    private let spaceProbe: (String) -> Bool?
    /// Lecture AX fraîche d'un cadre (seconde observation d'un refus, repli de la garde, stabilité ;
    /// A14, A19, A20). nil = lecture échouée : elle ne prouve rien (T218).
    private let readFrame: (WindowSnapshot) -> CGRect?
    /// Relevé de la passe rejoué pour sa copie de travail (R11, T210). nil = nouveau relevé.
    private let scanReplay: ReplayableSnapshotProvider?
    private let episodes: EpisodeContext
    private var cachedRuleEngine: WindowRuleEngine?
    /// Règles du moteur en cache ; nil = jamais lues.
    private var cachedRules: [WindowRule]?
    private var clampedFrames: [UInt32: ClampedFrame] = [:]
    /// Refus expirés gardés jusqu'à la demande suivante : un refus identique qui revient devient
    /// durable, sinon la fenêtre et ses voisines bougent toutes les 30 s (SPEC-083).
    private var expiredClamps: [UInt32: ClampedFrame] = [:]
    private var failedFrames: [UInt32: FailedFrame] = [:]
    /// Échecs expirés gardés de même : un échec identique qui revient devient durable, sinon
    /// l'écriture refusée est refaite toutes les 30 s (T3 Code, SPEC-086).
    private var expiredFailures: [UInt32: FailedFrame] = [:]
    /// Échecs des placements directs : attendre une nouvelle géométrie ou intention explicite.
    private var failedRestorations: [WindowID: FailedRestoration] = [:]
    private var lastRestorationActivationWindowID: WindowID?
    /// Transfert échoué : attend avant de refaire la même réparation (même PID et même cadre).
    private var failedDriftWindows: [WindowID: (window: WindowSnapshot, retryAt: Date)] = [:]
    /// Fenêtres neuves que le placement doit encore poser sur leur écran : macOS les ouvre souvent
    /// ailleurs, le rattachement physique attend la fin du délai (SPEC-083).
    private var newWindowDriftGraceUntil: [WindowID: Date] = [:]
    /// Fenêtres fermées que leur application garde en mémoire (SPEC-083, critères SPEC-065).
    private let retiredWindowProbe: ([WindowID: Int32]) -> Set<WindowID>
    private var nextRetiredCheckAt: Date?
    /// Écritures réussies que l'application a annulées (modes sans arbre seulement, A3).
    private var revertedAppliedFrames: [UInt32: RevertedAppliedFrame] = [:]
    /// Référence d'observation des modes sans arbre (A3) : un changement s'y lit par différence.
    /// Les modes à arbre ne s'en servent pas : l'arbre fait foi (R2, A4).
    private var lastObservedFrames: [UInt32: Rect]?
    /// Fenêtres en plein écran (natif ou zoom de commande), relues au début de chaque passe.
    private var tickFullscreen: [(entry: ScopedWindowSnapshot, display: DisplaySnapshot)] = []
    /// Scopes exclus de la disposition de la passe (R6) : plein écran, rafale, garde, commande.
    private var tickExcludedScopes: Set<StageScope> = []
    private var priorityWindowIDs: Set<WindowID> = []
    private var lastCommandIntentAt: Date?
    private var manualResizeApplyAfter: Date?
    private var lastDisplaySignature: String?
    private var lastDisplayTopologyChangedAt: Date?
    private var displayTopologySettlesUntil: Date?
    /// Suspension globale qui a arrêté la dernière passe avant le plan (T224) : fin du glisser ou
    /// de sa grâce, `.distantFuture` si l'accessibilité est refusée. nil = aucune.
    private var globalSuspensionUntil: Date?
    private var emittedRuleSkippedKeys: Set<String> = []
    private var emittedRuleAppliedKeys: Set<String> = []
    private var emittedRulePlacementIssueKeys: Set<String> = []
    private var observedRulePlacementWindowIDs: Set<WindowID> = []
    private var lastGrowthClampedExcludedWindowIDs: Set<WindowID> = []
    private var lastCommandActivitySuppressedAt: Date?
    /// Échéance de l'activité de commande qui a suspendu des scopes sans arbre.
    private var commandSuspendedUntil: Date?
    // Rafales et garde de bureau (A5, A6, A18, A19).
    private var lastActiveTiledStageMembershipSignatures: [StageScope: String] = [:]
    private var membershipActivity: [StageScope: MembershipActivity] = [:]
    private var lastActiveLiveMembers: [StageScope: Set<WindowID>] = [:]
    private var departedMembers: [StageScope: Set<WindowID>] = [:]
    private var lastNativeFullscreenWindows: [WindowID: DisplayID] = [:]
    private var spaceGuards: [DisplayID: SpaceGuard] = [:]
    // Budget d'écriture et classement des frames (A2, A4, A13, A14).
    private var lastGenerationSignature: String?
    private var writeCounts: [UInt32: (generation: UInt64, count: Int)] = [:]
    private var externalReverts: [UInt32: UInt64] = [:]
    private var correctedGenerations: [UInt32: UInt64] = [:]
    private struct TreeMinimum {
        var size: CGSize
        let pid: pid_t
        let bundleID: String
        let scope: StageScope
        let mode: WindowManagementMode
    }
    private var treeMinimums: [WindowID: TreeMinimum] = [:]
    private var reportedEchoWrites: [UInt32: Date] = [:]
    /// Lecture échouée d'un refus en attente : prochaine tentative (T218).
    private var refusalReadRetryAt: [UInt32: Date] = [:]
    /// Génération d'une commande appliquée sur un arbre, gardée par la passe interne suivante (T219).
    private var commandGeneration: UInt64?
    private var lastTreeWindowIDs: Set<UInt32> = []
    private var unreadyPlacementWindows: Set<WindowID> = []
    /// Une lecture réussie distingue la disponibilité initiale des refus ultérieurs,
    /// même si la fenêtre était déjà à sa cible et n'a jamais nécessité d'écriture.
    private var placementResolvedPIDs: [WindowID: Int32] = [:]
    // Mesure (A12, A20).
    private var pendingStability: PendingStability?
    private var lastPassEpisodeID: String?
    private var passIndex = 0
    private var settingsGeometryPending = false
    private var exactSettingsScopes: Set<StageScope> = []
    /// Une première relecture différente/inconnue autorise une seule reprise explicite.
    private var settingsRetryAt: [StageScope: Date] = [:]
    private var settingsRetryRunnableScopes: Set<StageScope> = []
    private enum SettingsFrameState { case needsRetry, completed }
    private var settingsFrameStates: [WindowID: SettingsFrameState] = [:]

    /// `service` nil : service de production sur un relevé AX rejouable (T210). Un service injecté
    /// le rejoue si `scanReplay` est son fournisseur.
    public init(
        service: SnapshotService? = nil,
        scanReplay: ReplayableSnapshotProvider? = nil,
        events: EventLog = EventLog(),
        intervalSeconds: TimeInterval = 0.5,
        ruleEngine: WindowRuleEngine? = nil,
        store: StageStore? = nil,
        dragActivity: WindowDragActivity = .shared,
        commandActivity: LayoutCommandActivity = .shared,
        mouseButtonsPressed: (() -> Bool)? = nil,
        missionControlActive: (() -> Bool)? = nil,
        previewHold: LayoutPreviewHold = .shared,
        writtenFrames: WrittenFrameRegistry? = nil,
        generations: PlacementGeneration? = nil,
        takeGesture: (() -> GestureSession?)? = nil,
        spaceProbe: ((String) -> Bool?)? = nil,
        readFrame: ((WindowSnapshot) -> CGRect?)? = nil,
        retiredWindowProbe: (([WindowID: Int32]) -> Set<WindowID>)? = nil,
        episodes: EpisodeContext = .shared,
        configService: ConfigReloadService = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        let replay = service == nil ? ReplayableSnapshotProvider(base: LiveSystemSnapshotProvider()) : scanReplay
        let service = service ?? SnapshotService(provider: replay!)
        self.service = service
        self.scanReplay = replay
        self.events = events
        self.intervalSeconds = intervalSeconds
        self.staticRuleEngine = ruleEngine
        self.configService = configService
        self.store = store ?? service.effectiveStageStore
        self.dragActivity = dragActivity
        self.commandActivity = commandActivity
        // Sous les tests, la souris, les gestes et les bureaux réels de la machine ne comptent pas.
        let testing = TestEnvironment.isRunningTests
        self.mouseButtonsPressed = mouseButtonsPressed
            ?? (testing ? { false } : {
                UserInputActivity.shared.blocksLayout(mouseButtonsPressed: NSEvent.pressedMouseButtons != 0)
            })
        self.missionControlActive = missionControlActive ?? (testing ? { false } : { MissionControlProbe.isActive() })
        self.previewHold = previewHold
        // Sous les tests, registre et génération propres à l'instance : les suites tournent en
        // parallèle avec les mêmes identifiants de fenêtre.
        self.writtenFrames = writtenFrames ?? (testing ? WrittenFrameRegistry() : .shared)
        self.generations = generations ?? (testing ? PlacementGeneration() : .shared)
        self.takeGesture = takeGesture ?? (testing ? { nil } : { UserInputActivity.shared.takeGesture() })
        self.spaceProbe = spaceProbe ?? (testing ? { _ in true } : { SpaceProbe.isUserSpaceActive(displayUUID: $0) })
        self.readFrame = readFrame ?? { [service] in service.readFrame(of: $0) }
        self.retiredWindowProbe = retiredWindowProbe ?? (testing ? { _ in [] } : { WindowSwitcherService.retiredWindows(pids: $0) })
        self.episodes = episodes
        self.now = now
    }

    public func tick() -> MaintenanceTick {
        tick(cause: "safety")
    }

    /// Fenêtres flottantes apparues (session 132) : place retenue ou décalage hors du rail. Ensuite, la place est
    /// seulement retenue après un déplacement. O(n) ; le rail et les règles ne sont lus que pour une fenêtre apparue.
    private func placeFloatingWindows(in snapshot: DaemonSnapshot) {
        let config = service.effectiveConfig
        let moves = floatingPlacement.observe(
            FloatingPlacement.candidates(in: snapshot), displays: snapshot.displays.map(\.frame.cgRect),
            avoidRail: config.exclusions.floatingAvoidRail, railWidth: { CGFloat(RailSettings.load().width) },
            key: { FloatingPlacement.rememberKey(for: $0, rules: config.rules) })
        for move in moves {
            let actual = service.setFrame(move.frame, of: move.window)
            floatingPlacement.applied(move.window.id, frame: actual ?? move.window.frame.cgRect)
            events.append(RoadieEvent(type: "floating.placed", details: [
                "windowID": String(move.window.id.rawValue), "app": move.window.appName, "reason": move.reason,
                "frame": "\(Int(move.frame.minX)),\(Int(move.frame.minY)) \(Int(move.frame.width))x\(Int(move.frame.height))",
                "applied": String(actual != nil)]))
        }
    }

    /// Une nouvelle géométrie de configuration remplace les placements mémorisés, même si
    /// leur écart reste dans la tolérance des intents. Les zooms et les arbres sont conservés.
    /// Appelé avant la demande à TickScheduler : aucune écriture AX ni contournement des gestes.
    public func configurationChanged(invalidateLayoutIntents: Bool) {
        service.invalidateSharedSnapshot()
        guard invalidateLayoutIntents else { return }
        pendingGesture = nil
        service.effectiveIntentStore.mutate { intents in
            intents = intents.filter { $0.value.zoomedWindowID != nil }
        }
        lastCommandIntentAt = nil
        // Nouvelle intention explicite : une variation d'un point dispose de son budget.
        failedRestorations.removeAll()
        settingsGeometryPending = true
        settingsRetryAt.removeAll()
        settingsRetryRunnableScopes.removeAll()
        settingsFrameStates.removeAll()
        _ = generations.next()
        clampedFrames.removeAll()
        expiredClamps.removeAll()
        failedFrames.removeAll()
        expiredFailures.removeAll()
        revertedAppliedFrames.removeAll()
    }

    /// Une passe (A1, A15) : état logique sur une copie de travail (règles, déplacements adoptés,
    /// zoom quitté), calcul des placements (masquage, épinglages, zoom, disposition), arbitrage
    /// par fenêtre, une seule application, puis focus. Seules les suspensions globales (topologie
    /// d'écrans, glisser, bouton enfoncé) arrêtent la passe avant le plan. Un seul relevé AX : la
    /// copie de travail rejoue ce relevé (R11, T210). `cause` suit le contrat des événements
    /// (`ax:<notification>`, `command:<nom>`, `drag`, `deadline`, `safety`) ; une échéance est nommée ici.
    // O(n · s) - n fenêtres, s scopes actifs.
    public func tick(cause: String) -> MaintenanceTick {
        // La précision des paramètres n'est jamais conservée dans les autres appels du service.
        defer { service.exactLayoutScopes = [] }
        let startedAt = Date()
        let observationStartedAt = now()
        // SPEC-062 : pendant Mission Control, macOS rapporte des cadres réduits et déplacés. Aucun relevé
        // (il enregistrerait ces cadres), aucune écriture (elle rétrécirait les fenêtres masquées), aucune
        // adoption de déplacement. La référence d'observation reste celle d'avant ; reprise après l'animation.
        // SPEC-078 : aperçu actif du lanceur ; ses cadres restent jusqu'à sa fin (ou son échéance).
        if previewHold.isHeld(at: observationStartedAt) {
            if previewPausedAt == nil {
                previewPausedAt = observationStartedAt
                events.append(RoadieEvent(type: "layout_paused_preview", details: ["cause": cause]))
            }
            globalSuspensionUntil = observationStartedAt.addingTimeInterval(0.1)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        if let pausedAt = previewPausedAt {
            previewPausedAt = nil
            events.append(RoadieEvent(type: "layout_resumed_preview", details: [
                "durationMs": String(format: "%.0f", observationStartedAt.timeIntervalSince(pausedAt) * 1000)
            ]))
        }
        if missionControlActive() { missionControlLastSeen = observationStartedAt }
        if let lastSeen = missionControlLastSeen,
           observationStartedAt.timeIntervalSince(lastSeen) < Self.missionControlSettle {
            if missionControlPausedAt == nil {
                missionControlPausedAt = observationStartedAt
                events.append(RoadieEvent(type: "layout_paused_mission_control", details: ["cause": cause]))
            }
            globalSuspensionUntil = observationStartedAt.addingTimeInterval(0.25)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        if let pausedAt = missionControlPausedAt {
            missionControlPausedAt = nil
            missionControlLastSeen = nil
            events.append(RoadieEvent(type: "layout_resumed_mission_control", details: [
                "durationMs": String(format: "%.0f", observationStartedAt.timeIntervalSince(pausedAt) * 1000)
            ]))
        }
        var scans = 1
        var snapshot = service.producerSnapshot(cycle: intervalSeconds)
        globalSuspensionUntil = nil
        guard snapshot.permissions.accessibilityTrusted else {
            globalSuspensionUntil = .distantFuture
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        let tickNow = now()

        let currentDisplaySignature = displaySignature(snapshot.displays)
        // Une fenêtre candidate sans scope attend le parking d'un écran absent. Au démarrage,
        // aucune notification d'écran n'est garantie ; la première passe stable le récupère.
        let needsDisplayRecovery = !snapshot.displays.isEmpty && snapshot.windows.contains {
            $0.window.isTileCandidate && $0.scope == nil
        }
        if (lastDisplaySignature != nil && lastDisplaySignature != currentDisplaySignature)
            || (lastDisplaySignature == nil && needsDisplayRecovery) {
            let previousSignature = lastDisplaySignature ?? "startup"
            self.lastDisplaySignature = currentDisplaySignature
            lastDisplayTopologyChangedAt = tickNow
            displayTopologySettlesUntil = tickNow.addingTimeInterval(LayoutTolerance.displayTopologySettle)
            lastObservedFrames = scopedFrames(in: snapshot)
            clampedFrames.removeAll()
            expiredClamps.removeAll()
            failedFrames.removeAll()
            expiredFailures.removeAll()
            failedRestorations.removeAll()
            failedDriftWindows.removeAll()
            revertedAppliedFrames.removeAll()
            events.append(RoadieEvent(type: "display.topology_settling", details: [
                "from": previousSignature,
                "to": currentDisplaySignature
            ]))
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        lastDisplaySignature = currentDisplaySignature
        if let displayTopologySettlesUntil, tickNow < displayTopologySettlesUntil {
            lastObservedFrames = scopedFrames(in: snapshot)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        displayTopologySettlesUntil = nil
        if needsDisplayRecovery {
            let report = DaemonHealthService(service: service, stageStore: store, events: events)
                .healDisplayChange(snapshot: snapshot)
            if report.kind == .park || report.kind == .restore || report.restoredStageCount > 0 {
                // Même relevé AX en production : seule la copie logique doit être reconstruite.
                scanReplay?.replayLastScan()
                snapshot = service.snapshot(followFocus: false)
                if scanReplay == nil { scans += 1 }
            }
        }
        if cause.hasPrefix("command:") {
            // Une intention explicite libère aussi le refus nonTree de la restauration focalisée.
            for id in failedRestorations.keys {
                failedFrames[id.rawValue] = nil
                expiredFailures[id.rawValue] = nil
            }
            failedRestorations.removeAll()
        }
        failedDriftWindows = failedDriftWindows.filter { tickNow < $0.value.retryAt }
        // Seules les fenêtres neuves ouvertes hors de l'écran de leur scope attendent : pas de passe
        // supplémentaire pour les autres, ni pour une fenêtre déjà fermée.
        let liveIDs = Set(snapshot.windows.map(\.window.id))
        newWindowDriftGraceUntil = newWindowDriftGraceUntil.filter { tickNow < $0.value && liveIDs.contains($0.key) }
        for entry in snapshot.windows where entry.isNewlyScoped {
            guard let scope = entry.scope,
                  let display = snapshot.displays.first(where: { $0.frame.cgRect.contains(entry.window.frame.center) }),
                  display.id != scope.displayID else { continue }
            newWindowDriftGraceUntil[entry.window.id] = tickNow.addingTimeInterval(LayoutTolerance.newWindowDriftGrace)
        }
        let cause = cause == "deadline" ? "deadline:\(dueDeadlineName(now: tickNow))" : cause
        forgetGoneWindows(liveWindowIDs: Set(snapshot.windows.map(\.window.id.rawValue)), now: tickNow)
        closeRetiredMembers(in: snapshot, now: tickNow)
        let currentWindowsByID = Dictionary(snapshot.windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { first, _ in first })
        for (id, failed) in failedRestorations {
            guard let window = currentWindowsByID[id],
                  window.pid != failed.pid || window.bundleID != failed.bundleID else { continue }
            failedRestorations[id] = nil
            failedFrames[id.rawValue] = nil
            expiredFailures[id.rawValue] = nil
        }
        tickFullscreen = fullscreenEntries(in: snapshot)
        tickExcludedScopes = []
        let generationBefore = generations.current
        var generation = currentGeneration(cause: cause, snapshot: snapshot)
        // Les gardes sont calculées après récupération, sur les scopes effectivement présents.
        let burstingScopes = burstScopes(in: snapshot, now: tickNow)
        var settlingScopes = spaceGuardScopes(in: snapshot, now: tickNow).union(burstingScopes)
        var treeScopes = activeTreeScopes(in: snapshot)
        // Pas de grâce de fin de glisser pour les modes à arbre : le relâchement fait la passe (A11).
        let releaseGrace = activeScopes(in: snapshot).contains { !treeScopes.contains($0) }
        if dragActivity.isActive(now: tickNow, includingReleaseGrace: releaseGrace) {
            globalSuspensionUntil = dragActivity.suspensionEnd()
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        if mouseButtonsPressed() {
            // FR-010 : aucun plan tant qu'un bouton est enfoncé (resize par un bord, clic long).
            // Référence d'observation et priorité conservées : le geste est traité au relâchement.
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        placeFloatingWindows(in: snapshot)

        if settingsGeometryPending {
            exactSettingsScopes.formUnion(activeScopes(in: snapshot).filter {
                snapshot.state.stage(scope: $0)?.mode.isTiled == true
            })
            settingsGeometryPending = false
        }
        service.exactLayoutScopes = exactSettingsScopes

        let waitingSettingsScopes = Set(settingsRetryAt.compactMap { scope, due in
            tickNow < due ? scope : nil
        })
        tickExcludedScopes.formUnion(waitingSettingsScopes)

        tickExcludedScopes.formUnion(settlingScopes)
        var observedFrames = scopedFrames(in: snapshot)
        let changedForChurn = changedWindows(in: observedFrames, outside: treeScopes, snapshot: snapshot)
        if !settlingScopes.isEmpty {
            observe(observedFrames, scopes: settlingScopes, in: snapshot)
        }
        var suspension = commandSuspension(in: snapshot, treeScopes: treeScopes, observedFrames: observedFrames, now: tickNow)
        tickExcludedScopes.formUnion(suspension.scopes)

        // Geste terminé sur une fenêtre d'un arbre : intention externe, nouvelle génération (A13).
        // Un geste n'est supprimé que sur preuve d'un dépôt reconnu pour cette session (A17, T216) :
        // dans ce processus, le dépôt consomme la session avant cette passe (un glisser encore en
        // cours arrête la passe plus haut sans la consommer) ; d'un autre processus, il laisse sa
        // preuve dans le fichier partagé du glisser, postérieure au début de la session.
        var gesture = layoutGesture(in: &snapshot, excluding: settlingScopes.union(waitingSettingsScopes), now: tickNow, observationStartedAt: observationStartedAt)
        observedFrames = scopedFrames(in: snapshot)
        if let raw = gesture?.windowID,
           let scope = snapshot.windows.first(where: { $0.window.id.rawValue == raw })?.scope,
           treeScopes.contains(scope) {
            generation = generations.next()
        }
        var resizedEntry = resizedGestureEntry(gesture, in: snapshot)
        if let resizedEntry, let scope = resizedEntry.scope {
            failedDriftWindows[resizedEntry.window.id] = nil
            // Une commande antérieure ne doit pas consommer le geste manuel qui la suit.
            suspension.resumed.insert(scope)
            suspension.scopes.remove(scope)
            tickExcludedScopes = settlingScopes.union(suspension.scopes)
        }
        let gestureWindowID = gesture?.windowID.map { WindowID(rawValue: $0) }

        // 1. État logique (A15) : règles, déplacements d'écran adoptés, rattachement physique.
        let changedWindowIDs = windowIDs(changedForChurn, outside: tickExcludedScopes, in: snapshot)
        let rulePlacements = evaluateRules(in: snapshot)
        var moveCandidates = changedWindowIDs
        if let gestureWindowID { moveCandidates.insert(gestureWindowID) }
        let adoptedMoves = adoptManualDisplayMoves(in: snapshot, changedWindowIDs: moveCandidates)
        // Un scope à arbre n'adopte pas un écran physique sans geste ni commande (T217).
        let driftMoves = adoptedMoves.isEmpty && changedWindowIDs.isEmpty
            ? reconcileStableVisibleDisplayDrift(in: snapshot, excluding: tickExcludedScopes.union(treeScopes))
            : []
        if !rulePlacements.isEmpty || !adoptedMoves.isEmpty || !driftMoves.isEmpty {
            // Copie de travail : l'état persisté vient de changer, la passe continue sur lui, avec
            // les fenêtres déjà relevées (T210). Scopes à arbre et exclusions en sont recalculés (T214).
            scanReplay?.replayLastScan()
            snapshot = service.snapshot(followFocus: false)
            if scanReplay == nil { scans += 1 }
            tickFullscreen = fullscreenEntries(in: snapshot)
            observedFrames = scopedFrames(in: snapshot)
            generation = generations.next()
            treeScopes = activeTreeScopes(in: snapshot)
            settlingScopes = Set(spaceGuards.keys.compactMap { snapshot.state.activeScope(on: $0) }).union(burstingScopes)
            suspension.treeDisplays = Set(treeScopes.map(\.displayID))
            suspension.scopes = activeScopes(in: snapshot).filter(suspension.covers)
            tickExcludedScopes = settlingScopes.union(suspension.scopes)
        }
        let closedZoomRestoration = closedZoomRestorationCommands(in: snapshot)
        // Réutilise la lecture courante du masquage, une seule fois et seulement avec un plein écran actif.
        let hasActiveFullscreen = tickFullscreen.contains { item in
            item.entry.scope.map { snapshot.state.activeScope(on: $0.displayID) == $0 } == true
        }
        let activatesApplication = cause.contains("didActivateApplication") || cause.contains("AXFocusedWindowChanged")
        let observedFocusedWindowID = hasActiveFullscreen || activatesApplication ? service.focusedWindowID() : nil
        if activatesApplication {
            if let id = observedFocusedWindowID, id != lastRestorationActivationWindowID,
               failedRestorations.removeValue(forKey: id) != nil {
                failedFrames[id.rawValue] = nil
                expiredFailures[id.rawValue] = nil
            }
            lastRestorationActivationWindowID = observedFocusedWindowID
        }
        let systemFocusedWindowID = hasActiveFullscreen ? observedFocusedWindowID : nil
        let focusRestore = focusedHiddenRestore(in: snapshot, cause: cause, systemFocusedWindowID: systemFocusedWindowID)

        // Une reprise ne récupère pas l'intent automatique construit sur le cadre ignoré.
        // Les échecs mémorisés ne doivent pas absorber cette unique nouvelle demande.
        let retryManualHold = manualResizeApplyAfter.map { tickNow < $0 } == true
            ? activeScopes(in: snapshot).filter { snapshot.state.stage(scope: $0)?.mode.usesTreeEngine != true }
            : []
        // Un zoom ordinaire/natif suspend la disposition. Le zoom réservant le rail
        // garde sa cible géométrique et peut appliquer la précision des paramètres.
        let retryFullscreenHold = Set(tickFullscreen.compactMap { item -> StageScope? in
            guard let scope = item.entry.scope else { return nil }
            return item.entry.window.furniture?.isNativeFullscreen == true
                || service.commandLayoutIntent(scope: scope)?.zoomReservesRail != true ? scope : nil
        })
        let authorizedRetryScopes = activeScopes(in: snapshot).subtracting(tickExcludedScopes).subtracting(
            retryFullscreenHold.union(retryManualHold)
        )
        for (scope, due) in settingsRetryAt where due <= tickNow && authorizedRetryScopes.contains(scope) {
            if service.commandLayoutIntent(scope: scope)?.zoomedWindowID == nil {
                service.removeLayoutIntent(scope: scope)
            }
            for entry in snapshot.windows where entry.scope == scope {
                clampedFrames[entry.window.id.rawValue] = nil
                expiredClamps[entry.window.id.rawValue] = nil
                failedFrames[entry.window.id.rawValue] = nil
                expiredFailures[entry.window.id.rawValue] = nil
                revertedAppliedFrames[entry.window.id.rawValue] = nil
            }
        }

        // 2. Calcul des placements depuis la copie de travail.
        var plan = PassPlan()
        suppressKnownUnmovableFrames(in: ApplyPlan(commands: closedZoomRestoration), snapshot: snapshot)
            .commands.forEach { plan.add($0, .layout) }
        if let restoration = focusRestore?.restoration {
            suppressKnownUnmovableFrames(in: restoration, snapshot: snapshot).commands.forEach { plan.add($0, .layout) }
        }
        let hiddenInactive = hideInactiveStageCommands(in: snapshot)
        let hiddenSiblings = fullscreenSiblingHideCommands(in: snapshot, systemFocusedWindowID: systemFocusedWindowID)
        let restoredPins = pinRestoreCommands(in: snapshot)
        let reanchoredZoomed = zoomReanchorCommands(in: snapshot)
        hiddenInactive.forEach { plan.add($0, .hide) }
        hiddenSiblings.forEach { plan.add($0, .hide) }
        restoredPins.forEach { plan.add($0, .pin) }
        reanchoredZoomed.forEach { plan.add($0, .zoom) }

        // Plein écran natif ou zoom de commande : seul son scope est exclu de la disposition (FR-016).
        let fullscreenScopes = Set(tickFullscreen.compactMap(\.entry.scope))
        if !fullscreenScopes.isEmpty {
            tickExcludedScopes.formUnion(fullscreenScopes)
            observe(observedFrames, scopes: fullscreenScopes, in: snapshot)
            handleFullscreenScopeChanges(in: snapshot, changedWindowIDs: changedForChurn, fullscreenScopes: fullscreenScopes)
        }

        if let pending = pendingGesture {
            if !validPendingGesture(pending, in: snapshot) || fullscreenScopes.contains(pending.scope) {
                pendingGesture = nil
                gesture = nil
                resizedEntry = nil
            } else if gesture == nil {
                // Ne pas réécrire l'ancienne tuile avant que l'application publie la taille finale.
                tickExcludedScopes.insert(pending.scope)
            }
        }

        if let gesture, let raw = gesture.windowID, let start = gesture.startFrame,
           let entry = snapshot.windows.first(where: { $0.window.id.rawValue == raw }),
           let scope = entry.scope, !tickExcludedScopes.contains(scope),
           !Self.matches(entry.window.frame.cgRect, start) {
            // Un geste confirmé autorise une nouvelle intention, même vers une cible refusée.
            failedRestorations[entry.window.id] = nil
            failedFrames[raw] = nil
            expiredFailures[raw] = nil
        }

        let waitingPlacementScopes = unreadyPlacementScopes(
            in: snapshot, scopes: treeScopes.subtracting(tickExcludedScopes)
        )
        tickExcludedScopes.formUnion(waitingPlacementScopes)
        let liveTreeScopes = treeScopes.subtracting(tickExcludedScopes)
        lastTreeWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope.map(liveTreeScopes.contains) == true ? entry.window.id.rawValue : nil
        })
        let nonTree = nonTreeLayout(
            in: snapshot,
            manualResizeWindowIDs: resizedEntry.map { [$0.window.id] } ?? [],
            observedFrames: observedFrames,
            changedWindowIDs: windowIDs(changedWindowIDs, outside: tickExcludedScopes, in: snapshot),
            adoptedWindowIDs: Set(adoptedMoves.map(\.window.id) + driftMoves.map(\.window.id)),
            focusPriority: focusRestore.map { Set($0.activeHiddenWindowIDs) } ?? [],
            excluding: tickExcludedScopes.union(treeScopes),
            now: tickNow
        )
        // Modes sans arbre (A3) : leur disposition naît d'un changement observé (geste par
        // différence, anti-rebond, intent) ; une passe qui leur écrit est une intention externe et
        // ouvre sa génération, sinon le budget du point d'écriture la refuserait (A13).
        if !nonTree.commands.isEmpty, generation == generationBefore {
            generation = generations.next()
        }
        let treePlan = treeLayoutCommands(
            in: snapshot,
            scopes: liveTreeScopes,
            gesture: gesture,
            generation: generation,
            now: tickNow
        )
        if gesture != nil, var pending = pendingGesture {
            if !tickExcludedScopes.contains(pending.scope) {
                pendingGesture = nil
            } else {
                // Déplacement sans taille changée, encore retenu par une commande sans arbre.
                // Garder l'intention sans réarmer une date déjà échue ni consommer le temps actif.
                pending.lastObservationAt = nil
                pending.pollAt = min(tickNow.addingTimeInterval(0.05), pending.expiresAt)
                pendingGesture = pending
            }
        }
        treePlan.commands.forEach { plan.add($0, .layout) }
        retargetStabilityCheck(treePlan.targets)
        nonTree.commands.forEach { plan.add($0, .layout) }
        if let focusRestore, let command = focusRestoreCommand(focusRestore, plan: plan, snapshot: snapshot) {
            plan.add(command, focusRestore.isFullscreen ? .zoom : .layout)
        }

        // 3. Arbitrage : une commande par fenêtre (fait par `PassPlan`), aucune écriture dans un
        //    scope en rafale, en garde ou suspendu par une commande (A6, FR-040).
        //    Sur un écran à arbre, masquage, épinglage et zoom comptent aussi au budget (A13).
        let scopesByID = Dictionary(snapshot.windows.compactMap { entry in entry.scope.map { (entry.window.id, $0) } }, uniquingKeysWith: { first, _ in first })
        let treeDisplays = Set(treeScopes.map(\.displayID))
        var restorativeIDs = Set(closedZoomRestoration.map(\.window.id))
        restorativeIDs.formUnion(focusRestore?.restoration?.commands.map(\.window.id) ?? [])
        restorativeIDs.formUnion(focusRestore?.activeHiddenWindowIDs ?? [])
        restorativeIDs.formUnion(hiddenInactive.map(\.window.id))
        restorativeIDs.formUnion(hiddenSiblings.map(\.window.id))
        restorativeIDs.formUnion(restoredPins.map(\.window.id))
        restorativeIDs.formUnion(reanchoredZoomed.map(\.window.id))
        let writable = plan.entries.compactMap { command, priority -> ApplyCommand? in
            guard !defersFailedDrift(command.window, now: tickNow) else { return nil }
            if restorativeIDs.contains(command.window.id), let failed = failedRestorations[command.window.id],
               failed.matches(command, scope: scopesByID[command.window.id])
                || !failed.permits(command, scope: scopesByID[command.window.id]) { return nil }
            guard let scope = scopesByID[command.window.id] else { return command }
            if settlingScopes.contains(scope) || suspension.covers(scope) || waitingSettingsScopes.contains(scope)
                || waitingPlacementScopes.contains(scope) { return nil }
            if priority != .layout || restorativeIDs.contains(command.window.id), treeDisplays.contains(scope.displayID),
               writesUsed(command.window.id.rawValue, generation: generation) >= LayoutTolerance.writeBudgetPerGeneration {
                return nil
            }
            return command
        }

        // 4. Application unique, puis 5. focus (action, pas une frame).
        let layoutWindowIDs = Set(plan.entries.compactMap { $0.priority == .layout ? $0.command.window.id : nil })
        let application = applyPass(
            ApplyPlan(commands: writable),
            in: snapshot,
            layoutWindowIDs: layoutWindowIDs,
            generation: generation,
            source: focusRestore == nil ? nil : "stage_focus_restore"
        )
        let writableByID = Dictionary(writable.map { ($0.window.id, $0) }, uniquingKeysWith: { _, last in last })
        for item in application.result.items where restorativeIDs.contains(item.windowID) {
            guard let command = writableByID[item.windowID] else { continue }
            if item.status == .failed {
                let scope = scopesByID[item.windowID]
                let previous = failedRestorations[item.windowID]
                let previousAttempts = previous.flatMap { $0.continues(command, scope: scope) ? $0.attempts : nil } ?? 0
                let attempts = previousAttempts + 1
                let observed = item.actual ?? readFrame(command.window).map { Rect($0) }
                failedRestorations[item.windowID] = FailedRestoration(command, scope: scope, observed: observed, attempts: attempts)
                // Le refus nonTree ne doit pas prendre notre déplacement partiel pour un geste.
                if let observed, failedFrames[item.windowID.rawValue] != nil {
                    failedFrames[item.windowID.rawValue]?.observedAtFailure = observed
                }
            } else if item.status == .applied {
                failedRestorations[item.windowID] = nil
            }
        }
        let writeEnd = now()
        // Un scope suspendu garde sa demande. Une frame exactement relue consomme la
        // précision ; un écart/inconnu autorise une seule reprise, puis la précision cesse.
        let awaitingManualResize = manualResizeApplyAfter.map { tickNow < $0 } == true
            ? activeScopes(in: snapshot).filter { snapshot.state.stage(scope: $0)?.mode.usesTreeEngine != true }
            : []
        // Sans fenêtre candidate, conserver la demande mais désarmer son réveil.
        // Ne pas utiliser seulement les cibles de la passe : avant l'échéance,
        // waitingSettingsScopes les exclut volontairement de la disposition.
        let populatedRetryScopes = Set(snapshot.windows.compactMap { entry in
            entry.window.isTileCandidate ? entry.scope : nil
        })
        settingsRetryRunnableScopes = activeScopes(in: snapshot).intersection(populatedRetryScopes).subtracting(
            settlingScopes.union(suspension.scopes).union(retryFullscreenHold).union(awaitingManualResize)
        )
        finishExactSettingsPass(
            result: application.result, scopesByID: scopesByID,
            targets: treePlan.targets.merging(Dictionary(plan.entries.map {
                ($0.command.window.id, $0.command.frame.cgRect)
            }, uniquingKeysWith: { _, last in last }), uniquingKeysWith: { _, last in last }),
            observedFrames: observedFrames,
            processedScopes: settingsRetryRunnableScopes.subtracting(waitingSettingsScopes), now: writeEnd
        )
        for placement in rulePlacements where placement.follow {
            _ = service.focus(placement.window)
        }
        finishDriftMoves(driftMoves, result: application.result)

        // Référence des modes sans arbre : frames de la passe, écritures comprises.
        if nonTree.updateBaseline || lastObservedFrames == nil || application.commands > 0 {
            lastObservedFrames = framesAfterApplying(application.result, fallback: observedFrames)
        }
        if nonTree.commands.isEmpty && nonTree.persistCurrentIntents {
            persistCurrentLayoutIntents(in: snapshot, excluding: tickExcludedScopes.union(treeScopes))
        }
        if application.commands > 0 && application.result.clamped == 0 && application.result.failed == 0 {
            persistLayoutIntent(in: snapshot, result: application.result, treeScopes: treeScopes)
        }
        let writtenIDs = Set(application.result.items.map(\.windowID))
        appendPassEvents(
            hiddenInactive: hiddenInactive.filter { writtenIDs.contains($0.window.id) },
            hiddenSiblings: hiddenSiblings.filter { writtenIDs.contains($0.window.id) },
            restoredPins: restoredPins.filter { writtenIDs.contains($0.window.id) },
            reanchoredZoomed: reanchoredZoomed.filter { writtenIDs.contains($0.window.id) },
            focusRestore: focusRestore,
            application: application,
            snapshot: snapshot,
            startedAt: startedAt
        )
        if application.commands > 0 {
            appendLayoutApplyEvent(
                application,
                priorityWindowIDs: nonTree.priorityWindowIDs,
                cause: cause,
                scans: scans,
                generation: generation,
                startedAt: startedAt
            )
            let successfulTargets = Dictionary(application.result.items.filter { $0.status != .failed }
                .map { ($0.windowID, $0.requested.cgRect) }, uniquingKeysWith: { _, last in last })
            if !successfulTargets.isEmpty {
                armStabilityCheck(targets: successfulTargets, startedAt: tickNow, writeEnd: writeEnd)
            }
        }
        checkStability(in: snapshot, now: tickNow, generation: generation)
        if deadlines(now: tickNow).contains(where: \.episode) {
            // Une échéance armée par l'épisode le garde ouvert (A20).
            episodes.continue()
        }
        return MaintenanceTick(
            commands: application.commands,
            applied: application.result.applied,
            clamped: application.result.clamped,
            failed: application.result.failed,
            manualResizeDetected: nonTree.manualResizeDetected
        )
    }

    /// Prochaine échéance interne (T211) : la vraie, même déjà passée, pour celles de l'épisode
    /// (rafale, garde, refus, stabilité), que seule une passe solde ; les autres (anti-rebond d'un
    /// geste des modes sans arbre, fin d'une commande, réglage d'écrans) seulement à venir. Le
    /// plancher anti-boucle est celui de l'ordonnanceur. Pendant une suspension globale (réglage
    /// d'écrans, glisser ou sa grâce), seule sa fin compte : la passe s'y arrête avant les
    /// échéances d'épisode (T224). Accessibilité refusée : aucune. nil = aucune. Ne lit ni l'écran
    /// ni l'état persisté. O(s + r).
    public func nextDeadline(now: Date) -> Date? {
        if let displayTopologySettlesUntil, displayTopologySettlesUntil > now { return displayTopologySettlesUntil }
        if let globalSuspensionUntil, globalSuspensionUntil > now {
            return globalSuspensionUntil == .distantFuture ? nil : globalSuspensionUntil
        }
        return deadlines(now: now).filter { $0.episode || $0.at > now }.map(\.at).min()
    }

    /// Nom de l'échéance qui vient d'échoir, pour la cause `deadline:<nom>` : la plus récente des
    /// échéances passées (les anciennes non soldées sont plus anciennes). O(s + r).
    private func dueDeadlineName(now: Date) -> String {
        deadlines(now: now).filter { $0.at <= now }.max { $0.at < $1.at }?.name ?? "none"
    }

    /// Échéances internes nommées. `episode` : armée par l'épisode en cours (A20) et soldée par
    /// une passe ; sinon, simple date, peut-être ancienne. O(s + r) - r fenêtres d'arbre suivies.
    private func deadlines(now: Date) -> [(name: String, at: Date, episode: Bool)] {
        var due: [(name: String, at: Date, episode: Bool)] = [
            ("topology_settle", displayTopologySettlesUntil), ("manual_resize", manualResizeApplyAfter),
            ("command_suspension", commandSuspendedUntil),
            ("command_intent", lastCommandIntentAt?.addingTimeInterval(LayoutTolerance.commandIntentHold)),
            ("drift_hold", lastDisplayTopologyChangedAt?.addingTimeInterval(LayoutTolerance.displayDriftReconcileHold))
        ].compactMap { name, at in at.map { (name, $0, false) } }
        due += membershipActivity.values.compactMap(\.burstEnd).map { ("burst", $0, true) }
        due += failedDriftWindows.values.map { ("drift_retry", $0.retryAt, false) }
        if let graceEnd = newWindowDriftGraceUntil.values.min() { due.append(("new_window_grace", graceEnd, false)) }
        due += settingsRetryAt.compactMap { scope, at in
            settingsRetryRunnableScopes.contains(scope) ? ("settings_retry", at, true) : nil
        }
        if let retryAt = service.destroyedWindowRetryDeadline(now: now) {
            due.append(("destroyed_window", retryAt, true))
        }
        if let pendingGesture { due.append(("gesture_pending", pendingGesture.pollAt, true)) }

        for guardState in spaceGuards.values {
            due.append(("guard_cap", guardState.openedAt.addingTimeInterval(LayoutTolerance.spaceGuardCap), true))
            due.append(("guard_poll", (guardState.lastPollAt ?? guardState.openedAt).addingTimeInterval(LayoutTolerance.spaceGuardPoll), true))
        }
        for id in lastTreeWindowIDs {
            guard let entry = writtenFrames.entry(for: id), entry.hasRefusal,
                  entry.generation == generations.current else { continue }
            if let confirmedAt = entry.refusalConfirmedAt {
                if correctedGenerations[id] != generations.current { due.append(("refusal_correct", confirmedAt, true)) }
            } else if now.timeIntervalSince(entry.writtenAt) < LayoutTolerance.echoWindow {
                // Au-delà de `echoWindow` sans confirmation, la réponse était transitoire (A2).
                // Une lecture échouée ou non concluante est retentée plus tard, pas en boucle (T218, REL-002).
                let confirmAt = entry.writtenAt.addingTimeInterval(LayoutTolerance.refusalConfirmDelay)
                due.append(("refusal_confirm", max(confirmAt, refusalReadRetryAt[id] ?? confirmAt), true))
            }
        }
        if let pendingStability, !pendingStability.checked { due.append(("stability", pendingStability.checkAt, true)) }
        return due
    }

    /// O(k + s) : seules les frames réellement relues après l'écriture servent de preuve.
    /// Un retour AX absent/différent garde une unique échéance courte. La seconde passe
    /// consomme la demande même si l'application arrondit ou refuse encore.
    private func finishExactSettingsPass(
        result: ApplyResult,
        scopesByID: [WindowID: StageScope],
        targets: [WindowID: CGRect],
        observedFrames: [UInt32: Rect],
        processedScopes: Set<StageScope>,
        now: Date
    ) {
        let resultByID = Dictionary(result.items.map { ($0.windowID, $0) }, uniquingKeysWith: { _, last in last })
        for item in result.items {
            guard let scope = scopesByID[item.windowID], exactSettingsScopes.contains(scope), processedScopes.contains(scope) else { continue }
            settingsFrameStates[item.windowID] = settingsFrameStates[item.windowID] == nil ? .needsRetry : .completed
            if let actual = item.actual {
                if framesAreClose(actual.cgRect, item.requested.cgRect, tolerance: 0)
                    || !framesAreClose(actual.cgRect, item.requested.cgRect, tolerance: LayoutTolerance.frameMatch) {
                    // Cible confirmée, ou vrai clamp pris en charge par le circuit de refus.
                    settingsFrameStates[item.windowID] = .completed
                }
            }
        }
        var unresolvedScopes: Set<StageScope> = []
        var retryScopes: Set<StageScope> = []
        var blockedScopes: Set<StageScope> = []
        let targetedScopes = Set(targets.keys.compactMap { scopesByID[$0] })
        for (id, target) in targets {
            guard let scope = scopesByID[id], exactSettingsScopes.contains(scope), processedScopes.contains(scope),
                  settingsFrameStates[id] != .completed else { continue }
            let item = resultByID[id]
            let actual = item?.actual?.cgRect ?? observedFrames[id.rawValue]?.cgRect
            let confirmed = item?.status != .failed && actual.map { framesAreClose($0, target, tolerance: 0) } == true
            if confirmed { settingsFrameStates[id] = .completed; continue }
            unresolvedScopes.insert(scope)
            if item == nil {
                // La cible est en écart, mais la commande a été retenue avant l'écriture
                // (backoff, budget). Garder la demande et l'échéance de sa garde, sans boucle.
                blockedScopes.insert(scope)
            } else {
                retryScopes.insert(scope)
            }
        }
        for scope in exactSettingsScopes.intersection(processedScopes) {
            guard targetedScopes.contains(scope) else { continue }
            if unresolvedScopes.contains(scope) {
                if retryScopes.contains(scope), settingsRetryAt[scope] == nil {
                    settingsRetryAt[scope] = now.addingTimeInterval(LayoutTolerance.refusalConfirmDelay)
                }
            } else {
                exactSettingsScopes.remove(scope)
                settingsRetryAt[scope] = nil
            }
        }
        settingsRetryRunnableScopes.subtract(blockedScopes)
    }

    /// Signal NSWorkspace activeSpaceDidChange transmis par l'ordonnanceur (A5, A19). Il compte
    /// pour le repli de la garde seulement s'il arrive après son ouverture. nil = tous les écrans.
    public func spaceDidChange(displayUUID: String?) {
        let date = now()
        for (displayID, guardState) in spaceGuards where displayUUID == nil || displayUUID == displayID.rawValue {
            guard date >= guardState.openedAt else { continue }
            spaceGuards[displayID]?.spaceDidChangeAt = date
        }
    }

    /// Génération de la passe (A13) : une intention externe ou un changement de membres ou de
    /// stage active en ouvre une nouvelle ; les déplacements et redimensionnements observés, les
    /// échéances et le filet de sécurité gardent la génération en cours (pas de lutte). Après une
    /// commande appliquée sur un arbre, ses changements de stage ou de membres sont déjà dans sa
    /// génération : la passe interne suivante la garde (T219).
    private func currentGeneration(cause: String, snapshot: DaemonSnapshot) -> UInt64 {
        let signature = snapshot.displays.compactMap { display -> String? in
            guard let scope = snapshot.state.activeScope(on: display.id) else { return nil }
            let ids = snapshot.windows.compactMap { entry -> String? in
                guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
                return "\(entry.window.id.rawValue):\(entry.window.pid):\(entry.window.bundleID)"
            }
            let mode = snapshot.state.stage(scope: scope)?.mode.rawValue ?? ""
            return "\(scope.description):\(mode):\(ids.sorted().joined(separator: ","))"
        }.sorted().joined(separator: "|")
        let internalCause = cause == "safety" || cause.hasPrefix("deadline")
            || cause.contains("Moved") || cause.contains("Resized")
        let commandOwnsChange = commandGeneration != nil && commandGeneration == generations.current
        defer {
            lastGenerationSignature = signature
            commandGeneration = nil
        }
        if !internalCause || (signature != lastGenerationSignature && !commandOwnsChange) || generations.current == 0 {
            return generations.next()
        }
        return generations.current
    }

    private func activeTreeScopes(in snapshot: DaemonSnapshot) -> Set<StageScope> {
        Set(snapshot.displays.compactMap { display -> StageScope? in
            guard let scope = snapshot.state.activeScope(on: display.id),
                  snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
            else { return nil }
            return scope
        })
    }

    /// Plan de passe (A1) : une commande par fenêtre ; en conflit, la priorité la plus forte gagne
    /// (masquage, puis épinglage, puis zoom, puis disposition). Ordre d'insertion conservé. O(1) par ajout.
    private struct PassPlan {
        enum Priority: Int, Comparable {
            case hide, pin, zoom, layout
            static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        private var byWindow: [WindowID: (priority: Priority, command: ApplyCommand)] = [:]
        private var order: [WindowID] = []

        mutating func add(_ command: ApplyCommand, _ priority: Priority) {
            if let existing = byWindow[command.window.id] {
                guard priority < existing.priority else { return }
            } else {
                order.append(command.window.id)
            }
            byWindow[command.window.id] = (priority, command)
        }

        func contains(_ windowID: WindowID) -> Bool { byWindow[windowID] != nil }

        var entries: [(command: ApplyCommand, priority: Priority)] {
            order.compactMap { id in byWindow[id].map { ($0.command, $0.priority) } }
        }
    }

    /// Résultat de l'application d'une passe.
    private struct PlanApplication {
        var result: ApplyResult
        /// Commandes envoyées : plan, réparation des voisines et résolution des scopes infaisables.
        var commands: Int
    }

    /// Application unique de la passe, puis, pour la disposition des modes sans arbre seulement,
    /// le bloc « recaler, réparer les voisines, isoler » (A3). L'application compte au budget de
    /// la génération (A13) ; le bloc sans arbre est hors budget (T222) : il réécrit plusieurs fois
    /// les mêmes fenêtres dans la passe. Un refus d'arbre attend sa seconde observation (A14).
    private func applyPass(
        _ plan: ApplyPlan,
        in snapshot: DaemonSnapshot,
        layoutWindowIDs: Set<WindowID>,
        generation: UInt64,
        source: String?
    ) -> PlanApplication {
        guard !plan.commands.isEmpty else { return PlanApplication(result: .empty, commands: 0) }
        let scopesByID = Dictionary(snapshot.windows.compactMap { entry in entry.scope.map { (entry.window.id, $0) } }, uniquingKeysWith: { first, _ in first })
        // Disposition sans arbre : seule partie qui passe par les réparations historiques. Le mode
        // de la stage est lu directement sur la copie finale de la passe (T214).
        let isRepairable = { (id: WindowID) in
            layoutWindowIDs.contains(id)
                && scopesByID[id].flatMap { snapshot.state.stage(scope: $0)?.mode.usesTreeEngine } != true
        }
        let before = Dictionary(uniqueKeysWithValues: plan.commands.map { ($0.window.id.rawValue, writtenFrames.entry(for: $0.window.id.rawValue)) })
        let firstResult = service.apply(plan, generation: generation)
        recordWrites(firstResult, before: before, generation: generation)

        // Les fenêtres qui refusent de grandir restent hors des réparations, comme du plan (A3).
        let snapshot = snapshotExcludingGrowthClampedWindows(snapshot)
        let nonTreeCommands = ApplyPlan(commands: plan.commands.filter { isRepairable($0.window.id) })
        let nonTreeResult = ApplyResult.filtering(firstResult) { isRepairable($0.windowID) }
        let directResult = ApplyResult.filtering(firstResult) { !isRepairable($0.windowID) }
        var result = stabilizeClampedPositions(nonTreeResult, from: nonTreeCommands, in: snapshot)
        let repairPlan = clampedSiblingRepairPlan(from: result, in: snapshot)
        if !repairPlan.commands.isEmpty {
            let repairResult = stabilizeClampedPositions(service.apply(repairPlan, generation: PlacementGeneration.outsideBudget), from: repairPlan, in: snapshot)
            result = result.merged(with: repairResult)
            var details = [
                "commands": String(repairPlan.commands.count),
                "windowIDs": repairPlan.commands.map { String($0.window.id.rawValue) }.sorted().joined(separator: ",")
            ]
            if let source { details["source"] = source }
            events.append(RoadieEvent(type: "layout_clamped_scope_repaired", details: details))
        }
        let resolution = resolveInfeasibleClampedScopes(from: result, in: snapshot)
        result = result.merged(with: resolution.result)
        let nonTreeAll = nonTreeCommands.commands + repairPlan.commands + resolution.commands
        record(result, from: ApplyPlan(commands: nonTreeAll))
        // Les refus de masquage et de restauration doivent aussi identifier leur fenêtre.
        appendItemEvents(result.merged(with: ApplyResult.filtering(directResult) {
            layoutWindowIDs.contains($0.windowID) || $0.status == .failed
        }), generation: generation)
        result = result.merged(with: directResult)
        result.applied += resolution.hidden
        return PlanApplication(
            result: result,
            commands: plan.commands.count + repairPlan.commands.count + resolution.commands.count + resolution.hidden
        )
    }

    /// Plan du service sans les écrans dont le scope actif est exclu : le planificateur ne touche
    /// ni les fenêtres ni les intents de ces scopes (R6). O(d + plan).
    private func plannedCommands(
        from snapshot: DaemonSnapshot,
        priorityWindowIDs: Set<WindowID> = [],
        excluding excluded: Set<StageScope>,
        generation: UInt64
    ) -> ApplyPlan {
        var planning = snapshot
        if !excluded.isEmpty {
            planning.displays.removeAll { display in
                snapshot.state.activeScope(on: display.id).map(excluded.contains) ?? false
            }
        }
        return service.applyPlan(from: planning, priorityWindowIDs: priorityWindowIDs, generation: generation)
    }

    /// Met à jour la référence d'observation pour les seules fenêtres des scopes donnés (R6).
    /// Sans référence préalable, la référence complète est posée. O(n).
    private func observe(_ frames: [UInt32: Rect], scopes: Set<StageScope>, in snapshot: DaemonSnapshot) {
        guard var observed = lastObservedFrames else {
            lastObservedFrames = frames
            return
        }
        for entry in snapshot.windows {
            guard let scope = entry.scope, scopes.contains(scope) else { continue }
            observed[entry.window.id.rawValue] = frames[entry.window.id.rawValue]
        }
        lastObservedFrames = observed
    }

    /// Fenêtres de `windowIDs` dont le scope n'est pas exclu. O(n).
    private func windowIDs(
        _ windowIDs: Set<WindowID>,
        outside excludedScopes: Set<StageScope>,
        in snapshot: DaemonSnapshot
    ) -> Set<WindowID> {
        guard !windowIDs.isEmpty, !excludedScopes.isEmpty else { return windowIDs }
        let excludedWindowIDs = Set(snapshot.windows.compactMap { entry -> WindowID? in
            guard let scope = entry.scope, excludedScopes.contains(scope) else { return nil }
            return entry.window.id
        })
        return windowIDs.subtracting(excludedWindowIDs)
    }

    // MARK: - Disposition des modes sans arbre (A3 : comportement actuel, plan unifié)

    /// Décision de disposition des modes `bsp`, `masterStack` et `float` pour la passe.
    private struct NonTreeLayout {
        var commands: [ApplyCommand] = []
        var manualResizeDetected = false
        /// Faux tant qu'une commande protège ses scopes : la référence garde l'ancienne géométrie.
        var updateBaseline = true
        var priorityWindowIDs: Set<WindowID> = []
        /// Vrai sur la branche finale : un plan vide y enregistre l'intent courant (016).
        var persistCurrentIntents = false
    }

    /// Chaîne de décision historique des modes sans arbre (geste par différence d'observation,
    /// intent de commande, anti-rebond), réduite à produire des commandes pour le plan unifié.
    private func nonTreeLayout(
        in snapshot: DaemonSnapshot,
        manualResizeWindowIDs: Set<WindowID>,
        observedFrames: [UInt32: Rect],
        changedWindowIDs: Set<WindowID>,
        adoptedWindowIDs: Set<WindowID>,
        focusPriority: Set<WindowID>,
        excluding excluded: Set<StageScope>,
        now: Date
    ) -> NonTreeLayout {
        if !adoptedWindowIDs.isEmpty {
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            return NonTreeLayout(
                commands: nonTreeLayoutPlan(from: snapshot, priority: adoptedWindowIDs, excluding: excluded),
                priorityWindowIDs: adoptedWindowIDs
            )
        }
        // Le signal de déplacement reste intact pour l'adoption multiécran. Seuls les candidats
        // au redimensionnement sont limités aux fenêtres visibles de la stage active. O(w).
        let visibleActiveIDs = Set(snapshot.windows.compactMap { entry -> WindowID? in
            guard let scope = entry.scope, snapshot.state.activeScope(on: scope.displayID) == scope,
                  entry.window.isTileCandidate, entry.window.isOnScreen,
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { return nil }
            return entry.window.id
        })
        let changedWindowIDs = Set(changedWindowIDs.intersection(visibleActiveIDs).filter { id in
            if let previous = lastObservedFrames?[id.rawValue],
               HiddenWindowPlacement.isHidden(previous.cgRect, in: snapshot.displays) { return false }
            guard let observed = observedFrames[id.rawValue] else { return false }
            return writtenFrames.classify(windowID: id.rawValue, observed: observed.cgRect, now: now) != .echo
        })
        let resized = windowIDs(manualResizeWindowIDs, outside: excluded, in: snapshot).intersection(visibleActiveIDs)
        if !resized.isEmpty {
            removeLayoutIntents(for: resized, in: snapshot)
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastCommandIntentAt = nil
            events.append(RoadieEvent(type: "manual_resize_detected", details: [
                "windowIDs": resized.map { String($0.rawValue) }.sorted().joined(separator: ","),
                "source": "gesture"
            ]))
            return NonTreeLayout(
                commands: nonTreeLayoutPlan(from: snapshot, priority: resized, excluding: excluded),
                manualResizeDetected: true, priorityWindowIDs: resized, persistCurrentIntents: true
            )
        }
        let unexcludedPriorityWindowIDs = windowIDs(priorityWindowIDs, outside: excluded, in: snapshot).intersection(visibleActiveIDs)
        if unexcludedPriorityWindowIDs != priorityWindowIDs {
            priorityWindowIDs = unexcludedPriorityWindowIDs
            if priorityWindowIDs.isEmpty {
                manualResizeApplyAfter = nil
            }
        }

        if !changedWindowIDs.isEmpty {
            if changedFramesMatchSavedIntent(in: snapshot, frames: observedFrames, changedWindowIDs: changedWindowIDs) {
                return NonTreeLayout()
            }
            let modeledScopes = Self.authoritativeModelScopes(for: changedWindowIDs, in: snapshot) {
                service.hasValidLayoutIntent(scope: $0, in: snapshot)
            }
            if !modeledScopes.isEmpty {
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                let commands = nonTreeLayoutPlan(from: snapshot, excluding: excluded)
                events.append(RoadieEvent(type: "external_geometry_snapped_to_layout_model", details: [
                    "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                    "scopes": modeledScopes.map(\.description).sorted().joined(separator: ","),
                    "commands": String(commands.count)
                ]))
                return NonTreeLayout(commands: commands)
            }
            if changedWindowIDs.count >= 2 {
                return NonTreeLayout()
            }
            priorityWindowIDs = changedWindowIDs
            manualResizeApplyAfter = now.addingTimeInterval(LayoutTolerance.manualResizeDebounce)
            removeLayoutIntents(for: changedWindowIDs, in: snapshot)
            events.append(RoadieEvent(type: "manual_resize_detected", details: [
                "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                "applyAfter": String(manualResizeApplyAfter?.timeIntervalSince1970 ?? 0)
            ]))
            return NonTreeLayout(manualResizeDetected: true)
        }

        if let manualResizeApplyAfter, now < manualResizeApplyAfter {
            return NonTreeLayout(manualResizeDetected: true)
        }
        manualResizeApplyAfter = nil

        let cutoff = now.addingTimeInterval(-LayoutTolerance.commandIntentHold)
        let commandProtectedScopes = priorityWindowIDs.isEmpty
            ? recentCommandScopes(in: snapshot, since: cutoff, now: now)
            : []
        // Un scope exclu (plein écran, rafale, arbre) garde son intent : pas de contrôle de dérive.
        let strictCommandProtectedScopes = strictAuthoritativeScopes(commandProtectedScopes, in: snapshot)
            .subtracting(excluded)
        if !strictCommandProtectedScopes.isEmpty {
            let driftedScopes = driftedCommandScopes(strictCommandProtectedScopes, frames: observedFrames)
            if !driftedScopes.isEmpty {
                return invalidateDriftedCommandIntents(driftedScopes, protected: strictCommandProtectedScopes, snapshot: snapshot, excluding: excluded)
            }
            lastCommandIntentAt = now
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            let commands = nonTreeLayoutPlan(from: snapshot, excluding: strictCommandProtectedScopes.union(excluded))
            events.append(RoadieEvent(type: "manual_resize_suppressed_by_command_intent", details: [
                "scopes": strictCommandProtectedScopes.map(\.description).sorted().joined(separator: ","),
                "unprotectedCommands": String(commands.count)
            ]))
            return NonTreeLayout(commands: commands, updateBaseline: false)
        }

        if let lastCommandIntentAt,
           priorityWindowIDs.isEmpty,
           now.timeIntervalSince(lastCommandIntentAt) < LayoutTolerance.commandIntentHold
        {
            let protectedScopes = strictAuthoritativeScopes(
                recentCommandScopes(in: snapshot, since: cutoff, now: now),
                in: snapshot
            ).subtracting(excluded)
            let driftedScopes = driftedCommandScopes(protectedScopes, frames: observedFrames)
            if !driftedScopes.isEmpty {
                return invalidateDriftedCommandIntents(driftedScopes, protected: protectedScopes, snapshot: snapshot, excluding: excluded)
            }
            priorityWindowIDs = []
            return NonTreeLayout(
                commands: nonTreeLayoutPlan(from: snapshot, excluding: protectedScopes.union(excluded)),
                updateBaseline: false
            )
        }
        if lastCommandIntentAt.map({ now.timeIntervalSince($0) >= LayoutTolerance.commandIntentHold }) == true {
            lastCommandIntentAt = nil
        }

        let priority = priorityWindowIDs.union(focusPriority)
        let commands = nonTreeLayoutPlan(from: snapshot, priority: priority, excluding: excluded)
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        return NonTreeLayout(commands: commands, priorityWindowIDs: priority, persistCurrentIntents: true)
    }

    private func invalidateDriftedCommandIntents(
        _ driftedScopes: Set<StageScope>,
        protected protectedScopes: Set<StageScope>,
        snapshot: DaemonSnapshot,
        excluding excluded: Set<StageScope>
    ) -> NonTreeLayout {
        for scope in driftedScopes {
            service.removeLayoutIntent(scope: scope)
        }
        lastCommandIntentAt = nil
        let remainingProtectedScopes = protectedScopes.subtracting(driftedScopes)
        let commands = nonTreeLayoutPlan(from: snapshot, excluding: remainingProtectedScopes.union(excluded))
        events.append(RoadieEvent(type: "command_intent_invalidated_by_manual_geometry", details: [
            "scopes": driftedScopes.map(\.description).sorted().joined(separator: ","),
            "remainingProtectedScopes": remainingProtectedScopes.map(\.description).sorted().joined(separator: ","),
            "commands": String(commands.count)
        ]))
        return NonTreeLayout(commands: commands)
    }

    /// Commandes de disposition des modes sans arbre : fenêtres qui refusent de grandir retirées,
    /// refus et échecs connus écartés, réponse de l'application acceptée (R9). O(plan).
    private func nonTreeLayoutPlan(
        from snapshot: DaemonSnapshot,
        priority: Set<WindowID> = [],
        excluding excluded: Set<StageScope>
    ) -> [ApplyCommand] {
        let planningSnapshot = snapshotExcludingGrowthClampedWindows(snapshot)
        let exactWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope.map(exactSettingsScopes.contains) == true ? entry.window.id : nil
        })
        // La génération ne sert qu'aux frames acceptées des scopes à arbre, exclus de ce plan.
        return suppressKnownUnmovableFrames(
            in: plannedCommands(from: planningSnapshot, priorityWindowIDs: priority, excluding: excluded, generation: generations.current),
            snapshot: planningSnapshot
        ).commands.filter { command in
            guard settingsFrameStates[command.window.id] == .completed,
                  exactWindowIDs.contains(command.window.id)
            else { return true }
            return !framesAreClose(command.window.frame.cgRect, command.frame.cgRect, tolerance: LayoutTolerance.frameMatch)
        }
    }

    // MARK: - Disposition des modes à arbre (A2, A4, A13, A14, A16, R9)

    /// Capture une fois, puis observe sans prolonger le plafond du relâchement. O(w), mémoire O(1).
    /// Seul un mouvement réel autorise l'attente d'une frame tardive ; les fixtures immédiates
    /// et les déplacements déjà visibles suivent le chemin existant, sans nouvelle inférence AX.
    private func layoutGesture(in snapshot: inout DaemonSnapshot, excluding blocked: Set<StageScope>, now: Date, observationStartedAt: Date) -> GestureSession? {
        if let session = takeGesture() {
            pendingGesture = nil
            if let raw = session.windowID, session.startFrame != nil,
               let entry = snapshot.windows.first(where: { $0.window.id.rawValue == raw }), let scope = entry.scope {
                let expires = (session.endedAt ?? now).addingTimeInterval(2)
                pendingGesture = PendingGesture(session: session, windowID: entry.window.id, pid: entry.window.pid,
                    scope: scope, expiresAt: expires, pollAt: now)
            }
        }
        guard var pending = pendingGesture else { return nil }
        let dropped = dragActivity.lastDrop(now: now).map {
            $0.windowID == pending.windowID && $0.at >= pending.session.startedAt
        } ?? false
        // Une observation commencée à temps reste recevable si AX met plusieurs secondes
        // à répondre. Le délai avant cette observation reste borné depuis le relâchement.
        guard !dropped, observationStartedAt < pending.expiresAt, validPendingGesture(pending, in: snapshot),
              !tickFullscreen.contains(where: { $0.entry.scope == pending.scope }),
              let index = snapshot.windows.firstIndex(where: { $0.window.id == pending.windowID }),
              let start = pending.session.startFrame
        else { pendingGesture = nil; return nil }

        let current = snapshot.windows[index].window.frame.cgRect
        let changed = !Self.matches(current, start)
        // Un simple clic ne doit créer ni délai ni échéance d'observation.
        if !pending.session.didDrag && !changed { pendingGesture = nil; return nil }
        if blocked.contains(pending.scope) {
            guard now < pending.expiresAt else { pendingGesture = nil; return nil }
            pending.lastObservationAt = nil
            pending.pollAt = min(now.addingTimeInterval(0.05), pending.expiresAt)
            pendingGesture = pending
            return nil
        }
        if let previous = pending.lastObservationAt {
            pending.observationRemaining -= max(0, observationStartedAt.timeIntervalSince(previous))
        }
        guard pending.observationRemaining > 0.001 else { pendingGesture = nil; return nil }
        pending.lastObservationAt = now

        if !changed, pending.session.didDrag,
           let fresh = readFrame(snapshot.windows[index].window),
           fresh.width > 0, fresh.height > 0,
           !HiddenWindowPlacement.isHidden(fresh, in: snapshot.displays) {
            snapshot.windows[index].window.frame = Rect(fresh)
        }
        if !Self.matches(snapshot.windows[index].window.frame.cgRect, start) {
            pendingGesture = pending
            return pending.session
        }
        pending.pollAt = min(now.addingTimeInterval(min(0.05, pending.observationRemaining)), pending.expiresAt)
        pendingGesture = pending
        return nil
    }

    /// L'identité et le scope du premier relevé ne sont jamais réinterprétés sur une autre fenêtre.
    private func validPendingGesture(_ pending: PendingGesture, in snapshot: DaemonSnapshot) -> Bool {
        guard let entry = snapshot.windows.first(where: { $0.window.id == pending.windowID }),
              entry.window.pid == pending.pid, entry.scope == pending.scope,
              entry.window.isTileCandidate, entry.window.isOnScreen,
              snapshot.state.activeScope(on: pending.scope.displayID) == pending.scope,
              snapshot.state.stage(scope: pending.scope)?.mode.isTiled == true
        else { return false }
        return !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
    }

    /// Un clic seul ne remplace jamais un intent : il faut une taille réellement changée. O(n).
    private func resizedGestureEntry(_ gesture: GestureSession?, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        guard let gesture, let id = gesture.windowID, let start = gesture.startFrame,
              let entry = snapshot.windows.first(where: { $0.window.id.rawValue == id }),
              entry.window.isTileCandidate, let scope = entry.scope,
              !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
              snapshot.state.activeScope(on: scope.displayID) == scope,
              snapshot.state.stage(scope: scope)?.mode.isTiled == true
        else { return nil }
        let current = entry.window.frame.cgRect
        return abs(current.width - start.width) > LayoutTolerance.frameMatch
            || abs(current.height - start.height) > LayoutTolerance.frameMatch ? entry : nil
    }

    /// Une fenêtre CG peut précéder sa fenêtre AX, même sur son écran cible. Ne pas réduire
    /// ses voisines tant qu'elle n'est pas lisible. La passe de sécurité reprend l'attente.
    /// O(m + n · d), m membres, d écrans, plus une lecture AX par identité non résolue.
    private func unreadyPlacementScopes(in snapshot: DaemonSnapshot, scopes: Set<StageScope>) -> Set<StageScope> {
        let displays = Dictionary(snapshot.displays.map { ($0.id, $0.frame.cgRect) }, uniquingKeysWith: { first, _ in first })
        let members = Set(store.state().scopes.flatMap { $0.stages.flatMap { $0.members.map(\.windowID) } })
        placementResolvedPIDs = placementResolvedPIDs.filter { members.contains($0.key) }
        var waiting: Set<StageScope> = []
        var unavailable: Set<WindowID> = []
        for entry in snapshot.windows {
            let id = entry.window.id
            guard entry.window.isTileCandidate, entry.pin == nil,
                  entry.window.furniture?.isNativeFullscreen != true,
                  let scope = entry.scope, scopes.contains(scope), displays[scope.displayID] != nil,
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
                  displays.values.contains(where: { $0.contains(entry.window.frame.center) }),
                  writtenFrames.entry(for: id.rawValue) == nil,
                  placementResolvedPIDs[id] != entry.window.pid
            else { continue }
            if readFrame(entry.window) == nil {
                waiting.insert(scope)
                unavailable.insert(id)
                if !unreadyPlacementWindows.contains(id) {
                    events.append(RoadieEvent(type: "layout_window_waiting_for_ax", scope: scope, details: [
                        "windowID": String(id.rawValue)
                    ]))
                }
            } else {
                placementResolvedPIDs[id] = entry.window.pid
                guard unreadyPlacementWindows.contains(id) else { continue }
                // Aucun appel de placement AX enregistré : un ancien échec de résolution
                // ne doit pas épuiser le budget avant la première écriture réelle.
                writeCounts[id.rawValue] = nil
                events.append(RoadieEvent(type: "layout_window_ax_ready", scope: scope, details: [
                    "windowID": String(id.rawValue)
                ]))
            }
        }
        unreadyPlacementWindows = unavailable
        return waiting
    }

    /// Disposition des scopes à arbre : l'arbre fait foi. Pour chaque fenêtre dont la frame
    /// observée s'écarte de sa cible, dans l'ordre : session de geste, écho, réponse de
    /// l'application, changement externe ; au plus 2 écritures par fenêtre et par génération.
    /// `targets` : cibles du plan de l'arbre, écrites ou non (stabilité, T225). Une fenêtre absente
    /// du plan est déjà à sa cible ou à sa frame acceptée : sa cible est sa frame observée.
    // O(n) par scope, plus le plan de l'arbre.
    private func treeLayoutCommands(
        in snapshot: DaemonSnapshot,
        scopes: Set<StageScope>,
        gesture: GestureSession?,
        generation: UInt64,
        now: Date
    ) -> (commands: [ApplyCommand], targets: [WindowID: CGRect]) {
        guard !scopes.isEmpty else { return ([], [:]) }
        let entriesByID = Dictionary(snapshot.windows.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Un identifiant CG réutilisé, un autre stage ou un autre mode ne prouvent pas
        // le minimum appris. Les contraintes des voisines encore valables restent actives.
        treeMinimums = treeMinimums.filter { id, minimum in
            guard let entry = entriesByID[id] else { return false }
            return entry.window.pid == minimum.pid && entry.window.bundleID == minimum.bundleID
                && entry.scope == minimum.scope
                && snapshot.state.stage(scope: minimum.scope)?.mode == minimum.mode
                && entry.window.furniture?.isNativeFullscreen != true
        }
        var snappedWindowID: WindowID?
        if let gesture, let raw = gesture.windowID,
           let entry = entriesByID[WindowID(rawValue: raw)],
           let scope = entry.scope, scopes.contains(scope),
           applyGesture(gesture, to: entry, scope: scope, snapshot: snapshot) {
            snappedWindowID = entry.window.id
        }
        confirmPendingRefusals(in: snapshot, scopes: scopes, generation: generation, now: now)
        // Une lecture lente ne doit pas réappliquer le plan précédant une nouvelle commande.
        guard generation == generations.current else { return ([], [:]) }
        correctConfirmedRefusals(in: snapshot, scopes: scopes, generation: generation)
        let otherScopes = Set(snapshot.displays.compactMap { snapshot.state.activeScope(on: $0.id) }).subtracting(scopes)
        let planned = plannedCommands(from: snapshot, excluding: otherScopes, generation: generation).commands
        let commands = planned.compactMap { command in
            let exact = settingsFrameStates[command.window.id] != .completed
                && entriesByID[command.window.id]?.scope.map(exactSettingsScopes.contains) == true
            let retry = exact && entriesByID[command.window.id]?.scope.flatMap { settingsRetryAt[$0] }.map { $0 <= now } == true
            return treeWrite(command, snapBack: command.window.id == snappedWindowID, exact: exact, retry: retry, generation: generation, now: now)
        }
        var targets: [WindowID: CGRect] = [:]
        for entry in snapshot.windows where entry.window.isTileCandidate && entry.scope.map(scopes.contains) == true {
            targets[entry.window.id] = entry.window.frame.cgRect
        }
        for command in planned { targets[command.window.id] = command.frame.cgRect }
        return (commands, targets)
    }

    /// Décide l'écriture d'une fenêtre d'arbre vers sa cible (R9, A2, A4, A13). nil = rien à écrire.
    // O(1)
    private func treeWrite(_ command: ApplyCommand, snapBack: Bool, exact: Bool, retry: Bool, generation: UInt64, now: Date) -> ApplyCommand? {
        let id = command.window.id.rawValue
        let observed = command.window.frame.cgRect
        let target = command.frame.cgRect
        // Tolérance unique (R9) : à refaire seulement au-delà de `frameMatch`.
        if framesAreClose(observed, target, tolerance: exact ? 0 : LayoutTolerance.frameMatch) { return nil }
        if snapBack { return command }
        // Taille imposée par l'application, répétée d'une génération à l'autre (SPEC-068).
        if !exact, writtenFrames.refusesLastingly(windowID: id, target: target, observed: observed) { return nil }
        let entry = writtenFrames.entry(for: id)
        let sameTarget = entry.map { framesAreClose($0.requested, target, tolerance: exact ? 0 : LayoutTolerance.frameMatch) } ?? false
        // R9 : la frame acceptée de la génération courante n'est pas à refaire.
        if !retry, sameTarget, let entry, entry.generation == generation,
           let accepted = entry.accepted, Self.matches(accepted, observed) {
            return nil
        }
        if writesUsed(id, generation: generation) >= LayoutTolerance.writeBudgetPerGeneration {
            acceptObserved(command, generation: generation, reason: "write_budget_exhausted")
            return nil
        }
        // Écho à 2 points : il ne prouve pas la première application explicite. Une seule
        // reprise conserve le budget normal et ne réarme pas une troisième tentative.
        if exact && retry { return command }
        guard sameTarget, let entry, entry.generation == generation else { return command }
        if let readBack = entry.readBack, entry.hasRefusal, Self.matches(readBack, observed) {
            // Écho de la relecture d'un refus : il attend sa seconde observation (A14).
            reportEcho(command, entry: entry)
            return nil
        }
        switch writtenFrames.classify(windowID: id, observed: observed, now: now) {
        case .echo:
            reportEcho(command, entry: entry)
            return nil
        case .appResponse:
            acceptObserved(command, generation: generation, reason: "app_response")
            return nil
        case .external:
            // Changement externe : une réécriture par génération, puis acceptation (A4, A13).
            guard externalReverts[id] != generation else {
                acceptObserved(command, generation: generation, reason: "external_change_repeated")
                return nil
            }
            externalReverts[id] = generation
            events.append(RoadieEvent(type: "layout_external_change_reverted", details: [
                "windowID": String(id),
                "observed": frameDescription(Rect(observed)),
                "target": frameDescription(command.frame)
            ]))
            return command
        }
    }

    /// Écritures faites pour cette fenêtre dans la génération : celles de la passe et celles que
    /// l'écrivain AX a enregistrées (commandes comprises). O(1).
    private func writesUsed(_ id: UInt32, generation: UInt64) -> Int {
        let local = writeCounts[id].flatMap { $0.generation == generation ? $0.count : nil } ?? 0
        let registry = writtenFrames.entry(for: id).flatMap { $0.generation == generation ? $0.writesInGeneration : nil } ?? 0
        return max(local, registry)
    }

    /// Compte les écritures au budget de la génération et les inscrit au registre quand
    /// l'écrivain ne l'a pas fait lui-même (doubles de test, génération non transmise). O(k).
    private func recordWrites(_ result: ApplyResult, before: [UInt32: WrittenFrame?], generation: UInt64) {
        let date = now()
        for item in result.items {
            let id = item.windowID.rawValue
            let used = writeCounts[id].flatMap { $0.generation == generation ? $0.count : nil } ?? 0
            writeCounts[id] = (generation, used + 1)
            if item.actual == nil, writtenFrames.entry(for: id) == nil {
                // La résolution peut disparaître entre lecture et écriture ; ne pas mémoriser
                // cette fenêtre comme prête tant qu'aucun appel AX n'a atteint le registre.
                placementResolvedPIDs[WindowID(rawValue: id)] = nil
            }
            guard let actual = item.actual else { continue }
            let after = writtenFrames.entry(for: id)
            if after == (before[id] ?? nil) || after?.generation != generation {
                writtenFrames.record(windowID: id, requested: item.requested.cgRect, readBack: actual.cgRect, generation: generation, at: date)
            }
        }
    }

    private func acceptObserved(_ command: ApplyCommand, generation: UInt64, reason: String) {
        let id = command.window.id.rawValue
        let observed = command.window.frame.cgRect
        if let accepted = writtenFrames.entry(for: id)?.accepted, Self.matches(accepted, observed) { return }
        writtenFrames.accept(windowID: id, frame: observed)
        var details = [
            "windowID": String(id),
            "requested": frameDescription(command.frame),
            "actual": frameDescription(command.window.frame),
            "reason": reason
        ]
        // Diagnostic déjà enregistré, uniquement pour cette génération et cette demande, à la tolérance de cadre près.
        if let entry = writtenFrames.entry(for: id), entry.generation == generation,
           Self.matches(entry.requested, command.frame.cgRect) {
            details["axWriteAttempts"] = String(entry.writesInGeneration)
            details["axReadBack"] = entry.readBack.map { frameDescription(Rect($0)) } ?? "-"
            details["axNativeFullscreenReading"] = entry.nativeFullscreenReading.map { String($0) } ?? "unknown"
            for (phase, code) in entry.axResultCodes ?? [:] { details["ax.\(phase)"] = String(code) }
        }
        events.append(RoadieEvent(type: "layout_app_response_accepted", details: details))
    }

    /// Une seule trace par écriture : la frame observée est celle que Roadie a relue. O(1).
    private func reportEcho(_ command: ApplyCommand, entry: WrittenFrame) {
        let id = command.window.id.rawValue
        guard reportedEchoWrites[id] != entry.writtenAt else { return }
        reportedEchoWrites[id] = entry.writtenAt
        let observed = command.window.frame
        let delta = max(abs(observed.x - command.frame.x), abs(observed.y - command.frame.y),
                        abs(observed.width - command.frame.width), abs(observed.height - command.frame.height))
        events.append(RoadieEvent(type: "layout_echo_ignored", details: [
            "windowID": String(id),
            "deltaPt": String(Int(delta.rounded()))
        ]))
    }

    /// Geste à la souris sur une fenêtre d'arbre (A4, A17). Une taille changée déplace la
    /// frontière de l'arbre sur chaque bord bougé (arbre complet, feuilles absentes exclues) ;
    /// une position seule, ou un bord sans frontière, ramène la fenêtre à l'arbre (vrai).
    // O(e · n) - e bords bougés (4 au plus), n feuilles.
    private func applyGesture(
        _ gesture: GestureSession,
        to entry: ScopedWindowSnapshot,
        scope: StageScope,
        snapshot: DaemonSnapshot
    ) -> Bool {
        guard let start = gesture.startFrame else { return false }
        let current = entry.window.frame.cgRect
        let tolerance = LayoutTolerance.frameMatch
        let sizeChanged = abs(current.width - start.width) > tolerance || abs(current.height - start.height) > tolerance
        guard sizeChanged else { return !Self.matches(current, start) }
        if var minimum = treeMinimums[entry.window.id] {
            // Une taille réellement obtenue par un nouveau geste réfute un ancien minimum
            // plus grand. Ne modifier que les axes dont cette observation prouve la baisse.
            minimum.size.width = max(LayoutTolerance.minimumTileSide, min(minimum.size.width, current.width))
            minimum.size.height = max(LayoutTolerance.minimumTileSide, min(minimum.size.height, current.height))
            treeMinimums[entry.window.id] = minimum
        }
        guard let tree = store.state().bspTree(for: scope),
              let geometry = treeGeometry(of: scope, in: snapshot)
        else { return true }
        let edges: [BSPEdge] = [
            (BSPEdge.left, current.minX - start.minX), (.right, current.maxX - start.maxX),
            (.up, current.minY - start.minY), (.down, current.maxY - start.maxY)
        ].compactMap { abs($0.1) > tolerance ? $0.0 : nil }
        let knownMinimums = treeMinimums.mapValues(\.size)
        let adjusted = edges.reduce(tree) { tree, edge in
            tree.adjustingFence(
                of: entry.window.id, edge: edge, to: current, in: geometry.container,
                innerGap: geometry.innerGap, excluding: geometry.absent, knownMinimums: knownMinimums
            )
        }
        guard adjusted != tree else { return true }
        store.mutate { $0.setBSPTree(adjusted, for: scope) }
        events.append(RoadieEvent(type: "layout_manual_gesture", scope: scope, details: [
            "windowID": String(entry.window.id.rawValue),
            "edge": edges.map(\.rawValue).joined(separator: ","),
            "ratio": Self.changedRatios(from: tree, to: adjusted).map { String(format: "%.3f", $0) }.joined(separator: ","),
            "frame": frameDescription(entry.window.frame)
        ]))
        return false
    }

    /// Nouveaux ratios des splits changés entre deux arbres de même forme (un geste ne change que
    /// des ratios), en ordre préfixe. O(n).
    static func changedRatios(from old: BSPTree, to new: BSPTree) -> [Double] {
        guard case let .split(_, oldRatio, oldFirst, oldSecond) = old,
              case let .split(_, newRatio, newFirst, newSecond) = new
        else { return [] }
        return (oldRatio == newRatio ? [] : [newRatio])
            + changedRatios(from: oldFirst, to: newFirst) + changedRatios(from: oldSecond, to: newSecond)
    }

    /// Conteneur, marge intérieure et feuilles absentes (membres hors relevé ou en plein écran
    /// natif) de l'arbre d'un scope, comme pour son placement (A9). O(n).
    private func treeGeometry(of scope: StageScope, in snapshot: DaemonSnapshot) -> (container: CGRect, innerGap: CGFloat, absent: Set<WindowID>)? {
        guard let container = service.treeContainer(for: scope, in: snapshot) else { return nil }
        let placed = Set(snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate && entry.window.furniture?.isNativeFullscreen != true
                ? entry.window.id : nil
        })
        let leaves = Set(store.state().bspTree(for: scope)?.windowIDs ?? [])
        return (container, CGFloat(service.innerGap()), leaves.subtracting(placed))
    }

    /// Seconde observation des refus en attente sans notification (A14) : une lecture AX fraîche
    /// à `refusalConfirmDelay` après l'écriture. Une lecture échouée ou non concluante ne confirme
    /// rien : elle est retentée `spaceGuardPoll` plus tard, tant que dure `echoWindow` (T218,
    /// audit REL-002). O(r) - r refus en attente.
    private func confirmPendingRefusals(in snapshot: DaemonSnapshot, scopes: Set<StageScope>, generation: UInt64, now: Date) {
        let pending = Set(writtenFrames.pendingRefusals())
        guard !pending.isEmpty else { return }
        for entry in snapshot.windows {
            let id = entry.window.id.rawValue
            guard pending.contains(id), let scope = entry.scope, scopes.contains(scope),
                  let written = writtenFrames.entry(for: id),
                  written.generation == generation,
                  written.writtenAt.addingTimeInterval(LayoutTolerance.refusalConfirmDelay) <= now,
                  now.timeIntervalSince(written.writtenAt) < LayoutTolerance.echoWindow,
                  (refusalReadRetryAt[id] ?? now) <= now
            else { continue }
            guard let observed = readFrame(entry.window) else {
                refusalReadRetryAt[id] = now.addingTimeInterval(LayoutTolerance.spaceGuardPoll)
                continue
            }
            // La lecture AX peut rendre la main après une nouvelle écriture. Sa réponse
            // ne peut confirmer que la demande présente au début de cette lecture.
            guard generation == generations.current, writtenFrames.entry(for: id) == written else { continue }
            writtenFrames.confirmRefusal(windowID: id, observed: observed, at: now, generation: generation)
            // Lecture qui ne tranche pas (ni demandée ni relue) : retentée plus tard, pas en boucle.
            let stillPending = writtenFrames.entry(for: id).map { $0.hasRefusal && $0.refusalConfirmedAt == nil } ?? false
            refusalReadRetryAt[id] = stillPending ? now.addingTimeInterval(LayoutTolerance.spaceGuardPoll) : nil
        }
    }

    /// Refus confirmé (A2, A16) : la taille minimale révélée est respectée par une mutation des
    /// splits nécessaires sur l'axe contraint, dans la génération en cours. Correction infaisable :
    /// la frame obtenue est acceptée (chevauchement, comme yabai). O(r · n).
    private func correctConfirmedRefusals(in snapshot: DaemonSnapshot, scopes: Set<StageScope>, generation: UInt64) {
        for entry in snapshot.windows {
            let id = entry.window.id.rawValue
            guard let scope = entry.scope, scopes.contains(scope),
                  let mode = snapshot.state.stage(scope: scope)?.mode,
                  let written = writtenFrames.entry(for: id),
                  written.generation == generation,
                  written.refusalConfirmedAt != nil, let readBack = written.readBack,
                  correctedGenerations[id] != generation
            else { continue }
            correctedGenerations[id] = generation
            let minimum = Self.minimumSize(requested: Rect(written.requested), actual: Rect(readBack))
            treeMinimums[entry.window.id] = TreeMinimum(
                size: Self.largest(treeMinimums[entry.window.id]?.size ?? .zero, minimum),
                pid: entry.window.pid, bundleID: entry.window.bundleID, scope: scope, mode: mode
            )
            // Sans arbre lisible, rien à corriger : la frame obtenue est acceptée.
            var reason = "minimum_size_infeasible"
            if let tree = store.state().bspTree(for: scope),
               let geometry = treeGeometry(of: scope, in: snapshot) {
                var knownMinimums = treeMinimums.filter { $0.key != entry.window.id }.mapValues(\.size)
                // Le côté minimal supposé évite de créer un nouveau refus chez une voisine
                // dont l'application n'a pas encore révélé sa contrainte (T228).
                for neighbour in tree.windowIDs where neighbour != entry.window.id && knownMinimums[neighbour] == nil {
                    knownMinimums[neighbour] = CGSize(
                        width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide
                    )
                }
                let corrected = tree.correctingForMinimumSize(
                    of: entry.window.id, minimum: minimum, in: geometry.container, innerGap: geometry.innerGap,
                    excluding: geometry.absent, knownMinimums: knownMinimums
                )
                if let corrected, corrected != tree {
                    store.mutate { $0.setBSPTree(corrected, for: scope) }
                    events.append(RoadieEvent(type: "layout_clamped_scope_repaired", scope: scope, details: [
                        "windowIDs": String(id),
                        "source": "tree_minimum_size",
                        "minimum": "\(Int(minimum.width))x\(Int(minimum.height))"
                    ]))
                    continue
                }
                // Arbre inchangé : le refus ne révèle aucune taille minimale (décalage, arrondi).
                if corrected != nil { reason = "refusal_without_minimum" }
            }
            writtenFrames.accept(windowID: id, frame: readBack)
            events.append(RoadieEvent(type: "layout_app_response_accepted", details: [
                "windowID": String(id),
                "requested": frameDescription(Rect(written.requested)),
                "actual": frameDescription(Rect(readBack)),
                "reason": reason
            ]))
        }
    }

    // MARK: - Rafales et garde de bureau (A5, A6, A18, A19)

    /// Changements de membres d'un scope actif. Un changement isolé est placé tout de suite ; un
    /// second en moins de `burstWindow` ouvre une rafale : le premier placement est conservé et
    /// une seule passe finale suit `burstQuiet` de calme, au plus `burstCap` après le début (A18).
    private struct MembershipActivity {
        var lastChangeAt: Date
        var burstStartedAt: Date?

        var burstEnd: Date? {
            burstStartedAt.map { min(lastChangeAt.addingTimeInterval(LayoutTolerance.burstQuiet), $0.addingTimeInterval(LayoutTolerance.burstCap)) }
        }
    }

    /// Scopes actifs en rafale de changements de membres. L'activation d'un scope n'est pas un
    /// changement de membres (FR-017 de la SPEC-016). O(n + s).
    private func burstScopes(in snapshot: DaemonSnapshot, now: Date) -> Set<StageScope> {
        var signatures: [StageScope: String] = [:]
        var bursting: Set<StageScope> = []
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled
            else { continue }
            let signature = stageMembershipSignature(scope: scope, mode: stage.mode, in: snapshot)
            signatures[scope] = signature
            if let previous = lastActiveTiledStageMembershipSignatures[scope], previous != signature {
                if var activity = membershipActivity[scope],
                   now.timeIntervalSince(activity.lastChangeAt) < LayoutTolerance.burstWindow {
                    if activity.burstStartedAt == nil {
                        activity.burstStartedAt = activity.lastChangeAt
                        events.append(RoadieEvent(type: "layout_stage_membership_settling", scope: scope, details: [
                            "scopes": scope.description,
                            "quietSeconds": String(LayoutTolerance.burstQuiet),
                            "holdSeconds": String(LayoutTolerance.burstCap)
                        ]))
                    }
                    activity.lastChangeAt = now
                    membershipActivity[scope] = activity
                } else {
                    membershipActivity[scope] = MembershipActivity(lastChangeAt: now)
                }
            }
            // Une commande appliquée sur l'arbre du scope après le début de la rafale la clôt (A15).
            if let start = membershipActivity[scope]?.burstStartedAt,
               let appliedAt = service.treeScopeAppliedAt(scope), appliedAt >= start {
                membershipActivity[scope]?.burstStartedAt = nil
            }
            if let end = membershipActivity[scope]?.burstEnd {
                if now < end {
                    bursting.insert(scope)
                } else {
                    // Fin de rafale : la passe en cours est la passe finale.
                    membershipActivity[scope]?.burstStartedAt = nil
                }
            }
        }
        membershipActivity = membershipActivity.filter { signatures[$0.key] != nil }
        lastActiveTiledStageMembershipSignatures = signatures
        return bursting
    }

    /// Membres vivants du scope (les membres disparus n'y sont plus), avec le mode. O(n).
    private func stageMembershipSignature(scope: StageScope, mode: WindowManagementMode, in snapshot: DaemonSnapshot) -> String {
        let ids = snapshot.windows
            .compactMap { $0.scope == scope && $0.window.isTileCandidate ? String($0.window.id.rawValue) : nil }
            .sorted()
            .joined(separator: ",")
        return "\(mode.rawValue):\(ids)"
    }

    /// Garde de transition de bureau d'un écran (A5, A19).
    private struct SpaceGuard {
        var openedAt: Date
        var reason: String
        var windowIDs: Set<WindowID>
        var spaceDidChangeAt: Date?
        var lastPollAt: Date?
        var sample: (at: Date, frames: [WindowID: CGRect])?
    }

    /// Ouvre une garde à la sortie du plein écran natif ou au retour d'un membre manquant, et la
    /// ferme quand le bureau courant de l'écran est un bureau utilisateur. Sonde indisponible :
    /// `spaceDidChange` reçu après l'ouverture puis deux lectures identiques à `spaceGuardPoll`
    /// d'écart. Plafond `spaceGuardCap`. Retourne les scopes actifs des écrans gardés. O(n).
    private func spaceGuardScopes(in snapshot: DaemonSnapshot, now: Date) -> Set<StageScope> {
        openSpaceGuards(in: snapshot, now: now)
        let entriesByID = Dictionary(snapshot.windows.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (displayID, guardState) in spaceGuards {
            var updated = guardState
            var closedBy: String?
            let commandAppliedAt = snapshot.state.activeScope(on: displayID).flatMap(service.treeScopeAppliedAt)
            // Comparaisons par addition de dates, comme les échéances rendues par `nextDeadline`.
            if guardState.openedAt.addingTimeInterval(LayoutTolerance.spaceGuardCap) <= now {
                closedBy = "timeout"
            } else if let commandAppliedAt, commandAppliedAt >= guardState.openedAt {
                // Une commande est une intention de l'utilisateur : elle clôt la garde (A15).
                closedBy = "command"
            } else {
                switch spaceProbe(displayID.rawValue) {
                case true?:
                    closedBy = "userSpace"
                case false?:
                    break
                case nil:
                    if guardState.spaceDidChangeAt != nil {
                        // Lectures fraîches de toutes les fenêtres gardées, sinon pas d'échantillon :
                        // la garde attend alors son plafond (T218).
                        let frames = guardState.windowIDs.reduce(into: [WindowID: CGRect]()) { frames, id in
                            guard let entry = entriesByID[id], let frame = readFrame(entry.window) else { return }
                            frames[id] = frame
                        }
                        if frames.isEmpty || frames.count != guardState.windowIDs.count {
                            updated.sample = nil
                        } else if let sample = guardState.sample,
                           sample.at.addingTimeInterval(LayoutTolerance.spaceGuardPoll) <= now,
                           frames.allSatisfy({ id, frame in sample.frames[id].map { Self.matches($0, frame) } ?? false }) {
                            closedBy = "spaceDidChange"
                        } else {
                            updated.sample = (now, frames)
                        }
                    }
                }
            }
            updated.lastPollAt = now
            if let closedBy {
                spaceGuards[displayID] = nil
                events.append(RoadieEvent(type: "space_transition_guard", details: [
                    "displayID": displayID.rawValue,
                    "reason": guardState.reason,
                    "closedBy": closedBy,
                    "heldMs": String(Int((now.timeIntervalSince(guardState.openedAt) * 1000).rounded()))
                ]))
            } else {
                spaceGuards[displayID] = updated
            }
        }
        return Set(spaceGuards.keys.compactMap { snapshot.state.activeScope(on: $0) })
    }

    /// Détecte les sorties de plein écran natif et les retours de membres manquants. O(n + s).
    private func openSpaceGuards(in snapshot: DaemonSnapshot, now: Date) {
        func open(_ displayID: DisplayID, reason: String, windowID: WindowID) {
            if spaceGuards[displayID] == nil {
                spaceGuards[displayID] = SpaceGuard(openedAt: now, reason: reason, windowIDs: [windowID])
            } else {
                spaceGuards[displayID]?.windowIDs.insert(windowID)
            }
        }
        var nativeFullscreen: [WindowID: DisplayID] = [:]
        for entry in snapshot.windows {
            guard let displayID = entry.scope?.displayID else { continue }
            if entry.window.furniture?.isNativeFullscreen == true {
                nativeFullscreen[entry.window.id] = displayID
            } else if lastNativeFullscreenWindows[entry.window.id] != nil {
                open(displayID, reason: "fullscreen_exit", windowID: entry.window.id)
            }
        }
        // Une fenêtre en plein écran natif peut quitter le relevé (son propre bureau) : on la garde.
        let liveIDs = Set(snapshot.windows.map(\.window.id))
        for (id, displayID) in lastNativeFullscreenWindows where !liveIDs.contains(id) && nativeFullscreen[id] == nil {
            nativeFullscreen[id] = displayID
        }
        let members = Set(store.state().scopes.flatMap { $0.stages.flatMap { $0.members.map(\.windowID) } })
        lastNativeFullscreenWindows = nativeFullscreen.filter { liveIDs.contains($0.key) || members.contains($0.key) }

        var live: [StageScope: Set<WindowID>] = [:]
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  snapshot.state.stage(scope: scope)?.mode.isTiled == true
            else { continue }
            let current = Set(snapshot.windows.compactMap { $0.scope == scope && $0.window.isTileCandidate ? $0.window.id : nil })
            live[scope] = current
            var departed = departedMembers[scope] ?? []
            if let previous = lastActiveLiveMembers[scope] {
                departed.formUnion(previous.subtracting(current))
            }
            for returned in departed.intersection(current) {
                open(scope.displayID, reason: "member_return", windowID: returned)
            }
            departed.subtract(current)
            departedMembers[scope] = departed.intersection(members)
        }
        departedMembers = departedMembers.filter { live[$0.key] != nil && !$0.value.isEmpty }
        lastActiveLiveMembers = live
    }

    /// Activité de commande (R12, FR-040) : seuls les scopes sans arbre qu'elle couvre sont
    /// suspendus ; un scope qui vient de perdre un membre est repris quand même.
    private struct CommandSuspension {
        var activity: LayoutCommandActivity.Activity?
        var scopes: Set<StageScope> = []
        var resumed: Set<StageScope> = []
        var treeDisplays: Set<DisplayID> = []

        /// Vrai si aucune écriture ne doit toucher une fenêtre de ce scope. O(s).
        func covers(_ scope: StageScope) -> Bool {
            guard let activity, activity.covers(scope), !treeDisplays.contains(scope.displayID) else { return false }
            return !resumed.contains { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }
        }
    }

    private func commandSuspension(
        in snapshot: DaemonSnapshot,
        treeScopes: Set<StageScope>,
        observedFrames: [UInt32: Rect],
        now: Date
    ) -> CommandSuspension {
        commandSuspendedUntil = nil
        guard let activity = commandActivity.activity(now: now) else { return CommandSuspension() }
        let resumed = activeTiledScopesWithRecentMissingMembers(in: snapshot, now: now)
        let commandScopes = activeScopes(in: snapshot)
            .filter(activity.covers)
            .subtracting(treeScopes)
            .subtracting(resumed)
        let suspension = CommandSuspension(
            activity: activity,
            scopes: commandScopes,
            resumed: resumed,
            treeDisplays: Set(treeScopes.map(\.displayID))
        )
        guard !commandScopes.isEmpty else { return suspension }
        commandSuspendedUntil = activity.activeUntil
        observe(observedFrames, scopes: commandScopes, in: snapshot)
        if lastCommandActivitySuppressedAt.map({ now.timeIntervalSince($0) > LayoutTolerance.repeatedEventInterval }) ?? true {
            lastCommandActivitySuppressedAt = now
            var details = [
                "activeUntil": String(activity.activeUntil.timeIntervalSince1970),
                "commandScopes": commandScopes.map(\.description).sorted().joined(separator: ",")
            ]
            if !resumed.isEmpty {
                details["bypassedForMissingReclaim"] = "true"
                details["scopes"] = resumed.map(\.description).sorted().joined(separator: ",")
            }
            events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: details))
        }
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        return suspension
    }

    private func activeScopes(in snapshot: DaemonSnapshot) -> Set<StageScope> {
        Set(snapshot.displays.compactMap { snapshot.state.activeScope(on: $0.id) })
    }

    // MARK: - Mesure (A12, A20)

    /// Stabilité à vérifier : cibles écrites depuis la dernière stabilité observée.
    private struct PendingStability {
        var startedAt: Date
        var checkAt: Date
        var targets: [WindowID: CGRect]
        var episode: String?
        var checked = false
    }

    /// Arme la lecture de stabilité 100 ms après la fin de la dernière écriture (A20, T209). Une
    /// vérification échouée ne garde pas ses cibles ; `stableAfterMs` se compte depuis la
    /// première passe de l'épisode qui arme (T225). O(k).
    private func armStabilityCheck(targets: [WindowID: CGRect], startedAt: Date, writeEnd: Date) {
        let episode = episodes.current
        var pending = pendingStability.flatMap { $0.checked ? nil : $0 }
            ?? PendingStability(startedAt: startedAt, checkAt: writeEnd, targets: [:], episode: episode)
        if pending.episode != episode {
            (pending.startedAt, pending.episode) = (startedAt, episode)
        }
        pending.targets.merge(targets) { _, new in new }
        pending.checkAt = writeEnd.addingTimeInterval(0.1)
        pending.checked = false
        pendingStability = pending
    }

    /// Une correction de l'arbre (refus confirmé) change la cible d'une fenêtre sans forcément la
    /// réécrire : déjà à sa nouvelle cible. La stabilité attendue vise alors les cibles du plan
    /// corrigé, pas l'ancienne taille refusée (T225). O(k).
    private func retargetStabilityCheck(_ targets: [WindowID: CGRect]) {
        guard var pending = pendingStability, !pending.checked else { return }
        for (id, target) in targets where pending.targets[id] != nil {
            pending.targets[id] = target
        }
        pendingStability = pending
    }

    /// Contraintes confirmées du tiler, partagées avec les prises explicites. O(w).
    /// Une autre identité, un autre mode ou un autre scope ne transporte aucun minimum.
    public func dividerMinimums(for scope: StageScope, in snapshot: DaemonSnapshot) -> [WindowID: CGSize] {
        var result: [WindowID: CGSize] = [:]
        for entry in snapshot.windows where entry.scope == scope {
            guard let minimum = treeMinimums[entry.window.id],
                  minimum.pid == entry.window.pid, minimum.bundleID == entry.window.bundleID,
                  minimum.scope == scope, snapshot.state.stage(scope: scope)?.mode == minimum.mode,
                  entry.window.furniture?.isNativeFullscreen != true else { continue }
            result[entry.window.id] = minimum.size
        }
        return result
    }

    /// Résultat d'une commande appliquée sur un arbre (T219, A15, A20), publié par
    /// `SnapshotService.applyTreeScope` : suivi des refus et de la génération, puis contrôle
    /// de stabilité 100 ms après l'écriture. Aucun placement ici. O(k) — fenêtres écrites.
    public func noteTreeScopeApplied(_ application: TreeScopeApplication) {
        lastTreeWindowIDs.formUnion(application.windowIDs.map(\.rawValue))
        commandGeneration = application.generation
        var targets: [WindowID: CGRect] = [:]
        for id in application.windowIDs {
            if let written = writtenFrames.entry(for: id.rawValue) { targets[id] = written.requested }
        }
        guard !targets.isEmpty else { return }
        armStabilityCheck(targets: targets, startedAt: application.appliedAt, writeEnd: application.appliedAt)
    }

    /// `layout_stable` (A20) : une observation fraîche, au moins 100 ms après la dernière écriture,
    /// montre chaque fenêtre de la passe à sa cible ou à sa frame acceptée. Une lecture échouée
    /// ne prouve pas la stabilité (T218). O(k).
    private func checkStability(in snapshot: DaemonSnapshot, now: Date, generation: UInt64) {
        guard var pending = pendingStability, now >= pending.checkAt else { return }
        let entriesByID = Dictionary(snapshot.windows.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stable = pending.targets.allSatisfy { id, target in
            guard let entry = entriesByID[id] else { return true }
            guard let observed = readFrame(entry.window) else { return false }
            if Self.matches(observed, target) { return true }
            return writtenFrames.entry(for: id.rawValue)?.accepted.map { Self.matches($0, observed) } ?? false
        }
        guard stable else {
            pending.checked = true
            pendingStability = pending
            return
        }
        pendingStability = nil
        events.append(RoadieEvent(type: "layout_stable", details: [
            "stableAfterMs": String(Int((now.timeIntervalSince(pending.startedAt) * 1000).rounded())),
            "windows": String(pending.targets.count),
            "layoutVersion": String(generation)
        ]))
    }

    /// `layout_apply` (R14, A12, A20) : durée, cause, rang dans l'épisode, relevés, écritures.
    private func appendLayoutApplyEvent(
        _ application: PlanApplication,
        priorityWindowIDs: Set<WindowID>,
        cause: String,
        scans: Int,
        generation: UInt64,
        startedAt: Date
    ) {
        let episode = episodes.current
        passIndex = episode != nil && episode == lastPassEpisodeID ? passIndex + 1 : 1
        lastPassEpisodeID = episode
        let writesByWindow = application.result.items.reduce(into: [UInt32: Int]()) { $0[$1.windowID.rawValue, default: 0] += 1 }
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(application.commands),
            "applied": String(application.result.applied),
            "clamped": String(application.result.clamped),
            "failed": String(application.result.failed),
            "priorityWindowIDs": priorityWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
            "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000),
            "cause": cause,
            "pass": String(passIndex),
            "scans": String(scans),
            // Écriture façon yabai : taille, position, taille (R8), soit trois appels AX par fenêtre.
            "axWrites": String(application.result.items.count * 3),
            "windowWrites": writesByWindow.keys.sorted().map { "\($0):\(writesByWindow[$0] ?? 0)" }.joined(separator: ","),
            "layoutVersion": String(generation)
        ]))
    }

    private func appendPassEvents(
        hiddenInactive: [ApplyCommand],
        hiddenSiblings: [ApplyCommand],
        restoredPins: [ApplyCommand],
        reanchoredZoomed: [ApplyCommand],
        focusRestore: FocusRestore?,
        application: PlanApplication,
        snapshot: DaemonSnapshot,
        startedAt: Date
    ) {
        if !restoredPins.isEmpty {
            events.append(RoadieEvent(type: "window.pin_restored", details: ["applied": String(restoredPins.count)]))
        }
        if !reanchoredZoomed.isEmpty {
            events.append(RoadieEvent(type: "fullscreen_sized_windows_reanchored", details: ["applied": String(reanchoredZoomed.count)]))
        }
        if !hiddenSiblings.isEmpty {
            events.append(RoadieEvent(type: "fullscreen_stage_siblings_hidden", details: ["applied": String(hiddenSiblings.count)]))
        }
        if !hiddenInactive.isEmpty {
            events.append(RoadieEvent(type: "stage_hide_inactive", details: ["applied": String(hiddenInactive.count)]))
        }
        guard let focusRestore,
              let item = application.result.items.first(where: { $0.windowID == focusRestore.entry.window.id })
        else { return }
        let scope = focusRestore.scope
        let hiddenIDs = Set(hiddenInactive.map(\.window.id))
        let hiddenOnDisplay = snapshot.windows.filter { hiddenIDs.contains($0.window.id) && $0.scope?.displayID == scope.displayID }.count
        var details = [
            "hiddenActive": String(focusRestore.activeHiddenWindowIDs.count),
            "focusedWindowID": String(focusRestore.entry.window.id.rawValue),
            "focusedDisplayID": scope.displayID.rawValue,
            "restored": String(item.status == .failed ? 0 : 1),
            "hiddenInactive": String(hiddenOnDisplay),
            "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000)
        ]
        if !focusRestore.isFullscreen {
            details["scopes"] = "\(scope.displayID.rawValue)/\(scope.desktopID.rawValue)/\(scope.stageID.rawValue)"
            details["commands"] = String(application.commands)
            details["applied"] = String(application.result.applied)
            details["clamped"] = String(application.result.clamped)
            details["failed"] = String(application.result.failed)
        }
        events.append(RoadieEvent(type: focusRestore.isFullscreen ? "stage_focus_fullscreen_restore" : "stage_focus_restore", details: details))
    }

    /// Oublie les refus de taille et les échecs de plus de 30 s, sauf les durables, et la
    /// mémoire des fenêtres disparues (FR-004, SPEC-083, SPEC-086). O(r) - r entrées mémorisées.
    private func forgetGoneWindows(liveWindowIDs: Set<UInt32>, now: Date) {
        let oldest = now.addingTimeInterval(-LayoutTolerance.refusalMemorySeconds)
        for (id, clamp) in clampedFrames where !clamp.lasting && clamp.recordedAt < oldest {
            expiredClamps[id] = clamp
        }
        clampedFrames = clampedFrames.filter {
            liveWindowIDs.contains($0.key) && ($0.value.lasting || $0.value.recordedAt >= oldest)
        }
        expiredClamps = expiredClamps.filter { liveWindowIDs.contains($0.key) && clampedFrames[$0.key] == nil }
        for (id, failure) in failedFrames where !failure.lasting && failure.recordedAt < oldest {
            expiredFailures[id] = failure
        }
        failedFrames = failedFrames.filter {
            liveWindowIDs.contains($0.key) && ($0.value.lasting || $0.value.recordedAt >= oldest)
        }
        expiredFailures = expiredFailures.filter { liveWindowIDs.contains($0.key) && failedFrames[$0.key] == nil }
        failedRestorations = failedRestorations.filter { liveWindowIDs.contains($0.key.rawValue) }
        revertedAppliedFrames = revertedAppliedFrames.filter { liveWindowIDs.contains($0.key) }
        writeCounts = writeCounts.filter { liveWindowIDs.contains($0.key) }
        externalReverts = externalReverts.filter { liveWindowIDs.contains($0.key) }
        correctedGenerations = correctedGenerations.filter { liveWindowIDs.contains($0.key) }
        reportedEchoWrites = reportedEchoWrites.filter { liveWindowIDs.contains($0.key) }
        refusalReadRetryAt = refusalReadRetryAt.filter { liveWindowIDs.contains($0.key) }
        treeMinimums = treeMinimums.filter { liveWindowIDs.contains($0.key.rawValue) }
    }

    /// Toutes les 30 s : un membre gardé seulement par l'inventaire (absent du relevé, même pid) et
    /// retiré par son application est marqué fermé ; l'absence ordinaire le retire ensuite de sa
    /// stage. Sinon la stage paraît occupée et ses bascules et restaurations l'attendent en vain.
    /// O(m) membres, plus une lecture AX par application concernée.
    private func closeRetiredMembers(in snapshot: DaemonSnapshot, now: Date) {
        guard nextRetiredCheckAt.map({ now >= $0 }) ?? true, let inventory = snapshot.existingWindowPIDs else { return }
        nextRetiredCheckAt = now.addingTimeInterval(LayoutTolerance.refusalMemorySeconds)
        let observed = Set(snapshot.windows.map(\.window.id))
        var candidates: [WindowID: Int32] = [:]
        for scope in store.state().scopes {
            for stage in scope.stages {
                for member in stage.members where !observed.contains(member.windowID) && member.confirmedClosedAt == nil {
                    if let pid = member.pid, inventory[member.windowID] == pid { candidates[member.windowID] = pid }
                }
            }
        }
        guard !candidates.isEmpty else { return }
        let retired = retiredWindowProbe(candidates)
        guard !retired.isEmpty else { return }
        store.mutate { $0.markConfirmedClosed(windowIDs: retired, at: now) }
        events.append(RoadieEvent(type: "window.retired_members_closed", details: [
            "windowIDs": retired.map { String($0.rawValue) }.sorted().joined(separator: ",")
        ]))
    }

    /// Égalité de deux frames à `LayoutTolerance.frameMatch` près : la tolérance unique (R9).
    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = LayoutTolerance.frameMatch
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    // MARK: - Placements de la passe (masquage, épinglages, zoom, focus)

    /// Fenêtre focalisée cachée dans le scope actif de son écran (Cmd-Tab vers une fenêtre masquée).
    private struct FocusRestore {
        var entry: ScopedWindowSnapshot
        var scope: StageScope
        var display: DisplaySnapshot
        var activeHiddenWindowIDs: [WindowID]
        /// Fenêtre zoomée par une commande : elle reprend le cadre plein écran, sans disposition.
        var isFullscreen: Bool
        var restoration: ApplyPlan?
    }

    /// La fermeture ou le départ de la fenêtre zoomée rend ses voisines visibles, même en float.
    /// O(w + s) hors coût du plan réutilisé ; aucune observation supplémentaire.
    private func closedZoomRestorationCommands(in snapshot: DaemonSnapshot) -> [ApplyCommand] {
        let liveScopes = Dictionary(snapshot.windows.compactMap { entry in
            entry.scope.map { (entry.window.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        return activeScopes(in: snapshot).flatMap { scope -> [ApplyCommand] in
            guard !tickExcludedScopes.contains(scope),
                  let zoomedID = service.commandLayoutIntent(scope: scope)?.zoomedWindowID,
                  liveScopes[zoomedID] != scope else { return [] }
            return service.restoreZoomLayoutIntent(scope: scope, from: snapshot, generation: generations.current).commands
        }
    }

    /// Focus sur une voisine du zoom : sortie logique avant le masquage, qu'elle soit déjà cachée
    /// ou encore visible (activation d'application, nouvelle fenêtre). Sinon, restaure le focus caché.
    /// O(w) hors coût du plan réutilisé ; conserve les exclusions de scope et le focus du snapshot.
    private func focusedHiddenRestore(in snapshot: DaemonSnapshot, cause: String, systemFocusedWindowID: WindowID?) -> FocusRestore? {
        guard let focusedWindowID = snapshot.focusedWindowID,
              let focusedEntry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              let focusedScope = focusedEntry.scope,
              snapshot.state.activeScope(on: focusedScope.displayID) == focusedScope,
              focusedEntry.window.isTileCandidate,
              !tickExcludedScopes.contains(focusedScope),
              let display = snapshot.displays.first(where: { $0.id == focusedScope.displayID })
        else { return nil }

        let zoomedID = service.commandLayoutIntent(scope: focusedScope)?.zoomedWindowID
        // Un repli mémorisé ne devient pas une activation après le masquage de la voisine.
        if let zoomedID, zoomedID != focusedWindowID {
            guard systemFocusedWindowID == focusedWindowID else { return nil }
        }
        let isHidden = HiddenWindowPlacement.isHidden(focusedEntry.window.frame.cgRect, in: snapshot.displays)
        let isNativeZoom = tickFullscreen.contains {
            $0.entry.window.id == zoomedID && $0.entry.window.furniture?.isNativeFullscreen == true
        }
        let activatesFocus = cause.contains("didActivateApplication") || cause.contains("AXFocusedWindowChanged")
            || cause.contains("AXWindowCreated")
        let confirmedVisibleFocus = activatesFocus && systemFocusedWindowID == focusedWindowID
        let isZoomSibling = zoomedID != nil && zoomedID != focusedWindowID && !isNativeZoom && confirmedVisibleFocus
        guard isHidden || isZoomSibling else { return nil }
        var restoration: ApplyPlan?
        if let zoomedWindowID = zoomedID,
           zoomedWindowID != focusedWindowID, !isNativeZoom {
            restoration = service.restoreZoomLayoutIntent(scope: focusedScope, from: snapshot, generation: generations.current)
            tickFullscreen.removeAll { $0.entry.window.id == zoomedWindowID }
            events.append(RoadieEvent(type: "layout_zoom_exited", scope: focusedScope, details: [
                "zoomedWindowID": String(zoomedWindowID.rawValue),
                "focusedWindowID": String(focusedWindowID.rawValue)
            ]))
        }
        let activeHidden = snapshot.windows.compactMap { entry -> WindowID? in
            entry.scope == focusedScope
                && entry.window.isTileCandidate
                && HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
                ? entry.window.id : nil
        }
        return FocusRestore(
            entry: focusedEntry,
            scope: focusedScope,
            display: display,
            activeHiddenWindowIDs: activeHidden,
            isFullscreen: tickFullscreen.contains { $0.entry.window.id == focusedWindowID },
            restoration: restoration
        )
    }

    /// Commande qui rend visible la fenêtre focalisée quand la disposition ne la place pas : cadre
    /// plein écran d'une fenêtre zoomée, sinon même taille centrée (plan du scope retenu par le
    /// plein écran ou un refus connu ; un échec mémorisé n'est pas redemandé).
    private func focusRestoreCommand(_ restore: FocusRestore, plan: PassPlan, snapshot: DaemonSnapshot) -> ApplyCommand? {
        let window = restore.entry.window
        if restore.isFullscreen {
            if service.commandLayoutIntent(scope: restore.scope)?.zoomReservesRail == true {
                return reservedZoomCommand(for: window, on: restore.display, scope: restore.scope)
            }
            guard let target = fullscreenSizedRestoreTarget(for: window.frame.cgRect, on: restore.display) else { return nil }
            return ApplyCommand(window: window, frame: Rect(target))
        }
        // Une voisine déjà visible quitte le zoom sans changer son cadre lorsqu'il est restauré.
        guard HiddenWindowPlacement.isHidden(window.frame.cgRect, in: snapshot.displays),
              !plan.contains(window.id) else { return nil }
        let command = ApplyCommand(window: window, frame: Rect(centeredVisibleFrame(for: window.frame.cgRect, on: restore.display)))
        return failedFrames[window.id.rawValue]?.matches(command: command) == true ? nil : command
    }

    /// Cadre visible de repli : même taille (bornée à la zone visible), centré sur l'écran.
    private func centeredVisibleFrame(for frame: CGRect, on display: DisplaySnapshot) -> CGRect {
        let visible = display.visibleFrame.cgRect
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    /// Masquage des fenêtres des stages inactives (hors épinglage visible et plein écran). O(n).
    private func hideInactiveStageCommands(in snapshot: DaemonSnapshot) -> [ApplyCommand] {
        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        return snapshot.windows.compactMap { entry -> ApplyCommand? in
            guard let scope = entry.scope,
                  let activeScope = snapshot.state.activeScope(on: scope.displayID),
                  scope != activeScope,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !HiddenWindowPlacement.isPreferred(entry.window.frame.cgRect, among: snapshot.displays),
                  !fullscreenWindowIDs.contains(entry.window.id),
                  entry.pin?.visibility(in: activeScope).shouldBeVisible != true
            else { return nil }
            let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            return ApplyCommand(window: entry.window, frame: Rect(frame), preservesSize: true)
        }
    }

    /// Masquage des voisines d'une fenêtre en plein écran dans son scope actif. La fenêtre qui a le
    /// focus du système n'est jamais cachée : l'utilisateur vient de la choisir (FR-002). O(n).
    private func fullscreenSiblingHideCommands(in snapshot: DaemonSnapshot, systemFocusedWindowID: WindowID?) -> [ApplyCommand] {
        let fullscreenItems = tickFullscreen.filter { item in
            guard let scope = item.entry.scope else { return false }
            return snapshot.state.activeScope(on: scope.displayID) == scope
        }
        guard !fullscreenItems.isEmpty else { return [] }
        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        let fullscreenScopes = Set(fullscreenItems.compactMap(\.entry.scope))
        // Focus réel relevé une fois avant la sortie du zoom et partagé avec cette décision.
        let intents = Dictionary(uniqueKeysWithValues: fullscreenScopes.compactMap { scope in
            service.commandLayoutIntent(scope: scope).map { (scope, $0) }
        })
        var newlyRestorable: [StageScope: [WindowID: Rect]] = [:]
        let commands = snapshot.windows.compactMap { entry -> ApplyCommand? in
            guard let scope = entry.scope,
                  fullscreenScopes.contains(scope),
                  !fullscreenWindowIDs.contains(entry.window.id),
                  entry.window.id != systemFocusedWindowID,
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { return nil }
            if let saved = intents[scope]?.restorePlacements, saved[entry.window.id] == nil {
                newlyRestorable[scope, default: [:]][entry.window.id] = entry.window.frame
            }
            let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            return ApplyCommand(window: entry.window, frame: Rect(frame), preservesSize: true)
        }
        // Une fenêtre ouverte pendant le zoom garde son cadre visible avant son premier masquage.
        // Le store existant conserve la capture atomiquement, sans remplacer la disposition initiale.
        if !newlyRestorable.isEmpty {
            service.effectiveIntentStore.mutate { stored in
                for (scope, additions) in newlyRestorable {
                    guard var intent = stored[scope.description], intent.zoomedWindowID != nil,
                          var saved = intent.restorePlacements else { continue }
                    saved.merge(additions) { initial, _ in initial }
                    intent.restorePlacements = saved
                    stored[scope.description] = intent
                }
            }
        }
        return commands
    }

    /// Recalage d'une fenêtre zoomée par commande dont l'origine a glissé (redémarrage, changement
    /// d'écran). Une fenêtre en plein écran natif appartient à macOS : jamais déplacée. O(f).
    private func zoomReanchorCommands(in snapshot: DaemonSnapshot) -> [ApplyCommand] {
        tickFullscreen.compactMap { item -> ApplyCommand? in
            let entry = item.entry
            guard let scope = entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  entry.window.furniture?.isNativeFullscreen != true,
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { return nil }
            if service.commandLayoutIntent(scope: scope)?.zoomReservesRail == true {
                return reservedZoomCommand(for: entry.window, on: item.display, scope: scope)
            }
            guard let target = fullscreenSizedReanchorTarget(for: entry.window.frame.cgRect, on: item.display) else { return nil }
            return ApplyCommand(window: entry.window, frame: Rect(target))
        }
    }

    /// Recalage réservé : cible actualisée, avec les mêmes mémoires de refus que la disposition.
    private func reservedZoomCommand(for window: WindowSnapshot, on display: DisplaySnapshot, scope: StageScope) -> ApplyCommand? {
        guard let target = service.maximizedFrame(on: display) else { return nil }
        let observed = window.frame.cgRect
        let exact = exactSettingsScopes.contains(scope) && settingsFrameStates[window.id] != .completed
        if framesAreClose(observed, target, tolerance: exact ? 0 : LayoutTolerance.frameMatch), observed.minX >= target.minX,
           display.visibleFrame.cgRect.contains(observed) { return nil }
        let command = ApplyCommand(window: window, frame: Rect(target))
        let id = window.id.rawValue
        guard clampedFrames[id]?.matches(command: command) != true,
              failedFrames[id]?.matches(command: command) != true,
              revertedAppliedFrames[id]?.matches(command: command) != true else { return nil }
        return command
    }

    /// Retour d'une fenêtre épinglée visible dans le scope actif à son dernier cadre. O(n).
    private func pinRestoreCommands(in snapshot: DaemonSnapshot) -> [ApplyCommand] {
        snapshot.windows.compactMap { entry -> ApplyCommand? in
            guard let pin = entry.pin,
                  let activeScope = snapshot.state.activeScope(on: pin.homeScope.displayID),
                  pin.visibility(in: activeScope).shouldBeVisible,
                  HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { return nil }
            return ApplyCommand(window: entry.window, frame: pin.lastFrame)
        }
    }

    /// Valeur du critère `is_floating` des règles (REL-007). Flottante = non gérée par la mosaïque :
    /// - hors du tiling (`isTileCandidate` faux : floating_bundles, action de règle `floating`,
    ///   popup) - c'est aussi `floating` dans `TargetInspectionService` ;
    /// - épinglée (jamais membre de la mosaïque, restaurée à son dernier cadre) ;
    /// - membre d'une stage en mode `float`.
    /// Une candidate sans scope (membre gardé pour un écran débranché, ou aucun écran) donne nil :
    /// son état n'est pas observable, aucune règle `is_floating` ne lui correspond, donc aucune
    /// règle `is_floating = true` ne la déplace hors de sa stage d'origine (`scope == nil` n'est pas
    /// une preuve de flottement). `AutomationSnapshotService` publie la même valeur, nil rendu faux. O(1).
    public static func ruleFloatingState(of entry: ScopedWindowSnapshot, in state: RoadieState) -> Bool? {
        guard entry.window.isTileCandidate else { return true }
        guard let scope = entry.scope else { return nil }
        if entry.pin != nil { return true }
        return state.stage(scope: scope).map { $0.mode == .float }
    }

    /// Moteur de règles de la configuration réellement active (REL-014). `currentConfig()` lit le
    /// chemin actif, y compris celui d'un `roadie config reload <fichier>` : le cache est invalidé
    /// par le contenu des règles, pas par la version du fichier par défaut. Des règles identiques
    /// venues d'un autre fichier donnent un moteur identique : rien à invalider.
    // O(r) par passe (comparaison des règles, r = nombre de règles) ; avant : relecture et somme de
    // contrôle complètes du fichier par défaut et de ses règles générées à chaque passe.
    private func currentRuleEngine() -> WindowRuleEngine? {
        if let staticRuleEngine {
            return staticRuleEngine
        }
        let rules = configService.currentConfig().rules
        if cachedRules != rules {
            cachedRules = rules
            cachedRuleEngine = rules.isEmpty ? nil : WindowRuleEngine(rules: rules)
            emittedRuleSkippedKeys.removeAll()
            emittedRulePlacementIssueKeys.removeAll()
        }
        return cachedRuleEngine
    }

    private func displaySignature(_ displays: [DisplaySnapshot]) -> String {
        displays
            .map { display in
                let frame = display.frame
                let visible = display.visibleFrame
                return [
                    display.id.rawValue,
                    String(Int(frame.x.rounded())),
                    String(Int(frame.y.rounded())),
                    String(Int(frame.width.rounded())),
                    String(Int(frame.height.rounded())),
                    String(Int(visible.x.rounded())),
                    String(Int(visible.y.rounded())),
                    String(Int(visible.width.rounded())),
                    String(Int(visible.height.rounded()))
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
    }

    /// Fenêtre placée par une règle dans la passe ; `follow` demande le focus après l'application.
    private struct RulePlacement {
        var window: WindowSnapshot
        var follow: Bool
    }

    /// Règles de placement : changements d'état logique de la passe (A15). Les frames (masquage
    /// d'une stage inactive, disposition de la stage cible) viennent du plan de la copie de travail.
    private func evaluateRules(in snapshot: DaemonSnapshot) -> [RulePlacement] {
        guard let ruleEngine = currentRuleEngine() else { return [] }
        guard ruleEngine.validationErrors.isEmpty else {
            appendRuleFailedEvents(ruleEngine.validationErrors)
            return []
        }
        var placements: [RulePlacement] = []
        let liveWindowIDs = Set(snapshot.windows.map(\.window.id))
        observedRulePlacementWindowIDs.formIntersection(liveWindowIDs)
        pruneRuleEventKeys(keeping: liveWindowIDs)
        for entry in snapshot.windows where entry.window.isOnScreen {
            // Rôle et sous-rôle AX transmis comme dans la politique du relevé ; état flottant
            // explicite (REL-007).
            let context = WindowRuleMatchContext(
                role: entry.window.role,
                subrole: entry.window.subrole,
                display: entry.scope?.displayID.rawValue,
                desktop: entry.scope.map { String($0.desktopID.rawValue) },
                stage: entry.scope?.stageID.rawValue,
                isFloating: Self.ruleFloatingState(of: entry, in: snapshot.state)
            )
            let application = ruleEngine.evaluate(window: entry.window, context: context)
            appendRuleEvents(application, window: entry.window)
            switch applyRulePlacement(application, entry: entry, snapshot: snapshot) {
            case .placed(let placement):
                placements.append(placement)
            case .deferred:
                // Destination indisponible : fenêtre non marquée, retentée à la passe suivante
                // (REL-008). Le refus est journalisé une seule fois (clé d'incident).
                continue
            case .settled:
                break
            }
            observedRulePlacementWindowIDs.insert(entry.window.id)
        }
        return placements
    }

    /// Issue d'une règle de placement pour une fenêtre dans la passe.
    private enum RulePlacementOutcome {
        /// Fenêtre placée dans la passe.
        case placed(RulePlacement)
        /// Destination indisponible (écran absent, bureau inconnu) : à retenter.
        case deferred
        /// Aucune action ou refus définitif.
        case settled
    }

    private func appendRuleFailedEvents(_ validationErrors: [ConfigValidationItem]) {
        for item in validationErrors {
            events.append(RoadieEventEnvelope(
                id: "rule_\(UUID().uuidString)",
                type: "rule.failed",
                scope: .rule,
                subject: AutomationSubject(kind: "config", id: "rules"),
                cause: .system,
                payload: [
                    "path": .string(item.path),
                    "message": .string(item.message)
                ]
            ))
        }
    }

    private func appendRuleEvents(_ application: WindowRuleApplication, window: WindowSnapshot) {
        guard !application.evaluations.isEmpty else { return }
        guard !observedRulePlacementWindowIDs.contains(window.id) else { return }
        let subject = AutomationSubject(kind: "window", id: String(window.id.rawValue))
        let basePayload: [String: AutomationPayload] = [
            "windowID": .string(String(window.id.rawValue)),
            "app": .string(window.appName),
            "title": .string(window.title)
        ]

        guard let matchedRuleID = application.matchedRuleID else {
            // Pas d'event rule.skipped pour les fenetres non gerables (overlays systeme :
            // Window Server StatusIndicator, Control Center, popups ephemeres). Elles
            // reapparaissent avec un nouveau windowID en permanence et generaient un spam
            // de rule.skipped (~7-13/min) sans valeur diagnostique. On ne loggue le skip
            // que pour les vraies fenetres candidates (utile : "pourquoi ma regle ne
            // matche pas cette fenetre ?").
            guard window.isTileCandidate else { return }
            let skippedKey = ruleEventKey(window: window, suffix: "skipped")
            guard !emittedRuleSkippedKeys.contains(skippedKey) else { return }
            emittedRuleSkippedKeys.insert(skippedKey)
            emittedRuleAppliedKeys = emittedRuleAppliedKeys.filter { !$0.hasPrefix("applied|\(window.id.rawValue)|") }
            events.append(RoadieEventEnvelope(
                id: "rule_\(UUID().uuidString)",
                type: "rule.skipped",
                scope: .window,
                subject: subject,
                cause: .system,
                payload: basePayload.merging([
                    "reason": .string("no matching rule")
                ]) { _, new in new }
            ))
            return
        }
        emittedRuleSkippedKeys.remove(ruleEventKey(window: window, suffix: "skipped"))
        let appliedKey = ruleAppliedEventKey(window: window, application: application)
        guard !emittedRuleAppliedKeys.contains(appliedKey) else { return }
        emittedRuleAppliedKeys = emittedRuleAppliedKeys.filter { !$0.hasPrefix("applied|\(window.id.rawValue)|") }
        emittedRuleAppliedKeys.insert(appliedKey)

        let matchedPayload = basePayload.merging([
            "ruleID": .string(matchedRuleID)
        ]) { _, new in new }
        events.append(RoadieEventEnvelope(
            id: "rule_\(UUID().uuidString)",
            type: "rule.matched",
            scope: .window,
            subject: subject,
            cause: .system,
            payload: matchedPayload
        ))
        events.append(RoadieEventEnvelope(
            id: "rule_\(UUID().uuidString)",
            type: "rule.applied",
            scope: .window,
            subject: subject,
            cause: .system,
            payload: matchedPayload.merging(ruleActionPayload(application)) { _, new in new }
        ))
    }

    private func ruleEventKey(window: WindowSnapshot, suffix: String) -> String {
        // Le titre est volontairement EXCLU : il change frequemment (terminal qui affiche
        // une commande, navigateur qui change d'onglet) et provoquait une re-emission de
        // rule.skipped a chaque changement de titre (spam ~7-10 events/min). La transition
        // skipped <-> matched est deja detectee par les deux sets emittedRuleSkippedKeys /
        // emittedRuleAppliedKeys, donc une regle title_regex reste correctement reevaluee.
        "\(suffix)|\(window.id.rawValue)|\(window.appName)"
    }

    private func ruleAppliedEventKey(window: WindowSnapshot, application: WindowRuleApplication) -> String {
        [
            "applied",
            String(window.id.rawValue),
            application.matchedRuleID ?? "",
            ruleActionSignature(application)
        ].joined(separator: "|")
    }

    private func ruleActionSignature(_ application: WindowRuleApplication) -> String {
        [
            "excluded=\(application.excluded)",
            "assignDesktop=\(application.assignDesktop ?? "")",
            "assignDisplay=\(application.assignDisplay ?? "")",
            "assignStage=\(application.assignStage ?? "")",
            "follow=\(application.follow.map(String.init) ?? "")",
            "floating=\(application.floating.map(String.init) ?? "")",
            "layout=\(application.layout ?? "")",
            "gapOverride=\(application.gapOverride.map(String.init) ?? "")",
            "scratchpad=\(application.scratchpad ?? "")"
        ].joined(separator: ";")
    }

    private func pruneRuleEventKeys(keeping liveWindowIDs: Set<WindowID>) {
        func containsLiveWindowID(_ key: String) -> Bool {
            key.split(separator: "|").contains { part in
                guard let raw = UInt32(part) else { return false }
                return liveWindowIDs.contains(WindowID(rawValue: raw))
            }
        }
        emittedRuleSkippedKeys = emittedRuleSkippedKeys.filter(containsLiveWindowID)
        emittedRuleAppliedKeys = emittedRuleAppliedKeys.filter(containsLiveWindowID)
        emittedRulePlacementIssueKeys = emittedRulePlacementIssueKeys.filter(containsLiveWindowID)
    }

    private func ruleActionPayload(_ application: WindowRuleApplication) -> [String: AutomationPayload] {
        var payload: [String: AutomationPayload] = [:]
        payload["excluded"] = .bool(application.excluded)
        if let assignDesktop = application.assignDesktop {
            payload["assignDesktop"] = .string(assignDesktop)
        }
        if let assignDisplay = application.assignDisplay {
            payload["assignDisplay"] = .string(assignDisplay)
        }
        if let assignStage = application.assignStage {
            payload["assignStage"] = .string(assignStage)
        }
        if let follow = application.follow {
            payload["follow"] = .bool(follow)
        }
        if let floating = application.floating {
            payload["floating"] = .bool(floating)
        }
        if let layout = application.layout {
            payload["layout"] = .string(layout)
        }
        if let gapOverride = application.gapOverride {
            payload["gapOverride"] = .int(gapOverride)
        }
        if let scratchpad = application.scratchpad {
            payload["scratchpad"] = .string(scratchpad)
        }
        return payload
    }

    private func applyRulePlacement(
        _ application: WindowRuleApplication,
        entry: ScopedWindowSnapshot,
        snapshot: DaemonSnapshot
    ) -> RulePlacementOutcome {
        guard application.matchedRuleID != nil,
              application.assignDisplay != nil || application.assignDesktop != nil || application.assignStage != nil
        else { return .settled }
        guard !application.excluded else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "excluded")
            return .settled
        }
        guard entry.window.isTileCandidate else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "not a tile candidate")
            return .settled
        }
        guard !observedRulePlacementWindowIDs.contains(entry.window.id) else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "window already managed")
            return .settled
        }

        // Décision et écriture dans une seule transaction sur l'état relu sous verrou (SPEC-016
        // FR-013). Une copie de travail n'est conservée qu'en cas de placement : les branches de
        // refus n'écrivent rien. Événements et AX après le bloc (verrou non réentrant).
        enum PlacementDecision {
            case skipped(String, StageScope?)
            case deferred
            case placed(RulePlacementDestination)
        }
        let decision: PlacementDecision = store.mutate { state in
            var working = state
            if working.suppressesRulePlacement(windowID: entry.window.id, ruleID: application.matchedRuleID) {
                return .skipped("manual placement override", nil)
            }
            guard let destination = resolvePlacementDestination(application, entry: entry, snapshot: snapshot, state: &working) else {
                return .deferred
            }
            if entry.scope == destination.scope {
                return .skipped("already on target", destination.scope)
            }
            var targetScope = working.scope(displayID: destination.scope.displayID, desktopID: destination.scope.desktopID)
            targetScope.ensureStage(destination.scope.stageID)
            if destination.follow {
                targetScope.activeStageID = destination.scope.stageID
                working.switchDesktop(displayID: destination.scope.displayID, to: destination.scope.desktopID)
                working.focusDisplay(destination.scope.displayID)
            }
            for scopeIndex in working.scopes.indices {
                working.scopes[scopeIndex].remove(windowID: entry.window.id)
            }
            targetScope.assign(window: entry.window, to: destination.scope.stageID)
            working.update(targetScope)
            working.updatePinHomeScope(windowID: entry.window.id, to: destination.scope)
            state = working
            return .placed(destination)
        }
        let destination: RulePlacementDestination
        switch decision {
        case .skipped(let reason, let target):
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, destination: target, reason: reason)
            return .settled
        case .deferred:
            appendPlacementEvent("rule.placement_deferred", application: application, entry: entry, reason: "destination unavailable")
            return .deferred
        case .placed(let placed):
            destination = placed
        }

        if let sourceScope = entry.scope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: destination.scope)
        appendPlacementEvent(
            "rule.placement_applied",
            application: application,
            entry: entry,
            destination: destination.scope,
            reason: "placed"
        )
        return .placed(RulePlacement(window: entry.window, follow: destination.follow))
    }

    /// Fenêtre déplacée à la main sur un autre écran : adoptée par la stage active de cet écran,
    /// sur l'état relu sous verrou (SPEC-016 FR-013). Changement d'état logique de la passe (A15).
    private func adoptManualDisplayMoves(
        in snapshot: DaemonSnapshot,
        changedWindowIDs: Set<WindowID>
    ) -> [(window: WindowSnapshot, source: StageScope, target: StageScope, removedPin: PersistentWindowPin?)] {
        guard !changedWindowIDs.isEmpty else { return [] }
        // Adoption sur l'état relu sous verrou (SPEC-016 FR-013) ; événements après le bloc.
        let adopted = store.mutate { state in
            var adopted: [(window: WindowSnapshot, source: StageScope, target: StageScope, removedPin: PersistentWindowPin?)] = []

            for entry in snapshot.windows where changedWindowIDs.contains(entry.window.id) {
                guard let sourceScope = entry.scope,
                      entry.window.isOnScreen,
                      entry.window.isTileCandidate,
                      !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
                      let targetDisplay = snapshot.displays.first(where: { $0.frame.cgRect.contains(entry.window.frame.center) }),
                      targetDisplay.id != sourceScope.displayID
                else { continue }

                let targetDesktopID = state.currentDesktopID(for: targetDisplay.id)
                var targetScope = state.scope(displayID: targetDisplay.id, desktopID: targetDesktopID)
                let targetStageID = targetScope.activeStageID
                let targetStageScope = StageScope(
                    displayID: targetDisplay.id,
                    desktopID: targetDesktopID,
                    stageID: targetStageID
                )

                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: entry.window.id)
                }
                targetScope = state.scope(displayID: targetDisplay.id, desktopID: targetDesktopID)
                targetScope.assign(window: entry.window, to: targetStageID)
                state.update(targetScope)
                state.focusDisplay(targetDisplay.id)
                let removedPin = state.removePin(windowID: entry.window.id)
                state.suppressRulePlacement(window: entry.window)
                adopted.append((entry.window, sourceScope, targetStageScope, removedPin))
            }
            return adopted
        }

        guard !adopted.isEmpty else { return [] }

        for item in adopted {
            service.removeLayoutIntent(scope: item.source)
            service.removeLayoutIntent(scope: item.target)
            if let removedPin = item.removedPin {
                var details = removedPin.eventDetails
                details["reason"] = "manual_window_move"
                events.append(RoadieEvent(type: "window.pin_removed", scope: item.target, details: details))
            }
            events.append(RoadieEvent(type: "window_manual_display_move_adopted", scope: item.target, details: [
                "windowID": String(item.window.id.rawValue),
                "fromDisplayID": item.source.displayID.rawValue,
                "toDisplayID": item.target.displayID.rawValue,
                "desktopID": String(item.target.desktopID.rawValue),
                "stageID": item.target.stageID.rawValue,
                "rulePlacementOverride": "true",
                "unpinned": String(item.removedPin != nil)
            ]))
        }

        return adopted
    }

    private func resolvePlacementDestination(
        _ application: WindowRuleApplication,
        entry: ScopedWindowSnapshot,
        snapshot: DaemonSnapshot,
        state: inout PersistentStageState
    ) -> RulePlacementDestination? {
        guard let display = resolveDisplay(application.assignDisplay, entry: entry, snapshot: snapshot) else {
            return nil
        }
        guard let desktopID = resolveDesktop(application.assignDesktop, displayID: display.id, state: state) else {
            return nil
        }
        var scope = state.scope(displayID: display.id, desktopID: desktopID)
        guard let stageID = resolveStage(application.assignStage, scope: &scope) else {
            return nil
        }
        state.update(scope)
        return RulePlacementDestination(
            scope: StageScope(displayID: display.id, desktopID: desktopID, stageID: stageID),
            follow: application.follow ?? false
        )
    }

    private func resolveDisplay(
        _ raw: String?,
        entry: ScopedWindowSnapshot,
        snapshot: DaemonSnapshot
    ) -> DisplaySnapshot? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            if let display = snapshot.displays.first(where: { $0.id.rawValue == trimmed }) {
                return display
            }
            if let display = snapshot.displays.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return display
            }
            if let index = Int(trimmed),
               let display = snapshot.displays.first(where: { $0.index == index }) {
                return display
            }
            return nil
        }
        if let displayID = entry.scope?.displayID,
           let display = snapshot.displays.first(where: { $0.id == displayID }) {
            return display
        }
        return snapshot.displays.first { $0.frame.cgRect.contains(entry.window.frame.center) } ?? snapshot.displays.first
    }

    private func resolveDesktop(_ raw: String?, displayID: DisplayID, state: PersistentStageState) -> DesktopID? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return state.currentDesktopID(for: displayID)
        }
        if let rawValue = Int(trimmed), rawValue > 0 {
            return DesktopID(rawValue: rawValue)
        }
        if let label = state.desktopLabels.first(where: {
            $0.displayID == displayID && $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return label.desktopID
        }
        return nil
    }

    private func resolveStage(_ raw: String?, scope: inout PersistentStageScope) -> StageID? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return scope.activeStageID
        }
        if let stage = scope.stages.first(where: { $0.id.rawValue == trimmed }) {
            return stage.id
        }
        if let stage = scope.stages.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return stage.id
        }
        let created = StageID(rawValue: trimmed)
        _ = scope.createStage(created, name: trimmed)
        return created
    }

    private func appendPlacementEvent(
        _ type: String,
        application: WindowRuleApplication,
        entry: ScopedWindowSnapshot,
        destination: StageScope? = nil,
        reason: String,
        extra: [String: AutomationPayload] = [:]
    ) {
        guard let matchedRuleID = application.matchedRuleID else { return }
        let issueKey = "\(type)|\(matchedRuleID)|\(entry.window.id.rawValue)|\(reason)"
        if type != "rule.placement_applied" {
            guard !emittedRulePlacementIssueKeys.contains(issueKey) else { return }
            emittedRulePlacementIssueKeys.insert(issueKey)
        } else {
            emittedRulePlacementIssueKeys = emittedRulePlacementIssueKeys.filter {
                !$0.contains("|\(matchedRuleID)|\(entry.window.id.rawValue)|")
            }
        }
        var payload: [String: AutomationPayload] = [
            "windowID": .string(String(entry.window.id.rawValue)),
            "app": .string(entry.window.appName),
            "title": .string(entry.window.title),
            "ruleID": .string(matchedRuleID),
            "reason": .string(reason)
        ]
        if let destination {
            payload["displayID"] = .string(destination.displayID.rawValue)
            payload["desktopID"] = .int(destination.desktopID.rawValue)
            payload["stageID"] = .string(destination.stageID.rawValue)
        }
        for (key, value) in extra {
            payload[key] = value
        }
        events.append(RoadieEventEnvelope(
            id: "rule_\(UUID().uuidString)",
            type: type,
            scope: .window,
            subject: AutomationSubject(kind: "window", id: String(entry.window.id.rawValue)),
            cause: .system,
            payload: payload
        ))
    }

    /// Commandes des modes sans arbre, sans les plein écrans ni les demandes déjà refusées,
    /// échouées ou annulées par l'application (protections des modes sans arbre, A3). O(plan)
    private func suppressKnownUnmovableFrames(in plan: ApplyPlan, snapshot: DaemonSnapshot) -> ApplyPlan {
        let cutoff = now().addingTimeInterval(-LayoutTolerance.recentRefusal)
        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        let fullscreenScopes = Set(tickFullscreen.compactMap(\.entry.scope))
        let windowsByID = Dictionary(snapshot.windows.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ApplyPlan(commands: plan.commands.compactMap { planned -> ApplyCommand? in
            if fullscreenWindowIDs.contains(planned.window.id) {
                return nil
            }
            if let scope = windowsByID[planned.window.id]?.scope,
               fullscreenScopes.contains(scope) {
                return nil
            }
            var command = planned
            if let known = clampedFrames[command.window.id.rawValue] {
                guard let adjusted = known.adjusted(command) else { return nil }
                command = adjusted
            }
            if let known = failedFrames[command.window.id.rawValue],
               known.matches(command: command) {
                return nil
            }
            if let known = revertedAppliedFrames[command.window.id.rawValue],
               known.appliedAt >= cutoff || known.isLasting,
               known.matches(command: command) {
                return nil
            }
            return command
        })
    }

    private func snapshotExcludingGrowthClampedWindows(_ snapshot: DaemonSnapshot) -> DaemonSnapshot {
        let excludedEntries = snapshot.windows.filter { entry in
            guard let known = clampedFrames[entry.window.id.rawValue] else { return false }
            return known.shouldExcludeFromLayout(window: entry.window)
        }
        guard !excludedEntries.isEmpty else {
            lastGrowthClampedExcludedWindowIDs = []
            return snapshot
        }

        let excludedIDs = Set(excludedEntries.map(\.window.id))
        if excludedIDs != lastGrowthClampedExcludedWindowIDs {
            events.append(RoadieEvent(type: "growth_clamped_windows_excluded_from_layout", details: [
                "windowIDs": excludedIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                "windows": excludedEntries
                    .map { "\($0.window.id.rawValue):\($0.window.appName):\($0.window.title)" }
                    .sorted()
                    .joined(separator: "|")
            ]))
            lastGrowthClampedExcludedWindowIDs = excludedIDs
        }

        var copy = snapshot
        copy.windows.removeAll { excludedIDs.contains($0.window.id) }
        return copy
    }

    /// Changements observés dans un scope en plein écran : le scope est exclu, ils sont seulement
    /// journalisés. Une entrée en plein écran natif invalide l'intent de son scope ; un zoom de
    /// commande garde le sien, qui porte le marqueur `zoomedWindowID`.
    private func handleFullscreenScopeChanges(
        in snapshot: DaemonSnapshot,
        changedWindowIDs: Set<WindowID>,
        fullscreenScopes: Set<StageScope>
    ) {
        guard !changedWindowIDs.isEmpty else { return }
        let changedFullscreen = tickFullscreen.filter { changedWindowIDs.contains($0.entry.window.id) }
        let nativeWindowIDs = Set(changedFullscreen.compactMap { item -> WindowID? in
            item.entry.window.furniture?.isNativeFullscreen == true ? item.entry.window.id : nil
        })
        if !nativeWindowIDs.isEmpty {
            removeLayoutIntents(for: nativeWindowIDs, in: snapshot)
        }
        for item in changedFullscreen {
            events.append(RoadieEvent(type: "fullscreen_layout_suppressed", scope: item.entry.scope, details: [
                "windowID": String(item.entry.window.id.rawValue),
                "app": item.entry.window.appName,
                "displayID": item.display.id.rawValue
            ]))
        }
        let fullscreenWindowIDs = Set(changedFullscreen.map(\.entry.window.id))
        let changedSiblingIDs = snapshot.windows.compactMap { entry -> String? in
            guard changedWindowIDs.contains(entry.window.id),
                  !fullscreenWindowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  fullscreenScopes.contains(scope)
            else { return nil }
            return String(entry.window.id.rawValue)
        }
        guard !changedSiblingIDs.isEmpty else { return }
        events.append(RoadieEvent(type: "fullscreen_scope_change_suppressed", details: [
            "windowIDs": changedSiblingIDs.sorted().joined(separator: ","),
            "scopes": fullscreenScopes.map(\.description).sorted().joined(separator: ",")
        ]))
    }

    /// Fenêtres en plein écran : plein écran natif signalé par macOS, ou fenêtre zoomée par une
    /// commande Roadie (`LayoutIntent.zoomedWindowID` de l'intent de commande de son scope).
    /// La taille seule ne compte jamais (FR-001, R5).
    // O(n + s) — n fenêtres, s scopes (une lecture d'intent par scope).
    private func fullscreenEntries(in snapshot: DaemonSnapshot) -> [(entry: ScopedWindowSnapshot, display: DisplaySnapshot)] {
        var zoomedWindowIDs: [StageScope: WindowID] = [:]
        var readScopes: Set<StageScope> = []
        return snapshot.windows.compactMap { entry in
            guard entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  let display = display(for: entry, in: snapshot)
            else { return nil }
            if entry.window.furniture?.isNativeFullscreen == true {
                return (entry, display)
            }
            guard let scope = entry.scope else { return nil }
            if readScopes.insert(scope).inserted {
                zoomedWindowIDs[scope] = service.commandLayoutIntent(scope: scope)?.zoomedWindowID
            }
            return zoomedWindowIDs[scope] == entry.window.id ? (entry, display) : nil
        }
    }

    private func display(for entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let displayID = entry.scope?.displayID,
           let display = snapshot.displays.first(where: { $0.id == displayID }) {
            return display
        }
        let center = entry.window.frame.center
        return snapshot.displays.first { $0.frame.cgRect.contains(center) }
    }

    private func isScreenDominantFullscreenSized(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        let visible = display.visibleFrame.cgRect
        let displayFrame = display.frame.cgRect
        guard frameSizeIsClose(frame, visible, tolerance: LayoutTolerance.fullscreenFrame)
                || frameSizeIsClose(frame, displayFrame, tolerance: LayoutTolerance.fullscreenFrame)
        else { return false }

        let overlap = frame.intersection(visible)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let visibleArea = max(1, visible.width * visible.height)
        let overlapArea = overlap.width * overlap.height
        return overlapArea / visibleArea >= LayoutTolerance.halfCoverage
    }

    /// Cible de recalage d'une fenêtre zoomée décalée : sa taille couvre encore l'écran mais son
    /// origine a glissé. nil si elle est déjà en place, à la tolérance de cadre près.
    private func fullscreenSizedReanchorTarget(
        for frame: CGRect,
        on display: DisplaySnapshot
    ) -> CGRect? {
        let tolerance = LayoutTolerance.fullscreenFrame
        guard !framesAreClose(frame, display.visibleFrame.cgRect, tolerance: tolerance),
              !framesAreClose(frame, display.frame.cgRect, tolerance: tolerance),
              isScreenDominantFullscreenSized(frame, on: display)
        else { return nil }

        return fullscreenSizedRestoreTarget(for: frame, on: display)
    }

    private func fullscreenSizedRestoreTarget(
        for frame: CGRect,
        on display: DisplaySnapshot
    ) -> CGRect? {
        let visible = display.visibleFrame.cgRect
        let displayFrame = display.frame.cgRect
        let target: CGRect
        if frameSizeIsClose(frame, visible, tolerance: LayoutTolerance.fullscreenFrame) {
            target = visible
        } else if frameSizeIsClose(frame, displayFrame, tolerance: LayoutTolerance.fullscreenFrame) {
            target = displayFrame
        } else {
            return nil
        }
        guard !framesAreClose(frame, target, tolerance: LayoutTolerance.frameNear) else { return nil }
        return target.integral
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func frameSizeIsClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    /// Mémoire des refus, des échecs et des annulations des modes sans arbre (FR-004, A3). O(k).
    private func record(_ result: ApplyResult, from plan: ApplyPlan) {
        let commandsByID = plan.commands.reduce(into: [WindowID: ApplyCommand]()) { result, command in
            result[command.window.id] = command
        }
        for item in result.items {
            switch item.status {
            case .clamped:
                if let actual = item.actual {
                    let id = item.windowID.rawValue
                    let previous = clampedFrames[id] ?? expiredClamps[id]
                    let repeated = previous.map {
                        $0.requested.isClose(to: item.requested, tolerance: LayoutTolerance.frameNear)
                            && $0.actual.isClose(to: actual, tolerance: LayoutTolerance.frameNear)
                    } == true
                    clampedFrames[id] = ClampedFrame(
                        requested: item.requested,
                        actual: actual,
                        recordedAt: now(),
                        lasting: repeated || previous?.lasting == true
                    )
                    expiredClamps[id] = nil
                }
                revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
            case .applied:
                // Un simple déplacement à la taille refusée garde un refus durable (SPEC-083).
                let movedAtRefusedSize = clampedFrames[item.windowID.rawValue].map {
                    $0.lasting && abs(item.requested.width - $0.actual.width) <= LayoutTolerance.frameNear
                        && abs(item.requested.height - $0.actual.height) <= LayoutTolerance.frameNear
                } == true
                if !movedAtRefusedSize { clampedFrames.removeValue(forKey: item.windowID.rawValue) }
                expiredClamps.removeValue(forKey: item.windowID.rawValue)
                failedFrames.removeValue(forKey: item.windowID.rawValue)
                expiredFailures.removeValue(forKey: item.windowID.rawValue)
                if let command = commandsByID[item.windowID],
                   !command.window.frame.isClose(to: item.requested, tolerance: LayoutTolerance.frameMatch) {
                    // La même écriture refaite depuis le même cadre : l'application est revenue
                    // d'elle-même à sa taille après la précédente (SPEC-083).
                    let previous = revertedAppliedFrames[item.windowID.rawValue]
                    let reverts = previous?.matches(command: command) == true ? (previous?.reverts ?? 0) + 1 : 0
                    revertedAppliedFrames[item.windowID.rawValue] = RevertedAppliedFrame(
                        requested: item.requested,
                        observedBeforeApply: command.window.frame,
                        appliedAt: now(),
                        reverts: reverts
                    )
                } else {
                    revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
                }
            case .failed:
                if let command = commandsByID[item.windowID] {
                    let id = item.windowID.rawValue
                    let previous = failedFrames[id] ?? expiredFailures[id]
                    failedFrames[id] = FailedFrame(
                        requested: item.requested,
                        observedAtFailure: command.window.frame,
                        recordedAt: now(),
                        lasting: previous?.matches(command: command) == true
                    )
                    expiredFailures[id] = nil
                }
                revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
            }
        }
    }

    private func appendItemEvents(_ result: ApplyResult, generation: UInt64) {
        for item in result.items {
            switch item.status {
            case .clamped:
                events.append(RoadieEvent(type: "layout_clamped", details: [
                    "windowID": String(item.windowID.rawValue),
                    "requested": frameDescription(item.requested),
                    "actual": item.actual.map(frameDescription) ?? "-"
                ]))
            case .failed:
                var details = [
                    "windowID": String(item.windowID.rawValue),
                    "requested": frameDescription(item.requested)
                ]
                if let entry = writtenFrames.entry(for: item.windowID.rawValue), entry.generation == generation,
                   Self.matches(entry.requested, item.requested.cgRect) {
                    details["axWriteAttempts"] = String(entry.writesInGeneration)
                    details["axReadBack"] = entry.readBack.map { frameDescription(Rect($0)) } ?? "-"
                    details["axNativeFullscreenReading"] = entry.nativeFullscreenReading.map { String($0) } ?? "unknown"
                    for (phase, code) in entry.axResultCodes ?? [:] { details["ax.\(phase)"] = String(code) }
                }
                events.append(RoadieEvent(type: "layout_failed", details: details))
            case .applied:
                break
            }
        }
    }

    private func frameDescription(_ frame: Rect) -> String {
        "\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))"
    }

    private func stabilizeClampedPositions(
        _ result: ApplyResult,
        from plan: ApplyPlan,
        in snapshot: DaemonSnapshot
    ) -> ApplyResult {
        var stabilizedItems = result.items
        let commandsByID = plan.commands.reduce(into: [WindowID: ApplyCommand]()) { result, command in
            result[command.window.id] = command
        }
        let windowsByID = snapshot.windows.reduce(into: [WindowID: ScopedWindowSnapshot]()) { result, entry in
            result[entry.window.id] = entry
        }

        for index in stabilizedItems.indices {
            var item = stabilizedItems[index]
            guard item.status == .clamped,
                  let actual = item.actual,
                  let command = commandsByID[item.windowID]
            else { continue }

            let display: DisplaySnapshot?
            if let entry = windowsByID[item.windowID] {
                display = self.display(for: entry, in: snapshot)
            } else {
                display = nil
            }
            let anchored = stabilizedClampedFrame(requested: item.requested, actual: actual, display: display)
            guard !actual.isClose(to: anchored, tolerance: LayoutTolerance.frameMatch),
                  let stabilized = service.setFrame(anchored.cgRect, of: command.window, generation: PlacementGeneration.outsideBudget)
            else { continue }

            item.actual = Rect(stabilized)
            stabilizedItems[index] = item
        }

        return ApplyResult(
            attempted: result.attempted,
            applied: result.applied,
            clamped: result.clamped,
            failed: result.failed,
            items: stabilizedItems
        )
    }

    /// Voisines des fenêtres clampées replacées dans l'espace restant (modes sans arbre, A3). O(s · n).
    private func clampedSiblingRepairPlan(from result: ApplyResult, in snapshot: DaemonSnapshot) -> ApplyPlan {
        let clampedItems = result.items.filter { $0.status == .clamped && $0.actual != nil }
        guard !clampedItems.isEmpty else { return ApplyPlan(commands: []) }

        let clampedIDs = Set(clampedItems.map(\.windowID))
        let clampedActualFrames = Dictionary(uniqueKeysWithValues: clampedItems.compactMap { item -> (WindowID, CGRect)? in
            guard let actual = item.actual else { return nil }
            return (item.windowID, actual.cgRect)
        })
        let entriesByID = snapshot.windows.reduce(into: [WindowID: ScopedWindowSnapshot]()) { result, entry in
            result[entry.window.id] = entry
        }
        let scopes = Set(clampedItems.compactMap { item in entriesByID[item.windowID]?.scope })
        var commands: [ApplyCommand] = []

        for scope in scopes {
            guard let stage = snapshot.state.stage(scope: scope),
                  stage.mode != .float,
                  !stage.mode.usesTreeEngine,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID })
            else { continue }

            let blockers = clampedIDs.compactMap { id -> CGRect? in
                guard entriesByID[id]?.scope == scope else { return nil }
                return clampedActualFrames[id]
            }
            guard let repairContainer = clampedSiblingRepairContainer(
                excluding: blockers,
                visibleFrame: display.visibleFrame.cgRect,
                innerGap: CGFloat(service.innerGap())
            ) else { continue }

            let siblingEntries = snapshot.windows.filter { entry in
                entry.scope == scope
                    && entry.window.isTileCandidate
                    && entry.window.isOnScreen
                    && !clampedIDs.contains(entry.window.id)
            }
            guard !siblingEntries.isEmpty else { continue }
            // Index des voisines hors boucle : O(n + m) au lieu de O(n · m), ordre de la stage conservé (PERF-004).
            let siblingIDSet = Set(siblingEntries.map(\.window.id))
            let siblingIDs = stage.windowIDs.filter(siblingIDSet.contains)
            guard !siblingIDs.isEmpty else { continue }

            let currentFrames = siblingEntries.reduce(into: [WindowID: CGRect]()) { result, entry in
                result[entry.window.id] = entry.window.frame.cgRect
            }
            let plan = LayoutPlanner.plan(LayoutRequest(
                scope: scope,
                mode: stage.mode,
                container: repairContainer.integral,
                windowIDs: siblingIDs,
                currentFrames: currentFrames,
                priorityWindowIDs: [],
                newWindowIDs: [],
                splitPolicy: service.effectiveConfig.tiling.splitPolicy,
                innerGap: service.innerGap(),
                masterRatio: service.effectiveConfig.tiling.masterRatio
            ))
            let windowsByID = siblingEntries.reduce(into: [WindowID: WindowSnapshot]()) { result, entry in
                result[entry.window.id] = entry.window
            }
            for id in siblingIDs {
                guard let window = windowsByID[id],
                      let target = plan.placements[id],
                      !window.frame.isClose(to: Rect(target), tolerance: LayoutTolerance.frameMatch)
                else { continue }
                commands.append(ApplyCommand(window: window, frame: Rect(target)))
            }
        }

        return ApplyPlan(commands: commands)
    }

    /// Scopes actifs sans arbre (A3) où au moins deux fenêtres clampées se chevauchent ou débordent encore.
    /// Replanifie avec les tailles minimales connues ; garde la fenêtre focalisée et cache les
    /// autres seulement si aucune disposition n'existe (dernier recours journalisé, FR-003).
    // O(r + s · n³) au pire - r résultats indexés une fois, s scopes concernés, n fenêtres par scope.
    // Avant PERF-009, la préparation des minimums ajoutait O(n·r) par scope.
    private func resolveInfeasibleClampedScopes(
        from result: ApplyResult,
        in snapshot: DaemonSnapshot
    ) -> (result: ApplyResult, commands: [ApplyCommand], hidden: Int) {
        var resolution = ApplyResult.empty
        var commands: [ApplyCommand] = []
        var hidden = 0
        let clampedItems = result.items.filter { $0.status == .clamped && $0.actual != nil }
        guard clampedItems.count >= 2 else { return (resolution, commands, hidden) }

        let entriesByID = snapshot.windows.reduce(into: [WindowID: ScopedWindowSnapshot]()) { result, entry in
            result[entry.window.id] = entry
        }
        let clampedScopes = Dictionary(grouping: clampedItems) { item in
            entriesByID[item.windowID]?.scope
        }
        let frames = framesAfterApplying(result, fallback: scopedFrames(in: snapshot))
        let requestedFrames = result.items.reduce(into: [WindowID: CGRect]()) { frames, item in
            frames[item.windowID] = item.requested.cgRect
        }
        let innerGap = CGFloat(service.innerGap())
        // Index des refus partagé par tous les scopes : un seul parcours des résultats (PERF-009).
        let refusedMinimums = Self.refusedMinimumSizes(in: result)
        let minimumFloor = CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide)

        for (optionalScope, scopedClampedItems) in clampedScopes {
            guard let scope = optionalScope,
                  scopedClampedItems.count >= 2,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled,
                  !stage.mode.usesTreeEngine,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID })
            else { continue }

            let entries = snapshot.windows.filter { entry in
                entry.scope == scope
                    && entry.window.isTileCandidate
                    && entry.window.isOnScreen
                    && !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            }
            let entryIDs = Set(entries.map(\.window.id))
            let orderedIDs = stage.windowIDs.filter { entryIDs.contains($0) }
            guard orderedIDs.count > 1 else { continue }

            var liveFrames = entries.reduce(into: [WindowID: CGRect]()) { result, entry in
                result[entry.window.id] = frames[entry.window.id.rawValue]?.cgRect ?? entry.window.frame.cgRect
            }
            let visibleFrame = display.visibleFrame.cgRect
            guard framesConflict(orderedIDs.compactMap { liveFrames[$0] }, in: visibleFrame) else { continue }

            // Conteneur du plan : union des cadres demandés, marges extérieures déjà appliquées.
            let container = orderedIDs
                .compactMap { requestedFrames[$0] ?? liveFrames[$0] }
                .reduce(CGRect.null) { $0.union($1) }
                .intersection(visibleFrame)
            // Taille minimale connue : plancher, refus mémorisés, refus de ce résultat.
            // O(n) par scope avec l'index ; avant : O(n·r), un parcours des r résultats par fenêtre.
            var minimumSizes = orderedIDs.reduce(into: [WindowID: CGSize]()) { sizes, id in
                var size = Self.largest(minimumFloor, refusedMinimums[id] ?? .zero)
                if let known = clampedFrames[id.rawValue] {
                    size = Self.largest(size, Self.minimumSize(requested: known.requested, actual: known.actual))
                }
                sizes[id] = size
            }
            // Deux essais au plus : le premier peut révéler de nouveaux minimums.
            var arranged = false
            for _ in 0..<2 {
                guard let targets = Self.minimumSizeArrangement(
                    orderedIDs.map { minimumSizes[$0] ?? .zero },
                    in: container,
                    innerGap: innerGap
                ) else { break }
                let plan = ApplyPlan(commands: zip(orderedIDs, targets).compactMap { id, target -> ApplyCommand? in
                    guard let window = entriesByID[id]?.window,
                          let live = liveFrames[id],
                          !Rect(live).isClose(to: Rect(target), tolerance: LayoutTolerance.frameMatch)
                    else { return nil }
                    return ApplyCommand(window: window, frame: Rect(target))
                })
                guard !plan.commands.isEmpty else { break }
                let attempt = service.apply(plan, generation: PlacementGeneration.outsideBudget)
                resolution = resolution.merged(with: attempt)
                commands += plan.commands
                for item in attempt.items where item.status != .failed {
                    liveFrames[item.windowID] = (item.actual ?? item.requested).cgRect
                    if item.status == .clamped, let actual = item.actual {
                        minimumSizes[item.windowID] = Self.largest(
                            minimumSizes[item.windowID] ?? .zero,
                            Self.minimumSize(requested: item.requested, actual: actual)
                        )
                    }
                }
                if !framesConflict(orderedIDs.compactMap { liveFrames[$0] }, in: visibleFrame) {
                    arranged = true
                    break
                }
            }

            if arranged {
                // L'intent garde la disposition trouvée : le plan suivant la rejoue au lieu de la défaire.
                let placements = orderedIDs.reduce(into: [WindowID: Rect]()) { placements, id in
                    placements[id] = liveFrames[id].map { Rect($0) }
                }
                service.saveLayoutIntent(scope: scope, windowIDs: orderedIDs, placements: placements)
                events.append(RoadieEvent(type: "layout_clamped_scope_rearranged", scope: scope, details: [
                    "windowIDs": orderedIDs.map { String($0.rawValue) }.joined(separator: ","),
                    "reason": "known_minimums_fit_visible_frame"
                ]))
                continue
            }

            let keepID = focusedWindowIDToKeep(in: entries, snapshot: snapshot)
            var hiddenIDs: [String] = []
            for entry in entries where entry.window.id != keepID {
                let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
                if service.setFrame(frame, of: entry.window, generation: PlacementGeneration.outsideBudget, preservingSize: true) != nil {
                    hidden += 1
                    hiddenIDs.append(String(entry.window.id.rawValue))
                }
            }
            guard !hiddenIDs.isEmpty else { continue }
            events.append(RoadieEvent(type: "layout_infeasible_scope_isolated", scope: scope, details: [
                "keptWindowID": String(keepID.rawValue),
                "hiddenWindowIDs": hiddenIDs.sorted().joined(separator: ","),
                "reason": "clamped_minimums_exceed_visible_frame"
            ]))
        }

        return (resolution, commands, hidden)
    }

    /// Minimums révélés par les refus (`clamped` avec cadre réel) d'un résultat, par fenêtre.
    /// Plusieurs refus d'une même fenêtre gardent le plus grand minimum de chaque axe.
    // O(r) - un seul parcours des r éléments du résultat.
    static func refusedMinimumSizes(in result: ApplyResult) -> [WindowID: CGSize] {
        result.items.reduce(into: [WindowID: CGSize]()) { sizes, item in
            guard item.status == .clamped, let actual = item.actual else { return }
            let size = minimumSize(requested: item.requested, actual: actual)
            sizes[item.windowID] = sizes[item.windowID].map { largest($0, size) } ?? size
        }
    }

    /// Vrai si des cadres se chevauchent ou débordent de la zone visible au-delà de la tolérance
    /// d'observation. O(n²).
    private func framesConflict(_ frames: [CGRect], in visibleFrame: CGRect) -> Bool {
        let tolerance = LayoutTolerance.observedChange
        let bounds = visibleFrame.insetBy(dx: -tolerance, dy: -tolerance)
        guard frames.allSatisfy({ bounds.contains($0) }) else { return true }
        for index in frames.indices {
            for otherIndex in frames.indices where otherIndex > index {
                let overlap = frames[index].intersection(frames[otherIndex])
                if !overlap.isNull, overlap.width > tolerance, overlap.height > tolerance {
                    return true
                }
            }
        }
        return false
    }

    /// Taille minimale révélée par un refus : un axe que l'application a gardé plus grand que la
    /// demande (rétrécissement refusé) fixe son minimum ; sinon le minimum de l'axe vaut
    /// `LayoutTolerance.minimumTileSide`.
    static func minimumSize(requested: Rect, actual: Rect) -> CGSize {
        func axis(requested: Double, actual: Double) -> CGFloat {
            actual > requested + LayoutTolerance.clampShrink ? CGFloat(actual) : LayoutTolerance.minimumTileSide
        }
        return CGSize(
            width: axis(requested: requested.width, actual: actual.width),
            height: axis(requested: requested.height, actual: actual.height)
        )
    }

    /// Disposition qui respecte des tailles minimales dans `container` : colonnes de fenêtres
    /// consécutives, puis rangées. Les fenêtres gardent leur ordre ; l'espace libre est partagé
    /// pour égaliser les tailles. nil si aucune disposition de ce type n'existe : seul cas où
    /// Roadie cache des fenêtres (FR-003). Implémentation unique, aussi pour les commandes de stage.
    // O(n³) au pire — 2n découpages essayés, chacun en O(n²). n = nombre de fenêtres du scope.
    static func minimumSizeArrangement(
        _ minimumSizes: [CGSize],
        in container: CGRect,
        innerGap: CGFloat
    ) -> [CGRect]? {
        guard !minimumSizes.isEmpty else { return [] }
        guard !container.isNull, container.width > 0, container.height > 0 else { return nil }
        let gap = max(0, innerGap)
        // Rejet immédiat : les surfaces minimales ne tiennent pas dans la surface disponible.
        let minimumArea = minimumSizes.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        guard minimumArea <= container.width * container.height else { return nil }
        let count = minimumSizes.count
        for groups in stride(from: count, through: 1, by: -1) {
            if let frames = shelfArrangement(minimumSizes, groups: groups, in: container, gap: gap, transposed: false) {
                return frames
            }
        }
        for groups in stride(from: 2, to: count, by: 1) {
            if let frames = shelfArrangement(minimumSizes, groups: groups, in: container, gap: gap, transposed: true) {
                return frames
            }
        }
        return nil
    }

    /// `groups` colonnes de fenêtres consécutives, empilées dans chaque colonne ; `transposed`
    /// échange les axes pour obtenir des rangées. Les dernières colonnes reçoivent une fenêtre de
    /// plus (maître à gauche, pile à droite). O(n²).
    private static func shelfArrangement(
        _ minimumSizes: [CGSize],
        groups: Int,
        in container: CGRect,
        gap: CGFloat,
        transposed: Bool
    ) -> [CGRect]? {
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        }
        let sizes = transposed ? minimumSizes.map { CGSize(width: $0.height, height: $0.width) } : minimumSizes
        let box = transposed ? flipped(container) : container
        let base = sizes.count / groups
        let longer = sizes.count % groups
        var columns: [Range<Int>] = []
        var next = 0
        for index in 0..<groups {
            let length = base + (index >= groups - longer ? 1 : 0)
            columns.append(next..<(next + length))
            next += length
        }
        let columnMinimums = columns.map { column in column.map { sizes[$0].width }.max() ?? 0 }
        guard let widths = shares(of: box.width - gap * CGFloat(groups - 1), minimums: columnMinimums) else {
            return nil
        }
        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        var x = box.minX
        for (columnIndex, column) in columns.enumerated() {
            guard let heights = shares(
                of: box.height - gap * CGFloat(column.count - 1),
                minimums: column.map { sizes[$0].height }
            ) else { return nil }
            var y = box.minY
            for (rowIndex, index) in column.enumerated() {
                frames[index] = CGRect(x: x, y: y, width: widths[columnIndex], height: heights[rowIndex])
                y += heights[rowIndex] + gap
            }
            x += widths[columnIndex] + gap
        }
        return transposed ? frames.map(flipped) : frames
    }

    /// Parts de `total` aussi égales que possible sans descendre sous les minimums, en points
    /// entiers (la dernière part reçoit le reste de l'arrondi). nil si les minimums dépassent `total`. O(n²).
    private static func shares(of total: CGFloat, minimums: [CGFloat]) -> [CGFloat]? {
        guard !minimums.isEmpty, minimums.reduce(0, +) <= total else { return nil }
        var shares = minimums
        var free = Array(minimums.indices)
        var remaining = total
        while !free.isEmpty {
            let equal = remaining / CGFloat(free.count)
            let pinned = Set(free.filter { minimums[$0] > equal })
            guard !pinned.isEmpty else {
                for index in free {
                    shares[index] = equal
                }
                break
            }
            for index in pinned {
                remaining -= minimums[index]
            }
            free.removeAll { pinned.contains($0) }
        }
        var rounded = shares.map { $0.rounded(.down) }
        rounded[rounded.count - 1] += max(0, total.rounded(.down) - rounded.reduce(0, +))
        return rounded
    }

    private static func largest(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: max(lhs.width, rhs.width), height: max(lhs.height, rhs.height))
    }

    private func focusedWindowIDToKeep(
        in entries: [ScopedWindowSnapshot],
        snapshot: DaemonSnapshot
    ) -> WindowID {
        if let focusedWindowID = snapshot.focusedWindowID,
           entries.contains(where: { $0.window.id == focusedWindowID }) {
            return focusedWindowID
        }
        return entries.max { $0.window.frame.cgRect.area < $1.window.frame.cgRect.area }?.window.id
            ?? entries[0].window.id
    }

    private func clampedSiblingRepairContainer(
        excluding blockers: [CGRect],
        visibleFrame: CGRect,
        innerGap: CGFloat
    ) -> CGRect? {
        guard !blockers.isEmpty else { return nil }
        let blocker = blockers.reduce(blockers[0]) { $0.union($1) }
        let gap = max(0, innerGap)
        var candidates: [CGRect] = []
        if blocker.height >= visibleFrame.height * LayoutTolerance.halfCoverage {
            candidates.append(CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: blocker.minX - gap - visibleFrame.minX,
                height: visibleFrame.height
            ))
            candidates.append(CGRect(
                x: blocker.maxX + gap,
                y: visibleFrame.minY,
                width: visibleFrame.maxX - blocker.maxX - gap,
                height: visibleFrame.height
            ))
        }
        if blocker.width >= visibleFrame.width * LayoutTolerance.halfCoverage {
            candidates.append(CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: blocker.minY - gap - visibleFrame.minY
            ))
            candidates.append(CGRect(
                x: visibleFrame.minX,
                y: blocker.maxY + gap,
                width: visibleFrame.width,
                height: visibleFrame.maxY - blocker.maxY - gap
            ))
        }
        return candidates
            .filter { $0.width >= LayoutTolerance.minimumTileSide && $0.height >= LayoutTolerance.minimumTileSide }
            .max { $0.area < $1.area }?
            .integral
    }

    private func stabilizedClampedFrame(
        requested: Rect,
        actual: Rect,
        display: DisplaySnapshot?
    ) -> Rect {
        guard let display else {
            return Rect(x: requested.x, y: requested.y, width: actual.width, height: actual.height)
        }

        let visible = display.visibleFrame.cgRect
        let displayFrame = display.frame.cgRect
        let actualRect = actual.cgRect
        let bounds = fittingBounds(for: actualRect, visible: visible, displayFrame: displayFrame)

        if frameSizeIsClose(actualRect, bounds, tolerance: LayoutTolerance.fullscreenFrame) {
            return Rect(x: bounds.minX, y: bounds.minY, width: actual.width, height: actual.height)
        }

        let maxX = bounds.maxX - actual.width
        let maxY = bounds.maxY - actual.height
        let x = maxX >= bounds.minX ? min(max(requested.x, bounds.minX), maxX) : bounds.minX
        let y = maxY >= bounds.minY ? min(max(requested.y, bounds.minY), maxY) : bounds.minY
        return Rect(x: x, y: y, width: actual.width, height: actual.height)
    }

    private func fittingBounds(
        for actual: CGRect,
        visible: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        if actual.width <= visible.width + LayoutTolerance.fullscreenFrame,
           actual.height <= visible.height + LayoutTolerance.fullscreenFrame {
            return visible
        }
        return displayFrame
    }

    private func scopedFrames(in snapshot: DaemonSnapshot) -> [UInt32: Rect] {
        Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry in
            guard entry.scope != nil else { return nil }
            return (entry.window.id.rawValue, entry.window.frame)
        })
    }

    private func framesAfterApplying(_ result: ApplyResult, fallback: [UInt32: Rect]) -> [UInt32: Rect] {
        var frames = fallback
        for item in result.items {
            guard item.status != .failed else { continue }
            frames[item.windowID.rawValue] = item.actual ?? item.requested
        }
        return frames
    }

    /// Intent des scopes sans arbre touchés par une application sans refus. Un zoom de commande
    /// conserve ses cadres acceptés aussi en mode arbre ; aucun intent automatique d'arbre normal (R2).
    private func persistLayoutIntent(in snapshot: DaemonSnapshot, result: ApplyResult, treeScopes: Set<StageScope>) {
        let resultFrames = Dictionary(uniqueKeysWithValues: result.items.compactMap { item -> (WindowID, Rect)? in
            guard item.status == .applied else { return nil }
            return (item.windowID, item.actual ?? item.requested)
        })
        // Une lecture d'intent par scope arbre, puis uniquement des recherches en mémoire.
        let zoomedTreeScopes = Set(treeScopes.filter {
            service.commandLayoutIntent(scope: $0)?.zoomedWindowID != nil
        })
        let touchedScopes = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard let scope = entry.scope,
                  !treeScopes.contains(scope) || zoomedTreeScopes.contains(scope),
                  resultFrames[entry.window.id] != nil || priorityWindowIDs.contains(entry.window.id)
            else { return nil }
            return snapshot.state.activeScope(on: scope.displayID) == scope ? scope : nil
        })

        for scope in touchedScopes {
            guard let stage = snapshot.state.stage(scope: scope) else { continue }
            var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
                guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
                return (entry.window.id, entry.window.frame)
            })
            // Seules les frames des membres de la stage : une fenêtre écrite sur un autre écran
            // dans la même passe n'empêche pas de sauver cette disposition (REL-009). O(k).
            for id in stage.windowIDs {
                if let frame = resultFrames[id] { placements[id] = frame }
            }
            guard Set(placements.keys) == Set(stage.windowIDs) else { continue }
            service.saveLayoutIntent(scope: scope, windowIDs: stage.windowIDs, placements: placements)
        }
    }

    private func persistCurrentLayoutIntents(in snapshot: DaemonSnapshot, excluding excludedScopes: Set<StageScope>) {
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  !excludedScopes.contains(scope)
            else { continue }
            guard !service.hasValidLayoutIntent(scope: scope, in: snapshot) else { continue }
            _ = service.saveCurrentLayoutIntentIfValid(scope: scope, from: snapshot)
        }
    }

    private func persistentStageHasRecentMissingMember(
        scope: StageScope,
        in state: PersistentStageState,
        now tickNow: Date
    ) -> Bool {
        guard let stage = state.scopes
            .first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
            .stages
            .first(where: { $0.id == scope.stageID })
        else { return false }

        return stage.members.contains { member in
            guard let missingSince = member.missingSince else { return false }
            return tickNow.timeIntervalSince(missingSince) < LayoutTolerance.burstCap
        }
    }

    private func activeTiledScopesWithRecentMissingMembers(
        in snapshot: DaemonSnapshot,
        now tickNow: Date
    ) -> Set<StageScope> {
        let persistentState = store.state()
        return Set(snapshot.displays.compactMap { display -> StageScope? in
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled,
                  persistentStageHasRecentMissingMember(scope: scope, in: persistentState, now: tickNow)
            else { return nil }
            return scope
        })
    }

    /// Annule seulement les déplacements de `reconcileStableVisibleDisplayDrift`, sur l'état relu
    /// sous verrou (SPEC-016 FR-013) : les autres changements écrits entre-temps sont conservés.
    /// Une fenêtre qui n'est plus dans sa stage cible a été déplacée par ailleurs : on la laisse.
    // O(m · M) — m = fenêtres déplacées, M = membres de l'état.
    private func revertReconciledDisplayMoves(_ moves: [ReconciledDisplayMove]) {
        let defaultMode = service.effectiveConfig.tiling.defaultStrategy
        store.mutate { state in
            for move in moves where state.stageScope(for: move.window.id) == move.target {
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: move.window.id)
                }
                var source = state.scope(displayID: move.source.displayID, desktopID: move.source.desktopID, defaultMode: defaultMode)
                source.ensureStage(move.source.stageID, mode: defaultMode)
                if let origin = move.origin,
                   let stageIndex = source.stages.firstIndex(where: { $0.id == move.source.stageID }) {
                    let members = source.stages[stageIndex].members
                    // Le relevé intermédiaire a pu adopter le mode par défaut de cette stage
                    // momentanément vide. L'échec doit rendre aussi son mode et son arbre.
                    // Une stage remplie entre-temps garde les changements concurrents.
                    if members.isEmpty && source.stages[stageIndex].mode == defaultMode {
                        source.stages[stageIndex].mode = origin.mode
                        source.stages[stageIndex].bspTree = origin.bspTree
                    }
                    source.stages[stageIndex].members.insert(origin.member, at: min(origin.index, members.count))
                    if origin.wasFocused {
                        source.stages[stageIndex].focusedWindowID = move.window.id
                        source.stages[stageIndex].previousFocusedWindowID = origin.previousFocusedWindowID
                    }
                } else {
                    source.assign(window: move.window, to: move.source.stageID, focusWindow: false, defaultMode: defaultMode)
                }
                state.update(source)
            }
        }
    }

    /// Fenêtre stable et visible sur un autre écran que celui de son scope : rattachée à la stage
    /// active de son écran physique (changement d'état logique, A15). Les frames viennent du plan
    /// de la passe ; `finishDriftMoves` annule le rattachement si l'application échoue.
    private func reconcileStableVisibleDisplayDrift(
        in snapshot: DaemonSnapshot,
        excluding excludedScopes: Set<StageScope>
    ) -> [ReconciledDisplayMove] {
        let tickNow = now()
        if let lastDisplayTopologyChangedAt,
           tickNow.timeIntervalSince(lastDisplayTopologyChangedAt) < LayoutTolerance.displayDriftReconcileHold
        {
            return []
        }

        // Déplacements calculés et écrits sur l'état relu sous verrou (SPEC-016 FR-013). La
        // place d'origine de chaque membre est gardée pour pouvoir annuler ce seul déplacement.
        let defaultMode = service.effectiveConfig.tiling.defaultStrategy
        let reconciled: [ReconciledDisplayMove] = store.mutate { state in
            var reconciled: [ReconciledDisplayMove] = []
            for entry in snapshot.windows {
                guard let sourceScope = entry.scope,
                      !defersFailedDrift(entry.window, now: tickNow),
                      newWindowDriftGraceUntil[entry.window.id].map({ tickNow >= $0 }) ?? true,
                      !excludedScopes.contains(sourceScope),
                      entry.pin == nil,
                      entry.window.isOnScreen,
                      entry.window.isTileCandidate,
                      !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
                      !state.suppressesRulePlacement(windowID: entry.window.id, ruleID: nil),
                      let physicalDisplay = snapshot.displays.first(where: { $0.frame.cgRect.contains(entry.window.frame.center) }),
                      physicalDisplay.id != sourceScope.displayID
                else { continue }

                let targetDesktopID = state.currentDesktopID(for: physicalDisplay.id)
                let targetStageID = state.scope(
                    displayID: physicalDisplay.id,
                    desktopID: targetDesktopID,
                    defaultMode: defaultMode
                ).activeStageID
                let origin = ReconciledDisplayMove.Origin(in: state, windowID: entry.window.id, scope: sourceScope)
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: entry.window.id)
                }
                var targetScope = state.scope(
                    displayID: physicalDisplay.id,
                    desktopID: targetDesktopID,
                    defaultMode: defaultMode
                )
                targetScope.assign(window: entry.window, to: targetStageID, defaultMode: defaultMode)
                state.update(targetScope)
                reconciled.append(ReconciledDisplayMove(
                    window: entry.window,
                    source: sourceScope,
                    target: StageScope(displayID: physicalDisplay.id, desktopID: targetDesktopID, stageID: targetStageID),
                    origin: origin
                ))
            }
            return reconciled
        }

        return reconciled
    }

    /// Fin du rattachement physique après l'application de la passe : annulé si une écriture de ces
    /// fenêtres a échoué, sinon journalisé et les intents des deux scopes oubliés. O(m · M).
    private func finishDriftMoves(_ moves: [ReconciledDisplayMove], result: ApplyResult) {
        guard !moves.isEmpty else { return }
        let movedIDs = Set(moves.map(\.window.id))
        let failed = result.items.filter { movedIDs.contains($0.windowID) && $0.status == .failed }
        if !failed.isEmpty {
            let failedIDs = Set(failed.map(\.windowID))
            for move in moves where failedIDs.contains(move.window.id) {
                failedDriftWindows[move.window.id] = (move.window, now().addingTimeInterval(LayoutTolerance.recentRefusal))
            }
            revertReconciledDisplayMoves(moves)
            events.append(RoadieEvent(type: "window.scope_reconcile_failed", details: [
                "windows": moves.map { String($0.window.id.rawValue) }.sorted().joined(separator: ","),
                "failed": String(failed.count),
                "reason": "frame_apply_failed"
            ]))
            return
        }
        for item in moves {
            service.removeLayoutIntent(scope: item.source)
            service.removeLayoutIntent(scope: item.target)
            events.append(RoadieEvent(type: "window.scope_reconciled_to_physical_display", scope: item.target, details: [
                "windowID": String(item.window.id.rawValue),
                "fromDisplayID": item.source.displayID.rawValue,
                "toDisplayID": item.target.displayID.rawValue,
                "desktopID": String(item.target.desktopID.rawValue),
                "stageID": item.target.stageID.rawValue,
                "reason": "stable_visible_frame_on_different_display"
            ]))
        }
    }

    /// O(1) : un cadre changé ou une nouvelle identité permet une réparation immédiate.
    private func defersFailedDrift(_ window: WindowSnapshot, now: Date) -> Bool {
        guard let failure = failedDriftWindows[window.id] else { return false }
        return now < failure.retryAt && window.pid == failure.window.pid
            && window.frame.isClose(to: failure.window.frame, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }

    /// Fenêtres des modes sans arbre dont le cadre a changé depuis la passe précédente (A3). Les
    /// scopes à arbre ne lisent jamais de géométrie pour décider (R2) : ils en sont exclus. O(n).
    private func changedWindows(in frames: [UInt32: Rect], outside treeScopes: Set<StageScope>, snapshot: DaemonSnapshot) -> Set<WindowID> {
        guard let previous = lastObservedFrames else { return [] }
        var result: Set<WindowID> = []
        for (id, frame) in frames {
            guard let previousFrame = previous[id] else { continue }
            if !frame.isClose(to: previousFrame, tolerance: LayoutTolerance.observedChange) {
                result.insert(WindowID(rawValue: id))
            }
        }
        return windowIDs(result, outside: treeScopes, in: snapshot)
    }

    /// O(w + s × V) : w fenêtres, s scopes uniques, V coût de validation de l'intent.
    /// La validation géométrique n'est exécutée qu'une fois par scope admissible (PERF-011).
    static func authoritativeModelScopes(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot,
        hasValidIntent: (StageScope) -> Bool
    ) -> Set<StageScope> {
        let candidates = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .bsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope
            else { return nil }
            return scope
        })
        return Set(candidates.filter(hasValidIntent))
    }

    private func strictAuthoritativeScopes(
        _ scopes: Set<StageScope>,
        in snapshot: DaemonSnapshot
    ) -> Set<StageScope> {
        Set(scopes.filter { scope in
            guard let mode = snapshot.state.stage(scope: scope)?.mode else { return false }
            return mode != .float
        })
    }

    private func changedFramesMatchSavedIntent(
        in snapshot: DaemonSnapshot,
        frames: [UInt32: Rect],
        changedWindowIDs: Set<WindowID>
    ) -> Bool {
        let focusedWindowID = service.focusedWindowID()
        let changedScopes = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard changedWindowIDs.contains(entry.window.id) else { return nil }
            return entry.scope
        })
        guard !changedScopes.isEmpty else { return false }
        return changedScopes.allSatisfy { scope in
            service.hasMatchingIntent(scope: scope, frames: frames, focusedWindowID: focusedWindowID)
        }
    }

    private func removeLayoutIntents(for windowIDs: Set<WindowID>, in snapshot: DaemonSnapshot) {
        let scopes = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id) else { return nil }
            return entry.scope
        })
        for scope in scopes {
            service.removeLayoutIntent(scope: scope)
        }
    }

    private func recentCommandScopes(
        in snapshot: DaemonSnapshot,
        since date: Date,
        now: Date,
        windowIDs: Set<WindowID> = []
    ) -> Set<StageScope> {
        let activeScopes = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard let scope = entry.scope else { return nil }
            guard windowIDs.isEmpty || windowIDs.contains(entry.window.id) else { return nil }
            return scope
        })
        guard !activeScopes.isEmpty else {
            return []
        }
        var result: Set<StageScope> = []
        for scope in activeScopes {
            if service.hasRecentCommandIntent(scope: scope, since: date) {
                result.insert(scope)
            }
        }
        return result
    }

    private func driftedCommandScopes(_ scopes: Set<StageScope>, frames: [UInt32: Rect]) -> Set<StageScope> {
        guard !scopes.isEmpty else { return [] }
        let focusedWindowID = service.focusedWindowID()
        return Set(scopes.filter { scope in
            !service.hasMatchingIntent(
                scope: scope,
                frames: frames,
                focusedWindowID: focusedWindowID,
                positionTolerance: LayoutTolerance.observedChange,
                sizeTolerance: LayoutTolerance.observedChange,
                focusedPositionTolerance: LayoutTolerance.observedChange,
                focusedSizeTolerance: LayoutTolerance.observedChange,
                allowFocusChromeDelta: false
            )
        })
    }
}

/// Déplacement d'une fenêtre vers la stage de son écran physique, avec sa place d'origine.
private struct ReconciledDisplayMove {
    struct Origin {
        var member: PersistentStageMember
        var index: Int
        var wasFocused: Bool
        var previousFocusedWindowID: WindowID?
        var mode: WindowManagementMode
        var bspTree: BSPTree?

        /// Place du membre dans la stage `scope` de `state`, nil s'il n'y est pas.
        init?(in state: PersistentStageState, windowID: WindowID, scope: StageScope) {
            guard let stage = state.scopes
                .first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
                .stages.first(where: { $0.id == scope.stageID }),
                  let index = stage.members.firstIndex(where: { $0.windowID == windowID })
            else { return nil }
            self.member = stage.members[index]
            self.index = index
            self.wasFocused = stage.focusedWindowID == windowID
            self.previousFocusedWindowID = stage.previousFocusedWindowID
            self.mode = stage.mode
            self.bspTree = stage.bspTree
        }
    }

    var window: WindowSnapshot
    var source: StageScope
    var target: StageScope
    var origin: Origin?
}

private struct RulePlacementDestination {
    var scope: StageScope
    var follow: Bool
}

/// Refus de taille mémorisé : l'application a gardé `actual` quand Roadie demandait `requested`.
/// Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004), sauf s'il s'est répété à
/// l'identique après expiration : il dure alors jusqu'à une autre demande acceptée (SPEC-083).
private struct ClampedFrame {
    var requested: Rect
    var actual: Rect
    var recordedAt: Date
    var lasting = false

    func matches(command: ApplyCommand) -> Bool {
        if command.window.frame.isClose(to: actual, tolerance: LayoutTolerance.frameNear),
           requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest) {
            return true
        }
        if impossibleKnownMinimumIsStillRequested(by: command) {
            return true
        }
        guard currentStillMatchesClamp(command.window.frame),
              requested.isClose(
                  to: command.frame,
                  positionTolerance: LayoutTolerance.clampedPositionDrift,
                  sizeTolerance: LayoutTolerance.clampShrink
              )
        else {
            return sameImpossibleAxisIsStillRequested(by: command)
        }
        return command.frame.width <= command.window.frame.width + LayoutTolerance.frameNear
            && command.frame.height <= command.window.frame.height + LayoutTolerance.frameNear
    }

    /// Commande à envoyer malgré ce refus : inchangée si le refus ne la concerne pas ; nil si elle
    /// reprend la position d'une demande déjà refusée ; sinon la nouvelle position est appliquée
    /// avec la taille actuelle, seule la taille refusée est abandonnée (FR-004).
    func adjusted(_ command: ApplyCommand) -> ApplyCommand? {
        guard matches(command: command) else { return command }
        let drift = LayoutTolerance.clampedPositionDrift
        guard abs(command.frame.x - requested.x) > drift || abs(command.frame.y - requested.y) > drift else {
            return nil
        }
        let current = command.window.frame
        let moved = Rect(x: command.frame.x, y: command.frame.y, width: current.width, height: current.height)
        guard !current.isClose(to: moved, tolerance: LayoutTolerance.frameMatch) else { return nil }
        return ApplyCommand(window: command.window, frame: moved)
    }

    func shouldExcludeFromLayout(window: WindowSnapshot) -> Bool {
        guard currentStillMatchesClamp(window.frame) else { return false }

        return requestedGrowthWasRejected(requested: requested.width, actual: actual.width)
            || requestedGrowthWasRejected(requested: requested.height, actual: actual.height)
    }

    private func currentStillMatchesClamp(_ frame: Rect) -> Bool {
        abs(frame.width - actual.width) <= LayoutTolerance.clampShrink
            && abs(frame.height - actual.height) <= LayoutTolerance.clampShrink
    }

    private func sameImpossibleAxisIsStillRequested(by command: ApplyCommand) -> Bool {
        guard currentStillMatchesClamp(command.window.frame) else { return false }

        return axisStillImpossible(
            requested: requested.width,
            actual: actual.width,
            nextRequested: command.frame.width
        ) || axisStillImpossible(
            requested: requested.height,
            actual: actual.height,
            nextRequested: command.frame.height
        )
    }

    private func axisStillImpossible(requested: Double, actual: Double, nextRequested: Double) -> Bool {
        requestedGrowthWasRejected(requested: requested, actual: actual)
            && requestedGrowthWasRejected(requested: nextRequested, actual: actual)
            || requestedShrinkWasRejected(requested: requested, actual: actual)
            && requestedShrinkWasRejected(requested: nextRequested, actual: actual)
    }

    private func impossibleKnownMinimumIsStillRequested(by command: ApplyCommand) -> Bool {
        let widthMinimumStillRelevant = command.window.frame.width >= actual.width - LayoutTolerance.clampShrink
            && requestedShrinkWasRejected(requested: command.frame.width, actual: actual.width)
        let heightMinimumStillRelevant = command.window.frame.height >= actual.height - LayoutTolerance.clampShrink
            && requestedShrinkWasRejected(requested: command.frame.height, actual: actual.height)
        return widthMinimumStillRelevant || heightMinimumStillRelevant
    }

    private func requestedGrowthWasRejected(requested: Double, actual: Double) -> Bool {
        let tolerance = max(LayoutTolerance.growthMinimum, actual * LayoutTolerance.growthRatio)
        return requested > actual + tolerance
    }

    private func requestedShrinkWasRejected(requested: Double, actual: Double) -> Bool {
        requested < actual - LayoutTolerance.clampShrink
    }
}

/// Refus d'une restauration directe. Les mêmes échos AX ne créent pas de nouvelle demande.
private struct FailedRestoration {
    var pid: Int32
    var bundleID: String
    var scope: StageScope?
    var requested: Rect
    var observed: Rect
    var observedReliably: Bool
    var attempts: Int

    init(_ command: ApplyCommand, scope: StageScope?, observed: Rect?, attempts: Int) {
        pid = command.window.pid
        bundleID = command.window.bundleID
        self.scope = scope
        requested = command.frame
        self.observed = observed ?? command.window.frame
        observedReliably = observed != nil
        self.attempts = attempts
    }

    /// Une réponse partielle peut arriver après la relecture : sa progression vers la cible
    /// conserve le budget. Un geste confirmé libère cette mémoire avant l'arbitrage.
    func continues(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        pid == command.window.pid && bundleID == command.window.bundleID && self.scope == scope
            && (!observedReliably
                || observed.isClose(to: command.window.frame, tolerance: LayoutTolerance.unchangedSinceRefusal)
                || isDelayedPartialResponse(command.window.frame))
    }

    /// Chaque composante doit rester entre la dernière observation et la cible refusée.
    /// Un axe qui s'en éloigne ou dépasse la cible constitue une nouvelle géométrie.
    private func isDelayedPartialResponse(_ current: Rect) -> Bool {
        let tolerance = LayoutTolerance.unchangedSinceRefusal
        let components = [
            (observed.x, requested.x, current.x), (observed.y, requested.y, current.y),
            (observed.width, requested.width, current.width), (observed.height, requested.height, current.height)
        ]
        var progressed = false
        for (before, target, actual) in components {
            guard actual >= min(before, target) - tolerance,
                  actual <= max(before, target) + tolerance else { return false }
            if abs(actual - before) > tolerance { progressed = true }
        }
        return progressed
    }

    func permits(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        !continues(command, scope: scope) || attempts < LayoutTolerance.writeBudgetPerGeneration
    }

    func matches(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        continues(command, scope: scope)
            && requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && observed.isClose(to: command.window.frame, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

/// Échec d'application mémorisé. Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004),
/// sauf s'il s'est répété à l'identique après expiration : il dure alors tant que la fenêtre
/// reste à ce cadre et que la demande ne change pas (SPEC-086).
private struct FailedFrame {
    var requested: Rect
    var observedAtFailure: Rect
    var recordedAt: Date
    var lasting = false

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedAtFailure, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

/// Écriture réussie puis annulée par l'application : la même demande n'est pas répétée tant que
/// la fenêtre reste à son cadre d'avant l'écriture (modes sans arbre, A3).
private struct RevertedAppliedFrame {
    var requested: Rect
    var observedBeforeApply: Rect
    var appliedAt: Date
    /// Retours de l'application à `observedBeforeApply` après cette même écriture.
    var reverts = 0

    /// Annulée deux fois de suite : la demande n'est plus refaite, quel que soit le délai, tant
    /// que la cible et le cadre observé restent les mêmes (SPEC-083).
    var isLasting: Bool { reverts >= 2 }

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedBeforeApply, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

private extension Rect {
    /// Tolérances explicites (SPEC-016 FR-041) : plus de valeur par défaut implicite.
    func isClose(to other: Rect, positionTolerance: Double, sizeTolerance: Double) -> Bool {
        abs(x - other.x) <= positionTolerance
            && abs(y - other.y) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
    }

    func isClose(to other: Rect, tolerance: Double) -> Bool {
        isClose(to: other, positionTolerance: tolerance, sizeTolerance: tolerance)
    }
}

private extension ApplyResult {
    /// Sous-résultat des seuls éléments retenus, compteurs recalculés. O(k).
    static func filtering(_ result: ApplyResult, _ isIncluded: (ApplyResultItem) -> Bool) -> ApplyResult {
        let items = result.items.filter(isIncluded)
        return ApplyResult(
            attempted: items.count,
            applied: items.filter { $0.status == .applied }.count,
            clamped: items.filter { $0.status == .clamped }.count,
            failed: items.filter { $0.status == .failed }.count,
            items: items
        )
    }

    func merged(with other: ApplyResult) -> ApplyResult {
        ApplyResult(
            attempted: attempted + other.attempted,
            applied: applied + other.applied,
            clamped: clamped + other.clamped,
            failed: failed + other.failed,
            items: items + other.items
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

/// Fournisseur qui garde son dernier relevé et peut le rejouer une fois (R11, T210) : la copie de
/// travail d'une passe qui change l'état logique (règle, déplacement adopté, dérive d'écran) se
/// reconstruit sur les fenêtres déjà relevées, sans second relevé AX. Hors rejeu, il délègue.
public final class ReplayableSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    private struct Scan {
        var permissions: PermissionSnapshot?
        var displays: [DisplaySnapshot]?
        var windows: [WindowSnapshot]?
        var existingWindowPIDs: [WindowID: Int32]??
        var focusedWindowID: WindowID??
        var mouseLocation: CGPoint??
    }

    private let base: any SystemSnapshotProviding
    private let lock = NSLock()
    private var last = Scan()
    private var replay = Scan()

    public init(base: any SystemSnapshotProviding) {
        self.base = base
    }

    /// Chaque lecture suivante rend, une fois, sa valeur du dernier relevé. O(1).
    public func replayLastScan() {
        lock.withLock { replay = last }
    }

    public func permissions(prompt: Bool) -> PermissionSnapshot {
        served(\.permissions) ?? recorded(\.permissions, base.permissions(prompt: prompt))
    }

    public func displays() -> [DisplaySnapshot] {
        served(\.displays) ?? recorded(\.displays, base.displays())
    }

    public func windows() -> [WindowSnapshot] {
        served(\.windows) ?? recorded(\.windows, base.windows())
    }

    public func existingWindowPIDs() -> [WindowID: Int32]? {
        served(\.existingWindowPIDs) ?? recorded(\.existingWindowPIDs, base.existingWindowPIDs())
    }

    public func focusedWindowID() -> WindowID? {
        served(\.focusedWindowID) ?? recorded(\.focusedWindowID, base.focusedWindowID())
    }

    public func mouseLocation() -> CGPoint? {
        served(\.mouseLocation) ?? recorded(\.mouseLocation, base.mouseLocation())
    }

    /// Valeur rejouée et consommée, nil hors rejeu.
    private func served<Value>(_ field: WritableKeyPath<Scan, Value?>) -> Value? {
        lock.withLock {
            defer { replay[keyPath: field] = nil }
            return replay[keyPath: field]
        }
    }

    private func recorded<Value>(_ field: WritableKeyPath<Scan, Value?>, _ value: Value) -> Value {
        lock.withLock { last[keyPath: field] = value }
        return value
    }
}
