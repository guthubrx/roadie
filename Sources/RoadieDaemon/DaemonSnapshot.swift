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

    public init(
        permissions: PermissionSnapshot,
        displays: [DisplaySnapshot],
        windows: [ScopedWindowSnapshot],
        state: RoadieState,
        focusedWindowID: WindowID? = nil
    ) {
        self.permissions = permissions
        self.displays = displays
        self.windows = windows
        self.state = state
        self.focusedWindowID = focusedWindowID
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

public struct SnapshotService {
    // AX/macOS peut faire disparaitre des fenetres pendant un plein ecran, un changement
    // de desktop, un redemarrage du daemon ou une reconfiguration display. Une absence
    // courte n'est donc pas une preuve de fermeture : si on prune trop vite, la fenetre
    // revient comme "nouvelle" et peut etre reassignee au mauvais ecran/stage.
    private static let stageMembershipMissingGrace: TimeInterval = 30 * 60

    private let provider: any SystemSnapshotProviding
    private let frameWriter: any WindowFrameWriting
    /// Config figée injectée (tests, commandes) ; nil = config du processus rechargée à chaud.
    private let fixedConfig: RoadieConfig?
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
    private let persistStateChanges: Bool
    private let userInput: UserInputActivity
    private let clock: @Sendable () -> Date
    /// Mémoire de processus partagée par les services du même fichier d'état.
    private let processState: SnapshotProcessState

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
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.frameWriter = frameWriter
        self.fixedConfig = config
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

    /// Config courante : relue à chaud via `ConfigReloadService.shared` (un stat par accès).
    /// Les fonctions qui la lisent plusieurs fois en prennent une copie locale.
    private var config: RoadieConfig {
        fixedConfig ?? ConfigReloadService.shared.currentConfig()
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

    /// Snapshot pour les composants lecteurs (bordure, focus-souris, rail) : réutilise le
    /// dernier snapshot publié dans le processus pour ce fichier d'état s'il est encore valide
    /// (150 ms, ou le cycle courant du tiler s'il vient de `producerSnapshot`) et que ni l'état
    /// persisté ni la config n'ont changé ; sinon en produit un (FR-023).
    public func sharedSnapshot(followFocus: Bool = true) -> DaemonSnapshot {
        if let recent = processState.recentSnapshot(
            followFocus: followFocus,
            now: clock(),
            stateStamp: fileModificationStamp(stageStore.fileURL.path),
            config: config
        ) {
            return recent
        }
        return snapshot(followFocus: followFocus)
    }

    /// Oublie le snapshot partagé (après une commande qui change fenêtres ou focus).
    public func invalidateSharedSnapshot() {
        processState.invalidatePublished()
    }

    public func snapshot(promptForPermissions: Bool = false, followFocus: Bool = true) -> DaemonSnapshot {
        snapshot(promptForPermissions: promptForPermissions, followFocus: followFocus, sharedMaxAge: SnapshotProcessState.sharedSnapshotMaxAge)
    }

    /// Snapshot du tick du tiler, producteur unique du processus quand il tourne (FR-023) : publié
    /// comme source partagée valable tout le cycle (`cycle` + marge, borné à 600 ms). Les lecteurs
    /// du processus le consomment au lieu de rescanner ; ailleurs la règle des 150 ms s'applique.
    public func producerSnapshot(cycle: TimeInterval) -> DaemonSnapshot {
        snapshot(promptForPermissions: false, followFocus: true, sharedMaxAge: SnapshotProcessState.producerMaxAge(cycle: cycle))
    }

    private func snapshot(promptForPermissions: Bool, followFocus: Bool, sharedMaxAge: TimeInterval) -> DaemonSnapshot {
        let config = self.config
        let now = clock()
        // Énumération Accessibility HORS verrou (R1) : seule la réconciliation, fonction pure
        // de (état, fenêtres vivantes), tourne sous le verrou de `StageStore.mutate`.
        let permissions = provider.permissions(prompt: promptForPermissions)
        let displays = provider.displays()
        let rawWindows = provider.windows()
        // Pre-calcule les structures lourdes (Set subroles, regles triees) une seule fois
        // par snapshot pour eviter O(n_windows) recompactations dans applyTilingPolicy.
        let policyContext = TilingPolicyContext(config: config)
        let windows = processState.stabilizedClassification(rawWindows.map { window in
            (raw: window, classified: Self.applyTilingPolicy(to: window, config: config, context: policyContext))
        })
        let stageManagedWindowIDs = Set(windows.compactMap { window in
            window.isTileCandidate ? window.id : nil
        })
        let providerFocusedID = provider.focusedWindowID()
        let mouseLocation = provider.mouseLocation()
        let liveDisplayIDs = Set(displays.map(\.id))
        // FR-009 : un changement de stage par le focus exige une saisie utilisateur récente,
        // postérieure à la dernière disparition de fenêtre et hors des 500 ms qui la suivent.
        let lastDisappearanceAt = processState.recordLiveWindows(stageManagedWindowIDs, now: now)
        let focusChangeAllowed = userInput.allowsFocusChange(now: now, lastDisappearanceAt: lastDisappearanceAt)
        let input = ReconciliationInput(
            config: config,
            displays: displays,
            windows: windows,
            stageManagedWindowIDs: stageManagedWindowIDs,
            liveDisplayIDs: liveDisplayIDs,
            providerFocusedID: providerFocusedID,
            mouseLocation: mouseLocation,
            followFocus: followFocus,
            focusChangeAllowed: focusChangeAllowed,
            now: now
        )

        let result: Reconciliation
        if persistStateChanges {
            intentStore.prune(keepingDisplayIDs: liveDisplayIDs)
            result = stageStore.mutate { persistedStages in
                reconcile(&persistedStages, input: input)
            }
            // Les events de reconciliation decrivent une mutation de l'etat persiste. En mode
            // lecteur (persistStateChanges=false, SPEC-011 atomique), plusieurs process appellent
            // snapshot() : seul le writer (tiler/run) doit emettre ces events, sinon ils sont
            // dupliques N fois (un par composant) dans events.jsonl.
            appendReconciliationEvents(result)
        } else {
            var persistedStages = stageStore.state()
            result = reconcile(&persistedStages, input: input)
        }

        let snapshot = DaemonSnapshot(
            permissions: permissions,
            displays: displays,
            windows: result.scopedWindows,
            state: result.state,
            focusedWindowID: result.focusedWindowID
        )
        processState.publish(
            snapshot,
            followFocus: followFocus,
            maxAge: sharedMaxAge,
            at: now,
            stateStamp: fileModificationStamp(stageStore.fileURL.path),
            config: config
        )
        return snapshot
    }

    /// Entrées de la réconciliation, lues hors verrou.
    private struct ReconciliationInput {
        let config: RoadieConfig
        let displays: [DisplaySnapshot]
        let windows: [WindowSnapshot]
        let stageManagedWindowIDs: Set<WindowID>
        let liveDisplayIDs: Set<DisplayID>
        let providerFocusedID: WindowID?
        let mouseLocation: CGPoint?
        let followFocus: Bool
        let focusChangeAllowed: Bool
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
    // O(w + m) — w fenêtres vivantes, m membres persistés (index inverse pré-calculé).
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
        let liveWindowIDs = stageManagedWindowIDs
        let mouseLocation = input.mouseLocation
        persistedStages.reconcileWindowIDs(with: windows.filter { stageManagedWindowIDs.contains($0.id) })
        let missingWindows = persistedStages.pruneMissingWindows(
            keeping: liveWindowIDs,
            liveDisplayIDs: liveDisplayIDs,
            missingGrace: Self.stageMembershipMissingGrace,
            now: now
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
            persistentScope.applyConfiguredStages(config.stageManager, defaultMode: config.tiling.defaultStrategy)
            persistentScope.adoptDefaultModeForEmptyDefaultStages(config.tiling.defaultStrategy)
            persistedStages.update(persistentScope)
            let activePersistentStage = persistentScope.stages.first { $0.id == persistentScope.activeStageID }
            try? state.createStage(
                id: persistentScope.activeStageID,
                name: "Stage \(persistentScope.activeStageID.rawValue)",
                mode: activePersistentStage?.mode ?? .bsp,
                in: display.id,
                desktopID: currentDesktopID
            )
            try? state.switchDesktop(currentDesktopID, on: display.id)
            try? state.switchStage(persistentScope.activeStageID, in: display.id, desktopID: currentDesktopID)
        }

        let fallbackDisplayID = displays.first?.id
        // Pre-compute inverse index O(total_members) pour eviter O(w * scopes * stages * members) sur le hot path.
        var stageIndex = persistedStages.stageScopeIndex()
        for window in windows {
            guard stageManagedWindowIDs.contains(window.id) else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            let pin = persistedStages.pin(for: window.id)
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
            } else if !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: displays),
                      // FR-037 : un cadre hors de tout écran présent (écran débranché) n'écrase pas la
                      // dernière position visible du membre. O(d), d = nombre d'écrans.
                      displays.contains(where: { $0.frame.cgRect.intersects(window.frame.cgRect) }) {
                var persistentScope = persistedStages.scope(
                    displayID: displayID,
                    desktopID: knownScope?.desktopID ?? persistedStages.currentDesktopID(for: displayID),
                    defaultMode: config.tiling.defaultStrategy
                )
                persistentScope.updateFrame(
                    window: window,
                    presentationState: presentationState(for: window, displayID: displayID, displays: displays)
                )
                persistedStages.update(persistentScope)
                persistedStages.updatePinFrame(window: window, now: now)
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
            persistedStages.updateBookmarkObservation(window: window, scope: scope, now: now)
            let isNewlyScoped = knownScope == nil
            let persistedScope = persistedStages.scopes.first {
                $0.displayID == scope.displayID && $0.desktopID == scope.desktopID
            }
            let persistedStage = persistedScope?.stages.first { $0.id == scope.stageID }
            try? state.createStage(
                id: scope.stageID,
                name: "Stage \(scope.stageID.rawValue)",
                mode: persistedStage?.mode ?? config.tiling.defaultStrategy,
                in: scope.displayID,
                desktopID: scope.desktopID
            )
            try? state.setMode(persistedStage?.mode ?? config.tiling.defaultStrategy, for: scope)
            if window.isTileCandidate, pin == nil {
                try? state.assignWindow(window.id, to: scope)
            }
            try? state.setGroups(persistedStage?.groups ?? [], for: scope)
            scopedWindows.append(ScopedWindowSnapshot(
                window: window,
                scope: scope,
                pin: pin,
                isNewlyScoped: isNewlyScoped
            ))
        }
        correctSoloMaximizedStates(in: &persistedStages, scopedWindows: scopedWindows, displays: displays, config: config)
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
        return Reconciliation(
            state: state,
            scopedWindows: scopedWindows,
            focusedWindowID: focusedID,
            missingWindows: missingWindows,
            prunedPins: prunedPins,
            prunedBookmarks: prunedBookmarks
        )
    }

    /// FR-027 : une fenêtre tilée seule dans son scope remplit l'écran par construction et n'est
    /// pas « agrandie ». Le nombre de fenêtres par scope n'est connu qu'après la boucle d'affectation,
    /// d'où cette correction a posteriori des états persistés. O(w).
    private func correctSoloMaximizedStates(
        in persistedStages: inout PersistentStageState,
        scopedWindows: [ScopedWindowSnapshot],
        displays: [DisplaySnapshot],
        config: RoadieConfig
    ) {
        let tiledCounts = WindowPresentationStateResolver.tiledWindowCounts(in: scopedWindows)
        for entry in scopedWindows where entry.window.isTileCandidate {
            guard let scope = entry.scope,
                  tiledCounts[scope] == 1,
                  !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: displays),
                  presentationState(for: entry.window, displayID: scope.displayID, displays: displays) == .maximized,
                  let display = displays.first(where: { $0.id == scope.displayID })
            else { continue }
            var persistentScope = persistedStages.scope(
                displayID: scope.displayID,
                desktopID: scope.desktopID,
                defaultMode: config.tiling.defaultStrategy
            )
            persistentScope.updateFrame(
                window: entry.window,
                presentationState: WindowPresentationStateResolver.state(
                    for: entry.window,
                    on: display,
                    isOnlyTiledWindowInScope: true
                )
            )
            persistedStages.update(persistentScope)
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

    /// Applique la policy de tiling sur une fenetre brute.
    /// Ordre de decision :
    ///   1. baseCandidate (criteres CG bruts) doit etre vrai sinon -> non tile-able
    ///   2. floating_bundles -> non tile-able
    ///   3. popup gate (heuristique aerospace) : si AX present et aucun bouton/flag d'etat,
    ///      c'est un popup/menu/tooltip -> non tile-able
    ///   4. AX subrole doit etre dans config.tiling.allowed_subroles (defaut ["AXStandardWindow"])
    ///      Si subrole inconnu (AX absent) -> on laisse passer (non-regression)
    ///   5. Premiere regle matchant peut overrider :
    ///        action.manage = true   -> force tile-able
    ///        action.exclude = true  -> force non tile-able
    ///        action.floating = true -> force non tile-able
    public static func applyTilingPolicy(to window: WindowSnapshot, config: RoadieConfig) -> WindowSnapshot {
        applyTilingPolicy(to: window, config: config, context: TilingPolicyContext(config: config))
    }

    static func applyTilingPolicy(
        to window: WindowSnapshot,
        config: RoadieConfig,
        context: TilingPolicyContext
    ) -> WindowSnapshot {
        var tile = window.isTileCandidate

        if tile && context.floatingBundles.contains(window.bundleID) {
            tile = false
        }

        // Popup gate (aerospace-like) : si AX nous a donne le mobilier mais qu'aucun signal
        // de "vraie fenetre" n'est present (boutons + isFocused + isMain), c'est un popup.
        if tile && config.tiling.popupFilter,
           let furniture = window.furniture,
           furniture.isModal {
            tile = false
        }

        if tile && config.tiling.popupFilter,
           isLikelyTransientSettingsWindow(window) {
            tile = false
        }

        if tile && config.tiling.popupFilter,
           isShortNonFullscreenUtilityWindow(window) {
            tile = false
        }

        if tile && config.tiling.popupFilter,
           isNonResizableStandardWindow(window) {
            tile = false
        }

        if tile && config.tiling.popupFilter,
           isUnidentifiedTransientWindow(window) {
            tile = false
        }

        if tile && config.tiling.popupFilter,
           let furniture = window.furniture,
           !furniture.isLikelyRealWindow,
           window.subrole != "AXStandardWindow" {
            tile = false
        }

        // Heuristique aerospace fine : fullscreenButton present mais desactive ->
        // probablement un dialog (Settings, About, IntelliJ Rebase, Calculator...).
        // Ne s'applique pas aux apps qui cachent legitimement le bouton fullscreen
        // (terminals, IDEs) : pour celles-la, l'utilisateur peut whitelister leur subrole
        // ou ajouter une regle action.manage.
        if tile && config.tiling.popupFilter,
           let furniture = window.furniture,
           furniture.fullscreenButtonDisabled,
           window.subrole != "AXStandardWindow" {
            tile = false
        }

        if tile {
            switch window.subrole {
            case .some(let value):
                if !context.allowedSubroles.contains(value) { tile = false }
            case .none:
                break // AX absent -> on laisse passer (non-regression apps non-AX)
            }
        }

        // Override par les regles user. Premiere regle matchant gagne (regles deja triees).
        let matchContext = WindowRuleMatchContext(role: window.role, subrole: window.subrole)
        if let rule = WindowRuleMatcher.firstMatch(sortedRules: context.sortedRules, window: window, context: matchContext) {
            if rule.action.manage == true {
                tile = window.isTileCandidate // force tile mais respect criteres CG (taille mini, layer)
            }
            if rule.action.exclude == true || rule.action.floating == true {
                tile = false
            }
        }

        var result = window
        result.isTileCandidate = tile
        return result
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

        return (isSmall && genericTitle) || systemPanelTitle
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
            return fallbackDisplayID ?? displayID(containing: window.frame.center, in: displays)
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

    public init(window: WindowSnapshot, frame: Rect) {
        self.window = window
        self.frame = frame
    }
}

public struct ApplyResult: Equatable, Codable, Sendable {
    public var attempted: Int
    public var applied: Int
    public var clamped: Int
    public var failed: Int
    public var items: [ApplyResultItem]

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
    func applyPlan(
        from snapshot: DaemonSnapshot,
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = []
    ) -> ApplyPlan {
        var commands: [ApplyCommand] = []
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }

            guard let stage = snapshot.state.stage(scope: scope) else { continue }
            let effectiveMode = mode ?? stage.mode
            if effectiveMode.isTiled,
               let intent = validIntent(for: scope, from: snapshot),
               shouldApplyLayoutIntent(intent, mode: effectiveMode, scope: scope, from: snapshot) {
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

    private func shouldApplyLayoutIntent(
        _ intent: LayoutIntent,
        mode: WindowManagementMode,
        scope: StageScope,
        from snapshot: DaemonSnapshot
    ) -> Bool {
        if intent.source == .command { return true }
        if mode != .mutableBsp { return true }

        let scopedWindows = snapshot.windows.filter { entry in
            entry.scope == scope && intent.windowIDs.contains(entry.window.id)
        }
        guard !scopedWindows.isEmpty else { return true }

        return scopedWindows.contains { entry in
            !entry.window.isOnScreen || HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
        }
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
        guard effectiveMode.usesSpatialBSPOrdering else { return liveStageWindowIDs }

        return spatiallyOrdered(liveStageWindowIDs, frames: currentFrames, container: display.visibleFrame.cgRect)
    }

    func innerGap() -> Double {
        config.tiling.gapsInner
    }

    func saveLayoutIntent(scope: StageScope, windowIDs: [WindowID], placements: [WindowID: Rect]) {
        saveLayoutIntent(scope: scope, windowIDs: windowIDs, placements: placements, source: .auto)
    }

    func saveLayoutIntent(
        scope: StageScope,
        windowIDs: [WindowID],
        placements: [WindowID: Rect],
        source: LayoutIntent.Source,
        zoomedWindowID: WindowID? = nil
    ) {
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: windowIDs,
            placements: placements,
            source: source,
            zoomedWindowID: zoomedWindowID
        ))
    }

    func removeLayoutIntent(scope: StageScope) {
        intentStore.remove(scope: scope)
    }

    func removeLayoutIntents(in snapshot: DaemonSnapshot) {
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }
            intentStore.remove(scope: scope)
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

    func commandLayoutIntentNeedsApply(scope: StageScope, in snapshot: DaemonSnapshot) -> Bool {
        guard let intent = validIntent(for: scope, from: snapshot),
              intent.source == .command
        else { return false }

        let frames = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (UInt32, Rect)? in
            guard entry.scope == scope,
                  intent.placements[entry.window.id] != nil
            else { return nil }
            return (entry.window.id.rawValue, entry.window.frame)
        })
        guard frames.count == intent.placements.count else { return true }

        return !hasMatchingIntent(
            scope: scope,
            frames: frames,
            focusedWindowID: snapshot.focusedWindowID,
            positionTolerance: LayoutTolerance.observedChange,
            sizeTolerance: LayoutTolerance.observedChange,
            focusedPositionTolerance: LayoutTolerance.observedChange,
            focusedSizeTolerance: LayoutTolerance.observedChange,
            allowFocusChromeDelta: false
        )
    }

    func hasValidLayoutIntent(scope: StageScope, in snapshot: DaemonSnapshot) -> Bool {
        validIntent(for: scope, from: snapshot) != nil
    }

    @discardableResult
    func saveCurrentLayoutIntentIfValid(scope: StageScope, from snapshot: DaemonSnapshot) -> Bool {
        guard let stage = snapshot.state.stage(scope: scope),
              stage.mode.isTiled,
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
            requireReasonableTileSizes: stage.mode != .mutableBsp
        ) else { return false }
        intentStore.save(intent)
        return true
    }

    @discardableResult
    func repairMutableBspOrderForCurrentGeometry(
        scopes: Set<StageScope>,
        in snapshot: DaemonSnapshot,
        reason: String
    ) -> Bool {
        guard !scopes.isEmpty else { return false }
        let state = stageStore.state()
        var repaired: [(scope: StageScope, old: [WindowID], new: [WindowID])] = []

        for scope in scopes {
            guard let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .mutableBsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID })
            else { continue }

            let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
            let liveStageWindowIDs = stage.windowIDs.filter { windowsByID[$0] != nil }
            let currentFrames = Dictionary(uniqueKeysWithValues: liveStageWindowIDs.compactMap { id in
                windowsByID[id].map { (id, $0.frame.cgRect) }
            })
            let ordered = spatiallyOrdered(liveStageWindowIDs, frames: currentFrames, container: display.visibleFrame.cgRect)
            guard ordered != liveStageWindowIDs,
                  Set(ordered) == Set(liveStageWindowIDs),
                  state.scopes.contains(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })
            else { continue }

            repaired.append((scope, stage.windowIDs, ordered))
            intentStore.remove(scope: scope)
        }

        guard !repaired.isEmpty else { return false }
        // Réordonne sur l'état relu sous verrou (FR-013) pour ne pas écraser une écriture concurrente.
        stageStore.mutate { state in
            for item in repaired {
                guard var persistentScope = state.scopes.first(where: {
                    $0.displayID == item.scope.displayID && $0.desktopID == item.scope.desktopID
                }) else { continue }
                persistentScope.orderMembers(item.new, in: item.scope.stageID)
                state.update(persistentScope)
            }
        }
        for item in repaired {
            events.append(RoadieEvent(type: "mutable_bsp_order_repaired", scope: item.scope, details: [
                "reason": reason,
                "old": item.old.map { String($0.rawValue) }.joined(separator: ","),
                "new": item.new.map { String($0.rawValue) }.joined(separator: ",")
            ]))
        }
        return true
    }

    func applyPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = []
    ) -> ApplyPlan {
        let plan = layoutPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs,
            mode: mode,
            priorityWindowIDs: priorityWindowIDs
        )
        guard let stage = snapshot.state.stage(scope: scope) else { return ApplyPlan(commands: []) }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        let currentPlan = LayoutPlan(placements: currentFrames)

        let commands = LayoutDiff.commands(previous: currentPlan, next: plan).compactMap { command -> ApplyCommand? in
            guard let window = windowsByID[command.windowID] else { return nil }
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
        let liveOrderedWindowIDs = orderedWindowIDs.filter { windowsByID[$0] != nil }
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        // Fenetres tout juste decouvertes : leur frame macOS est arbitraire, le moteur
        // doit les splitter 50/50 et non heriter de cette frame.
        let newWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.isNewlyScoped ? entry.window.id : nil
        })
        let effectiveMode = mode ?? stage.mode
        // Mode BSP à arbre persistant (SPEC-013) : on reconcilie l'arbre du stage avec les
        // fenêtres réelles (insertion des nouvelles à côté du focus, retrait des disparues),
        // on le persiste si writer autorisé, et on le fournit à la stratégie pour le placement.
        var bspTree: BSPTree? = nil
        if effectiveMode == .spatialBsp {
            bspTree = reconciledBSPTree(
                for: scope,
                liveOrderedWindowIDs: liveOrderedWindowIDs,
                focus: snapshot.focusedWindowID,
                containerIsWide: display.visibleFrame.cgRect.width >= display.visibleFrame.cgRect.height
            )
        }
        return LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: effectiveMode,
            container: display.visibleFrame.cgRect,
            windowIDs: liveOrderedWindowIDs,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs,
            bspTree: bspTree,
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: liveOrderedWindowIDs.count, display: display),
            innerGap: config.tiling.gapsInner
        ))
    }

    /// Reconcilie les arbres BSP de TOUS les stages `.spatialBsp` ayant des fenêtres live,
    /// indépendamment du stage actif ou d'une décision de re-tile. Retourne les scopes dont
    /// l'arbre a changé (nouvelle/fenêtre disparue), pour que l'appelant force un re-tile.
    /// Sans cela, l'arbre d'un stage n'était reconcilié que lors d'un re-tile explicite, donc
    /// une fenêtre ouverte/fermée n'était pas intégrée immédiatement (SPEC-013 fix).
    @discardableResult
    func reconcileSpatialBSPTrees(
        in snapshot: DaemonSnapshot,
        excluding excludedScopes: Set<StageScope> = []
    ) -> Set<StageScope> {
        guard persistStateChanges else { return [] }
        var changedScopes: Set<StageScope> = []
        let scopes = Set(snapshot.windows.compactMap(\.scope))
        let side: BSPInsertionSide = config.windowPlacement.newWindowSide == "left" ? .left : .right
        let currentState = stageStore.state()
        for scope in scopes {
            guard !excludedScopes.contains(scope) else { continue }
            guard let stage = snapshot.state.stage(scope: scope), stage.mode == .spatialBsp,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID })
            else { continue }
            let ordered = orderedWindowIDs(in: scope, from: snapshot)
            guard !ordered.isEmpty else { continue }
            let wide = display.visibleFrame.cgRect.width >= display.visibleFrame.cgRect.height
            let reconcile = { (existing: BSPTree) in
                existing.reconciled(
                    liveWindowIDs: ordered,
                    focus: Self.bspInsertionAnchor(
                        tree: existing,
                        liveWindowIDs: ordered,
                        globalFocus: snapshot.focusedWindowID,
                        scope: scope,
                        state: currentState
                    ),
                    side: side,
                    containerIsWide: wide
                )
            }
            // Pré-contrôle sans verrou : au repos, aucun verrou ni écriture.
            let existing = currentState.bspTree(for: scope) ?? .empty
            guard reconcile(existing) != existing else { continue }
            if persistBSPTree(for: scope, reconcile) {
                changedScopes.insert(scope)
            }
        }
        return changedScopes
    }

    /// Reconcilie l'arbre BSP persistant d'un stage avec les fenêtres réellement présentes.
    /// Persiste l'arbre mis à jour uniquement si ce process est writer (persistStateChanges),
    /// pour ne pas écraser l'état canonique en mode lecteur (SPEC-011/012).
    private func reconciledBSPTree(
        for scope: StageScope,
        liveOrderedWindowIDs: [WindowID],
        focus: WindowID?,
        containerIsWide: Bool
    ) -> BSPTree {
        let state = stageStore.state()
        let existing = state.bspTree(for: scope) ?? .empty
        let side: BSPInsertionSide = config.windowPlacement.newWindowSide == "left" ? .left : .right
        let reconcile = { (tree: BSPTree) in
            tree.reconciled(
                liveWindowIDs: liveOrderedWindowIDs,
                focus: Self.bspInsertionAnchor(
                    tree: tree,
                    liveWindowIDs: liveOrderedWindowIDs,
                    globalFocus: focus,
                    scope: scope,
                    state: state
                ),
                side: side,
                containerIsWide: containerIsWide
            )
        }
        let reconciled = reconcile(existing)
        if persistStateChanges, reconciled != existing {
            persistBSPTree(for: scope, reconcile)
        }
        return reconciled
    }

    /// FR-005 : point d'ancrage BSP d'une nouvelle fenêtre = premier candidat déjà feuille vivante
    /// de l'arbre parmi le focus global, le focus de la stage et son focus précédent ; `nil` sinon
    /// (insertion sur la première feuille). Le focus global seul ne suffit pas : c'est souvent la
    /// nouvelle fenêtre elle-même, et la stage l'a déjà adoptée comme focus (le précédent reste).
    // O(n) - n = feuilles de l'arbre + fenêtres vivantes.
    fileprivate static func bspInsertionAnchor(
        tree: BSPTree,
        liveWindowIDs: [WindowID],
        globalFocus: WindowID?,
        scope: StageScope,
        state: PersistentStageState
    ) -> WindowID? {
        let stage = state.scopes
            .first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
            .stages
            .first { $0.id == scope.stageID }
        let anchors = Set(tree.windowIDs).intersection(liveWindowIDs)
        return [globalFocus, stage?.focusedWindowID, stage?.previousFocusedWindowID]
            .lazy
            .compactMap { $0 }
            .first { anchors.contains($0) }
    }

    /// Recalcule l'arbre sur l'état relu sous verrou et l'écrit s'il change (FR-013).
    @discardableResult
    private func persistBSPTree(for scope: StageScope, _ reconcile: (BSPTree) -> BSPTree) -> Bool {
        stageStore.mutate { state in
            let existing = state.bspTree(for: scope) ?? .empty
            let reconciled = reconcile(existing)
            guard reconciled != existing else { return false }
            state.setBSPTree(reconciled, for: scope)
            return true
        }
    }

    private func validIntent(for scope: StageScope, from snapshot: DaemonSnapshot) -> LayoutIntent? {
        guard let intent = intentStore.intent(for: scope) else { return nil }
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
        guard !framesLeaveLargeUntiledCells(
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

    private func framesLeaveLargeUntiledCells(
        _ frames: [CGRect],
        in container: CGRect,
        allowedGap: CGFloat
    ) -> Bool {
        guard frames.count > 1 else { return false }
        let tolerance = max(LayoutTolerance.untiledCell, allowedGap)
        let xEdges = sortedEdges([container.minX, container.maxX] + frames.flatMap { [$0.minX, $0.maxX] })
        let yEdges = sortedEdges([container.minY, container.maxY] + frames.flatMap { [$0.minY, $0.maxY] })

        for xIndex in 0..<max(0, xEdges.count - 1) {
            let minX = xEdges[xIndex]
            let maxX = xEdges[xIndex + 1]
            let width = maxX - minX
            guard width > tolerance else { continue }
            for yIndex in 0..<max(0, yEdges.count - 1) {
                let minY = yEdges[yIndex]
                let maxY = yEdges[yIndex + 1]
                let height = maxY - minY
                guard height > tolerance else { continue }
                let cell = CGRect(x: minX, y: minY, width: width, height: height)
                guard container.contains(cell, tolerance: 1),
                      !frames.contains(where: { frameContainsCellCenter($0, cell: cell, tolerance: 1) })
                else { continue }
                return true
            }
        }
        return false
    }

    private func frameContainsCellCenter(_ frame: CGRect, cell: CGRect, tolerance: CGFloat) -> Bool {
        let point = CGPoint(x: cell.midX, y: cell.midY)
        return point.x >= frame.minX - tolerance
            && point.y >= frame.minY - tolerance
            && point.x <= frame.maxX + tolerance
            && point.y <= frame.maxY + tolerance
    }

    private func sortedEdges(_ values: [CGFloat]) -> [CGFloat] {
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
            innerGap: config.tiling.gapsInner
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
        let commands = intent.windowIDs.compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let target = intent.placements[id] else {
                return nil
            }
            if id == focusedWindowID,
               isLikelyFocusWindowChromeDelta(window.frame, baseline: target) {
                return nil
            }
            guard !window.frame.isClose(to: target, positionTolerance: 1, sizeTolerance: 1) else {
                return nil
            }
            return ApplyCommand(window: window, frame: target)
        }
        return ApplyPlan(commands: commands)
    }

    func apply(_ plan: ApplyPlan) -> ApplyResult {
        if !plan.commands.isEmpty { invalidateSharedSnapshot() }
        var items: [ApplyResultItem] = []
        let updates = plan.commands.map { command in
            WindowFrameUpdate(window: command.window, frame: command.frame.cgRect)
        }
        let actualFrames = frameWriter.setFrames(updates)

        for command in plan.commands {
            guard let rawActual = actualFrames[command.window.id], let actual = rawActual else {
                items.append(ApplyResultItem(
                    windowID: command.window.id,
                    status: .failed,
                    requested: command.frame,
                    actual: nil
                ))
                continue
            }
            let actualRect = Rect(actual)
            items.append(ApplyResultItem(
                windowID: command.window.id,
                status: actualRect.isClose(
                    to: command.frame,
                    positionTolerance: LayoutTolerance.appliedFrame,
                    sizeTolerance: LayoutTolerance.appliedFrame
                ) ? .applied : .clamped,
                requested: command.frame,
                actual: actualRect
            ))
        }
        var applied = 0, clamped = 0, failed = 0
        for item in items {
            switch item.status {
            case .applied: applied += 1
            case .clamped: clamped += 1
            case .failed: failed += 1
            }
        }
        return ApplyResult(
            attempted: plan.commands.count,
            applied: applied,
            clamped: clamped,
            failed: failed,
            items: items
        )
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        invalidateSharedSnapshot()
        return frameWriter.focus(window)
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

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        invalidateSharedSnapshot()
        return frameWriter.setFrame(frame, of: window)
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
        let sorted = windowIDs.sorted { lhs, rhs in
            spatiallyComesBefore(lhs, rhs, frames: frames, horizontal: horizontal)
        }
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

    func spatiallyComesBefore(
        _ lhs: WindowID,
        _ rhs: WindowID,
        frames: [WindowID: CGRect],
        horizontal: Bool
    ) -> Bool {
        guard let lhsFrame = frames[lhs], let rhsFrame = frames[rhs] else {
            return lhs < rhs
        }
        if horizontal {
            if abs(lhsFrame.midX - rhsFrame.midX) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midX < rhsFrame.midX
            }
            if abs(lhsFrame.midY - rhsFrame.midY) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midY < rhsFrame.midY
            }
        } else {
            if abs(lhsFrame.midY - rhsFrame.midY) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midY < rhsFrame.midY
            }
            if abs(lhsFrame.midX - rhsFrame.midX) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midX < rhsFrame.midX
            }
        }
        return lhs < rhs
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

    private func currentRailSettings() -> RailSettings {
        railSettings ?? RailSettings.load()
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

    func contains(_ other: CGRect, tolerance: CGFloat) -> Bool {
        other.minX >= minX - tolerance
            && other.minY >= minY - tolerance
            && other.maxX <= maxX + tolerance
            && other.maxY <= maxY + tolerance
    }
}

