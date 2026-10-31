import Foundation
import os
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler

public struct DaemonSnapshot: Equatable, Codable, Sendable {
    public var permissions: PermissionSnapshot
    public var displays: [DisplaySnapshot]
    public var windows: [ScopedWindowSnapshot]
    public var state: RoadieState
    public var focusedWindowID: WindowID?
    /// Inventaire CG du même relevé, réutilisé par le rail sans nouvelle énumération.
    public var existingWindowPIDs: [WindowID: Int32]?

    public init(
        permissions: PermissionSnapshot,
        displays: [DisplaySnapshot],
        windows: [ScopedWindowSnapshot],
        state: RoadieState,
        focusedWindowID: WindowID? = nil,
        existingWindowPIDs: [WindowID: Int32]? = nil
    ) {
        self.permissions = permissions
        self.displays = displays
        self.windows = windows
        self.state = state
        self.focusedWindowID = focusedWindowID
        self.existingWindowPIDs = existingWindowPIDs
    }
}

public extension DaemonSnapshot {
    func automationSnapshot(generatedAt: Date = Date(), service: AutomationSnapshotService = AutomationSnapshotService()) -> RoadieStateSnapshot {
        service.snapshot(from: self, generatedAt: generatedAt)
    }
}

public struct ScopedWindowSnapshot: Equatable, Codable, Sendable {
    public var window: WindowSnapshot
    public var scope: StageScope?
    public var pin: PersistentWindowPin?
    public var isNewlyScoped: Bool

    public init(
        window: WindowSnapshot,
        scope: StageScope?,
        pin: PersistentWindowPin? = nil,
        isNewlyScoped: Bool = false
    ) {
        self.window = window
        self.scope = scope
        self.pin = pin
        self.isNewlyScoped = isNewlyScoped
    }

    enum CodingKeys: String, CodingKey {
        case window
        case scope
        case pin
        case isNewlyScoped
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.window = try c.decode(WindowSnapshot.self, forKey: .window)
        self.scope = try c.decodeIfPresent(StageScope.self, forKey: .scope)
        self.pin = try c.decodeIfPresent(PersistentWindowPin.self, forKey: .pin)
        self.isNewlyScoped = try c.decodeIfPresent(Bool.self, forKey: .isNewlyScoped) ?? false
    }
}

public struct SnapshotService: Sendable {
    /// Une application explicite de géométrie ne laisse pas la tolérance anti-jitter
    /// absorber un pas de réglage d'un point. Ce contexte est local à la passe du maintainer.
    var exactLayoutScopes: Set<StageScope> = []
    // AX/macOS peut faire disparaitre des fenetres pendant un plein ecran, un changement
    // de desktop, un redemarrage du daemon ou une reconfiguration display. Une absence
    // courte n'est donc pas une preuve de fermeture : si on prune trop vite, la fenetre
    // revient comme "nouvelle" et peut etre reassignee au mauvais ecran/stage.
    private static let stageMembershipMissingGrace: TimeInterval = 30 * 60

    private let provider: any SystemSnapshotProviding
    private let frameWriter: any WindowFrameWriting
    /// Frames écrites par Roadie (SPEC-017 R9) : la frame acceptée d'une cible évite de la redemander.
    private let frameRegistry: WrittenFrameRegistry
    /// Config figée injectée (tests, commandes) ; nil = config du processus rechargée à chaud.
    private let fixedConfig: RoadieConfig?
    private let configService: ConfigReloadService
    private let railSettings: RailSettings?
    private let railRuntimeStateStore: RailRuntimeStateStore
    private let intentStore: LayoutIntentStore
    private let stageStore: StageStore
    private let events: EventLog
    /// Si `false`, `snapshot()` n'ecrit aucun changement dans `stages.json` / `intent.json`.
    /// Active pour les sous-commandes "lecteurs" (rail, border, focus-mouse, etc.) en mode
    /// SPEC-011 atomique, pour eviter qu'ils ne s'ecrasent mutuellement l'etat canonique
    /// maintenu par `tiler` ou `run`. Les commandes utilisateur explicites (StageCommands,
    /// WindowCommands, etc.) continuent a ecrire via leurs propres transactions
    /// `stageStore.mutate { ... }` (verrou flock POSIX, FR-013).
    private var persistStateChanges: Bool
    private let userInput: UserInputActivity
    /// Vrai pendant Mission Control (SPEC-062) : un relevé y voit des cadres réduits et déplacés.
    private let missionControlActive: @Sendable () -> Bool
    /// Interne (et non privé) : aussi lu par `applyCommandPlacement` (audit TEST-003).
    let clock: @Sendable () -> Date
    /// Mémoire de processus partagée par les services du même fichier d'état.
    private let processState: SnapshotProcessState
    /// Destination des applications d'arbre par commande (T219) ; injectable pour les tests.
    let treeScopeApplications: TreeScopeApplicationCenter

    /// Detecte via la variable d'env `ROADIE_PERSIST_STATE_CHANGES` si le snapshot
    /// doit persister ses mutations dans `stages.json`. SPEC-011 atomique : le
    /// dispatch des sous-commandes lecteur (rail, border, focus-mouse, etc.) set
    /// cette env a "0" pour qu'aucun de ces process n'ecrase l'etat canonique
    /// maintenu par `tiler` (qui lui garde `persistStateChanges=true`).
    public static var defaultPersistStateChanges: Bool {
        persistStateChanges(environmentValue: ProcessInfo.processInfo.environment["ROADIE_PERSIST_STATE_CHANGES"])
    }

    /// Décision pure (testable sans `setenv`) à partir de `ROADIE_PERSIST_STATE_CHANGES`.
    public static func persistStateChanges(environmentValue raw: String?) -> Bool {
        guard let raw else { return true }
        switch raw.lowercased() {
        case "0", "false", "no", "off": return false
        default: return true
        }
    }

    public init(
        provider: any SystemSnapshotProviding = LiveSystemSnapshotProvider(),
        frameWriter: any WindowFrameWriting = AXWindowFrameWriter(),
        config: RoadieConfig? = nil,
        railSettings: RailSettings? = nil,
        railRuntimeStateStore: RailRuntimeStateStore = RailRuntimeStateStore(),
        intentStore: LayoutIntentStore = LayoutIntentStore(),
        stageStore: StageStore = StageStore(),
        events: EventLog = EventLog(),
        persistStateChanges: Bool = Self.defaultPersistStateChanges,
        userInput: UserInputActivity = .shared,
        clock: @escaping @Sendable () -> Date = { Date() },
        frameRegistry: WrittenFrameRegistry = .shared,
        treeScopeApplications: TreeScopeApplicationCenter = .shared,
        configService: ConfigReloadService = .shared,
        missionControlActive: (@Sendable () -> Bool)? = nil
    ) {
        if let missionControlActive { self.missionControlActive = missionControlActive }
        else if TestEnvironment.isRunningTests { self.missionControlActive = { false } }
        else { self.missionControlActive = { MissionControlProbe.isActive() } }
        self.treeScopeApplications = treeScopeApplications
        self.provider = provider
        self.frameWriter = frameWriter
        self.frameRegistry = frameRegistry
        self.fixedConfig = config
        self.configService = configService
        self.railSettings = railSettings
        self.railRuntimeStateStore = railRuntimeStateStore
        self.intentStore = intentStore
        self.stageStore = stageStore
        self.events = events
        self.persistStateChanges = persistStateChanges
        self.userInput = userInput
        self.clock = clock
        self.processState = SnapshotProcessState.forStatePath(stageStore.fileURL.path)
    }

    /// Mission Control ouvert : relevés provisoires, ni enregistrés ni partagés (SPEC-062). O(n).
    public func isMissionControlActive() -> Bool { missionControlActive() }

    /// Config courante : relue à chaud via `ConfigReloadService.shared` (un stat par accès).
    /// Les fonctions qui la lisent plusieurs fois en prennent une copie locale.
    private var config: RoadieConfig {
        fixedConfig ?? configService.currentConfig()
    }

    public var effectiveConfig: RoadieConfig {
        config
    }

    public var effectiveIntentStore: LayoutIntentStore {
        intentStore
    }

    public var effectiveStageStore: StageStore {
        stageStore
    }

    public var effectiveEvents: EventLog {
        events
    }

    /// Présence utilisée par le rail, sans ajouter de fenêtre au relevé de placement.
    public func railWindowIDs(in snapshot: DaemonSnapshot, state: PersistentStageState? = nil) -> Set<WindowID> {
        Self.existingManagedWindowIDs(
            in: state ?? stageStore.state(), windows: snapshot.windows.map(\.window),
            inventory: snapshot.existingWindowPIDs
        )
    }

    /// Une identité persistante vérifiée n'est pas une nouvelle fenêtre à adopter. O(w + m).
    private static func existingManagedWindowIDs(
        in state: PersistentStageState, windows: [WindowSnapshot],
        inventory: [WindowID: Int32]?, excluding: Set<WindowID> = []
    ) -> Set<WindowID> {
        var present = Set(windows.compactMap { $0.isTileCandidate ? $0.id : nil })
        guard let inventory else { return present }
        let observed = Set(windows.map(\.id))
        for scope in state.scopes {
            for stage in scope.stages {
                for member in stage.members where !observed.contains(member.windowID) {
                    guard member.confirmedClosedAt == nil, !excluding.contains(member.windowID),
                          let pid = member.pid, inventory[member.windowID] == pid else { continue }
                    present.insert(member.windowID)
                }
            }
        }
        return present
    }

    /// Les commandes du sélecteur écrivent seulement leur transaction explicite, jamais les observations.
    func withoutObservationPersistence() -> SnapshotService {
        var copy = self
        copy.persistStateChanges = false
        return copy
    }

    /// Snapshot pour les composants lecteurs (bordure, focus-souris, rail) : réutilise le
    /// dernier snapshot publié dans le processus pour ce fichier d'état s'il est encore valide
    /// (150 ms, ou le cycle courant du tiler s'il vient de `producerSnapshot`) et que ni l'état
    /// persisté ni la config n'ont changé ; sinon en produit un (FR-023).
    public func sharedSnapshot(followFocus: Bool = true) -> DaemonSnapshot {
        sharedSnapshotCountingScan(followFocus: followFocus).snapshot
    }

    /// Ancrage au clic sans acquisition ni E/S ; ne vaut pas une observation fraîche. O(1).
    public func cachedGestureSnapshot() -> DaemonSnapshot? {
        processState.latestPublishedSnapshot()
    }

    /// `sharedSnapshot`, avec `scanned` vrai si un relevé complet a été fait (compteur `scans`, A12).
    private func sharedSnapshotCountingScan(followFocus: Bool) -> (snapshot: DaemonSnapshot, scanned: Bool) {
        if let recent = processState.recentSnapshot(
            followFocus: followFocus,
            now: clock(),
            stateStamp: fileModificationStamp(stageStore.fileURL.path),
            config: config
        ) {
            return (recent, false)
        }
        return (snapshot(followFocus: followFocus), true)
    }

    /// Acquisition des lecteurs graphiques : aucune attente AX sur MainActor.
    /// Les commandes gardent sharedSnapshot/snapshot et leur contrat synchrone.
    @MainActor
    func readerSnapshot(followFocus: Bool = true) async -> DaemonSnapshot? {
        func recent() -> DaemonSnapshot? {
            processState.recentSnapshot(followFocus: followFocus, now: clock(),
                                       stateStamp: fileModificationStamp(stageStore.fileURL.path), config: config,
                                       allowQuietReuse: true)
        }
        if let snapshot = recent() { return snapshot }
        let expectedConfig = config
        let stamp = fileModificationStamp(stageStore.fileURL.path)
        let displays = provider.displays() // AppKit reste sur le fil principal.
        let permissions = provider.permissions(prompt: false)
        let acquisition: SnapshotProcessState.ReaderAcquisition
        if let pending = processState.readerAcquisition {
            acquisition = pending
        } else {
            let provider = self.provider
            let clock = self.clock
            acquisition = .init(revision: processState.publicationRevision, observation: processState.observationGeneration,
                                stateStamp: stamp, config: expectedConfig, displays: displays, task: Task.detached(priority: .userInitiated) {
                let windows = provider.windows()
                let inventory = provider.existingWindowPIDs()
                // Sélectionner l'application après le relevé des fenêtres, sur MainActor.
                let readFocus = await provider.focusedWindowReader()
                return SnapshotWindowObservation(windows: windows, inventory: inventory,
                                                 focusedWindowID: readFocus(), completedAt: clock())
            })
            processState.readerAcquisition = acquisition
        }
        let observation = await acquisition.task.value
        if processState.readerAcquisition?.id == acquisition.id { processState.readerAcquisition = nil }
        guard !Task.isCancelled else { return nil }
        // Un autre lecteur ou le producteur peut avoir publié pendant l'attente.
        if let snapshot = recent() { return snapshot }
        guard processState.publicationRevision == acquisition.revision,
              acquisition.config == config, acquisition.stateStamp == fileModificationStamp(stageStore.fileURL.path),
              acquisition.displays == provider.displays(),
              clock().timeIntervalSince(observation.completedAt) < SnapshotProcessState.sharedSnapshotMaxAge
        else { return nil }
        let prepared = PreparedSnapshot(permissions: permissions, displays: displays,
                                       observation: observation, mouseLocation: provider.mouseLocation(),
                                       observationGeneration: acquisition.observation)
        return snapshot(promptForPermissions: false, followFocus: followFocus,
                        sharedMaxAge: SnapshotProcessState.sharedSnapshotMaxAge, producer: false, prepared: prepared)
    }

    private struct PreparedSnapshot {
        let permissions: PermissionSnapshot
        let displays: [DisplaySnapshot]
        let observation: SnapshotWindowObservation
        let mouseLocation: CGPoint?
        /// Génération d'observation au départ de l'acquisition (SPEC-048).
        let observationGeneration: UInt64
    }

    /// Changement observé (événement AX ou NSWorkspace, commande, écrans) : les lecteurs ne
    /// réutilisent plus le relevé publié au-delà de la règle des 150 ms (SPEC-048). O(1).
    public func noteObservationChange() {
        processState.noteObservationChange()
    }

    /// Active la réutilisation silencieuse pour les lecteurs de ce fichier d'état (SPEC-048, ADR 015).
    /// Réservé au processus dont le tiler signale chaque événement : un lecteur sans ordonnanceur
    /// (mode modulaire, `--no-live-events`) garde la règle des 150 ms. `cap` : intervalle du filet.
    public func enableQuietReaderReuse(cap: TimeInterval) {
        processState.enableQuietReuse(cap: cap)
    }

    /// Oublie le snapshot partagé (après une commande qui change fenêtres ou focus).
    public func invalidateSharedSnapshot() {
        processState.invalidatePublished()
    }

    public func snapshot(promptForPermissions: Bool = false, followFocus: Bool = true) -> DaemonSnapshot {
        snapshot(promptForPermissions: promptForPermissions, followFocus: followFocus, sharedMaxAge: SnapshotProcessState.sharedSnapshotMaxAge, producer: false)
    }

    /// Snapshot du tick du tiler, producteur unique du processus quand il tourne (FR-023) : publié
    /// comme source partagée valable tout le cycle (`cycle` + marge, borné à 600 ms). Les lecteurs
    /// du processus le consomment au lieu de rescanner ; ailleurs la règle des 150 ms s'applique.
    public func producerSnapshot(cycle: TimeInterval) -> DaemonSnapshot {
        snapshot(promptForPermissions: false, followFocus: true, sharedMaxAge: SnapshotProcessState.producerMaxAge(cycle: cycle), producer: true)
    }

    /// Destruction confirmée d'une fenêtre (`kAXUIElementDestroyedNotification`, SPEC-017 A9) : sa
    /// feuille est retirée de l'arbre au prochain snapshot écrivain, sans attendre la purge du membre.
    /// Premier cadre connu d'une fenêtre (session 125), pour `roadie window explain`. O(1).
    func initialFrame(of windowID: WindowID) -> Rect? {
        processState.initialFrame(of: windowID)
    }

    /// Décision de tuilage d'une fenêtre relevée, avec sa raison (session 125). O(r).
    func tilingDecision(for window: WindowSnapshot) -> TilingDecision {
        let config = self.config
        return Self.tilingDecision(for: window, config: config, context: TilingPolicyContext(config: config),
                                   initialFrame: processState.initialFrame(of: window.id))
    }

    public func noteWindowDestroyed(_ windowID: WindowID) {
        processState.noteDestroyed(windowID, at: clock())
    }