public enum SnapshotEncoding {
    public static func json(_ snapshot: DaemonSnapshot, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ plan: ApplyPlan, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(plan)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ result: ApplyResult, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(result)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ report: StateAuditReport, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ report: StateHealReport, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ report: DaemonHealthReport, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ report: DaemonHealReport, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ metrics: RoadieMetrics, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(metrics)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ dump: TreeDump, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(dump)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Mémoire de processus partagée par les `SnapshotService` d'un même fichier d'état (SPEC-016) :
/// dernier snapshot publié (FR-023), fenêtres vivantes précédentes (FR-009) et dernier classement
/// tilable lisible (FR-008). La clé est le chemin du fichier d'état : les tests, qui injectent
/// chacun leur `StageStore`, restent isolés.
final class SnapshotProcessState: @unchecked Sendable {
    /// Validité du snapshot partagé : couvre la bordure (120 ms) et le focus-souris (100 ms).
    static let sharedSnapshotMaxAge: TimeInterval = 0.15
    /// Marge ajoutée à l'intervalle du tiler pour qu'un tick en retard ne force pas de rescan.
    static let producerMargin: TimeInterval = 0.1
    /// Validité maximale d'un snapshot du tiler, quel que soit son intervalle.
    static let producerMaxAgeCap: TimeInterval = 0.6

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
    }

    private let lock = NSLock()
    /// Clé : option `followFocus` du snapshot publié.
    private var published: [Bool: Published] = [:]
    private var liveWindowIDs: Set<WindowID>?
    private var lastDisappearanceAt: Date?
    private var tileClassification: [WindowID: Bool] = [:]

    func publish(_ snapshot: DaemonSnapshot, followFocus: Bool, maxAge: TimeInterval, at date: Date, stateStamp: [Int64], config: RoadieConfig) {
        lock.withLock {
            published[followFocus] = Published(snapshot: snapshot, maxAge: maxAge, at: date, stateStamp: stateStamp, config: config)
        }
    }

    /// Dernier snapshot publié s'il est récent et que ni l'état persisté ni la config n'ont changé.
    func recentSnapshot(followFocus: Bool, now: Date, stateStamp: [Int64], config: RoadieConfig) -> DaemonSnapshot? {
        lock.withLock {
            guard let entry = published[followFocus] else { return nil }
            let age = now.timeIntervalSince(entry.at)
            guard age >= 0, age < entry.maxAge,
                  entry.stateStamp == stateStamp,
                  entry.config == config
            else { return nil }
            return entry.snapshot
        }
    }

    func invalidatePublished() {
        lock.withLock { published.removeAll() }
    }

    /// Enregistre les fenêtres gérées vivantes ; renvoie la date de la dernière disparition vue.
    // O(n)
    func recordLiveWindows(_ ids: Set<WindowID>, now: Date) -> Date? {
        lock.withLock {
            if let previous = liveWindowIDs, !previous.isSubset(of: ids) {
                lastDisappearanceAt = now
            }
            liveWindowIDs = ids
            return lastDisappearanceAt
        }
    }

    /// Hystérésis du classement tilable (FR-008) : une fenêtre dont les attributs AX sont tous
    /// illisibles (application lente) garde son dernier classement obtenu avec des attributs lisibles.
    /// Les critères CoreGraphics bruts (taille, layer) restent prioritaires.
    // O(n)
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