    /// Un placement explicite confirme une fenêtre vivante. Seul un signal antérieur à la
    /// commande est révoqué ; une fermeture arrivée pendant le relevé reste prioritaire.
    func confirmLiveWindowPlacement(_ windowID: WindowID, in snapshot: DaemonSnapshot, requestedAt: Date) {
        guard snapshot.windows.contains(where: { $0.window.id == windowID && $0.window.isTileCandidate }),
              processState.retractDestruction(windowID, observedBefore: requestedAt)
        else { return }
        invalidateSharedSnapshot()
        events.append(RoadieEvent(type: "window_destruction_retracted", details: [
            "windowID": String(windowID.rawValue), "reason": "explicit_placement",
        ]))
    }

    /// Prochaine relecture courte d'une fermeture que CoreGraphics présente encore.
    func destroyedWindowRetryDeadline(now: Date) -> Date? {
        processState.destroyedWindowRetryDeadline(now: now)
    }

    /// Dernière application d'arbre demandée par une commande pour ce scope (A15). Le maintainer
    /// clôt la rafale ou la garde de transition d'un scope si cette date suit leur ouverture.
    public func treeScopeAppliedAt(_ scope: StageScope) -> Date? {
        processState.treeScopeAppliedAt(scope)
    }

    private func snapshot(promptForPermissions: Bool, followFocus: Bool, sharedMaxAge: TimeInterval, producer: Bool, prepared: PreparedSnapshot? = nil) -> DaemonSnapshot {
        let config = self.config
        let now = clock()
        let observationGeneration = prepared?.observationGeneration ?? processState.observationGeneration
        // Énumération Accessibility HORS verrou (R1) : seule la réconciliation, fonction pure
        // de (état, fenêtres vivantes), tourne sous le verrou de `StageStore.mutate`.
        let permissions = prepared?.permissions ?? provider.permissions(prompt: promptForPermissions)
        let displays = prepared?.displays ?? provider.displays()
        if producer, persistStateChanges, processState.claimLegacyTreeMigration() {
            migrateLegacyTreeModes(displays: displays)
        }
        let rawWindows = prepared?.observation.windows ?? provider.windows()
        // Pre-calcule les structures lourdes (Set subroles, regles triees) une seule fois
        // par snapshot pour eviter O(n_windows) recompactations dans applyTilingPolicy.
        let policyContext = TilingPolicyContext(config: config)
        let initialFrames = processState.initialFrames(rawWindows)
        let windows = processState.stabilizedClassification(rawWindows.map { window in
            (raw: window, classified: Self.applyTilingPolicy(to: window, config: config, context: policyContext,
                                                             initialFrame: initialFrames[window.id]))
        })
        let stageManagedWindowIDs = Set(windows.compactMap { window in
            window.isTileCandidate ? window.id : nil
        })
        let providerFocusedID = prepared.map { $0.observation.focusedWindowID } ?? provider.focusedWindowID()
        let mouseLocation = prepared.map { $0.mouseLocation } ?? provider.mouseLocation()
        let inventory = prepared.map { $0.observation.inventory } ?? provider.existingWindowPIDs()
        let liveDisplayIDs = Set(displays.map(\.id))
        let hiddenWindowIDs = processState.observedHiddenWindowIDs(windows, in: displays, now: now)
        // FR-009 : un changement de stage par le focus exige une saisie utilisateur récente,
        // postérieure à la dernière disparition de fenêtre et hors des 500 ms qui la suivent.
        let observation = processState.recordLiveWindows(stageManagedWindowIDs, now: now)
        let focusChangeAllowed = userInput.allowsFocusChange(now: now, lastDisappearanceAt: observation.lastDisappearanceAt)
        // Le relevé peut recevoir une notification AX après `now`. Capture les identifiants et
        // leur fraîcheur ensemble, avec une heure relue après l'énumération CoreGraphics.
        let destructionSnapshot = processState.destructionSnapshot(now: clock())
        let destroyedWindowIDs = destructionSnapshot.pending
        let recentDestroyedWindowIDs = destructionSnapshot.recent
        let input = ReconciliationInput(
            config: config,
            displays: displays,
            windows: windows,
            hiddenWindowIDs: hiddenWindowIDs,
            lastObservedWindowAt: observation.lastSeenAt,
            stageManagedWindowIDs: stageManagedWindowIDs,
            existingWindowPIDs: inventory,
            liveDisplayIDs: liveDisplayIDs,
            providerFocusedID: providerFocusedID,
            mouseLocation: mouseLocation,
            followFocus: followFocus,
            focusChangeAllowed: focusChangeAllowed,
            destroyedWindowIDs: destroyedWindowIDs,
            recentDestroyedWindowIDs: recentDestroyedWindowIDs,
            now: now
        )

        let result: Reconciliation
        // SPEC-062 : pendant Mission Control, les cadres rapportés sont réduits et déplacés. Le relevé
        // est réconcilié sur une copie : aucune frame transitoire n’entre dans stages.json.
        let transient = missionControlActive()
        if persistStateChanges, !transient {
            intentStore.prune(keepingDisplayIDs: liveDisplayIDs)
            // SPEC-051 B-01 : réconcilier d'abord une copie, sans verrou. Sans changement, aucune
            // transaction exclusive sur stages.json. Sinon, la transaction réutilise ce résultat si le
            // fichier n'a pas bougé entre-temps : la réconciliation (et ses événements) ne tourne qu'une fois.
            let original = stageStore.state()
            var candidate = original
            let precheck = reconcile(&candidate, input: input)
            if candidate == original {
                result = precheck
            } else {
                result = stageStore.mutate { persistedStages in
                    guard persistedStages == original else { return reconcile(&persistedStages, input: input) }
                    persistedStages = candidate
                    return precheck
                }
            }
            // Les events de reconciliation decrivent une mutation de l'etat persiste. En mode
            // lecteur (persistStateChanges=false, SPEC-011 atomique), plusieurs process appellent
            // snapshot() : seul le writer (tiler/run) doit emettre ces events, sinon ils sont
            // dupliques N fois (un par composant) dans events.jsonl.
            appendReconciliationEvents(result)
            // Une destruction est consommée quand la fenêtre a quitté la liste vivante : avant,
            // elle bloque seulement sa réinsertion (liste CoreGraphics en retard sur AX).
            processState.recordDestructionReconciliation(
                observedDestroyedWindowIDs: destroyedWindowIDs,
                liveWindowIDs: stageManagedWindowIDs,
                at: clock(),
                advancesRetry: producer
            )
        } else {
            var persistedStages = stageStore.state()
            result = reconcile(&persistedStages, input: input)
        }

        let snapshot = DaemonSnapshot(
            permissions: permissions,
            displays: displays,
            windows: result.scopedWindows,
            state: result.state,
            focusedWindowID: result.focusedWindowID,
            existingWindowPIDs: inventory
        )
        // Relevé provisoire : rendu à l’appelant, jamais publié comme relevé partagé.
        if transient { return snapshot }
        processState.publish(
            snapshot,
            followFocus: followFocus,
            maxAge: sharedMaxAge,
            // Une lecture AX lente ne doit pas épuiser le cache avant sa publication.
            at: prepared?.observation.completedAt ?? clock(),
            stateStamp: fileModificationStamp(stageStore.fileURL.path),
            config: config,
            observationGeneration: observationGeneration
        )
        return snapshot
    }

    /// Entrées de la réconciliation, lues hors verrou.
    private struct ReconciliationInput {
        let config: RoadieConfig
        let displays: [DisplaySnapshot]
        let windows: [WindowSnapshot]
        let hiddenWindowIDs: Set<WindowID>
        let lastObservedWindowAt: [WindowID: Date]
        let stageManagedWindowIDs: Set<WindowID>
        let existingWindowPIDs: [WindowID: Int32]?
        let liveDisplayIDs: Set<DisplayID>
        let providerFocusedID: WindowID?
        let mouseLocation: CGPoint?
        let followFocus: Bool
        let focusChangeAllowed: Bool
        let destroyedWindowIDs: Set<WindowID>
        let recentDestroyedWindowIDs: Set<WindowID>
        let now: Date
    }

    private struct Reconciliation {
        var state: RoadieState
        var scopedWindows: [ScopedWindowSnapshot]
        var focusedWindowID: WindowID?
        var missingWindows: MissingWindowReconciliationReport
        var prunedPins: [PersistentWindowPin]
        var prunedBookmarks: [PersistentWindowBookmark]
    }

    private func appendReconciliationEvents(_ result: Reconciliation) {
        appendMissingWindowReconciliationEvent(result.missingWindows)
        for pin in result.prunedPins {
            events.append(RoadieEvent(
                type: "window.pin_pruned",
                scope: pin.homeScope,
                details: pinEventDetails(pin)
            ))
        }
        for bookmark in result.prunedBookmarks {
            events.append(RoadieEvent(
                type: "window.bookmark_pruned",
                scope: bookmark.scope,
                details: bookmarkEventDetails(bookmark)
            ))
        }
    }

    /// Réconcilie l'état persisté avec les fenêtres vivantes et construit l'état runtime.
    /// Fonction de (état, entrées) : appelée sous le verrou de `StageStore.mutate` en mode writer.
    // Observations connues : O(w·d + m + p + b), d écrans, m membres, p pins, b signets.
    // Adoption et remappage d'identités : coûts documentés dans PersistentStageState.
    private func reconcile(_ persistedStages: inout PersistentStageState, input: ReconciliationInput) -> Reconciliation {
        let config = input.config
        let displays = input.displays
        let windows = input.windows
        let stageManagedWindowIDs = input.stageManagedWindowIDs
        let liveDisplayIDs = input.liveDisplayIDs
        let providerFocusedID = input.providerFocusedID
        let now = input.now
        persistedStages.pruneExpiredCommandFocusProtection(now: now)
        if let activeDisplayID = persistedStages.activeDisplayID,
           !liveDisplayIDs.contains(activeDisplayID) {
            persistedStages.activeDisplayID = fallbackDisplayID(
                in: displays,
                persistedStages: persistedStages,
                focusedWindowID: providerFocusedID,
                windows: windows
            )
        }
        let activeDisplayIDBeforeMissingReconciliation = persistedStages.activeDisplayID
        let liveWindowIDs = Self.existingManagedWindowIDs(
            in: persistedStages, windows: windows, inventory: input.existingWindowPIDs,
            excluding: input.recentDestroyedWindowIDs
        )
        let mouseLocation = input.mouseLocation
        persistedStages.reconcileWindowIDs(with: windows.filter { stageManagedWindowIDs.contains($0.id) })
        let missingWindows = persistedStages.pruneMissingWindows(
            keeping: liveWindowIDs,
            liveDisplayIDs: liveDisplayIDs,
            missingGrace: Self.stageMembershipMissingGrace,
            lastObservedAt: input.lastObservedWindowAt,
            now: now
        )
        persistedStages.markConfirmedClosed(
            windowIDs: input.recentDestroyedWindowIDs.subtracting(stageManagedWindowIDs),
            at: now
        )
        let prunedPins = persistedStages.pruneMissingPins(keeping: liveWindowIDs, now: now)
        let prunedBookmarks = persistedStages.pruneMissingBookmarks(keeping: liveWindowIDs, now: now)
        var state = RoadieState()
        var scopedWindows: [ScopedWindowSnapshot] = []
        for display in displays {
            state.ensureDisplay(display.id)
            let currentDesktopID = persistedStages.currentDesktopID(for: display.id)
            var persistentScope = persistedStages.scope(
                displayID: display.id,
                desktopID: currentDesktopID,
                defaultMode: config.tiling.defaultStrategy
            )
            persistentScope.applyConfiguredStages(config.stageManager, defaultMode: config.tiling.defaultStrategy,
                takenNames: config.stageManager.workspaces.isEmpty ? [] : persistedStages.namedStageKeys(excludingDisplay: display.id, desktop: currentDesktopID))
            persistentScope.adoptDefaultModeForEmptyDefaultStages(config.tiling.defaultStrategy)
            persistedStages.update(persistentScope)
            let activePersistentStage = persistentScope.stages.first { $0.id == persistentScope.activeStageID }
            let activeMode = activePersistentStage?.mode ?? config.tiling.defaultStrategy
            try? state.createStage(
                id: persistentScope.activeStageID,
                name: "Stage \(persistentScope.activeStageID.rawValue)",
                mode: activeMode,
                in: display.id,
                desktopID: currentDesktopID
            )
            // ensureDisplay crée déjà le stage 1 : createStage seul ne restaure pas son mode.
            // Le mode doit aussi être correct quand aucune fenêtre vivante ne passe dans la boucle.
            try? state.setMode(activeMode, for: StageScope(
                displayID: display.id, desktopID: currentDesktopID, stageID: persistentScope.activeStageID
            ))
            try? state.switchDesktop(currentDesktopID, on: display.id)
            try? state.switchStage(persistentScope.activeStageID, in: display.id, desktopID: currentDesktopID)
        }

        let fallbackDisplayID = displays.first?.id
        // Pre-compute inverse index O(total_members) pour eviter O(w * scopes * stages * members) sur le hot path.
        var stageIndex = persistedStages.stageScopeIndex()
        let pinsByWindow = Dictionary(persistedStages.windowPins.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var metadata: [StageScope: (mode: WindowManagementMode, groups: [WindowGroup])] = [:]
        for persisted in persistedStages.scopes {
            for stage in persisted.stages {
                metadata[StageScope(displayID: persisted.displayID, desktopID: persisted.desktopID, stageID: stage.id)] = (stage.mode, stage.groups)
            }
        }
        var initializedScopes: Set<StageScope> = []
        var observedWindows: [WindowID: WindowSnapshot] = [:]
        var observedScopes: [WindowID: StageScope] = [:]
        var observedPresentations: [WindowID: WindowPresentationState] = [:]
        var initialMemberships: [(WindowID, StageScope)] = []
        for window in windows {
            guard stageManagedWindowIDs.contains(window.id) else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            let pin = pinsByWindow[window.id]
            let indexedScope = stageIndex[window.id]
            let liveIndexedScope = indexedScope.flatMap { liveDisplayIDs.contains($0.displayID) ? $0 : nil }
            let livePinnedScope = (pin?.homeScope).flatMap { liveDisplayIDs.contains($0.displayID) ? $0 : nil }
            // Fenetre indexee sur un display deconnecte : on PRESERVE le membership (scope nil
            // transitoire) jusqu'au "parking heal" (DaemonHealthService.heal) declenche par le
            // changement de parametres d'ecran. Migrer ici casserait le retour propre du display.
            if indexedScope != nil, liveIndexedScope == nil {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil, pin: pin))
                continue
            }
            let knownScope = liveIndexedScope ?? livePinnedScope
            guard let displayID = knownScope?.displayID ?? newWindowDisplayID(
                for: window,
                displays: displays,
                persistedStages: persistedStages,
                mouseLocation: mouseLocation,
                fallbackDisplayID: fallbackDisplayID,
                newAppsTarget: config.windowPlacement.newAppsTarget
            ) else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            if knownScope == nil {
                if indexedScope != nil {
                    persistedStages.remove(windowID: window.id)
                    stageIndex.removeValue(forKey: window.id)
                }
                var persistentScope = persistedStages.scope(
                    displayID: displayID,
                    desktopID: persistedStages.currentDesktopID(for: displayID),
                    defaultMode: config.tiling.defaultStrategy
                )
                let presentationState = presentationState(for: window, displayID: displayID, displays: displays)
                // `focusWindow: false` : une fenêtre adoptée ne devient le focus de la stage que si
                // elle a réellement le focus (suivi plus bas, via `setFocusedWindow`, qui garde le
                // focus précédent). Sinon l'historique servant d'ancrage BSP serait perdu (FR-005).
                persistentScope.assign(
                    window: window,
                    to: persistentScope.activeStageID,
                    focusWindow: false,
                    defaultMode: config.tiling.defaultStrategy,
                    presentationState: presentationState
                )
                persistedStages.update(persistentScope)
                stageIndex[window.id] = StageScope(
                    displayID: persistentScope.displayID,
                    desktopID: persistentScope.desktopID,
                    stageID: persistentScope.activeStageID
                )
            }
            let desktopID = knownScope?.desktopID ?? persistedStages.currentDesktopID(for: displayID)
            let stageID = knownScope?.stageID
                ?? persistedStages.scope(
                    displayID: displayID,
                    desktopID: desktopID,
                    defaultMode: config.tiling.defaultStrategy
                ).activeStageID
            let scope = StageScope(
                displayID: displayID,
                desktopID: desktopID,
                stageID: stageID
            )
            if !input.hiddenWindowIDs.contains(window.id),
               displays.contains(where: { $0.frame.cgRect.intersects(window.frame.cgRect) }) {
                // FR-037 : garder la dernière position visible quand l'écran a disparu.
                observedWindows[window.id] = window
                observedScopes[window.id] = scope
                observedPresentations[window.id] = presentationState(for: window, displayID: displayID, displays: displays)
            }
            let isNewlyScoped = knownScope == nil
            if initializedScopes.insert(scope).inserted {
                let stage = metadata[scope]
                try? state.createStage(
                    id: scope.stageID, name: "Stage \(scope.stageID.rawValue)",
                    mode: stage?.mode ?? config.tiling.defaultStrategy,
                    in: scope.displayID, desktopID: scope.desktopID
                )
                try? state.setMode(stage?.mode ?? config.tiling.defaultStrategy, for: scope)
                try? state.setGroups(stage?.groups ?? [], for: scope)
            }
            if window.isTileCandidate, pin == nil {
                initialMemberships.append((window.id, scope))
            }
            scopedWindows.append(ScopedWindowSnapshot(
                window: window,
                scope: scope,
                pin: pin,
                isNewlyScoped: isNewlyScoped
            ))
        }
        // PERF-010 : l'état est neuf ; éviter removeWindow/insert pour chaque fenêtre.
        try? state.initializeWindowMemberships(initialMemberships)
        correctSoloMaximizedStates(
            in: &observedPresentations, scopedWindows: scopedWindows, hiddenWindowIDs: input.hiddenWindowIDs,
            displays: displays
        )
        persistedStages.updateWindowObservations(observedWindows, scopes: observedScopes,
            presentationStates: observedPresentations, now: now)
        var focusedID: WindowID?
        if input.followFocus,
           let providerFocusedID,
           let focusedEntry = scopedWindows.first(where: { $0.window.id == providerFocusedID }),
           let focusedScope = focusedEntry.scope,
           !shouldSuppressHiddenCrossDisplayFocusAfterMissing(
                entry: focusedEntry,
                scope: focusedScope,
                previousActiveDisplayID: activeDisplayIDBeforeMissingReconciliation,
                missingWindows: missingWindows,
                displays: displays
           ),
           shouldFollowFocus(entry: focusedEntry, scope: focusedScope, persistedStages: persistedStages, displays: displays),
           !persistedStages.commandFocusProtectionBlocks(focusedScope: focusedScope, focusedWindowID: providerFocusedID, now: now),
           input.focusChangeAllowed || !focusChangesActiveScope(focusedScope, state: state, persistedStages: persistedStages),
           config.focus.stageFollowsFocus || state.activeScope(on: focusedScope.displayID) == focusedScope {
            var persistentScope = persistedStages.scope(
                displayID: focusedScope.displayID,
                desktopID: focusedScope.desktopID,
                defaultMode: config.tiling.defaultStrategy
            )
            persistentScope.activeStageID = focusedScope.stageID
            persistentScope.setFocusedWindow(providerFocusedID, in: focusedScope.stageID)
            persistedStages.update(persistentScope)
            persistedStages.switchDesktop(displayID: focusedScope.displayID, to: focusedScope.desktopID)
            persistedStages.focusDisplay(focusedScope.displayID)
            try? state.switchDesktop(focusedScope.desktopID, on: focusedScope.displayID)
            try? state.switchStage(focusedScope.stageID, in: focusedScope.displayID, desktopID: focusedScope.desktopID)
            try? state.setFocusedWindow(providerFocusedID, for: focusedScope)
            focusedID = providerFocusedID
        } else {
            focusedID = activeFocusedWindowID(in: state, scopedWindows: scopedWindows, displays: displays)
        }
        reconcileTrees(in: &persistedStages, input: input)
        applyPersistedMetadata(to: &state, from: persistedStages)
        return Reconciliation(
            state: state,
            scopedWindows: scopedWindows,
            focusedWindowID: focusedID,
            missingWindows: missingWindows,
            prunedPins: prunedPins,
            prunedBookmarks: prunedBookmarks
        )
    }

    /// REL-005 : l'état runtime reprend, pour chaque écran présent, les desktops, labels et stages
    /// persistés (nom et mode), stages vides comprises. Sans cela, il ne contient que la stage
    /// active et celles des fenêtres vivantes, sous un nom générique. Une stage déjà créée (stage 1
    /// par défaut d'un desktop, stage d'une fenêtre vivante) reçoit aussi le nom et le mode
    /// persistés ; ses fenêtres et son focus ne changent pas. Un desktop non courant reprend sa
    /// stage active persistée ; celle du desktop courant reste celle décidée plus haut (focus suivi).
    // O(s + d·l) - s stages persistées, d desktops runtime, l labels persistés (bornés).
    private func applyPersistedMetadata(to state: inout RoadieState, from persistedStages: PersistentStageState) {
        var displays = state.displays
        for scope in persistedStages.scopes {
            guard let display = displays[scope.displayID] else { continue }
            var desktop = display.desktops[scope.desktopID]
                ?? DesktopState(id: scope.desktopID, activeStageID: scope.activeStageID)
            for persisted in scope.stages {
                if desktop.stages[persisted.id] == nil {
                    desktop.stages[persisted.id] = StageState(id: persisted.id, name: persisted.name, mode: persisted.mode)
                } else {
                    desktop.stages[persisted.id]?.name = persisted.name
                    desktop.stages[persisted.id]?.mode = persisted.mode
                }
            }
            if scope.desktopID != display.currentDesktopID, desktop.stages[scope.activeStageID] != nil {
                desktop.activeStageID = scope.activeStageID
            }
            displays[scope.displayID]?.desktops[scope.desktopID] = desktop
        }
        for (displayID, display) in displays {
            for desktopID in display.desktops.keys {
                displays[displayID]?.desktops[desktopID]?.label = persistedStages.label(displayID: displayID, desktopID: desktopID)
            }
        }
        state = RoadieState(displays: displays)
    }

    /// Réconciliation unique des arbres des stages à arbre, sous le verrou du snapshot (SPEC-017
    /// T081, A9). La feuille d'un membre absent (plein écran natif, autre bureau) est gardée tant que
    /// le membre existe, donc pendant sa grâce réelle de 30 min : la fenêtre reprend sa place à son
    /// retour (FR-007). Elle est retirée à la purge du membre, à son départ de la stage, à son
    /// épinglage ou sur destruction confirmée. Une fenêtre vivante sans feuille coupe la feuille
    /// active selon la forme de cette feuille (R3). Ne lit aucune géométrie de fenêtre (FR-003).
    // O(Σ (f + m)) par stage à arbre sans insertion, voir `reconciledTree`.
    private func reconcileTrees(in persistedStages: inout PersistentStageState, input: ReconciliationInput) {
        let side: BSPInsertionSide = input.config.windowPlacement.newWindowSide == "left" ? .left : .right
        let innerGap = CGFloat(input.config.tiling.gapsInner)
        let containers = Dictionary(input.displays.map { ($0.id, $0.visibleFrame.cgRect) }, uniquingKeysWith: { first, _ in first })
        let pinned = Set(persistedStages.windowPins.map(\.windowID))
        for scopeIndex in persistedStages.scopes.indices {
            let persistentScope = persistedStages.scopes[scopeIndex]
            guard let container = containers[persistentScope.displayID] else { continue }
            for stageIndex in persistentScope.stages.indices where persistentScope.stages[stageIndex].mode.usesTreeEngine {
                let stage = persistentScope.stages[stageIndex]
                let kept = Set(stage.members.map(\.windowID)).subtracting(input.destroyedWindowIDs).subtracting(pinned)
                let tree = Self.reconciledTree(
                    stage.bspTree ?? .empty,
                    stage: stage,
                    kept: kept,
                    live: input.stageManagedWindowIDs,
                    globalFocus: input.providerFocusedID,
                    side: side,
                    container: container,
                    innerGap: innerGap
                )
                let next: BSPTree? = tree.isEmpty && stage.bspTree == nil ? nil : tree
                guard next != stage.bspTree else { continue }
                persistedStages.scopes[scopeIndex].stages[stageIndex].bspTree = next
            }
        }
    }

    /// Arbre d'une stage après réconciliation : feuilles hors de `kept` retirées, puis membres
    /// vivants sans feuille insérés dans l'ordre des membres. Les feuilles sont collectées une
    /// seule fois ; l'ensemble `leaves` sert à l'appartenance et suit les insertions (PERF-002).
    /// La projection retire toutes les feuilles d'un coup, avec le même arbre que des retraits
    /// successifs : chaque retrait remplace un split par son côté restant.
    // Avant : O(f² + k·f + m·f) sur un arbre en chaîne (deux lectures de `windowIDs`, un `removing`
    // par feuille retirée, un `contains` par membre). Après : O(f + m) sans insertion, plus
    // O(f²) par insertion réelle (`inserting`, voir BSPTree) - f feuilles, k retirées, m membres.
    static func reconciledTree(
        _ initial: BSPTree,
        stage: PersistentStage,
        kept: Set<WindowID>,
        live: Set<WindowID>,
        globalFocus: WindowID?,
        side: BSPInsertionSide,
        container: CGRect,
        innerGap: CGFloat
    ) -> BSPTree {
        var leaves = Set(initial.windowIDs)
        let removed = leaves.subtracting(kept)
        var tree = initial.projected(excluding: removed)
        leaves.subtract(removed)
        let absent = leaves.subtracting(live)
        var anchor = bspInsertionAnchor(leaves: leaves, live: live, globalFocus: globalFocus, stage: stage)
        for member in stage.members where kept.contains(member.windowID) && live.contains(member.windowID) {
            guard leaves.insert(member.windowID).inserted else { continue }
            tree = tree.inserting(member.windowID, at: anchor, side: side, in: container, innerGap: innerGap, excluding: absent)
            anchor = member.windowID // une rafale se greffe à côté de la dernière insérée
        }
        return tree
    }

    /// Migration SPEC-017 (T082, A8) des stages `mutableBsp`, une fois par processus producteur :
    /// arbre déduit de la géométrie connue des membres, dans le cadre visible de leur écran.
    private func migrateLegacyTreeModes(displays: [DisplaySnapshot]) {
        let containers = Dictionary(displays.map { ($0.id, $0.visibleFrame.cgRect) }, uniquingKeysWith: { first, _ in first })
        // Échec de lecture ou d'écriture : les stages restent `mutableBsp`, servies par le même
        // moteur à arbre (`usesTreeEngine`) ; la migration est retentée au prochain démarrage.
        guard let migrated = try? stageStore.migrateLegacyTreeModes(
            infer: { BSPTree.inferred(from: $0, in: $1) },
            container: { containers[$0.displayID] }
        ), migrated > 0 else { return }
        events.append(RoadieEvent(type: "state_migrated", details: [
            "stages": String(migrated),
            "backup": stageStore.fileURL.path + ".pre-017"
        ]))
    }

    /// FR-027 : une fenêtre tilée seule dans son scope remplit l'écran par construction et n'est
    /// pas « agrandie ». Le nombre de fenêtres par scope n'est connu qu'après la boucle d'affectation,
    /// d'où cette correction a posteriori des états persistés. O(w).
    private func correctSoloMaximizedStates(
        in presentations: inout [WindowID: WindowPresentationState],
        scopedWindows: [ScopedWindowSnapshot],
        hiddenWindowIDs: Set<WindowID>,
        displays: [DisplaySnapshot]
    ) {
        let tiledCounts = WindowPresentationStateResolver.tiledWindowCounts(in: scopedWindows)
        for entry in scopedWindows where entry.window.isTileCandidate {
            guard let scope = entry.scope,
                  tiledCounts[scope] == 1,
                  !hiddenWindowIDs.contains(entry.window.id),
                  presentationState(for: entry.window, displayID: scope.displayID, displays: displays) == .maximized,
                  let display = displays.first(where: { $0.id == scope.displayID })
            else { continue }
            presentations[entry.window.id] = WindowPresentationStateResolver.state(
                    for: entry.window,
                    on: display,
                    isOnlyTiledWindowInScope: true
            )
        }
    }

    /// `true` si suivre ce focus changerait la stage, le desktop ou le display actif.
    /// Mettre à jour le membre focalisé de la stage déjà active n'est pas un changement.
    private func focusChangesActiveScope(
        _ scope: StageScope,
        state: RoadieState,
        persistedStages: PersistentStageState
    ) -> Bool {
        if state.activeScope(on: scope.displayID) != scope { return true }
        guard let activeDisplayID = persistedStages.activeDisplayID else { return false }
        return activeDisplayID != scope.displayID
    }

    private func shouldSuppressHiddenCrossDisplayFocusAfterMissing(
        entry: ScopedWindowSnapshot,
        scope: StageScope,
        previousActiveDisplayID: DisplayID?,
        missingWindows: MissingWindowReconciliationReport,
        displays: [DisplaySnapshot]
    ) -> Bool {
        guard !missingWindows.markedMissingWindowIDs.isEmpty,
              let previousActiveDisplayID,
              previousActiveDisplayID != scope.displayID,
              HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: displays)
        else { return false }

        events.append(RoadieEvent(type: "focus.hidden_cross_display_after_missing_suppressed", scope: scope, details: [
            "windowID": String(entry.window.id.rawValue),
            "previousActiveDisplayID": previousActiveDisplayID.rawValue,
            "focusedDisplayID": scope.displayID.rawValue,
            "markedMissingIDs": formattedWindowIDs(missingWindows.markedMissingWindowIDs)
        ]))
        return true
    }

    private func appendMissingWindowReconciliationEvent(_ report: MissingWindowReconciliationReport) {
        guard !report.isEmpty else { return }
        events.append(RoadieEvent(type: "windows.missing_reconciled", details: [
            "markedMissing": String(report.markedMissingWindowIDs.count),
            "restored": String(report.restoredWindowIDs.count),
            "pruned": String(report.prunedWindowIDs.count),
            "markedMissingIDs": formattedWindowIDs(report.markedMissingWindowIDs),
            "restoredIDs": formattedWindowIDs(report.restoredWindowIDs),
            "prunedIDs": formattedWindowIDs(report.prunedWindowIDs)
        ]))
    }

    private func formattedWindowIDs(_ ids: Set<WindowID>, limit: Int = 12) -> String {
        let ordered = ids.map(\.rawValue).sorted()
        let prefix = ordered.prefix(limit).map(String.init).joined(separator: ",")
        guard ordered.count > limit else { return prefix }
        return "\(prefix),+\(ordered.count - limit)"
    }

    /// Contexte pre-calcule pour `applyTilingPolicy`. Construit une seule fois par snapshot
    /// pour eviter le cout O(n_windows) de Set(allowedSubroles) et du tri des regles a chaque
    /// appel. Sans ce contexte, applyTilingPolicy etait O(n_windows * (n_subroles + n_rules log n_rules)).
    /// Avec, c'est O(n_windows * n_rules) (matching lineaire dans les regles deja triees).
    struct TilingPolicyContext {
        let allowedSubroles: Set<String>
        let floatingBundles: Set<String>
        let sortedRules: [WindowRule]

        init(config: RoadieConfig) {
            self.allowedSubroles = Set(config.tiling.allowedSubroles)
            self.floatingBundles = Set(config.exclusions.floatingBundles)
            self.sortedRules = config.rules
                .filter(\.enabled)
                .sorted { lhs, rhs in
                    if lhs.priority == rhs.priority {
                        return lhs.id < rhs.id
                    }
                    return lhs.priority > rhs.priority
                }
        }
    }

    /// Applique la policy de tiling sur une fenetre brute ; la premiere regle matchant peut
    /// overrider : manage force le tuilage, exclude et floating le retirent.
    public static func applyTilingPolicy(to window: WindowSnapshot, config: RoadieConfig) -> WindowSnapshot {
        applyTilingPolicy(to: window, config: config, context: TilingPolicyContext(config: config))
    }

    static func applyTilingPolicy(
        to window: WindowSnapshot,
        config: RoadieConfig,
        context: TilingPolicyContext,
        initialFrame: Rect? = nil
    ) -> WindowSnapshot {
        var result = window
        result.isTileCandidate = tilingDecision(for: window, config: config, context: context, initialFrame: initialFrame).tile
        return result
    }

    /// Décision de tuilage et sa raison, lue par `roadie window explain` (session 125).
    struct TilingDecision: Equatable, Sendable {
        let tile: Bool
        let reason: String
    }

    /// Les critères de taille jugent la fenêtre à sa naissance (`initialFrame`, session 125) : une
    /// fois tuilée, une petite fenêtre d'appoint a la taille de sa place et ne paraît plus petite.
    /// O(r), r règles.
    static func tilingDecision(
        for window: WindowSnapshot,
        config: RoadieConfig,
        context: TilingPolicyContext,
        initialFrame: Rect? = nil
    ) -> TilingDecision {
        var born = window
        if let initialFrame { born.frame = initialFrame }
        var decision = baseTilingDecision(for: born, config: config, context: context)
        // Override par les regles user. Premiere regle matchant gagne (regles deja triees).
        let matchContext = WindowRuleMatchContext(role: window.role, subrole: window.subrole)
        if let rule = WindowRuleMatcher.firstMatch(sortedRules: context.sortedRules, window: window, context: matchContext) {
            if rule.action.manage == true {
                // Force le tuilage mais respecte les criteres CG (taille mini, layer).
                decision = TilingDecision(tile: window.isTileCandidate, reason: tr("règle \(rule.id) : manage", "rule \(rule.id): manage"))
            }
            if rule.action.exclude == true || rule.action.floating == true {
                let kind = rule.action.exclude == true ? "exclude" : "floating"
                decision = TilingDecision(tile: false, reason: tr("règle \(rule.id) : \(kind)", "rule \(rule.id): \(kind)"))
            }
        }
        return decision
    }

    /// Ordre de decision :
    ///   1. baseCandidate (criteres CG bruts) doit etre vrai sinon -> non tile-able
    ///   2. floating_bundles -> non tile-able
    ///   3. popup gate (heuristique aerospace) : si AX present et aucun bouton/flag d'etat,
    ///      c'est un popup/menu/tooltip -> non tile-able
    ///   4. AX subrole doit etre dans config.tiling.allowed_subroles (defaut ["AXStandardWindow"])
    ///      Si subrole inconnu (AX absent) -> on laisse passer (non-regression)
    /// Les regles user (etape 5) sont appliquees par `tilingDecision`.
    private static func baseTilingDecision(
        for window: WindowSnapshot,
        config: RoadieConfig,
        context: TilingPolicyContext
    ) -> TilingDecision {
        func float(_ reason: String) -> TilingDecision { TilingDecision(tile: false, reason: reason) }
        guard window.isTileCandidate else { return float(tr("CoreGraphics : calque, opacité ou taille sous 80 × 60", "CoreGraphics: layer, opacity or size under 80 × 60")) }
        let popups = config.tiling.popupFilter
        if popups, window.role == "AXSheet" { return float(tr("feuille (AXSheet)", "sheet (AXSheet)")) }
        if context.floatingBundles.contains(window.bundleID) { return float(tr("application dans floating_bundles", "app in floating_bundles")) }
        // Popup gate (aerospace-like) : une fenetre modale bloque son app, hors tuilage.
        if popups, let furniture = window.furniture, furniture.isModal { return float(tr("fenêtre modale", "modal window")) }
        if popups, isLikelyTransientSettingsWindow(window) { return float(tr("petite fenêtre de réglages sans plein écran", "small settings window without full screen")) }
        if popups, isShortNonFullscreenUtilityWindow(window) { return float(tr("panneau de 180 points de haut au plus, sans plein écran", "panel at most 180 points high, without full screen")) }
        if popups, isNonResizableStandardWindow(window) { return float(tr("taille non modifiable", "size cannot change")) }
        if popups, isUnidentifiedTransientWindow(window) { return float(tr("fenêtre sans accessibilité ni titre utile", "window without accessibility or useful title")) }
        if popups, let furniture = window.furniture, !furniture.isLikelyRealWindow, window.subrole != "AXStandardWindow" {
            return float(tr("aucun bouton ni focus : popup", "no buttons or focus: popup"))
        }
        // Heuristique aerospace fine : fullscreenButton present mais desactive ->
        // probablement un dialog (Settings, About, IntelliJ Rebase, Calculator...).
        // Ne s'applique pas aux apps qui cachent legitimement le bouton fullscreen
        // (terminals, IDEs) : pour celles-la, l'utilisateur peut whitelister leur subrole
        // ou ajouter une regle action.manage.
        if popups, let furniture = window.furniture, furniture.fullscreenButtonDisabled, window.subrole != "AXStandardWindow" {
            return float(tr("bouton plein écran désactivé", "full-screen button disabled"))
        }
        if let subrole = window.subrole, !context.allowedSubroles.contains(subrole) {
            return float(tr("sous-rôle \(subrole) hors allowed_subroles", "subrole \(subrole) not in allowed_subroles"))
        }
        // AX absent -> on laisse passer (non-regression apps non-AX)
        return TilingDecision(tile: true, reason: window.subrole == nil ? tr("accessibilité illisible : tuilée par défaut", "accessibility unreadable: tiled by default") : tr("fenêtre standard", "standard window"))
    }

    private static func isLikelyTransientSettingsWindow(_ window: WindowSnapshot) -> Bool {
        let frame = window.frame.cgRect
        let isSmall = frame.width <= 760 && frame.height <= 760
        let title = window.title.lowercased()
        let titleLooksLikeSettings = [
            "settings",
            "preferences",
            "préférences",
            "reglages",
            "réglages"
        ].contains { title.contains($0) }
        let isNonResizable = window.furniture.map { !$0.hasFullscreenButton } ?? false
        return isSmall && isNonResizable && titleLooksLikeSettings
    }

    private static func isShortNonFullscreenUtilityWindow(_ window: WindowSnapshot) -> Bool {
        guard window.subrole == "AXStandardWindow",
              let furniture = window.furniture
        else { return false }

        let frame = window.frame.cgRect
        let isShortPanel = frame.height <= 180
        let cannotBecomeDocumentWindow = !furniture.hasFullscreenButton || furniture.fullscreenButtonDisabled
        let hasWindowChrome = furniture.hasCloseButton || furniture.hasMinimizeButton || furniture.hasZoomButton

        return isShortPanel && cannotBecomeDocumentWindow && hasWindowChrome
    }

    private static func isNonResizableStandardWindow(_ window: WindowSnapshot) -> Bool {
        guard window.subrole == "AXStandardWindow",
              let furniture = window.furniture
        else { return false }

        return !furniture.isResizable
    }

    private static func isUnidentifiedTransientWindow(_ window: WindowSnapshot) -> Bool {
        let frame = window.frame.cgRect
        guard window.subrole == nil,
              window.role == nil,
              window.furniture == nil
        else { return false }

        let normalizedTitle = window.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isSmall = frame.width <= 760 && frame.height <= 760
        let genericTitle = normalizedTitle.isEmpty
            || normalizedTitle == "untitled"
            || normalizedTitle == "sans titre"
        let systemPanelTitle = [
            "save",
            "open",
            "print",
            "export",
            "enregistrer",
            "ouvrir",
            "imprimer",
            "exporter"
        ].contains(normalizedTitle)

        // Sans titre ni AX, quelle que soit la taille : ces fenetres sont des surcouches
        // (liserés JankyBorders, Dock, HUD) que Roadie ne peut de toute facon pas deplacer.
        // Les ranger fait sauter le layout a chaque apparition ou disparition.
        return normalizedTitle.isEmpty || (isSmall && genericTitle) || systemPanelTitle
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
    }

    /// Appelée sous le verrou des stages : la cible vient de la config de l'entrée, jamais de
    /// `self.config` qui relirait le fichier de config (T213).
    private func newWindowDisplayID(
        for window: WindowSnapshot,
        displays: [DisplaySnapshot],
        persistedStages: PersistentStageState,
        mouseLocation: CGPoint?,
        fallbackDisplayID: DisplayID?,
        newAppsTarget: String
    ) -> DisplayID? {
        switch newAppsTarget {
        case "mouse":
            if let mouseLocation,
               let displayID = displayID(containing: mouseLocation, in: displays) {
                return displayID
            }
            return displayID(containing: window.frame.center, in: displays) ?? fallbackDisplayID
        case "focused_display":
            let liveDisplayIDs = Set(displays.map(\.id))
            if let activeDisplayID = persistedStages.activeDisplayID,
               liveDisplayIDs.contains(activeDisplayID) {
                return activeDisplayID
            }
            return displayID(containing: window.frame.center, in: displays) ?? fallbackDisplayID
        case "macos":
            fallthrough
        default:
            return displayID(containing: window.frame.center, in: displays) ?? fallbackDisplayID
        }
    }

    private func fallbackDisplayID(
        in displays: [DisplaySnapshot],
        persistedStages: PersistentStageState,
        focusedWindowID: WindowID?,
        windows: [WindowSnapshot]
    ) -> DisplayID? {
        let liveDisplayIDs = Set(displays.map(\.id))
        if let activeDisplayID = persistedStages.activeDisplayID,
           liveDisplayIDs.contains(activeDisplayID) {
            return activeDisplayID
        }
        if let focusedWindowID,
           let focusedWindow = windows.first(where: { $0.id == focusedWindowID }),
           let displayID = displayID(containing: focusedWindow.frame.center, in: displays) {
            return displayID
        }
        return displays.first(where: \.isMain)?.id ?? displays.first?.id
    }

    private func presentationState(
        for window: WindowSnapshot,
        displayID: DisplayID,
        displays: [DisplaySnapshot]
    ) -> WindowPresentationState {
        guard let display = displays.first(where: { $0.id == displayID }) else {
            return .normal
        }
        return WindowPresentationStateResolver.state(for: window, on: display)
    }

    private func shouldFollowFocus(
        entry: ScopedWindowSnapshot,
        scope: StageScope,
        persistedStages: PersistentStageState,
        displays: [DisplaySnapshot]
    ) -> Bool {
        if !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: displays) {
            return true
        }

        // Une fenetre cachee dans le meme desktop peut etre une stage inactive que macOS vient
        // de focaliser via AltTab/clic externe : Roadie doit alors activer cette stage.
        // Une fenetre cachee dans un autre desktop est en revanche souvent un ancien focus AX
        // stale apres une commande desktop ; le suivre ramene l'utilisateur en arriere.
        return scope.desktopID == persistedStages.currentDesktopID(for: scope.displayID)
    }

    private func activeFocusedWindowID(
        in state: RoadieState,
        scopedWindows: [ScopedWindowSnapshot],
        displays: [DisplaySnapshot]
    ) -> WindowID? {
        for display in displays {
            guard let scope = state.activeScope(on: display.id),
                  let stage = state.stage(scope: scope)
            else { continue }
            if let focusedID = stage.focusedWindowID,
               scopedWindows.contains(where: { $0.window.id == focusedID && $0.scope == scope && $0.window.isTileCandidate }) {
                return focusedID
            }
            if let lastID = stage.windowIDs.last,
               scopedWindows.contains(where: { $0.window.id == lastID && $0.scope == scope && $0.window.isTileCandidate }) {
                return lastID
            }
        }
        return nil
    }

    private func pinEventDetails(_ pin: PersistentWindowPin) -> [String: String] {
        [
            "windowID": String(pin.windowID.rawValue),
            "bundleID": pin.bundleID,
            "title": pin.title,
            "pinScope": pin.pinScope.rawValue,
            "displayID": pin.homeScope.displayID.rawValue,
            "desktopID": String(pin.homeScope.desktopID.rawValue),
            "stageID": pin.homeScope.stageID.rawValue
        ]
    }

    private func bookmarkEventDetails(_ bookmark: PersistentWindowBookmark) -> [String: String] {
        [
            "name": bookmark.name,
            "windowID": String(bookmark.windowID.rawValue),
            "bundleID": bookmark.bundleID,
            "title": bookmark.title,
            "displayID": bookmark.scope.displayID.rawValue,
            "desktopID": String(bookmark.scope.desktopID.rawValue),
            "stageID": bookmark.scope.stageID.rawValue
        ]
    }
}

public struct ApplyPlan: Equatable, Codable, Sendable {
    public var commands: [ApplyCommand]

    public init(commands: [ApplyCommand]) {
        self.commands = commands
    }
}

public struct ApplyCommand: Equatable, Codable, Sendable {
    public var window: WindowSnapshot
    public var frame: Rect
    /// Garer une fenêtre de stage masquée : position seule, la taille réelle est conservée (SPEC-062).
    public var preservesSize: Bool
    public var positionsBeforeResizing: Bool

    public init(window: WindowSnapshot, frame: Rect, preservesSize: Bool = false,
                positionsBeforeResizing: Bool = false) {
        self.window = window
        self.frame = frame
        self.preservesSize = preservesSize
        self.positionsBeforeResizing = positionsBeforeResizing
    }

    enum CodingKeys: String, CodingKey { case window, frame, preservesSize, positionsBeforeResizing }
    /// Les commandes encodées avant SPEC-062 n’ont pas `preservesSize`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(window: try container.decode(WindowSnapshot.self, forKey: .window),
                  frame: try container.decode(Rect.self, forKey: .frame),
                  preservesSize: try container.decodeIfPresent(Bool.self, forKey: .preservesSize) ?? false,
                  positionsBeforeResizing: try container.decodeIfPresent(Bool.self, forKey: .positionsBeforeResizing) ?? false)
    }
}

/// Résultat d'une application d'arbre faite par une commande (T219). Publié au maintainer du même
/// processus pour qu'il suive fenêtres, génération, refus et stabilité, sans refaire le placement.
public struct TreeScopeApplication: Equatable, Sendable {
    public var scope: StageScope
    public var generation: UInt64
    public var windowIDs: [WindowID]
    public var appliedAt: Date

    public init(scope: StageScope, generation: UInt64, windowIDs: [WindowID], appliedAt: Date) {
        self.scope = scope
        self.generation = generation
        self.windowIDs = windowIDs
        self.appliedAt = appliedAt
    }
}

/// Point de publication des applications de commande, global au processus (les `SnapshotService`
/// sont des valeurs créées par chaque commande). Le daemon y branche le maintainer et l'ordonnanceur.
public final class TreeScopeApplicationCenter: @unchecked Sendable {
    public static let shared = TreeScopeApplicationCenter()
    private let lock = NSLock()
    private var handler: (@Sendable (TreeScopeApplication) -> Void)?

    public init() {}

    public func setHandler(_ handler: (@Sendable (TreeScopeApplication) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    public func publish(_ application: TreeScopeApplication) {
        let current = lock.withLock { handler }
        current?(application)
    }
}

extension SnapshotService {
    /// Application immédiate de l'arbre d'un scope pour une commande (A15, A20), après sa mutation
    /// de l'arbre : un snapshot (le partagé s'il est encore valide), le plan de l'arbre projeté du
    /// scope (avec le marqueur de zoom), une seule écriture groupée avec `generation`. Une commande
    /// est une intention de l'utilisateur : elle s'applique même si le scope est en rafale ou en
    /// garde, et clôt cette attente (`treeScopeAppliedAt`). Sans effet hors mode à arbre ou si le
    /// scope n'est pas la stage active de son écran.
    /// Épisode (A12, T207) : `episodeID` est celui que la commande a ouvert à son entrée ; nil = la
    /// commande en ouvre un ici (`command:<nom>`). Le `layout_apply` porte les champs du contrat, et
    /// le résultat est publié au maintainer (T219).
    // O(n log n) - n = fenêtres du scope.
    public func applyTreeScope(
        _ scope: StageScope,
        cause: String,
        generation: UInt64,
        episodeID: String? = nil,
        using preparedSnapshot: DaemonSnapshot? = nil,
        onApplied: ((ApplyResult) -> Void)? = nil
    ) -> MaintenanceTick {
        let startedAt = clock()
        // Un glisser de séparation réutilise son inventaire figé : aucun relevé AX à chaque mouvement.
        // Le coordinateur vérifie le scope et l'arbre persistés avant chaque mutation.
        let (snapshot, scanned) = preparedSnapshot.map { ($0, false) }
            ?? sharedSnapshotCountingScan(followFocus: true)
        guard snapshot.permissions.accessibilityTrusted else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        guard let stage = snapshot.state.stage(scope: scope),
              stage.mode.usesTreeEngine,
              snapshot.state.activeScope(on: scope.displayID) == scope
        else { return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0) }
        let commandCause = cause.hasPrefix("command:") ? cause : "command:\(cause)"
        let episode = episodeID ?? EpisodeContext.shared.begin(cause: commandCause)
        processState.noteTreeScopeApplied(scope, at: startedAt)
        let plan = treeApplyPlan(for: scope, in: snapshot, mode: stage.mode, generation: generation)
        let result = apply(plan, generation: generation)
        onApplied?(result)
        let writesByWindow = result.items.reduce(into: [UInt32: Int]()) { $0[$1.windowID.rawValue, default: 0] += 1 }
        events.append(RoadieEvent(type: "layout_apply", scope: scope, details: [
            "cause": commandCause,
            "durationMs": String(format: "%.1f", clock().timeIntervalSince(startedAt) * 1000),
            "pass": String(processState.nextCommandPass(episode: episode)),
            "scans": scanned ? "1" : "0",
            // Écriture façon yabai : taille, position, taille (R8), comme le maintainer.
            "axWrites": String(result.items.count * 3),
            "layoutVersion": String(generation),
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "windowWrites": writesByWindow.keys.sorted().map { "\($0):\(writesByWindow[$0] ?? 0)" }.joined(separator: ",")
        ], episodeId: episode))
        treeScopeApplications.publish(TreeScopeApplication(
            scope: scope, generation: generation, windowIDs: result.items.map(\.windowID), appliedAt: clock()
        ))
        return MaintenanceTick(commands: plan.commands.count, applied: result.applied, clamped: result.clamped, failed: result.failed)
    }

}

public struct ApplyResult: Equatable, Codable, Sendable {
    public var attempted: Int
    public var applied: Int
    public var clamped: Int
    public var failed: Int
    public var items: [ApplyResultItem]
    public var deferred: Int { items.filter { $0.status == .deferred }.count }

    public init(attempted: Int, applied: Int, clamped: Int, failed: Int, items: [ApplyResultItem]) {
        self.attempted = attempted
        self.applied = applied
        self.clamped = clamped
        self.failed = failed
        self.items = items
    }

    /// Résultat d'une application qui n'a rien tenté.
    public static let empty = ApplyResult(attempted: 0, applied: 0, clamped: 0, failed: 0, items: [])
}

public struct ApplyResultItem: Equatable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case applied
        case clamped
        case failed
        case deferred
    }

    public var windowID: WindowID
    public var status: Status
    public var requested: Rect
    public var actual: Rect?

    public init(windowID: WindowID, status: Status, requested: Rect, actual: Rect?) {
        self.windowID = windowID
        self.status = status
        self.requested = requested
        self.actual = actual
    }
}

public extension SnapshotService {
    /// `generation` : génération du plan ; une frame acceptée d'une autre génération ne retire pas
    /// une commande d'arbre (T215).
    func applyPlan(
        from snapshot: DaemonSnapshot,
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = [],
        generation: UInt64 = PlacementGeneration.shared.current
    ) -> ApplyPlan {
        var commands: [ApplyCommand] = []
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }

            guard let stage = snapshot.state.stage(scope: scope) else { continue }
            let effectiveMode = mode ?? stage.mode
            if effectiveMode.usesTreeEngine {
                commands.append(contentsOf: treeApplyPlan(for: scope, in: snapshot, mode: effectiveMode, generation: generation).commands)
            } else if effectiveMode.isTiled || intentStore.intent(for: scope)?.zoomedWindowID != nil,
                      let intent = validIntent(for: scope, from: snapshot) {
                commands.append(contentsOf: applyPlan(from: snapshot, intent: intent).commands)
            } else {
                let orderedWindowIDs = orderedWindowIDs(in: scope, from: snapshot, mode: effectiveMode)
                commands.append(contentsOf: applyPlan(
                    from: snapshot,
                    scope: scope,
                    orderedWindowIDs: orderedWindowIDs,
                    mode: effectiveMode,
                    priorityWindowIDs: priorityWindowIDs
                ).commands)
            }
        }
        return ApplyPlan(commands: commands)
    }

    /// Plan d'un scope à arbre (SPEC-017 R2, T080) : frames de l'arbre projeté ; seul le marqueur
    /// de zoom d'un intent (`zoomedWindowID`) remplace les frames de l'arbre de ses fenêtres (A15).
    /// Aucun autre intent, automatique ou de commande, n'entre dans le calcul.
    // O(n log n) - n = fenêtres du scope (tri des commandes).
    private func treeApplyPlan(
        for scope: StageScope,
        in snapshot: DaemonSnapshot,
        mode: WindowManagementMode,
        generation: UInt64
    ) -> ApplyPlan {
        var targets = layoutPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs(in: scope, from: snapshot, mode: mode),
            mode: mode
        ).placements
        if intentStore.intent(for: scope)?.zoomedWindowID != nil,
           let zoom = validIntent(for: scope, from: snapshot) {
            for (id, frame) in zoom.placements { targets[id] = frame.cgRect }
        }
        return treeCommands(targets: targets, in: snapshot, generation: generation)
    }

    /// Commandes vers les cibles de l'arbre, avec la tolérance unique (R9, FR-010) : une fenêtre est
    /// laissée si sa frame est à `frameMatch` de sa cible, ou si elle est la frame acceptée par le
    /// registre pour cette même cible **et pour la génération du plan** (refus de taille confirmé,
    /// arrondi de terminal). Une acceptation d'une génération antérieure ne retire rien (T215).
    // O(n log n) - n = cibles.
    private func treeCommands(targets: [WindowID: CGRect], in snapshot: DaemonSnapshot, generation: UInt64) -> ApplyPlan {
        let windowsByID = Dictionary(snapshot.windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { first, _ in first })
        let exactWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope.map(exactLayoutScopes.contains) == true ? entry.window.id : nil
        })
        return ApplyPlan(commands: targets.keys.sorted().compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let target = targets[id] else { return nil }
            let observed = window.frame.cgRect
            let exact = exactWindowIDs.contains(id)
            if observed.matchesFrame(target, tolerance: exact ? 0 : LayoutTolerance.frameMatch) { return nil }
            if !exact, let entry = frameRegistry.entry(for: id.rawValue), entry.generation == generation,
               let accepted = entry.accepted, entry.requested.matchesFrame(target), accepted.matchesFrame(observed) {
                return nil
            }
            // Taille imposée par l'application, répétée d'une génération à l'autre (SPEC-068).
            if !exact, frameRegistry.refusesLastingly(windowID: id.rawValue, target: target, observed: observed) { return nil }
            return ApplyCommand(window: window, frame: Rect(target))
        })
    }

    func orderedWindowIDs(
        in scope: StageScope,
        from snapshot: DaemonSnapshot,
        mode: WindowManagementMode? = nil
    ) -> [WindowID] {
        guard let stage = snapshot.state.stage(scope: scope),
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return [] }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let liveStageWindowIDs = stage.windowIDs.filter { windowsByID[$0] != nil }
        let currentFrames = Dictionary(uniqueKeysWithValues: liveStageWindowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        let effectiveMode = mode ?? stage.mode
        // Modes à arbre : l'ordre ne se déduit jamais de la géométrie observée (FR-003).
        guard effectiveMode.usesSpatialBSPOrdering, !effectiveMode.usesTreeEngine else { return liveStageWindowIDs }

        return spatiallyOrdered(liveStageWindowIDs, frames: currentFrames, container: display.visibleFrame.cgRect)
    }

    func innerGap() -> Double {
        config.tiling.gapsInner
    }

    /// Conteneur réel de l'arbre d'un scope, celui de `layoutPlan` : cadre visible de l'écran moins
    /// les marges extérieures (smart gaps compris, selon les fenêtres placées). nil sans stage ni écran.
    // O(w) - w = fenêtres du snapshot.
    func treeContainer(for scope: StageScope, in snapshot: DaemonSnapshot) -> CGRect? {
        guard snapshot.state.stage(scope: scope) != nil,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return nil }
        let placed = treePlacedWindowIDs(orderedWindowIDs(in: scope, from: snapshot), in: snapshot)
        return display.visibleFrame.cgRect.inset(by: outerGaps(windowCount: placed.count, display: display))
    }

    /// Rail replié : toute la zone visible. Rail visible ou épinglé : réservation du panneau.
    /// O(d) — d overrides d'écran ; le nombre de fenêtres ne change pas ce cadre.
    func maximizedFrame(on display: DisplaySnapshot) -> CGRect? {
        let settings = currentRailSettings()
        let runtime = railRuntimeStateStore.load()
        if settings.autoHide, !runtime.isPinned,
           (runtime.visibleWidths[display.id.rawValue] ?? settings.edgeHitWidth) <= settings.edgeHitWidth {
            let visible = display.visibleFrame.cgRect.integral
            guard visible.minX.isFinite, visible.minY.isFinite, visible.width.isFinite,
                  visible.height.isFinite, !visible.isEmpty else { return nil }
            return visible
        }
        var gaps = outerGaps(windowCount: 1, display: display)
        gaps.left = max(gaps.left, settings.width)
        let available = display.visibleFrame.cgRect.inset(by: gaps)
        let minX = ceil(available.minX)
        let minY = ceil(available.minY)
        let width = floor(available.maxX) - minX
        let height = floor(available.maxY) - minY
        guard minX.isFinite, minY.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Quitte le zoom par le mécanisme propre au mode : arbre, intent valide ou cadres float.
    /// O(w log w) en mode arbre ; O(w²) pour valider les placements sans arbre.
    /// Maintenance : un échec d'écriture des intents est journalisé et la sortie de zoom continue.
    func restoreZoomLayoutIntent(
        scope: StageScope,
        from snapshot: DaemonSnapshot,
        generation: UInt64 = PlacementGeneration.shared.current
    ) -> ApplyPlan {
        restoreZoom(scope: scope, from: snapshot, generation: generation, remove: intentStore.remove(scope:), save: intentStore.save)
    }

    /// Variante des commandes (REL-021) : lève si l'intent n'a pas été écrit, avant tout plan.
    func restoreZoomLayoutIntentChecked(
        scope: StageScope,
        from snapshot: DaemonSnapshot,
        generation: UInt64 = PlacementGeneration.shared.current
    ) throws -> ApplyPlan {
        try restoreZoom(scope: scope, from: snapshot, generation: generation, remove: intentStore.removeChecked(scope:), save: intentStore.saveChecked)
    }

    private func restoreZoom(
        scope: StageScope,
        from snapshot: DaemonSnapshot,
        generation: UInt64,
        remove: (StageScope) throws -> Void,
        save: (LayoutIntent) throws -> Void
    ) rethrows -> ApplyPlan {
        let zoom = commandLayoutIntent(scope: scope)
        try remove(scope)
        let entries = snapshot.windows.filter { $0.scope == scope && $0.window.isTileCandidate }
        let mode = snapshot.state.stage(scope: scope)?.mode
        if let saved = zoom?.restorePlacements, mode == .float {
            return ApplyPlan(commands: entries.compactMap { entry in
                guard let frame = saved[entry.window.id], frame.width > 0, frame.height > 0,
                      !entry.window.frame.cgRect.matchesFrame(frame.cgRect) else { return nil }
                return ApplyCommand(window: entry.window, frame: frame)
            })
        }
        if let zoom, let saved = zoom.restorePlacements, mode?.usesTreeEngine != true {
            let liveIDs = Set(entries.map(\.window.id))
            let ordered = zoom.windowIDs.filter(liveIDs.contains)
            if liveIDs == Set(ordered), liveIDs.isSubset(of: Set(saved.keys)) {
                try save(LayoutIntent(scope: scope, windowIDs: ordered, placements: saved, source: .command))
                _ = validIntent(for: scope, from: snapshot)
            }
        }
        guard let mode else { return ApplyPlan(commands: []) }
        if mode.usesTreeEngine {
            return treeApplyPlan(for: scope, in: snapshot, mode: mode, generation: generation)
        }
        if mode.isTiled, let restored = validIntent(for: scope, from: snapshot) {
            return applyPlan(from: snapshot, intent: restored)
        }
        return applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs(in: scope, from: snapshot, mode: mode),
            mode: mode,
            generation: generation
        )
    }

    /// Fenêtres placées par l'arbre : vivantes et hors plein écran natif (leur feuille reste). O(w).
    private func treePlacedWindowIDs(_ ids: [WindowID], in snapshot: DaemonSnapshot) -> [WindowID] {
        let placeable = Set(snapshot.windows.compactMap { entry in
            entry.window.furniture?.isNativeFullscreen == true ? nil : entry.window.id
        })
        return ids.filter(placeable.contains)
    }

    func saveLayoutIntent(scope: StageScope, windowIDs: [WindowID], placements: [WindowID: Rect]) {
        saveLayoutIntent(scope: scope, windowIDs: windowIDs, placements: placements, source: .auto)
    }

    /// Maintenance : un échec d'écriture est journalisé sur stderr, comme `LayoutIntentStore.save`.
    func saveLayoutIntent(
        scope: StageScope,
        windowIDs: [WindowID],
        placements: [WindowID: Rect],
        source: LayoutIntent.Source,
        zoomedWindowID: WindowID? = nil
    ) {
        do {
            try saveLayoutIntentChecked(
                scope: scope,
                windowIDs: windowIDs,
                placements: placements,
                source: source,
                zoomedWindowID: zoomedWindowID
            )
        } catch {
            fputs("roadie: \(error)\n", stderr)
        }
    }

    /// Variante des commandes (REL-021) : lève `JSONPersistence.PersistenceError` si l'intent
    /// n'a pas été écrit, au lieu d'un succès silencieux.
    func saveLayoutIntentChecked(
        scope: StageScope,
        windowIDs: [WindowID],
        placements: [WindowID: Rect],
        source: LayoutIntent.Source,
        zoomedWindowID: WindowID? = nil
    ) throws {
        // Une observation automatique actualise les cadres acceptés sans remplacer le zoom
        // logique ni sa disposition à restaurer (nouvelle voisine, recalage de largeur du rail).
        if source == .auto, zoomedWindowID == nil,
           commandLayoutIntent(scope: scope)?.zoomedWindowID != nil {
            try intentStore.mutateChecked { stored in
                guard var zoom = stored[scope.description], zoom.source == .command,
                      zoom.zoomedWindowID != nil else { return }
                let liveIDs = Set(windowIDs)
                let retained = zoom.windowIDs.filter(liveIDs.contains)
                let retainedIDs = Set(retained)
                zoom.windowIDs = retained + windowIDs.filter { !retainedIDs.contains($0) }
                zoom.placements = placements
                stored[scope.description] = zoom
            }
            return
        }
        // Modes à arbre : aucun intent automatique persisté, l'arbre fait foi (R2, T080).
        if source == .auto, zoomedWindowID == nil,
           stageStore.state().scopes
               .first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
               .stages.first(where: { $0.id == scope.stageID })?.mode.usesTreeEngine == true {
            return
        }
        try intentStore.saveChecked(LayoutIntent(
            scope: scope,
            windowIDs: windowIDs,
            placements: placements,
            source: source,
            zoomedWindowID: zoomedWindowID
        ))
    }

    /// Maintenance : échec journalisé par le store, sans effet sur l'appelant.
    func removeLayoutIntent(scope: StageScope) {
        intentStore.remove(scope: scope)
    }

    /// Variante des commandes (REL-021) : lève si la suppression n'a pas été écrite.
    func removeLayoutIntentChecked(scope: StageScope) throws {
        try intentStore.removeChecked(scope: scope)
    }

    /// Commande `balance` (REL-021) : lève dès qu'une suppression n'a pas été écrite.
    func removeLayoutIntents(in snapshot: DaemonSnapshot) throws {
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }
            try intentStore.removeChecked(scope: scope)
        }
    }

    func hasMatchingIntent(
        scope: StageScope,
        frames: [UInt32: Rect],
        focusedWindowID: WindowID? = nil,
        positionTolerance: CGFloat = 8,
        sizeTolerance: CGFloat = 8,
        focusedPositionTolerance: CGFloat = 12,
        focusedSizeTolerance: CGFloat = 36,
        allowFocusChromeDelta: Bool = true
    ) -> Bool {
        guard let intent = intentStore.intent(for: scope) else { return false }
        return intent.placements.allSatisfy { id, frame in
            guard let observed = frames[id.rawValue] else { return false }
            if id == focusedWindowID {
                return (allowFocusChromeDelta && isLikelyFocusWindowChromeDelta(observed, baseline: frame))
                    || observed.isClose(
                        to: frame,
                        positionTolerance: focusedPositionTolerance,
                        sizeTolerance: focusedSizeTolerance
                    )
            }
            return observed.isClose(to: frame, positionTolerance: positionTolerance, sizeTolerance: sizeTolerance)
        }
    }

    func hasRecentCommandIntent(scope: StageScope, since date: Date) -> Bool {
        guard let intent = intentStore.intent(for: scope) else { return false }
        return intent.source == .command && intent.createdAt >= date
    }

    func commandLayoutIntent(scope: StageScope) -> LayoutIntent? {
        guard let intent = intentStore.intent(for: scope),
              intent.source == .command
        else { return nil }
        return intent
    }

    func hasValidLayoutIntent(scope: StageScope, in snapshot: DaemonSnapshot) -> Bool {
        validIntent(for: scope, from: snapshot) != nil
    }

    @discardableResult
    func saveCurrentLayoutIntentIfValid(scope: StageScope, from snapshot: DaemonSnapshot) -> Bool {
        guard let stage = snapshot.state.stage(scope: scope),
              stage.mode.isTiled,
              !stage.mode.usesTreeEngine,
              snapshot.state.activeScope(on: scope.displayID) == scope
        else { return false }

        let orderedIDs = orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
        let placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        guard Set(placements.keys) == Set(orderedIDs) else { return false }

        let intent = LayoutIntent(
            scope: scope,
            windowIDs: orderedIDs,
            placements: placements,
            source: .auto
        )
        guard intentStillTilesCurrentContainer(
            intent,
            scope: scope,
            from: snapshot,
            requireReasonableTileSizes: true
        ) else { return false }
        intentStore.save(intent)
        return true
    }

    func applyPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = [],
        generation: UInt64 = PlacementGeneration.shared.current
    ) -> ApplyPlan {
        let plan = layoutPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs,
            mode: mode,
            priorityWindowIDs: priorityWindowIDs
        )
        guard let stage = snapshot.state.stage(scope: scope) else { return ApplyPlan(commands: []) }
        if (mode ?? stage.mode).usesTreeEngine {
            return treeCommands(targets: plan.placements, in: snapshot, generation: generation)
        }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        let currentPlan = LayoutPlan(placements: currentFrames)

        let exact = exactLayoutScopes.contains(scope)
        let diff = LayoutDiff.commands(previous: exact ? nil : currentPlan, next: plan)
        let commands = diff.compactMap { command -> ApplyCommand? in
            guard let window = windowsByID[command.windowID] else { return nil }
            if exact, window.frame.cgRect.matchesFrame(command.frame, tolerance: 0) { return nil }
            return ApplyCommand(window: window, frame: Rect(command.frame))
        }
        return ApplyPlan(commands: commands)
    }

    func layoutPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = []
    ) -> LayoutPlan {
        guard let stage = snapshot.state.stage(scope: scope),
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return LayoutPlan(placements: [:]) }

        let config = self.config
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let effectiveMode = mode ?? stage.mode
        if effectiveMode.usesTreeEngine {
            // Arbre déjà réconcilié par le snapshot de la passe (T081) : projeté sans les feuilles
            // absentes ni les fenêtres en plein écran natif, puis placé (A9, FR-007). La stratégie
            // garde le filet de sécurité d'une fenêtre vivante encore sans feuille.
            let placed = treePlacedWindowIDs(orderedWindowIDs, in: snapshot)
            return LayoutPlanner.plan(LayoutRequest(
                scope: scope,
                mode: .spatialBsp,
                container: display.visibleFrame.cgRect,
                windowIDs: placed,
                bspTree: stageStore.state().bspTree(for: scope),
                outerGaps: outerGaps(windowCount: placed.count, display: display),
                innerGap: config.tiling.gapsInner
            ))
        }
        let liveOrderedWindowIDs = orderedWindowIDs.filter { windowsByID[$0] != nil }
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        // Fenetres tout juste decouvertes : leur frame macOS est arbitraire, le moteur
        // doit les splitter 50/50 et non heriter de cette frame.
        let newWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.isNewlyScoped ? entry.window.id : nil
        })
        return LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: effectiveMode,
            container: display.visibleFrame.cgRect,
            windowIDs: liveOrderedWindowIDs,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs,
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: liveOrderedWindowIDs.count, display: display),
            innerGap: config.tiling.gapsInner,
            masterRatio: config.tiling.masterRatio
        ))
    }

    /// FR-005 : point d'ancrage BSP d'une nouvelle fenêtre = premier candidat déjà feuille vivante
    /// de l'arbre parmi le focus global, le focus de la stage et son focus précédent ; `nil` sinon
    /// (insertion sur la première feuille). Le focus global seul ne suffit pas : c'est souvent la
    /// nouvelle fenêtre elle-même, et la stage l'a déjà adoptée comme focus (le précédent reste).
    // O(f) - f = feuilles de l'arbre, déjà collectées par l'appelant.
    fileprivate static func bspInsertionAnchor(
        leaves: Set<WindowID>,
        live: Set<WindowID>,
        globalFocus: WindowID?,
        stage: PersistentStage
    ) -> WindowID? {
        let anchors = leaves.intersection(live)
        return [globalFocus, stage.focusedWindowID, stage.previousFocusedWindowID]
            .lazy
            .compactMap { $0 }
            .first { anchors.contains($0) }
    }

    private func validIntent(for scope: StageScope, from snapshot: DaemonSnapshot) -> LayoutIntent? {
        guard var intent = intentStore.intent(for: scope) else { return nil }
        let scopedIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate ? entry.window.id : nil
        })
        // Intent de zoom (FR-001, FR-012) : fenêtre zoomée et voisines cachées se chevauchent
        // ou sortent du conteneur par construction. Seule la présence de la fenêtre zoomée
        // dans le scope le valide.
        if let zoomedWindowID = intent.zoomedWindowID {
            guard scopedIDs.contains(zoomedWindowID), intent.placements[zoomedWindowID] != nil else {
                removeInvalidIntent(scope: scope)
                return nil
            }
            if intent.zoomReservesRail == true {
                guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                      let frame = maximizedFrame(on: display) else { return nil }
                intent.placements[zoomedWindowID] = Rect(frame)
            }
            return intent
        }
        guard scopedIDs == Set(intent.windowIDs) else {
            removeInvalidIntent(scope: scope)
            return nil
        }
        if intent.source == .command,
           intentStillTilesCurrentContainer(intent, scope: scope, from: snapshot, requireReasonableTileSizes: false) {
            return intent
        }
        guard intentStillTilesCurrentContainer(intent, scope: scope, from: snapshot, requireReasonableTileSizes: true) else {
            removeInvalidIntent(scope: scope)
            return nil
        }
        return intent
    }

    /// Un processus lecteur ne retire pas d'intent (FR-014) : le writer s'en charge.
    private func removeInvalidIntent(scope: StageScope) {
        if persistStateChanges {
            intentStore.remove(scope: scope)
        }
    }

    private func intentStillTilesCurrentContainer(
        _ intent: LayoutIntent,
        scope: StageScope,
        from snapshot: DaemonSnapshot,
        requireReasonableTileSizes: Bool
    ) -> Bool {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
              !intent.windowIDs.isEmpty
        else { return false }

        let targetArea = canonicalTiledArea(for: intent, display: display)
        guard targetArea > 0 else { return false }

        let container = display.visibleFrame.cgRect.inset(by: outerGaps(windowCount: intent.windowIDs.count, display: display))
        let frames = intent.windowIDs.compactMap { intent.placements[$0]?.cgRect }
        guard frames.count == intent.windowIDs.count else { return false }
        guard frames.allSatisfy({ container.contains($0, tolerance: LayoutTolerance.intentContainerSlack) }) else { return false }
        guard !framesContainSignificantOverlap(frames) else { return false }
        guard !Self.framesLeaveLargeUntiledCells(
            frames,
            in: container,
            allowedGap: CGFloat(config.tiling.gapsInner) + LayoutTolerance.intentUntiledGapSlack
        ) else { return false }
        if requireReasonableTileSizes {
            guard framesHaveReasonableTileSizes(frames, in: container) else { return false }
        }

        let intentArea = frames.reduce(CGFloat(0)) { $0 + $1.area }
        return intentArea >= targetArea * LayoutTolerance.intentMinimumAreaRatio
    }

    private func framesHaveReasonableTileSizes(_ frames: [CGRect], in container: CGRect) -> Bool {
        guard frames.count > 1 else { return true }
        let minimumSide = max(LayoutTolerance.minimumTileSide, min(container.width, container.height) * LayoutTolerance.minimumTileSideRatio)
        return frames.allSatisfy { frame in
            frame.width >= minimumSide && frame.height >= minimumSide
        }
    }

    /// Vrai si une cellule de la grille des bords (largeur et hauteur > tolérance, dans le
    /// conteneur) n'a son centre dans aucun cadre élargi de 1 pt : un trou de disposition.
    /// Chaque cadre couvre un intervalle contigu de colonnes et un de lignes de centres, trouvés une
    /// fois par dichotomie. Chaque colonne cumule ensuite les intervalles de lignes des cadres qui la
    /// couvrent (tableau de différences) au lieu de tester tous les cadres pour chaque cellule.
    // Avant : O(n³) (O(n²) cellules × n cadres). Après : O(n²) temps, O(n) mémoire - n cadres.
    static func framesLeaveLargeUntiledCells(
        _ frames: [CGRect],
        in container: CGRect,
        allowedGap: CGFloat
    ) -> Bool {
        guard frames.count > 1 else { return false }
        let tolerance = max(LayoutTolerance.untiledCell, allowedGap)
        let xEdges = sortedEdges([container.minX, container.maxX] + frames.flatMap { [$0.minX, $0.maxX] })
        let yEdges = sortedEdges([container.minY, container.maxY] + frames.flatMap { [$0.minY, $0.maxY] })
        let columnCount = max(0, xEdges.count - 1)
        let rowCount = max(0, yEdges.count - 1)
        guard columnCount > 0, rowCount > 0 else { return false }
        // Centres calculés comme `midX`/`midY` de la cellule : mêmes valeurs que le test point par point.
        let xCenters = (0..<columnCount).map {
            CGRect(x: xEdges[$0], y: 0, width: xEdges[$0 + 1] - xEdges[$0], height: 0).midX
        }
        let yCenters = (0..<rowCount).map {
            CGRect(x: 0, y: yEdges[$0], width: 0, height: yEdges[$0 + 1] - yEdges[$0]).midY
        }
        // Centres c avec minimum - 1 <= c <= maximum + 1 (tolérance 1 pt), centres triés.
        let spans: [(columns: Range<Int>, rows: Range<Int>)] = frames.compactMap { frame in
            let columns = centerRange(xCenters, from: frame.minX - 1, to: frame.maxX + 1)
            let rows = centerRange(yCenters, from: frame.minY - 1, to: frame.maxY + 1)
            return columns.isEmpty || rows.isEmpty ? nil : (columns, rows)
        }

        var rowDelta = [Int](repeating: 0, count: rowCount + 1)
        for column in 0..<columnCount {
            let width = xEdges[column + 1] - xEdges[column]
            guard width > tolerance else { continue }
            for index in rowDelta.indices { rowDelta[index] = 0 }
            for span in spans where span.columns.contains(column) {
                rowDelta[span.rows.lowerBound] += 1
                rowDelta[span.rows.upperBound] -= 1
            }
            var coveringFrames = 0
            for row in 0..<rowCount {
                coveringFrames += rowDelta[row]
                let height = yEdges[row + 1] - yEdges[row]
                guard coveringFrames == 0, height > tolerance else { continue }
                let cell = CGRect(x: xEdges[column], y: yEdges[row], width: width, height: height)
                if container.contains(cell, tolerance: 1) { return true }
            }
        }
        return false
    }

    /// Indices des valeurs triées comprises dans [lower, upper]. O(log n) par dichotomie.
    private static func centerRange(_ sorted: [CGFloat], from lower: CGFloat, to upper: CGFloat) -> Range<Int> {
        func firstIndex(where isPast: (CGFloat) -> Bool) -> Int {
            var low = 0
            var high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if isPast(sorted[middle]) { high = middle } else { low = middle + 1 }
            }
            return low
        }
        let start = firstIndex { $0 >= lower }
        let end = firstIndex { $0 > upper }
        return start < end ? start..<end : start..<start
    }

    private static func sortedEdges(_ values: [CGFloat]) -> [CGFloat] {
        let sorted = values.sorted()
        return sorted.reduce(into: [CGFloat]()) { result, value in
            if result.last.map({ abs($0 - value) > 1 }) ?? true {
                result.append(value)
            }
        }
    }

    private func canonicalTiledArea(for intent: LayoutIntent, display: DisplaySnapshot) -> CGFloat {
        let config = self.config
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: intent.scope,
            mode: config.tiling.defaultStrategy,
            container: display.visibleFrame.cgRect,
            windowIDs: intent.windowIDs,
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: intent.windowIDs.count, display: display),
            innerGap: config.tiling.gapsInner,
            masterRatio: config.tiling.masterRatio
        ))
        return plan.placements.values.reduce(CGFloat(0)) { $0 + $1.area }
    }

    // Complexite : O(n^2) avec sortie precoce.
    // n borne par le nombre de fenetres tilees par display (typiquement <20),
    // donc <=190 comparaisons au pire cas observable. Acceptable pour ce hot path.
    private func framesContainSignificantOverlap(_ frames: [CGRect]) -> Bool {
        guard frames.count > 1 else { return false }
        for index in frames.indices {
            for otherIndex in frames.index(after: index)..<frames.endIndex {
                if frames[index].intersection(frames[otherIndex]).area > LayoutTolerance.intentOverlapArea {
                    return true
                }
            }
        }
        return false
    }

    private func isLikelyFocusWindowChromeDelta(_ observed: Rect, baseline: Rect) -> Bool {
        let dx = abs(observed.x - baseline.x)
        let dy = abs(observed.y - baseline.y)
        let dw = abs(observed.width - baseline.width)
        let dh = abs(observed.height - baseline.height)
        return dx <= LayoutTolerance.focusChromeDeltaX
            && (dy <= LayoutTolerance.focusChromeDeltaY || dh <= LayoutTolerance.focusChromeDeltaY)
            && (dw <= LayoutTolerance.focusChromeDeltaWidth && dh <= LayoutTolerance.focusChromeDeltaHeight)
    }

    private func applyPlan(from snapshot: DaemonSnapshot, intent: LayoutIntent) -> ApplyPlan {
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let focusedWindowID = focusedWindowID()
        let exact = exactLayoutScopes.contains(intent.scope)
        let commands = intent.windowIDs.compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let target = intent.placements[id] else {
                return nil
            }
            if !exact, id == focusedWindowID,
               isLikelyFocusWindowChromeDelta(window.frame, baseline: target) {
                return nil
            }
            // Tolérance unique (T201, R9) : à refaire seulement au-delà de `frameMatch`.
            guard !window.frame.cgRect.matchesFrame(target.cgRect, tolerance: exact ? 0 : LayoutTolerance.frameMatch) else { return nil }
            return ApplyCommand(window: window, frame: target)
        }
        return ApplyPlan(commands: commands)
    }

    /// Écrit le plan en un lot, avec la génération de placement (A13 ; par défaut la génération en
    /// cours). « Réussi » suit la tolérance unique (R9) : frame relue à `frameMatch` de la demande,
    /// ou frame acceptée par le registre pour cette demande ; sinon « clamped ». Le snapshot partagé
    /// est ensuite republié avec les frames relues au lieu d'être invalidé (R11, A12).
    /// Budget A13 épuisé pour une fenêtre dans `generation` : pas d'écriture (l'écrivain AX la
    /// refuserait aussi), la frame observée est acceptée et signalée ; la fenêtre est absente des
    /// `items` et de `attempted` (T213).
    // O(n) - n = commandes.
    func apply(_ plan: ApplyPlan, generation: UInt64 = PlacementGeneration.shared.current,
               isCurrent: @Sendable () -> Bool = { true }, publish: Bool = true,
               respectLastingRefusals: Bool = false, animation: AnimationAction = .move,
               immediateWindowIDs: Set<WindowID> = []) -> ApplyResult {
        // Les appels interactifs publish=false gardent leur contrat immédiat. Les commandes
        // hors MainActor restent immédiates ; aucun transfert synchrone vers le fil principal.
        if publish, Thread.isMainThread, effectiveConfig.fx.animations.enabled {
            let deferred = MainActor.assumeIsolated {
                let runtime = FrameTransitionRuntime.shared
                return runtime.acceptsCommands ? runtime.schedule(plan, service: self, generation: generation, action: animation,
                    immediateWindowIDs: immediateWindowIDs) : nil
            }
            if let deferred { return deferred }
        }
        var items: [ApplyResultItem] = []
        let commands = plan.commands.filter { command in
            if respectLastingRefusals && frameRegistry.refusesLastingly(windowID: command.window.id.rawValue,
                target: command.frame.cgRect, observed: command.window.frame.cgRect) { return false }
            guard frameRegistry.isOverBudget(windowID: command.window.id.rawValue, generation: generation) else { return true }
            acceptOverBudget(command.window, requested: command.frame, generation: generation)
            return false
        }
        let updates = commands.map { command in
            WindowFrameUpdate(window: command.window, frame: command.frame.cgRect, preservesSize: command.preservesSize,
                              positionsBeforeResizing: command.positionsBeforeResizing || immediateWindowIDs.contains(command.window.id))
        }
        let actualFrames = updates.isEmpty ? [:] : frameWriter.setFrames(updates, generation: generation, isCurrent: isCurrent)

        for command in commands {
            guard let rawActual = actualFrames[command.window.id], let actual = rawActual else {
                items.append(ApplyResultItem(
                    windowID: command.window.id,
                    status: .failed,
                    requested: command.frame,
                    actual: nil
                ))
                continue
            }
            let requested = command.frame.cgRect
            let entry = frameRegistry.entry(for: command.window.id.rawValue)
            let accepted = entry.flatMap { $0.requested.matchesFrame(requested) ? $0.accepted : nil }
            items.append(ApplyResultItem(
                windowID: command.window.id,
                status: actual.matchesFrame(requested) || accepted?.matchesFrame(actual) == true ? .applied : .clamped,
                requested: command.frame,
                actual: Rect(actual)
            ))
        }
        if publish && isCurrent() { republishSharedSnapshot(after: items, windows: commands.map(\.window)) }
        var applied = 0, clamped = 0, failed = 0
        for item in items {
            switch item.status {
            case .applied: applied += 1
            case .clamped: clamped += 1
            case .failed: failed += 1
            case .deferred: break
            }
        }
        return ApplyResult(
            attempted: commands.count,
            applied: applied,
            clamped: clamped,
            failed: failed,
            items: items
        )
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        // Un focus seul conserve les cadres ; ne pas perdre le clic qui suit le focus-souris.
        processState.invalidatePublished(preservingGesture: true)
        return frameWriter.focus(window)
    }

    /// Fenêtre sur un autre espace macOS (plein écran natif actif, session 106). Au plus 1,5 s d'attente.
    func focusOnOtherSpace(_ window: WindowSnapshot) -> SpaceFocusOutcome {
        processState.invalidatePublished(preservingGesture: true)
        return frameWriter.focusOnOtherSpace(window, timeout: 1.5)
    }

    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.focusApplicationWindow(bundleID: bundleID, windowID: windowID, title: title, frame: frame)
    }

    func activateApplication(bundleID: String) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.activateApplication(bundleID: bundleID)
    }

    func reset(_ window: WindowSnapshot) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.reset(window)
    }

    func toggleZoom(_ window: WindowSnapshot) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.toggleZoom(window)
    }

    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.toggleNativeFullscreen(window)
    }

    func focusedWindowID() -> WindowID? {
        provider.focusedWindowID()
    }

    /// Écriture directe d'une fenêtre (T213) : `generation` est celle de la commande, par défaut la
    /// génération en cours. Budget A13 épuisé : nil sans écriture, frame observée acceptée et signalée.
    /// `preservingSize` : position seule, pour garer une fenêtre sans toucher sa taille (SPEC-062).
    func setFrame(
        _ frame: CGRect,
        of window: WindowSnapshot,
        generation: UInt64 = PlacementGeneration.shared.current,
        preservingSize: Bool = false
    ) -> CGRect? {
        if frameRegistry.isOverBudget(windowID: window.id.rawValue, generation: generation) {
            acceptOverBudget(window, requested: Rect(frame), generation: generation)
            return nil
        }
        let actual = preservingSize
            ? frameWriter.setFrames([WindowFrameUpdate(window: window, frame: frame, preservesSize: true)], generation: generation)[window.id] ?? nil
            : frameWriter.setFrame(frame, of: window, generation: generation)
        republishSharedSnapshot(after: [ApplyResultItem(
            windowID: window.id,
            status: actual == nil ? .failed : .applied,
            requested: Rect(frame),
            actual: actual.map { Rect($0) }
        )], windows: [window])
        return actual
    }

    /// Budget épuisé (A13) : la frame observée est acceptée, comme dans le maintainer. O(1).
    private func acceptOverBudget(_ window: WindowSnapshot, requested: Rect, generation: UInt64) {
        frameRegistry.accept(windowID: window.id.rawValue, frame: window.frame.cgRect)
        // Même format que les événements du maintainer : « x,y lxh ».
        let describe = { (frame: Rect) in "\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))" }
        events.append(RoadieEvent(type: "layout_app_response_accepted", details: [
            "windowID": String(window.id.rawValue),
            "requested": describe(requested),
            "actual": describe(window.frame),
            "reason": "write_budget_exhausted",
            "layoutVersion": String(generation)
        ]))
    }

    /// Lecture AX fraîche du cadre d'une fenêtre (seconde observation d'un refus, A14). nil si illisible.
    func readFrame(of window: WindowSnapshot) -> CGRect? {
        frameWriter.readFrame(of: window)
    }

    /// Republie le snapshot partagé avec les frames relues après une écriture (R11, A12) : les
    /// lecteurs (bordure, focus-souris, navrail) ne refont pas de relevé complet. Une écriture en
    /// échec laisse la fenêtre dans un état inconnu ; un snapshot partiel n'existant pas, elle
    /// invalide le snapshot partagé, et le prochain lecteur refait un relevé.
    private func republishSharedSnapshot(after items: [ApplyResultItem], windows: [WindowSnapshot]) {
        guard !items.isEmpty else { return }
        let frames = Dictionary(items.compactMap { item in item.actual.map { (item.windowID, $0) } },
                                uniquingKeysWith: { _, last in last })
        // Le read-back AX prouve le masquage même si une autre écriture du lot échoue ou si
        // le focus invalide ensuite le cache avant le premier relevé de la nouvelle topologie.
        processState.recordWrittenWindows(windows.compactMap { window in
            guard let frame = frames[window.id] else { return nil }
            var observed = window
            observed.frame = frame
            return observed
        })
        if items.contains(where: { $0.actual == nil }) {
            invalidateSharedSnapshot()
            return
        }
        processState.republish(frames: frames)
    }

    /// Publication sur MainActor après validation de la session, jamais depuis un lot devenu ancien.
    @MainActor func publishInteractive(_ result: ApplyResult, commands: [ApplyCommand]) {
        republishSharedSnapshot(after: result.items, windows: commands.map(\.window))
    }

    /// Le cadre appartient au geste de l'utilisateur, pas au registre de nos écritures.
    /// Le clic suivant doit retrouver cette frame, même avant la prochaine passe complète.
    @MainActor func publishNativeObservation(windowID: WindowID, frame: CGRect) {
        processState.republish(frames: [windowID: Rect(frame)])
    }
}

private extension SnapshotService {
    func spatiallyOrdered(
        _ windowIDs: [WindowID],
        frames: [WindowID: CGRect],
        container: CGRect
    ) -> [WindowID] {
        guard windowIDs.count > 1 else { return windowIDs }

        let horizontal = container.width >= container.height
        let leftCount = windowIDs.count / 2
        let sorted = spatialSortOrder(windowIDs, frames: frames, horizontal: horizontal)
        let left = Array(sorted.prefix(leftCount))
        let right = Array(sorted.dropFirst(leftCount))

        let leftRect: CGRect
        let rightRect: CGRect
        if horizontal {
            let splitX = rects(for: left, in: frames).map(\.maxX).max() ?? container.midX
            leftRect = CGRect(x: container.minX, y: container.minY, width: max(0, splitX - container.minX), height: container.height)
            rightRect = CGRect(x: splitX, y: container.minY, width: max(0, container.maxX - splitX), height: container.height)
        } else {
            let splitY = rects(for: left, in: frames).map(\.maxY).max() ?? container.midY
            leftRect = CGRect(x: container.minX, y: container.minY, width: container.width, height: max(0, splitY - container.minY))
            rightRect = CGRect(x: container.minX, y: splitY, width: container.width, height: max(0, container.maxY - splitY))
        }

        return spatiallyOrdered(left, frames: frames, container: leftRect)
            + spatiallyOrdered(right, frames: frames, container: rightRect)
    }

    /// Ordre total (REL-006). L'ancien comparateur changeait d'axe selon l'écart de deux centres :
    /// relation non transitive, résultat dépendant de l'ordre d'entrée. Les bandes sont formées une
    /// seule fois sur l'axe principal, puis sur l'axe secondaire dans chaque bande principale. Tri par
    /// bande principale, bande secondaire, puis ID : comme avant, deux fenêtres alignées sur les deux
    /// axes restent dans l'ordre de leurs ID. Fenêtre sans cadre : après les autres, par ID.
    // O(n log n) - n fenêtres du conteneur.
    func spatialSortOrder(_ windowIDs: [WindowID], frames: [WindowID: CGRect], horizontal: Bool) -> [WindowID] {
        let placed = windowIDs.compactMap { id in
            frames[id].map { (id: id, primary: horizontal ? $0.midX : $0.midY, secondary: horizontal ? $0.midY : $0.midX) }
        }
        .sorted { ($0.primary, $0.id) < ($1.primary, $1.id) }
        let primaryBands = alignmentBands(placed.map(\.primary))
        var keys: [(primary: Int, secondary: Int, id: WindowID)] = []
        var runStart = 0
        while runStart < placed.count {
            var runEnd = runStart + 1
            while runEnd < placed.count, primaryBands[runEnd] == primaryBands[runStart] { runEnd += 1 }
            let run = placed[runStart..<runEnd].sorted { ($0.secondary, $0.id) < ($1.secondary, $1.id) }
            for (entry, secondaryBand) in zip(run, alignmentBands(run.map(\.secondary))) {
                keys.append((primaryBands[runStart], secondaryBand, entry.id))
            }
            runStart = runEnd
        }
        let unplaced = windowIDs.filter { frames[$0] == nil }.sorted()
        return keys.sorted { ($0.primary, $0.secondary, $0.id) < ($1.primary, $1.secondary, $1.id) }.map(\.id) + unplaced
    }

    /// Bande de chaque valeur triée : une bande s'ouvre quand une valeur dépasse de plus de
    /// `spatialAlignment` la valeur qui a ouvert la bande courante. O(n).
    func alignmentBands(_ sortedValues: [CGFloat]) -> [Int] {
        var band = 0
        var bandStart = sortedValues.first ?? 0
        return sortedValues.map { value in
            if value - bandStart > LayoutTolerance.spatialAlignment {
                band += 1
                bandStart = value
            }
            return band
        }
    }

    func rects(for windowIDs: [WindowID], in frames: [WindowID: CGRect]) -> [CGRect] {
        windowIDs.compactMap { frames[$0] }
    }

    func outerGaps(windowCount: Int, display: DisplaySnapshot? = nil) -> Insets {
        let config = self.config
        let railSettings = currentRailSettings()
        let override = display.flatMap { display in
            config.tiling.displayOverrides.first { override in
                override.displayID == display.id.rawValue || override.displayName == display.name
            }
        }
        let base = override?.gapsOuter ?? config.tiling.gapsOuter
        var top = override?.gapsOuterTop ?? override?.gapsOuter ?? config.tiling.gapsOuterTop ?? base
        var right = override?.gapsOuterRight ?? override?.gapsOuter ?? config.tiling.gapsOuterRight ?? base
        var bottom = override?.gapsOuterBottom ?? override?.gapsOuter ?? config.tiling.gapsOuterBottom ?? base
        var left = override?.gapsOuterLeft ?? override?.gapsOuter ?? config.tiling.gapsOuterLeft ?? base
        if railSettings.autoHide {
            switch railSettings.layoutMode {
            case "resize":
                if let display {
                    let visibleWidth = railRuntimeStateStore.load().visibleWidths[display.id.rawValue]
                    left = min(left, visibleWidth ?? railSettings.edgeHitWidth)
                }
            default:
                if railSettings.dynamicLeftGap {
                    left = min(left, railSettings.edgeHitWidth)
                }
            }
        }

        if config.tiling.smartGapsSolo && windowCount == 1 {
            let sides = config.tiling.smartGapsSoloSides
            if sides.contains(.top) { top = 0 }
            if sides.contains(.right) { right = 0 }
            if sides.contains(.bottom) { bottom = 0 }
            if sides.contains(.left) { left = 0 }
        }

        return Insets(top: top, right: right, bottom: bottom, left: left)
    }

    internal func currentRailSettings() -> RailSettings {
        railSettings ?? RailSettings.load(path: configService.state.activePath ?? RoadieConfigLoader.defaultConfigPath())
    }
}

private extension Rect {
    func isClose(to other: Rect, positionTolerance: Double, sizeTolerance: Double) -> Bool {
        abs(x - other.x) <= positionTolerance
            && abs(y - other.y) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

extension CGRect {
    /// Tolérance unique de comparaison de frames (R9, FR-010) : `frameMatch` sur chaque composante.
    func matchesFrame(_ other: CGRect, tolerance: CGFloat = LayoutTolerance.frameMatch) -> Bool {
        return abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }

    func contains(_ other: CGRect, tolerance: CGFloat) -> Bool {
        other.minX >= minX - tolerance
            && other.minY >= minY - tolerance
            && other.maxX <= maxX + tolerance
            && other.maxY <= maxY + tolerance
    }
}

public enum SnapshotEncoding {
    /// Encodage JSON commun des sorties CLI : clés triées, indenté par défaut.
    public static func json<T: Encodable>(_ value: T, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Mémoire de processus partagée par les `SnapshotService` d'un même fichier d'état (SPEC-016) :
/// dernier snapshot publié (FR-023), fenêtres vivantes précédentes (FR-009) et dernier classement
/// tilable lisible (FR-008). La clé est le chemin du fichier d'état : les tests, qui injectent
/// chacun leur `StageStore`, restent isolés.
private struct SnapshotWindowObservation: Sendable {
    let windows: [WindowSnapshot]
    let inventory: [WindowID: Int32]?
    let focusedWindowID: WindowID?
    let completedAt: Date
}

final class SnapshotProcessState: @unchecked Sendable {
    /// Validité du snapshot partagé : couvre la bordure (120 ms) et le focus-souris (100 ms).
    static let sharedSnapshotMaxAge: TimeInterval = 0.15
    /// Marge ajoutée à l'intervalle du tiler pour qu'un tick en retard ne force pas de rescan.
    static let producerMargin: TimeInterval = 0.1
    /// Validité maximale d'un snapshot du tiler, quel que soit son intervalle.
    static let producerMaxAgeCap: TimeInterval = 0.6
    /// Une preuve AX ancienne ne doit pas transformer une future absence transitoire en fermeture.
    static let destroyedMembershipEvidenceMaxAge: TimeInterval = 5
    static let destroyedWindowRetryDelay: TimeInterval = 0.05
    static let destroyedWindowRetryLimit = 10

    static func producerMaxAge(cycle: TimeInterval) -> TimeInterval {
        min(max(cycle, 0) + producerMargin, producerMaxAgeCap)
    }

    /// Registre protégé par un seul verrou (T218).
    private static let registry = OSAllocatedUnfairLock<[String: SnapshotProcessState]>(initialState: [:])

    static func forStatePath(_ path: String) -> SnapshotProcessState {
        registry.withLock { registry in
            if let existing = registry[path] { return existing }
            let created = SnapshotProcessState()
            registry[path] = created
            return created
        }
    }

    private struct Published {
        let snapshot: DaemonSnapshot
        let maxAge: TimeInterval
        let at: Date
        let stateStamp: [Int64]
        let config: RoadieConfig
        let observationGeneration: UInt64
    }

    private struct DestroyedWindowEvidence {
        let observedAt: Date
        var scheduledRetries: Int
        var retryAt: Date?
    }

    struct ReaderAcquisition {
        let id = UUID()
        let revision: UInt64
        let observation: UInt64
        let stateStamp: [Int64]
        let config: RoadieConfig
        let displays: [DisplaySnapshot]
        fileprivate let task: Task<SnapshotWindowObservation, Never>
    }
    @MainActor var readerAcquisition: ReaderAcquisition?
    private var revision: UInt64 = 0
    var publicationRevision: UInt64 { lock.withLock { revision } }
    private var observation: UInt64 = 0
    /// Génération d'observation : incrémentée à chaque changement signalé (SPEC-048). O(1).
    var observationGeneration: UInt64 { lock.withLock { observation } }
    func noteObservationChange() { lock.withLock { observation &+= 1 } }
    /// Durée de réutilisation silencieuse pour les lecteurs ; 0 tant que le tiler ne l'active pas.
    /// Elle borne les changements sans notification (titre, application sans observateur).
    private var quietReuseCap: TimeInterval = 0
    func enableQuietReuse(cap: TimeInterval) { lock.withLock { quietReuseCap = max(0, cap) } }

    private let lock = NSLock()
    /// Clé : option `followFocus` du snapshot publié.
    private var published: [Bool: Published] = [:]
    private var gestureSnapshot: DaemonSnapshot?

    func latestPublishedSnapshot() -> DaemonSnapshot? {
        lock.withLock { gestureSnapshot }
    }
    private var liveWindowIDs: Set<WindowID>?
    private var recentWindowObservations: [WindowID: Date] = [:]
    private var lastDisappearanceAt: Date?
    private var tileClassification: [WindowID: Bool] = [:]
    /// Cadre de chaque fenêtre au premier relevé lisible par l'accessibilité (session 125).
    private var firstFrames: [WindowID: Rect] = [:]
    /// Masquages réellement observés, indépendants du cache publié. Une nouvelle topologie
    /// peut rendre leur ancienne position visible avant que le maintainer les remasque.
    private var hiddenWindows: [WindowID: (window: WindowSnapshot, missingSince: Date?)] = [:]
    private var observedDisplays: [DisplaySnapshot] = []
    /// Arbres (SPEC-017) : destructions confirmées en attente, dernière application par commande,
    /// migration déjà tentée.
    private var destroyed: Set<WindowID> = []
    private var destroyedEvidence: [WindowID: DestroyedWindowEvidence] = [:]
    private var treeAppliedAt: [StageScope: Date] = [:]
    private var legacyTreeMigrationClaimed = false
    /// Rang de la dernière passe de commande dans son épisode (`pass` de `layout_apply`, A12).
    private var commandPass: (episode: String, pass: Int)?

    func publish(_ snapshot: DaemonSnapshot, followFocus: Bool, maxAge: TimeInterval, at date: Date, stateStamp: [Int64],
                 config: RoadieConfig, observationGeneration: UInt64) {
        if followFocus, let focused = snapshot.focusedWindowID,
           snapshot.windows.contains(where: { $0.window.id == focused }) {
            WindowSwitcherFocusHistory.shared.observe(focused)
            WindowSwitcherRuntimeBridge.publishFocus(focused)
        }
        lock.withLock {
            revision &+= 1
            gestureSnapshot = snapshot
            published[followFocus] = Published(snapshot: snapshot, maxAge: maxAge, at: date, stateStamp: stateStamp,
                                               config: config, observationGeneration: observationGeneration)
        }
    }

    /// Dernier snapshot publié s'il est récent et que ni l'état persisté ni la config n'ont changé.
    /// `allowQuietReuse` (lecteurs) : au-delà de `maxAge`, le relevé reste valable si aucun changement
    /// n'a été observé depuis son acquisition et si son âge reste sous `quietReuseCap`. O(1).
    func recentSnapshot(followFocus: Bool, now: Date, stateStamp: [Int64], config: RoadieConfig,
                        allowQuietReuse: Bool = false) -> DaemonSnapshot? {
        lock.withLock {
            guard let entry = published[followFocus] else { return nil }
            let age = now.timeIntervalSince(entry.at)
            let quiet = allowQuietReuse && entry.observationGeneration == observation && age < quietReuseCap
            guard age >= 0, age < entry.maxAge || quiet,
                  entry.stateStamp == stateStamp,
                  entry.config == config
            else { return nil }
            return entry.snapshot
        }
    }

    func invalidatePublished(preservingGesture: Bool = false) {
        lock.withLock {
            revision &+= 1
            published.removeAll()
            if !preservingGesture { gestureSnapshot = nil }
        }
    }

    /// Garde la preuve de masquage tant que l'identité et la frame observées sont les mêmes.
    /// Une absence AX courte ne l'efface pas ; une frame différente ou une destruction l'efface.
    /// O(w × d + h), avec w fenêtres, d écrans et h preuves récentes.
    func observedHiddenWindowIDs(_ windows: [WindowSnapshot], in displays: [DisplaySnapshot], now: Date) -> Set<WindowID> {
        lock.withLock {
            observedDisplays = displays
            let liveIDs = Set(windows.map(\.id))
            for id in Array(hiddenWindows.keys) {
                guard let previous = hiddenWindows[id] else { continue }
                if destroyed.contains(id) || previous.missingSince.map({ now.timeIntervalSince($0) >= LayoutTolerance.missingWindowGraceSeconds }) == true {
                    hiddenWindows.removeValue(forKey: id)
                } else if !liveIDs.contains(id) {
                    hiddenWindows[id] = (previous.window, previous.missingSince ?? now)
                }
            }
            var hidden: Set<WindowID> = []
            for window in windows {
                let previous = hiddenWindows[window.id]?.window
                let sameObservedFrame = previous?.pid == window.pid
                    && previous?.bundleID == window.bundleID && previous?.frame == window.frame
                if HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: displays) || sameObservedFrame {
                    hidden.insert(window.id)
                    if !destroyed.contains(window.id) { hiddenWindows[window.id] = (window, nil) }
                } else {
                    hiddenWindows.removeValue(forKey: window.id)
                }
            }
            return hidden
        }
    }

    /// Enregistre les cadres réellement relus après une écriture, avec leur identité et la
    /// dernière topologie observée. Cette preuve survit à l'invalidation du cache. O(w × d).
    func recordWrittenWindows(_ windows: [WindowSnapshot]) {
        lock.withLock {
            for window in windows {
                if !destroyed.contains(window.id),
                   HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: observedDisplays) {
                    hiddenWindows[window.id] = (window, nil)
                } else {
                    hiddenWindows.removeValue(forKey: window.id)
                }
            }
        }
    }

    /// Remplace les frames des fenêtres écrites dans les snapshots publiés, sans changer leur âge. O(w).
    func republish(frames: [WindowID: Rect]) {
        guard !frames.isEmpty else { return }
        lock.withLock {
            revision &+= 1
            if var cached = gestureSnapshot {
                for index in cached.windows.indices {
                    if let frame = frames[cached.windows[index].window.id] { cached.windows[index].window.frame = frame }
                }
                gestureSnapshot = cached
            }
            for (key, entry) in published {
                var snapshot = entry.snapshot
                for index in snapshot.windows.indices {
                    if let frame = frames[snapshot.windows[index].window.id] {
                        snapshot.windows[index].window.frame = frame
                    }
                }
                published[key] = Published(snapshot: snapshot, maxAge: entry.maxAge, at: entry.at, stateStamp: entry.stateStamp,
                                           config: entry.config, observationGeneration: entry.observationGeneration)
            }
        }
    }

    func noteDestroyed(_ id: WindowID, at date: Date) {
        lock.withLock {
            guard destroyed.insert(id).inserted else { return }
            revision &+= 1
            published.removeAll()
            gestureSnapshot = nil
            destroyedEvidence[id] = DestroyedWindowEvidence(
                observedAt: date,
                scheduledRetries: 0,
                retryAt: nil
            )
        }
    }

    func retractDestruction(_ id: WindowID, observedBefore date: Date) -> Bool {
        lock.withLock {
            guard let evidence = destroyedEvidence[id], evidence.observedAt <= date else { return false }
            destroyed.remove(id)
            destroyedEvidence[id] = nil
            return true
        }
    }

    func destructionSnapshot(now: Date) -> (pending: Set<WindowID>, recent: Set<WindowID>) {
        lock.withLock {
            let recent = Set(destroyedEvidence.compactMap { id, evidence in
                let age = now.timeIntervalSince(evidence.observedAt)
                return age >= 0 && age <= Self.destroyedMembershipEvidenceMaxAge ? id : nil
            })
            return (destroyed, recent)
        }
    }

    /// Consomme les fermetures disparues. Un snapshot producteur programme au plus dix relectures
    /// par identifiant quand CoreGraphics présente encore la fenêtre. Les lecteurs ne comptent pas.
    func recordDestructionReconciliation(
        observedDestroyedWindowIDs: Set<WindowID>,
        liveWindowIDs: Set<WindowID>,
        at date: Date,
        advancesRetry: Bool
    ) {
        lock.withLock {
            // Le relevé et cette décision forment une même photographie. Une destruction arrivée
            // pendant le relevé reste donc en attente de la passe suivante.
            let observed = destroyed.intersection(observedDestroyedWindowIDs)
            let consumed = observed.subtracting(liveWindowIDs)
            destroyed.subtract(consumed)
            for id in consumed { destroyedEvidence[id] = nil }
            guard advancesRetry else { return }
            for id in observed.intersection(liveWindowIDs) {
                guard var evidence = destroyedEvidence[id] else { continue }
                let age = date.timeIntervalSince(evidence.observedAt)
                guard age >= 0,
                      age <= Self.destroyedMembershipEvidenceMaxAge,
                      evidence.scheduledRetries < Self.destroyedWindowRetryLimit
                else {
                    evidence.retryAt = nil
                    destroyedEvidence[id] = evidence
                    continue
                }
                if let retryAt = evidence.retryAt, date < retryAt { continue }
                evidence.scheduledRetries += 1
                evidence.retryAt = date.addingTimeInterval(Self.destroyedWindowRetryDelay)
                destroyedEvidence[id] = evidence
            }
        }
    }

    func destroyedWindowRetryDeadline(now: Date) -> Date? {
        lock.withLock {
            destroyedEvidence.values.compactMap { evidence in
                let age = now.timeIntervalSince(evidence.observedAt)
                return age >= 0 && age <= Self.destroyedMembershipEvidenceMaxAge
                    ? evidence.retryAt
                    : nil
            }.min()
        }
    }

    func noteTreeScopeApplied(_ scope: StageScope, at date: Date) {
        lock.withLock { treeAppliedAt[scope] = date }
    }

    func treeScopeAppliedAt(_ scope: StageScope) -> Date? {
        lock.withLock { treeAppliedAt[scope] }
    }

    /// Rang de la prochaine passe de commande dans `episode` : 1 pour un nouvel épisode. O(1).
    func nextCommandPass(episode: String) -> Int {
        lock.withLock {
            let pass = commandPass?.episode == episode ? (commandPass?.pass ?? 0) + 1 : 1
            commandPass = (episode, pass)
            return pass
        }
    }

    /// Vrai au premier appel seulement : la migration des modes hérités est tentée une fois.
    func claimLegacyTreeMigration() -> Bool {
        lock.withLock {
            defer { legacyTreeMigrationClaimed = true }
            return !legacyTreeMigrationClaimed
        }
    }

    /// Enregistre les fenêtres réellement vues, sans écrire au repos. Les dates récentes restent
    /// disponibles après une absence, même si un lecteur la relève avant le snapshot écrivain.
    // O(n)
    func recordLiveWindows(_ ids: Set<WindowID>, now: Date) -> (lastDisappearanceAt: Date?, lastSeenAt: [WindowID: Date]) {
        lock.withLock {
            if let previous = liveWindowIDs, !previous.isSubset(of: ids) {
                lastDisappearanceAt = now
            }
            liveWindowIDs = ids
            recentWindowObservations = recentWindowObservations.filter {
                ids.contains($0.key) || now.timeIntervalSince($0.value) <= LayoutTolerance.missingWindowGraceSeconds
            }
            for id in ids { recentWindowObservations[id] = now }
            return (lastDisappearanceAt, recentWindowObservations)
        }
    }

    /// Hystérésis du classement tilable (FR-008) : une fenêtre dont les attributs AX sont tous
    /// illisibles (application lente) garde son dernier classement obtenu avec des attributs lisibles.
    /// Les critères CoreGraphics bruts (taille, layer) restent prioritaires.
    // O(n)
    /// Premier cadre de chaque fenêtre vivante, retenu au premier relevé où l'accessibilité répond :
    /// avant qu'elle ne réponde, le cadre peut encore être celui d'une fenêtre en cours de création.
    /// Les fenêtres disparues sont oubliées. O(n).
    func initialFrames(_ windows: [WindowSnapshot]) -> [WindowID: Rect] {
        lock.withLock {
            var next: [WindowID: Rect] = [:]
            for window in windows {
                if let known = firstFrames[window.id] { next[window.id] = known }
                else if window.furniture != nil { next[window.id] = window.frame }
            }
            firstFrames = next
            return next
        }
    }

    /// Premier cadre retenu d'une fenêtre, nil si inconnu. O(1).
    func initialFrame(of id: WindowID) -> Rect? {
        lock.withLock { firstFrames[id] }
    }

    func stabilizedClassification(_ windows: [(raw: WindowSnapshot, classified: WindowSnapshot)]) -> [WindowSnapshot] {
        lock.withLock {
            var next: [WindowID: Bool] = [:]
            let result = windows.map { pair -> WindowSnapshot in
                var window = pair.classified
                let unreadable = pair.raw.role == nil && pair.raw.subrole == nil && pair.raw.furniture == nil
                if !unreadable {
                    next[window.id] = window.isTileCandidate
                } else if let previous = tileClassification[window.id] {
                    if pair.raw.isTileCandidate {
                        window.isTileCandidate = previous
                    }
                    next[window.id] = previous
                }
                return window
            }
            tileClassification = next
            return result
        }
    }
}

// MARK: - Aperçu actif du lanceur (SPEC-078)

extension SnapshotService {
    /// Identifiant qui tient la place d'une fenêtre à venir dans la disposition future.
    static let previewPhantomID = WindowID(rawValue: 0xFFFF_FFF0)

    /// Disposition de `scope` si `incoming` y arrivait, insérée comme la réconciliation insère une
    /// nouvelle fenêtre : même ancre (focus global, de la stage, précédent), même côté
    /// (`new_window_side`), même moteur que la stage. `incoming` peut être une vraie fenêtre (venue
    /// d'ailleurs) ou `previewPhantomID`. Ne lit ni n'écrit aucun état persistant. O(n log n).
    func previewPlacements(scope: StageScope, incoming: WindowID, in snapshot: DaemonSnapshot) -> [WindowID: CGRect] {
        guard let stage = snapshot.state.stage(scope: scope),
              let display = snapshot.displays.first(where: { $0.id == scope.displayID }) else { return [:] }
        let container = display.visibleFrame.cgRect
        let ordered = orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode).filter { $0 != incoming }
        if stage.mode.usesTreeEngine {
            let placed = treePlacedWindowIDs(ordered, in: snapshot)
            let persistent = stageStore.state().scopes
                .first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages.first { $0.id == scope.stageID }
            let tree = (persistent?.bspTree ?? .empty).removing(incoming)
            let leaves = Set(tree.windowIDs)
            let anchor = persistent.flatMap {
                Self.bspInsertionAnchor(leaves: leaves, live: Set(placed), globalFocus: snapshot.focusedWindowID, stage: $0)
            }
            let side: BSPInsertionSide = config.windowPlacement.newWindowSide == "left" ? .left : .right
            let next = tree.inserting(incoming, at: anchor, side: side, in: container,
                                      innerGap: CGFloat(config.tiling.gapsInner), excluding: leaves.subtracting(placed))
            return LayoutPlanner.plan(LayoutRequest(
                scope: scope,
                mode: .spatialBsp,
                container: container,
                windowIDs: placed + [incoming],
                bspTree: next,
                outerGaps: outerGaps(windowCount: placed.count + 1, display: display),
                innerGap: config.tiling.gapsInner
            )).placements
        }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let live = ordered.filter { windowsByID[$0] != nil }
        let currentFrames = Dictionary(uniqueKeysWithValues: live.compactMap { id in windowsByID[id].map { (id, $0.frame.cgRect) } })
        return LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: stage.mode,
            container: container,
            windowIDs: live + [incoming],
            currentFrames: currentFrames,
            newWindowIDs: [incoming],
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: live.count + 1, display: display),
            innerGap: config.tiling.gapsInner,
            masterRatio: config.tiling.masterRatio
        )).placements
    }
}
