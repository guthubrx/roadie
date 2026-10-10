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
    private let service: SnapshotService
    private let events: EventLog
    private let intervalSeconds: TimeInterval
    private let commandIntentHoldSeconds: TimeInterval
    private let manualResizeDebounceSeconds: TimeInterval
    private let displayDriftReconcileHoldSeconds: TimeInterval
    private let stageMembershipSettleSeconds: TimeInterval
    private let now: () -> Date
    private let staticRuleEngine: WindowRuleEngine?
    private let store: StageStore
    private let dragActivity: WindowDragActivity
    private let commandActivity: LayoutCommandActivity
    /// Vrai tant qu'un bouton de souris est enfoncé (FR-010). Injectable pour les tests.
    private let mouseButtonsPressed: () -> Bool
    private var cachedRuleEngine: WindowRuleEngine?
    private var cachedRulesVersion: String?
    private var clampedFrames: [UInt32: ClampedFrame] = [:]
    private var failedFrames: [UInt32: FailedFrame] = [:]
    private var revertedAppliedFrames: [UInt32: RevertedAppliedFrame] = [:]
    private var lastObservedFrames: [UInt32: Rect]?
    /// Fenêtres en plein écran (natif ou zoom de commande), relues au début de chaque tick.
    private var tickFullscreen: [(entry: ScopedWindowSnapshot, display: DisplaySnapshot)] = []
    /// Scopes exclus du tick en cours (R6) : plein écran, stabilisation, commande en cours.
    private var tickExcludedScopes: Set<StageScope> = []
    private var priorityWindowIDs: Set<WindowID> = []
    private var lastCommandIntentAt: Date?
    private var manualResizeApplyAfter: Date?
    private var lastDisplaySignature: String?
    private var lastDisplayTopologyChangedAt: Date?
    private var displayTopologySettlesUntil: Date?
    private var emittedRuleSkippedKeys: Set<String> = []
    private var emittedRuleAppliedKeys: Set<String> = []
    private var emittedRulePlacementIssueKeys: Set<String> = []
    private var observedRulePlacementWindowIDs: Set<WindowID> = []
    private var lastGrowthClampedExcludedWindowIDs: Set<WindowID> = []
    private var lastCommandActivitySuppressedAt: Date?
    private var lastMutableBspSuppressionSignature: String?
    private var lastActiveTiledStageMembershipSignatures: [StageScope: String] = [:]
    private var activeTiledStageMembershipChangedAt: [StageScope: Date] = [:]
    private var lastStageMembershipSettlingSignature: String?

    public init(
        service: SnapshotService = SnapshotService(),
        events: EventLog = EventLog(),
        intervalSeconds: TimeInterval = 0.5,
        ruleEngine: WindowRuleEngine? = nil,
        store: StageStore? = nil,
        dragActivity: WindowDragActivity = .shared,
        commandActivity: LayoutCommandActivity = .shared,
        mouseButtonsPressed: (() -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.events = events
        self.intervalSeconds = intervalSeconds
        self.commandIntentHoldSeconds = LayoutTolerance.commandIntentHold.seconds(intervalSeconds: intervalSeconds)
        self.manualResizeDebounceSeconds = LayoutTolerance.manualResizeDebounce.seconds(intervalSeconds: intervalSeconds)
        self.displayDriftReconcileHoldSeconds = LayoutTolerance.displayDriftReconcileHold.seconds(intervalSeconds: intervalSeconds)
        self.stageMembershipSettleSeconds = LayoutTolerance.stageMembershipSettle.seconds(intervalSeconds: intervalSeconds)
        self.staticRuleEngine = ruleEngine
        self.store = store ?? service.effectiveStageStore
        self.dragActivity = dragActivity
        self.commandActivity = commandActivity
        // Sous les tests, la souris réelle de la machine ne doit pas suspendre les ticks.
        self.mouseButtonsPressed = mouseButtonsPressed
            ?? (TestEnvironment.isRunningTests ? { false } : { NSEvent.pressedMouseButtons != 0 })
        self.now = now
    }

    public func tick() -> MaintenanceTick {
        // Snapshot du tick publié comme source partagée du cycle (FR-023, T212).
        let snapshot = service.producerSnapshot(cycle: intervalSeconds)
        guard snapshot.permissions.accessibilityTrusted else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        let tickNow = now()
        forgetExpiredRefusals(liveWindowIDs: Set(snapshot.windows.map(\.window.id.rawValue)), now: tickNow)
        // Plein écran lu une seule fois, avant tout calcul de plan (R5).
        tickFullscreen = fullscreenEntries(in: snapshot)
        tickExcludedScopes = []
        let observedFramesForChurn = scopedFrames(in: snapshot)
        let changedWindowIDsForChurn = changedWindows(in: observedFramesForChurn)
        let settlingLayoutScopes = activeTiledStageMembershipSettlingScopes(
            in: snapshot,
            changedWindowIDs: changedWindowIDsForChurn,
            now: tickNow
        )
        // SPEC-013/014 : reconcilie les arbres BSP persistants de tous les stages spatial_bsp
        // (intègre les fenêtres ouvertes/fermées). Si un arbre change, on invalide l'intent du
        // scope pour forcer un re-tile immédiat depuis l'arbre, sans attendre un autre déclencheur.
        let changedTreeScopes = service.reconcileSpatialBSPTrees(in: snapshot, excluding: settlingLayoutScopes)
        for scope in changedTreeScopes {
            service.removeLayoutIntent(scope: scope)
        }
        let currentDisplaySignature = displaySignature(snapshot.displays)
        if let lastDisplaySignature, lastDisplaySignature != currentDisplaySignature {
            self.lastDisplaySignature = currentDisplaySignature
            lastDisplayTopologyChangedAt = tickNow
            displayTopologySettlesUntil = tickNow.addingTimeInterval(
                LayoutTolerance.displayTopologySettle.seconds(intervalSeconds: intervalSeconds)
            )
            lastObservedFrames = scopedFrames(in: snapshot)
            clampedFrames.removeAll()
            failedFrames.removeAll()
            revertedAppliedFrames.removeAll()
            lastMutableBspSuppressionSignature = nil
            events.append(RoadieEvent(type: "display.topology_settling", details: [
                "from": lastDisplaySignature,
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
        if dragActivity.isActive(now: tickNow) {
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        if mouseButtonsPressed() {
            // FR-010 : aucun plan tant qu'un bouton est enfoncé (resize par un bord, clic long).
            // Référence d'observation et priorité conservées : le geste est traité au relâchement.
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }

        // Scopes exclus de ce tick : chaque garde exclut son scope au lieu d'arrêter tout le tick
        // (R6, FR-040). Leur référence d'observation est mise à jour, celle des autres scopes non.
        if !settlingLayoutScopes.isEmpty {
            tickExcludedScopes.formUnion(settlingLayoutScopes)
            observe(observedFramesForChurn, scopes: settlingLayoutScopes, in: snapshot)
            appendStageMembershipSettlingEvent(scopes: settlingLayoutScopes)
        }
        let missingMemberReclaimScopes = activeTiledScopesWithRecentMissingMembers(in: snapshot, now: tickNow)
        if let activity = commandActivity.activity(now: tickNow) {
            let activeUntil = String(activity.activeUntil.timeIntervalSince1970)
            if activity.isGlobal && missingMemberReclaimScopes.isEmpty {
                // Commande sans scope connu (globale) : tick suspendu.
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                lastObservedFrames = scopedFrames(in: snapshot)
                if lastCommandActivitySuppressedAt.map({ tickNow.timeIntervalSince($0) > LayoutTolerance.repeatedEventInterval }) ?? true {
                    lastCommandActivitySuppressedAt = tickNow
                    events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: [
                        "activeUntil": activeUntil
                    ]))
                }
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }
            // Seuls les scopes touchés par la commande sont exclus (tous si elle est globale), sauf
            // ceux qui ont perdu un membre et doivent être repris (FR-040).
            let commandScopes = activeScopes(in: snapshot)
                .filter(activity.covers)
                .subtracting(missingMemberReclaimScopes)
            tickExcludedScopes.formUnion(commandScopes)
            observe(observedFramesForChurn, scopes: commandScopes, in: snapshot)
            if activity.isGlobal {
                events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: [
                    "activeUntil": activeUntil,
                    "bypassedForMissingReclaim": "true",
                    "scopes": missingMemberReclaimScopes.map(\.description).sorted().joined(separator: ",")
                ]))
            } else if !commandScopes.isEmpty,
                      lastCommandActivitySuppressedAt.map({ tickNow.timeIntervalSince($0) > LayoutTolerance.repeatedEventInterval }) ?? true {
                lastCommandActivitySuppressedAt = tickNow
                events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: [
                    "activeUntil": activeUntil,
                    "commandScopes": commandScopes.map(\.description).sorted().joined(separator: ",")
                ]))
            }
        }
        let rulePlacements = evaluateRules(in: snapshot)
        if rulePlacements > 0 {
            return MaintenanceTick(commands: rulePlacements, applied: rulePlacements, clamped: 0, failed: 0)
        }

        let restoredPins = restoreVisiblePinnedWindows(in: snapshot)
        if restoredPins > 0 {
            events.append(RoadieEvent(type: "window.pin_restored", details: ["applied": String(restoredPins)]))
            return MaintenanceTick(commands: restoredPins, applied: restoredPins, clamped: 0, failed: 0)
        }

        if let focusRestore = restoreFocusedActiveStageIfNeeded(
            in: snapshot,
            observedFrames: observedFramesForChurn
        ) {
            return focusRestore
        }

        let reanchoredZoomed = reanchorShiftedZoomedWindows(in: snapshot)
        if reanchoredZoomed > 0 {
            events.append(RoadieEvent(type: "fullscreen_sized_windows_reanchored", details: [
                "applied": String(reanchoredZoomed)
            ]))
            return MaintenanceTick(commands: reanchoredZoomed, applied: reanchoredZoomed, clamped: 0, failed: 0)
        }

        let hiddenFullscreenSiblings = hideActiveStageSiblingsOfFullscreenWindows(in: snapshot)
        if hiddenFullscreenSiblings > 0 {
            events.append(RoadieEvent(type: "fullscreen_stage_siblings_hidden", details: [
                "applied": String(hiddenFullscreenSiblings)
            ]))
            return MaintenanceTick(commands: hiddenFullscreenSiblings, applied: hiddenFullscreenSiblings, clamped: 0, failed: 0)
        }

        // Plein écran natif ou zoom de commande : seul son scope est exclu (FR-016).
        let fullscreenScopes = Set(tickFullscreen.compactMap(\.entry.scope))
        if !fullscreenScopes.isEmpty {
            tickExcludedScopes.formUnion(fullscreenScopes)
            observe(observedFramesForChurn, scopes: fullscreenScopes, in: snapshot)
            handleFullscreenScopeChanges(
                in: snapshot,
                changedWindowIDs: changedWindowIDsForChurn,
                fullscreenScopes: fullscreenScopes
            )
        }

        let hiddenInactive = hideInactiveStageWindows(in: snapshot)
        if hiddenInactive > 0 {
            events.append(RoadieEvent(type: "stage_hide_inactive", details: ["applied": String(hiddenInactive)]))
            return MaintenanceTick(commands: hiddenInactive, applied: hiddenInactive, clamped: 0, failed: 0)
        }

        let observedFrames = observedFramesForChurn
        let changedWindowIDs = windowIDs(changedWindowIDsForChurn, outside: tickExcludedScopes, in: snapshot)
        let unexcludedPriorityWindowIDs = windowIDs(priorityWindowIDs, outside: tickExcludedScopes, in: snapshot)
        if unexcludedPriorityWindowIDs != priorityWindowIDs {
            priorityWindowIDs = unexcludedPriorityWindowIDs
            if priorityWindowIDs.isEmpty {
                manualResizeApplyAfter = nil
            }
        }
        let now = now()
        let cutoff = now.addingTimeInterval(-commandIntentHoldSeconds)

        if !changedWindowIDs.isEmpty {
            if changedFramesMatchSavedIntent(in: snapshot, frames: observedFrames, changedWindowIDs: changedWindowIDs) {
                lastObservedFrames = observedFrames
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }

            if let tick = adoptManualDisplayMoves(in: snapshot, changedWindowIDs: changedWindowIDs) {
                lastObservedFrames = scopedFrames(in: service.snapshot(followFocus: false))
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                return tick
            }

            let modeledScopes = authoritativeModelScopes(for: changedWindowIDs, in: snapshot)
            if !modeledScopes.isEmpty {
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                let tick = applyPlan(from: snapshot, observedFrames: observedFrames, excluding: tickExcludedScopes)
                events.append(RoadieEvent(type: "external_geometry_snapped_to_layout_model", details: [
                    "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                    "scopes": modeledScopes.map(\.description).sorted().joined(separator: ","),
                    "commands": String(tick.commands)
                ]))
                return tick
            }

            if let tick = adoptMutableBspGeometryChange(
                in: snapshot,
                changedWindowIDs: changedWindowIDs
            ) {
                return tick
            }

            if changedWindowIDs.count >= 2 {
                lastObservedFrames = observedFrames
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }

            priorityWindowIDs = changedWindowIDs
            manualResizeApplyAfter = now.addingTimeInterval(manualResizeDebounceSeconds)
            removeLayoutIntents(for: changedWindowIDs, in: snapshot)
            lastObservedFrames = observedFrames
            events.append(RoadieEvent(type: "manual_resize_detected", details: [
                "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                "applyAfter": String(manualResizeApplyAfter?.timeIntervalSince1970 ?? 0)
            ]))
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }

        if let tick = reconcileStableVisibleDisplayDrift(in: snapshot, excluding: tickExcludedScopes) {
            return tick
        }

        if let manualResizeApplyAfter, now < manualResizeApplyAfter {
            lastObservedFrames = observedFrames
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }
        manualResizeApplyAfter = nil

        let commandProtectedScopes = priorityWindowIDs.isEmpty
            ? recentCommandScopes(in: snapshot, since: cutoff, now: now)
            : []
        // Un scope exclu (plein écran, stabilisation) garde son intent : pas de contrôle de dérive.
        let strictCommandProtectedScopes = strictAuthoritativeScopes(commandProtectedScopes, in: snapshot)
            .subtracting(tickExcludedScopes)
        if !strictCommandProtectedScopes.isEmpty {
            let driftedScopes = driftedCommandScopes(strictCommandProtectedScopes, frames: observedFrames)
            if !driftedScopes.isEmpty {
                for scope in driftedScopes {
                    service.removeLayoutIntent(scope: scope)
                }
                lastCommandIntentAt = nil
                let remainingProtectedScopes = strictCommandProtectedScopes.subtracting(driftedScopes)
                let tick = applyPlan(
                    from: snapshot,
                    observedFrames: observedFrames,
                    excluding: remainingProtectedScopes.union(tickExcludedScopes)
                )
                events.append(RoadieEvent(type: "command_intent_invalidated_by_manual_geometry", details: [
                    "scopes": driftedScopes.map(\.description).sorted().joined(separator: ","),
                    "remainingProtectedScopes": remainingProtectedScopes.map(\.description).sorted().joined(separator: ","),
                    "commands": String(tick.commands)
                ]))
                return tick
            }
            lastCommandIntentAt = now
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            let tick = applyPlan(
                from: snapshot,
                observedFrames: observedFrames,
                excluding: strictCommandProtectedScopes.union(tickExcludedScopes),
                updateBaselineWhenEmpty: false
            )
            events.append(RoadieEvent(type: "manual_resize_suppressed_by_command_intent", details: [
                "scopes": strictCommandProtectedScopes.map(\.description).sorted().joined(separator: ","),
                "unprotectedCommands": String(tick.commands)
            ]))
            return tick
        }

        if let lastCommandIntentAt,
           priorityWindowIDs.isEmpty,
           now.timeIntervalSince(lastCommandIntentAt) < commandIntentHoldSeconds
        {
            let protectedScopes = strictAuthoritativeScopes(
                recentCommandScopes(in: snapshot, since: cutoff, now: now),
                in: snapshot
            ).subtracting(tickExcludedScopes)
            let driftedScopes = driftedCommandScopes(protectedScopes, frames: observedFrames)
            if !driftedScopes.isEmpty {
                for scope in driftedScopes {
                    service.removeLayoutIntent(scope: scope)
                }
                self.lastCommandIntentAt = nil
                let remainingProtectedScopes = protectedScopes.subtracting(driftedScopes)
                let tick = applyPlan(
                    from: snapshot,
                    observedFrames: observedFrames,
                    excluding: remainingProtectedScopes.union(tickExcludedScopes)
                )
                events.append(RoadieEvent(type: "command_intent_invalidated_by_manual_geometry", details: [
                    "scopes": driftedScopes.map(\.description).sorted().joined(separator: ","),
                    "remainingProtectedScopes": remainingProtectedScopes.map(\.description).sorted().joined(separator: ","),
                    "commands": String(tick.commands)
                ]))
                return tick
            }
            priorityWindowIDs = []
            return applyPlan(
                from: snapshot,
                observedFrames: observedFrames,
                excluding: protectedScopes.union(tickExcludedScopes),
                updateBaselineWhenEmpty: false
            )
        }

        let repairedPlanningSnapshot = repairMutableBspOrderBeforePriorityApplyIfNeeded(
            snapshot: snapshot,
            priorityWindowIDs: priorityWindowIDs
        )
        let planningSnapshot = snapshotExcludingGrowthClampedWindows(repairedPlanningSnapshot ?? snapshot)
        let planningObservedFrames = repairedPlanningSnapshot.map { scopedFrames(in: $0) } ?? observedFrames
        let plan = suppressKnownUnmovableFrames(
            in: plannedCommands(from: planningSnapshot, priorityWindowIDs: priorityWindowIDs),
            snapshot: planningSnapshot
        )
        let protectedMutableScopes = priorityWindowIDs.isEmpty
            ? stableVisibleMutableBspScopes(in: planningSnapshot)
            : []
        let protectedLayoutScopes = protectedMutableScopes.union(tickExcludedScopes)
        lastObservedFrames = planningObservedFrames
        let windowsByID = Dictionary(uniqueKeysWithValues: planningSnapshot.windows.map { ($0.window.id, $0) })
        let filteredPlan = ApplyPlan(commands: plan.commands.filter { command in
            guard let scope = windowsByID[command.window.id]?.scope else { return true }
            return !protectedLayoutScopes.contains(scope)
        })
        if !protectedMutableScopes.isEmpty && filteredPlan.commands.count != plan.commands.count {
            appendMutableBspSuppressionEvent(
                scopes: protectedMutableScopes,
                suppressed: plan.commands.count - filteredPlan.commands.count
            )
        }
        guard !filteredPlan.commands.isEmpty else {
            persistCurrentLayoutIntents(in: planningSnapshot, excluding: tickExcludedScopes)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        let application = applyRepairingClamps(filteredPlan, in: planningSnapshot)
        if application.result.clamped == 0 && application.result.failed == 0 {
            persistLayoutIntent(in: planningSnapshot, result: application.result)
        }
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(application.commands),
            "applied": String(application.result.applied),
            "clamped": String(application.result.clamped),
            "failed": String(application.result.failed),
            "priorityWindowIDs": priorityWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ",")
        ]))
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = framesAfterApplying(application.result, fallback: planningObservedFrames)
        return application.tick
    }

    private func applyPlan(
        from snapshot: DaemonSnapshot,
        observedFrames: [UInt32: Rect],
        excluding protectedScopes: Set<StageScope>,
        updateBaselineWhenEmpty: Bool = true
    ) -> MaintenanceTick {
        let planningSnapshot = snapshotExcludingGrowthClampedWindows(snapshot)
        let windowsByID = Dictionary(uniqueKeysWithValues: planningSnapshot.windows.map { ($0.window.id, $0) })
        let plan = suppressKnownUnmovableFrames(
            in: plannedCommands(from: planningSnapshot, priorityWindowIDs: priorityWindowIDs),
            snapshot: planningSnapshot
        )
        let filtered = ApplyPlan(commands: plan.commands.filter { command in
            guard let scope = windowsByID[command.window.id]?.scope else { return true }
            return !protectedScopes.contains(scope)
        })
        guard !filtered.commands.isEmpty else {
            if updateBaselineWhenEmpty || lastObservedFrames == nil {
                lastObservedFrames = observedFrames
            }
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        let application = applyRepairingClamps(filtered, in: planningSnapshot)
        if application.result.clamped == 0 && application.result.failed == 0 {
            persistLayoutIntent(in: planningSnapshot, result: application.result)
        }
        lastObservedFrames = framesAfterApplying(application.result, fallback: observedFrames)
        return application.tick
    }

    /// Résultat du bloc « appliquer, réparer, isoler, émettre ».
    private struct PlanApplication {
        var result: ApplyResult
        /// Commandes envoyées : plan, réparation des voisines et résolution des scopes infaisables.
        var commands: Int

        var tick: MaintenanceTick {
            MaintenanceTick(commands: commands, applied: result.applied, clamped: result.clamped, failed: result.failed)
        }
    }

    /// Bloc unique « appliquer, réparer, isoler, émettre » (FR-040) : applique le plan, recale les
    /// fenêtres clampées, replace leurs voisines, résout les scopes infaisables, mémorise les refus
    /// et émet les événements par fenêtre.
    private func applyRepairingClamps(
        _ plan: ApplyPlan,
        in snapshot: DaemonSnapshot,
        source: String? = nil
    ) -> PlanApplication {
        var result = stabilizeClampedPositions(service.apply(plan), from: plan, in: snapshot)
        let repairPlan = clampedSiblingRepairPlan(from: result, in: snapshot)
        if !repairPlan.commands.isEmpty {
            let repairResult = stabilizeClampedPositions(service.apply(repairPlan), from: repairPlan, in: snapshot)
            result = result.merged(with: repairResult)
            var details = [
                "commands": String(repairPlan.commands.count),
                "windowIDs": repairPlan.commands
                    .map { String($0.window.id.rawValue) }
                    .sorted()
                    .joined(separator: ",")
            ]
            if let source {
                details["source"] = source
            }
            events.append(RoadieEvent(type: "layout_clamped_scope_repaired", details: details))
        }
        let resolution = resolveInfeasibleClampedScopes(from: result, in: snapshot)
        result = result.merged(with: resolution.result)
        let commands = plan.commands + repairPlan.commands + resolution.commands
        record(result, from: ApplyPlan(commands: commands))
        appendItemEvents(result)
        if result.applied > 0 || result.clamped > 0 || result.failed > 0 {
            lastMutableBspSuppressionSignature = nil
        }
        result.applied += resolution.hidden
        return PlanApplication(result: result, commands: commands.count + resolution.hidden)
    }

    /// Plan du service sans les écrans dont le scope actif est exclu du tick : le planificateur ne
    /// touche ni les fenêtres ni les intents de ces scopes (R6). O(d + plan).
    private func plannedCommands(
        from snapshot: DaemonSnapshot,
        priorityWindowIDs: Set<WindowID> = []
    ) -> ApplyPlan {
        var planning = snapshot
        if !tickExcludedScopes.isEmpty {
            planning.displays.removeAll { display in
                snapshot.state.activeScope(on: display.id).map { tickExcludedScopes.contains($0) } ?? false
            }
        }
        return service.applyPlan(from: planning, priorityWindowIDs: priorityWindowIDs)
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

    /// Note dans la référence d'observation un cadre posé par Roadie, pour ne pas le prendre
    /// au tick suivant pour un changement manuel.
    private func recordObservedFrame(_ frame: CGRect, of windowID: WindowID) {
        lastObservedFrames?[windowID.rawValue] = Rect(frame)
    }

    private func activeScopes(in snapshot: DaemonSnapshot) -> Set<StageScope> {
        Set(snapshot.displays.compactMap { snapshot.state.activeScope(on: $0.id) })
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

    public func run(maxTicks: Int? = nil, onTick: (MaintenanceTick) -> Void = { _ in }) {
        var ticks = 0
        while maxTicks.map({ ticks < $0 }) ?? true {
            let result = tick()
            onTick(result)
            ticks += 1
            Thread.sleep(forTimeInterval: intervalSeconds)
        }
    }

    public static func defaultRuleEngine() -> WindowRuleEngine? {
        let config = ConfigReloadService.shared.currentConfig()
        guard !config.rules.isEmpty else {
            return nil
        }
        return WindowRuleEngine(rules: config.rules)
    }

    private func currentRuleEngine() -> WindowRuleEngine? {
        if let staticRuleEngine {
            return staticRuleEngine
        }
        let version = RoadieConfigLoader.rulesVersion()
        if cachedRulesVersion != version {
            cachedRulesVersion = version
            cachedRuleEngine = Self.defaultRuleEngine()
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

    private func evaluateRules(in snapshot: DaemonSnapshot) -> Int {
        guard let ruleEngine = currentRuleEngine() else { return 0 }
        guard ruleEngine.validationErrors.isEmpty else {
            appendRuleFailedEvents(ruleEngine.validationErrors)
            return 0
        }
        var placements = 0
        let liveWindowIDs = Set(snapshot.windows.map(\.window.id))
        observedRulePlacementWindowIDs.formIntersection(liveWindowIDs)
        pruneRuleEventKeys(keeping: liveWindowIDs)
        for entry in snapshot.windows where entry.window.isOnScreen {
            let context = WindowRuleMatchContext(
                display: entry.scope?.displayID.rawValue,
                desktop: entry.scope.map { String($0.desktopID.rawValue) },
                stage: entry.scope?.stageID.rawValue
            )
            let application = ruleEngine.evaluate(window: entry.window, context: context)
            appendRuleEvents(application, window: entry.window)
            if applyRulePlacement(application, entry: entry, snapshot: snapshot) {
                placements += 1
            }
            observedRulePlacementWindowIDs.insert(entry.window.id)
        }
        return placements
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
    ) -> Bool {
        guard application.matchedRuleID != nil,
              application.assignDisplay != nil || application.assignDesktop != nil || application.assignStage != nil
        else { return false }
        guard !application.excluded else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "excluded")
            return false
        }
        guard entry.window.isTileCandidate else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "not a tile candidate")
            return false
        }
        guard !observedRulePlacementWindowIDs.contains(entry.window.id) else {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "window already managed")
            return false
        }

        // Décision et écriture dans une seule transaction sur l'état relu sous verrou (SPEC-016
        // FR-013). Une copie de travail n'est conservée qu'en cas de placement : les branches de
        // refus n'écrivent rien. Événements et AX après le bloc (verrou non réentrant).
        enum PlacementDecision {
            case skipped(String, StageScope?)
            case deferred
            case placed(RulePlacementDestination, activeScope: StageScope)
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
            return .placed(destination, activeScope: working.activeScopeEquivalent(on: destination.scope.displayID))
        }
        let destination: RulePlacementDestination
        let activeScope: StageScope
        switch decision {
        case .skipped(let reason, let target):
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, destination: target, reason: reason)
            return false
        case .deferred:
            appendPlacementEvent("rule.placement_deferred", application: application, entry: entry, reason: "destination unavailable")
            return false
        case .placed(let placed, let active):
            destination = placed
            activeScope = active
        }

        let sourceScope = entry.scope

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: destination.scope)

        if !destination.follow {
            if activeScope != destination.scope {
                _ = service.setFrame(HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: destination.display, among: snapshot.displays), of: entry.window)
            }
        }

        let result = service.apply(service.applyPlan(from: service.snapshot(followFocus: false)))
        if destination.follow {
            _ = service.focus(entry.window)
        }
        appendPlacementEvent(
            "rule.placement_applied",
            application: application,
            entry: entry,
            destination: destination.scope,
            reason: "placed",
            extra: ["layout": .int(result.attempted)]
        )
        return true
    }

    private func adoptManualDisplayMoves(
        in snapshot: DaemonSnapshot,
        changedWindowIDs: Set<WindowID>
    ) -> MaintenanceTick? {
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

        guard !adopted.isEmpty else { return nil }

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

        let updatedSnapshot = service.snapshot(followFocus: false)
        let plan = suppressKnownUnmovableFrames(
            in: plannedCommands(from: updatedSnapshot, priorityWindowIDs: Set(adopted.map(\.window.id))),
            snapshot: updatedSnapshot
        )
        let result = service.apply(plan)
        record(result, from: plan)
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "reason": "manual_display_move_adopted",
            "priorityWindowIDs": adopted.map { String($0.window.id.rawValue) }.sorted().joined(separator: ",")
        ]))
        appendItemEvents(result)
        return MaintenanceTick(
            commands: max(adopted.count, plan.commands.count),
            applied: adopted.count + result.applied,
            clamped: result.clamped,
            failed: result.failed
        )
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
            display: display,
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

    private func suppressKnownUnmovableFrames(in plan: ApplyPlan, snapshot: DaemonSnapshot) -> ApplyPlan {
        let cutoff = now().addingTimeInterval(-LayoutTolerance.recentRefusal.seconds(intervalSeconds: intervalSeconds))
        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        let fullscreenScopes = Set(tickFullscreen.compactMap(\.entry.scope))
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
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
               known.appliedAt >= cutoff,
               known.matches(command: command) {
                return nil
            }
            return command
        })
    }

    /// Oublie les refus de taille et les échecs de plus de 30 s, et ceux des fenêtres disparues
    /// (FR-004). O(r) — r refus mémorisés.
    private func forgetExpiredRefusals(liveWindowIDs: Set<UInt32>, now: Date) {
        let oldest = now.addingTimeInterval(-LayoutTolerance.refusalMemorySeconds)
        clampedFrames = clampedFrames.filter { liveWindowIDs.contains($0.key) && $0.value.recordedAt >= oldest }
        failedFrames = failedFrames.filter { liveWindowIDs.contains($0.key) && $0.value.recordedAt >= oldest }
        revertedAppliedFrames = revertedAppliedFrames.filter { liveWindowIDs.contains($0.key) }
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

    private func record(_ result: ApplyResult, from plan: ApplyPlan) {
        let commandsByID = plan.commands.reduce(into: [WindowID: ApplyCommand]()) { result, command in
            result[command.window.id] = command
        }
        for item in result.items {
            switch item.status {
            case .clamped:
                if let actual = item.actual {
                    clampedFrames[item.windowID.rawValue] = ClampedFrame(
                        requested: item.requested,
                        actual: actual,
                        recordedAt: now()
                    )
                }
                revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
            case .applied:
                clampedFrames.removeValue(forKey: item.windowID.rawValue)
                failedFrames.removeValue(forKey: item.windowID.rawValue)
                if let command = commandsByID[item.windowID],
                   !command.window.frame.isClose(to: item.requested, tolerance: LayoutTolerance.frameMatch) {
                    revertedAppliedFrames[item.windowID.rawValue] = RevertedAppliedFrame(
                        requested: item.requested,
                        observedBeforeApply: command.window.frame,
                        appliedAt: now()
                    )
                } else {
                    revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
                }
            case .failed:
                if let command = commandsByID[item.windowID] {
                    failedFrames[item.windowID.rawValue] = FailedFrame(
                        requested: item.requested,
                        observedAtFailure: command.window.frame,
                        recordedAt: now()
                    )
                }
                revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
            }
        }
    }

    private func appendItemEvents(_ result: ApplyResult) {
        for item in result.items {
            switch item.status {
            case .clamped:
                events.append(RoadieEvent(type: "layout_clamped", details: [
                    "windowID": String(item.windowID.rawValue),
                    "requested": frameDescription(item.requested),
                    "actual": item.actual.map(frameDescription) ?? "-"
                ]))
            case .failed:
                events.append(RoadieEvent(type: "layout_failed", details: [
                    "windowID": String(item.windowID.rawValue),
                    "requested": frameDescription(item.requested)
                ]))
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
                  let stabilized = service.setFrame(anchored.cgRect, of: command.window)
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
            let siblingIDs = stage.windowIDs.filter { id in
                siblingEntries.contains { $0.window.id == id }
            }
            guard !siblingIDs.isEmpty else { continue }

            let currentFrames = siblingEntries.reduce(into: [WindowID: CGRect]()) { result, entry in
                result[entry.window.id] = entry.window.frame.cgRect
            }
            let mode: WindowManagementMode = stage.mode == .spatialBsp ? .mutableBsp : stage.mode
            let plan = LayoutPlanner.plan(LayoutRequest(
                scope: scope,
                mode: mode,
                container: repairContainer.integral,
                windowIDs: siblingIDs,
                currentFrames: currentFrames,
                priorityWindowIDs: [],
                newWindowIDs: [],
                splitPolicy: service.effectiveConfig.tiling.splitPolicy,
                innerGap: service.innerGap()
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

    /// Scopes actifs où au moins deux fenêtres clampées se chevauchent ou débordent encore.
    /// Replanifie avec les tailles minimales connues ; garde la fenêtre focalisée et cache les
    /// autres seulement si aucune disposition n'existe (dernier recours journalisé, FR-003).
    // O(s · n³) au pire — s scopes concernés, n fenêtres par scope (n petit).
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

        for (optionalScope, scopedClampedItems) in clampedScopes {
            guard let scope = optionalScope,
                  scopedClampedItems.count >= 2,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled,
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
            var minimumSizes = orderedIDs.reduce(into: [WindowID: CGSize]()) { sizes, id in
                sizes[id] = knownMinimumSize(of: id, in: result)
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
                let attempt = service.apply(plan)
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
                if service.setFrame(frame, of: entry.window) != nil {
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

    /// Taille minimale connue d'une fenêtre : refus de ce résultat et refus mémorisés. O(r).
    private func knownMinimumSize(of windowID: WindowID, in result: ApplyResult) -> CGSize {
        var size = CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide)
        if let known = clampedFrames[windowID.rawValue] {
            size = Self.largest(size, Self.minimumSize(requested: known.requested, actual: known.actual))
        }
        for item in result.items where item.windowID == windowID && item.status == .clamped {
            if let actual = item.actual {
                size = Self.largest(size, Self.minimumSize(requested: item.requested, actual: actual))
            }
        }
        return size
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

    private func persistLayoutIntent(in snapshot: DaemonSnapshot, result: ApplyResult) {
        let resultFrames = Dictionary(uniqueKeysWithValues: result.items.compactMap { item -> (WindowID, Rect)? in
            guard item.status == .applied else { return nil }
            return (item.windowID, item.actual ?? item.requested)
        })
        let touchedScopes = Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard let scope = entry.scope,
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
            for (id, frame) in resultFrames {
                placements[id] = frame
            }
            guard Set(placements.keys) == Set(stage.windowIDs) else { continue }
            let orderedIDs = stage.mode == .mutableBsp
                ? service.orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
                : stage.windowIDs
            service.saveLayoutIntent(scope: scope, windowIDs: orderedIDs, placements: placements)
        }
    }

    private func repairMutableBspOrderBeforePriorityApplyIfNeeded(
        snapshot: DaemonSnapshot,
        priorityWindowIDs: Set<WindowID>
    ) -> DaemonSnapshot? {
        guard !priorityWindowIDs.isEmpty else { return nil }
        let scopes = activeMutableBspScopes(for: priorityWindowIDs, in: snapshot)
        guard !scopes.isEmpty else { return nil }
        let repaired = service.repairMutableBspOrderForCurrentGeometry(
            scopes: scopes,
            in: snapshot,
            reason: "manual_resize_priority_apply"
        )
        return repaired ? service.snapshot(followFocus: false) : nil
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

    private func appendMutableBspSuppressionEvent(scopes: Set<StageScope>, suppressed: Int) {
        let scopeDescriptions = scopes.map(\.description).sorted()
        let signature = scopeDescriptions.joined(separator: ",")
        guard signature != lastMutableBspSuppressionSignature else { return }
        lastMutableBspSuppressionSignature = signature
        events.append(RoadieEvent(type: "mutable_bsp_auto_relayout_suppressed", details: [
            "scopes": scopeDescriptions.joined(separator: ","),
            "suppressed": String(suppressed)
        ]))
    }

    private func appendStageMembershipSettlingEvent(scopes: Set<StageScope>) {
        let scopeDescriptions = scopes.map(\.description).sorted()
        let signature = scopeDescriptions.joined(separator: ",")
        guard signature != lastStageMembershipSettlingSignature else { return }
        lastStageMembershipSettlingSignature = signature
        events.append(RoadieEvent(type: "layout_stage_membership_settling", details: [
            "scopes": scopeDescriptions.joined(separator: ","),
            "holdSeconds": String(stageMembershipSettleSeconds)
        ]))
    }

    private func activeTiledStageMembershipSettlingScopes(
        in snapshot: DaemonSnapshot,
        changedWindowIDs: Set<WindowID>,
        now tickNow: Date
    ) -> Set<StageScope> {
        let persistentState = store.state()
        let geometryChangedScopes = activeTiledScopes(for: changedWindowIDs, in: snapshot)
        var currentSignatures: [StageScope: String] = [:]
        var candidateScopes: Set<StageScope> = []
        var settlingScopes: Set<StageScope> = []

        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled
            else { continue }

            let signature = stageMembershipSignature(stage)
            currentSignatures[scope] = signature
            // Un scope qui vient de devenir actif (changement de stage) n'a pas de signature
            // précédente : son activation n'est pas un changement de membres (FR-017).
            if let previous = lastActiveTiledStageMembershipSignatures[scope],
               previous != signature {
                candidateScopes.insert(scope)
            }

            if persistentStageHasRecentMissingMember(scope: scope, in: persistentState, now: tickNow) {
                candidateScopes.insert(scope)
            }

            if candidateScopes.contains(scope), geometryChangedScopes.contains(scope) {
                activeTiledStageMembershipChangedAt[scope] = tickNow
            }

            if let changedAt = activeTiledStageMembershipChangedAt[scope],
               tickNow.timeIntervalSince(changedAt) < stageMembershipSettleSeconds {
                settlingScopes.insert(scope)
            }
        }

        let activeScopes = Set(currentSignatures.keys)
        activeTiledStageMembershipChangedAt = activeTiledStageMembershipChangedAt.filter { activeScopes.contains($0.key) }
        lastActiveTiledStageMembershipSignatures = currentSignatures
        if settlingScopes.isEmpty {
            lastStageMembershipSettlingSignature = nil
        }
        return settlingScopes
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
            return tickNow.timeIntervalSince(missingSince) < stageMembershipSettleSeconds
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

    private func stageMembershipSignature(_ stage: StageState) -> String {
        let ids = stage.windowIDs
            .map { String($0.rawValue) }
            .sorted()
            .joined(separator: ",")
        return "\(stage.mode.rawValue):\(ids)"
    }

    private func activeTiledScopes(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> Set<StageScope> {
        Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode.isTiled,
                  snapshot.state.activeScope(on: scope.displayID) == scope
            else { return nil }
            return scope
        })
    }

    private func activeMutableBspScopes(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> Set<StageScope> {
        Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .mutableBsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope
            else { return nil }
            return scope
        })
    }

    private func activeMutableBspChangedWindowIDs(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> Set<WindowID> {
        Set(snapshot.windows.compactMap { entry -> WindowID? in
            guard windowIDs.contains(entry.window.id),
                  entry.window.isTileCandidate,
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .mutableBsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope
            else { return nil }
            return entry.window.id
        })
    }

    private func adoptMutableBspGeometryChange(
        in snapshot: DaemonSnapshot,
        changedWindowIDs: Set<WindowID>
    ) -> MaintenanceTick? {
        let mutableChangedWindowIDs = activeMutableBspChangedWindowIDs(for: changedWindowIDs, in: snapshot)
        let mutableScopes = activeMutableBspScopes(for: mutableChangedWindowIDs, in: snapshot)
        guard !mutableScopes.isEmpty else { return nil }

        let resizeAxes = singleWindowResizeAxes(for: mutableChangedWindowIDs, in: snapshot)
        let shouldRepairOrder = resizeAxes == nil
        let repaired = shouldRepairOrder && service.repairMutableBspOrderForCurrentGeometry(
            scopes: mutableScopes,
            in: snapshot,
            reason: mutableChangedWindowIDs.count >= 2
                ? "manual_multi_window_geometry_change"
                : "manual_window_geometry_change"
        )
        let updatedSnapshot = repaired ? service.snapshot(followFocus: false) : snapshot
        let planningSnapshot = snapshotByPreservingOrthogonalResizeAxis(
            in: updatedSnapshot,
            resizeAxes: resizeAxes
        )
        for scope in mutableScopes {
            service.removeLayoutIntent(scope: scope)
        }

        if mutableChangedWindowIDs.count == 1,
           let propagated = propagateMutableBspSingleWindowResize(
                in: planningSnapshot,
                scopes: mutableScopes,
                changedWindowIDs: mutableChangedWindowIDs,
                resizeAxes: resizeAxes
           ) {
            return propagated
        }

        for scope in mutableScopes {
            _ = service.saveCurrentLayoutIntentIfValid(scope: scope, from: updatedSnapshot)
        }
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = scopedFrames(in: updatedSnapshot)
        events.append(RoadieEvent(type: "mutable_bsp_geometry_adopted", details: [
            "windowIDs": mutableChangedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
            "ignoredWindowIDs": changedWindowIDs.subtracting(mutableChangedWindowIDs).map { String($0.rawValue) }.sorted().joined(separator: ","),
            "scopes": mutableScopes.map(\.description).sorted().joined(separator: ","),
            "resizeAxes": resizeAxesEventValue(resizeAxes)
        ]))
        return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
    }

    private func propagateMutableBspSingleWindowResize(
        in snapshot: DaemonSnapshot,
        scopes: Set<StageScope>,
        changedWindowIDs: Set<WindowID>,
        resizeAxes: [WindowID: MutableResizeAxes]?
    ) -> MaintenanceTick? {
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
        let planned = suppressKnownUnmovableFrames(
            in: plannedCommands(from: snapshot, priorityWindowIDs: changedWindowIDs),
            snapshot: snapshot
        )
        let rawPlan = planByPreservingOrthogonalResizeAxis(
            planned,
            in: snapshot,
            resizeAxes: resizeAxes,
            windowsByID: windowsByID,
            scopes: scopes
        )
        let plan = ApplyPlan(commands: rawPlan.commands.filter { command in
            guard !changedWindowIDs.contains(command.window.id),
                  let scope = windowsByID[command.window.id]?.scope
            else { return false }
            return scopes.contains(scope)
        })

        let observedFrames = scopedFrames(in: snapshot)
        if plan.commands.isEmpty {
            for scope in scopes {
                _ = service.saveCurrentLayoutIntentIfValid(scope: scope, from: snapshot)
            }
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastObservedFrames = observedFrames
            events.append(RoadieEvent(type: "mutable_bsp_geometry_adopted", details: [
                "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
                "scopes": scopes.map(\.description).sorted().joined(separator: ","),
                "reason": "single_window_no_neighbor_delta"
            ]))
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }

        var result = service.apply(plan)
        result = stabilizeClampedPositions(result, from: plan, in: snapshot)
        record(result, from: plan)
        appendItemEvents(result)
        if result.clamped == 0 && result.failed == 0 {
            persistLayoutIntent(in: snapshot, result: result)
        }

        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = framesAfterApplying(result, fallback: observedFrames)
        events.append(RoadieEvent(type: "mutable_bsp_resize_propagated", details: [
            "windowIDs": changedWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ","),
            "scopes": scopes.map(\.description).sorted().joined(separator: ","),
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "resizeAxes": resizeAxesEventValue(resizeAxes)
        ]))
        return MaintenanceTick(
            commands: plan.commands.count,
            applied: result.applied,
            clamped: result.clamped,
            failed: result.failed,
            manualResizeDetected: true
        )
    }

    private func planByPreservingOrthogonalResizeAxis(
        _ plan: ApplyPlan,
        in snapshot: DaemonSnapshot,
        resizeAxes: [WindowID: MutableResizeAxes]?,
        windowsByID: [WindowID: ScopedWindowSnapshot],
        scopes: Set<StageScope>
    ) -> ApplyPlan {
        guard let axis = resizeAxes?.values.first else { return plan }

        return ApplyPlan(commands: plan.commands.map { command in
            guard let entry = windowsByID[command.window.id],
                  let scope = entry.scope,
                  scopes.contains(scope),
                  let previousFrame = visiblePreviousFrame(of: entry, in: snapshot)
            else { return command }

            var frame = command.frame
            switch axis {
            case .horizontal:
                frame.y = previousFrame.y
                frame.height = previousFrame.height
            case .vertical:
                frame.x = previousFrame.x
                frame.width = previousFrame.width
            }
            return ApplyCommand(window: command.window, frame: frame)
        })
    }

    private enum MutableResizeAxes: String {
        case horizontal
        case vertical
    }

    private func singleWindowResizeAxes(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> [WindowID: MutableResizeAxes]? {
        guard windowIDs.count == 1,
              let windowID = windowIDs.first,
              let axes = resizeAxesFor(windowID, in: snapshot)
        else { return nil }
        return [windowID: axes]
    }

    private func resizeAxesFor(
        _ windowID: WindowID,
        in snapshot: DaemonSnapshot
    ) -> MutableResizeAxes? {
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let previous = visiblePreviousFrame(of: entry, in: snapshot)
        else { return nil }

        let current = entry.window.frame
        let horizontalDelta = abs(current.x - previous.x) + abs(current.width - previous.width)
        let verticalDelta = abs(current.y - previous.y) + abs(current.height - previous.height)
        let threshold = LayoutTolerance.observedChange

        if horizontalDelta > threshold,
           verticalDelta <= max(LayoutTolerance.clampShrink, horizontalDelta * LayoutTolerance.growthRatio) {
            return .horizontal
        }
        if verticalDelta > threshold,
           horizontalDelta <= max(LayoutTolerance.clampShrink, verticalDelta * LayoutTolerance.growthRatio) {
            return .vertical
        }
        return nil
    }

    /// Cadre observé au tick précédent, seulement s'il était visible sur l'écran de la fenêtre.
    /// Un cadre caché ou hors de `visibleFrame` ne sert pas de référence d'axe (moteur 15).
    private func visiblePreviousFrame(of entry: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> Rect? {
        guard let previous = lastObservedFrames?[entry.window.id.rawValue],
              let display = display(for: entry, in: snapshot),
              !HiddenWindowPlacement.isHidden(previous.cgRect, in: snapshot.displays)
        else { return nil }
        let tolerance = LayoutTolerance.observedChange
        let bounds = display.visibleFrame.cgRect.insetBy(dx: -tolerance, dy: -tolerance)
        return bounds.contains(previous.cgRect) ? previous : nil
    }

    private func snapshotByPreservingOrthogonalResizeAxis(
        in snapshot: DaemonSnapshot,
        resizeAxes: [WindowID: MutableResizeAxes]?
    ) -> DaemonSnapshot {
        guard let resizeAxes else { return snapshot }
        return DaemonSnapshot(
            permissions: snapshot.permissions,
            displays: snapshot.displays,
            windows: snapshot.windows.map { entry in
                guard let axis = resizeAxes[entry.window.id],
                      let previousFrame = visiblePreviousFrame(of: entry, in: snapshot)
                else { return entry }
                var window = entry.window
                switch axis {
                case .horizontal:
                    window.frame.y = previousFrame.y
                    window.frame.height = previousFrame.height
                case .vertical:
                    window.frame.x = previousFrame.x
                    window.frame.width = previousFrame.width
                }
                return ScopedWindowSnapshot(
                    window: window,
                    scope: entry.scope,
                    pin: entry.pin,
                    isNewlyScoped: entry.isNewlyScoped
                )
            },
            state: snapshot.state,
            focusedWindowID: snapshot.focusedWindowID
        )
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

    private func resizeAxesEventValue(_ axes: [WindowID: MutableResizeAxes]?) -> String {
        guard let axes, !axes.isEmpty else { return "" }
        return axes.keys.sorted().map { id in
            "\(id.rawValue):\(axes[id]?.rawValue ?? "")"
        }.joined(separator: ",")
    }

    private func reconcileStableVisibleDisplayDrift(
        in snapshot: DaemonSnapshot,
        excluding excludedScopes: Set<StageScope>
    ) -> MaintenanceTick? {
        let tickNow = now()
        if let lastDisplayTopologyChangedAt,
           tickNow.timeIntervalSince(lastDisplayTopologyChangedAt) < displayDriftReconcileHoldSeconds
        {
            return nil
        }

        // Déplacements calculés et écrits sur l'état relu sous verrou (SPEC-016 FR-013). La
        // place d'origine de chaque membre est gardée pour pouvoir annuler ce seul déplacement.
        let defaultMode = service.effectiveConfig.tiling.defaultStrategy
        let reconciled: [ReconciledDisplayMove] = store.mutate { state in
            var reconciled: [ReconciledDisplayMove] = []
            for entry in snapshot.windows {
                guard let sourceScope = entry.scope,
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

        guard !reconciled.isEmpty else { return nil }

        let updatedSnapshot = service.snapshot(followFocus: false)
        let plan = suppressKnownUnmovableFrames(
            in: plannedCommands(from: updatedSnapshot, priorityWindowIDs: Set(reconciled.map(\.window.id))),
            snapshot: updatedSnapshot
        )
        let result = service.apply(plan)
        record(result, from: plan)
        appendItemEvents(result)
        if result.failed > 0 {
            revertReconciledDisplayMoves(reconciled)
            lastObservedFrames = scopedFrames(in: snapshot)
            events.append(RoadieEvent(type: "window.scope_reconcile_failed", details: [
                "windows": reconciled.map { String($0.window.id.rawValue) }.sorted().joined(separator: ","),
                "commands": String(plan.commands.count),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed),
                "reason": "frame_apply_failed"
            ]))
            events.append(RoadieEvent(type: "layout_apply", details: [
                "commands": String(plan.commands.count),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed),
                "reason": "physical_display_reconcile_failed",
                "priorityWindowIDs": reconciled.map { String($0.window.id.rawValue) }.sorted().joined(separator: ",")
            ]))
            return MaintenanceTick(
                commands: plan.commands.count,
                applied: result.applied,
                clamped: result.clamped,
                failed: result.failed
            )
        }

        for item in reconciled {
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

        lastObservedFrames = framesAfterApplying(result, fallback: scopedFrames(in: updatedSnapshot))
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "reason": "physical_display_reconciled",
            "priorityWindowIDs": reconciled.map { String($0.window.id.rawValue) }.sorted().joined(separator: ",")
        ]))
        return MaintenanceTick(
            commands: max(reconciled.count, plan.commands.count),
            applied: reconciled.count + result.applied,
            clamped: result.clamped,
            failed: result.failed
        )
    }

    private func stableVisibleMutableBspScopes(in snapshot: DaemonSnapshot) -> Set<StageScope> {
        let persistentState = store.state()
        return Set(snapshot.displays.compactMap { display -> StageScope? in
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .mutableBsp,
                  !stage.windowIDs.isEmpty
            else { return nil }
            let persistentStage = persistentState.scopes
                .first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages
                .first { $0.id == scope.stageID }
            if let persistentStage,
               Set(persistentStage.members.map(\.windowID)) != Set(stage.windowIDs) {
                return nil
            }

            let entries = snapshot.windows.filter { entry in
                entry.scope == scope && entry.window.isTileCandidate
            }
            guard Set(entries.map(\.window.id)) == Set(stage.windowIDs) else { return nil }
            if service.commandLayoutIntentNeedsApply(scope: scope, in: snapshot) {
                return nil
            }
            if let lastObservedFrames,
               entries.contains(where: { lastObservedFrames[$0.window.id.rawValue] == nil }) {
                return nil
            }
            guard entries.allSatisfy({ entry in
                entry.window.isOnScreen
                    && !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            }) else { return nil }
            guard stableMutableBspFramesLookUsable(entries.map(\.window.frame.cgRect), on: display) else {
                return nil
            }

            return scope
        })
    }

    private func stableMutableBspFramesLookUsable(_ frames: [CGRect], on display: DisplaySnapshot) -> Bool {
        let container = display.visibleFrame.cgRect
        let overflow = LayoutTolerance.clampShrink
        guard frames.allSatisfy({ container.insetBy(dx: -overflow, dy: -overflow).contains($0) }) else {
            return false
        }
        guard frames.count > 1 else { return true }
        for index in frames.indices {
            for otherIndex in frames.index(after: index)..<frames.endIndex {
                // Chevauchement réel seulement s'il dépasse le bruit d'application sur les deux axes
                // (l'ancien seuil comparait une aire à une tolérance en points).
                let intersection = frames[index].intersection(frames[otherIndex])
                if intersection.width > LayoutTolerance.frameNear && intersection.height > LayoutTolerance.frameNear {
                    return false
                }
            }
        }
        return true
    }

    private func changedWindows(in frames: [UInt32: Rect]) -> Set<WindowID> {
        guard let previous = lastObservedFrames else { return [] }
        var result: Set<WindowID> = []
        for (id, frame) in frames {
            guard let previousFrame = previous[id] else { continue }
            if !frame.isClose(to: previousFrame, tolerance: LayoutTolerance.observedChange) {
                result.insert(WindowID(rawValue: id))
            }
        }
        return result
    }

    private func authoritativeModelScopes(
        for windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> Set<StageScope> {
        Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .bsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  service.hasValidLayoutIntent(scope: scope, in: snapshot)
            else { return nil }
            return scope
        })
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

    private func hideInactiveStageWindows(in snapshot: DaemonSnapshot, onlyDisplayID: DisplayID? = nil) -> Int {
        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        var applied = 0
        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  onlyDisplayID.map({ scope.displayID == $0 }) ?? true,
                  let activeScope = snapshot.state.activeScope(on: scope.displayID),
                  scope != activeScope,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !HiddenWindowPlacement.isPreferred(entry.window.frame.cgRect, among: snapshot.displays),
                  !fullscreenWindowIDs.contains(entry.window.id)
            else { continue }
            if entry.pin?.visibility(in: activeScope).shouldBeVisible == true {
                continue
            }

            let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            if let actual = service.setFrame(frame, of: entry.window) {
                recordObservedFrame(actual, of: entry.window.id)
                applied += 1
            }
        }
        return applied
    }

    /// Cache les voisines d'une fenêtre en plein écran dans son scope actif. La fenêtre qui a le
    /// focus du système n'est jamais cachée : l'utilisateur vient de la choisir (FR-002).
    private func hideActiveStageSiblingsOfFullscreenWindows(in snapshot: DaemonSnapshot) -> Int {
        let fullscreenItems = tickFullscreen.filter { item in
            guard let scope = item.entry.scope else { return false }
            return snapshot.state.activeScope(on: scope.displayID) == scope
        }
        guard !fullscreenItems.isEmpty else { return 0 }

        let fullscreenWindowIDs = Set(tickFullscreen.map(\.entry.window.id))
        let fullscreenScopes = Set(fullscreenItems.compactMap(\.entry.scope))
        // Focus réel du système (pas le focus mémorisé de la stage).
        let systemFocusedWindowID = service.focusedWindowID()
        var applied = 0

        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  fullscreenScopes.contains(scope),
                  !fullscreenWindowIDs.contains(entry.window.id),
                  entry.window.id != systemFocusedWindowID,
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { continue }

            let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            if let actual = service.setFrame(frame, of: entry.window) {
                recordObservedFrame(actual, of: entry.window.id)
                applied += 1
            }
        }
        return applied
    }

    /// Recale une fenêtre zoomée par commande dont l'origine a glissé (redémarrage, changement
    /// d'écran). Une fenêtre en plein écran natif appartient à macOS : jamais déplacée.
    private func reanchorShiftedZoomedWindows(in snapshot: DaemonSnapshot) -> Int {
        var applied = 0
        for item in tickFullscreen {
            let entry = item.entry
            guard let scope = entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  entry.window.furniture?.isNativeFullscreen != true,
                  !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays),
                  let target = fullscreenSizedReanchorTarget(for: entry.window.frame.cgRect, on: item.display)
            else { continue }

            if let actual = service.setFrame(target, of: entry.window) {
                recordObservedFrame(actual, of: entry.window.id)
                applied += 1
            }
        }
        return applied
    }

    /// Rend visible la fenêtre focalisée quand elle est cachée dans le scope actif de son écran
    /// (Cmd-Tab vers une fenêtre masquée). nil s'il n'y a rien à appliquer : le tick continue (FR-002).
    private func restoreFocusedActiveStageIfNeeded(
        in snapshot: DaemonSnapshot,
        observedFrames: [UInt32: Rect]
    ) -> MaintenanceTick? {
        let startedAt = Date()
        guard let focusedWindowID = snapshot.focusedWindowID,
              let focusedEntry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              let focusedScope = focusedEntry.scope,
              snapshot.state.activeScope(on: focusedScope.displayID) == focusedScope,
              focusedEntry.window.isTileCandidate,
              HiddenWindowPlacement.isHidden(focusedEntry.window.frame.cgRect, in: snapshot.displays),
              !tickExcludedScopes.contains(focusedScope),
              let display = snapshot.displays.first(where: { $0.id == focusedScope.displayID })
        else { return nil }

        // Membre disparu récemment : scope exclu le temps que la composition se stabilise (R6).
        if persistentStageHasRecentMissingMember(scope: focusedScope, in: store.state(), now: now()) {
            tickExcludedScopes.insert(focusedScope)
            observe(observedFrames, scopes: [focusedScope], in: snapshot)
            appendStageMembershipSettlingEvent(scopes: [focusedScope])
            return nil
        }

        // FR-002 : le focus sur une voisine cachée d'une fenêtre zoomée sort du zoom. L'intent de
        // zoom (voisines aux cadres cachés) est retiré et la fenêtre zoomée quitte le plein écran
        // du tick : le scope est redisposé normalement au lieu de rester exclu.
        if let zoomedWindowID = service.commandLayoutIntent(scope: focusedScope)?.zoomedWindowID,
           zoomedWindowID != focusedWindowID {
            service.removeLayoutIntent(scope: focusedScope)
            tickFullscreen.removeAll { $0.entry.window.id == zoomedWindowID }
            events.append(RoadieEvent(type: "layout_zoom_exited", scope: focusedScope, details: [
                "zoomedWindowID": String(zoomedWindowID.rawValue),
                "focusedWindowID": String(focusedWindowID.rawValue)
            ]))
        }

        let activeHiddenEntries = snapshot.windows.filter { entry in
            entry.scope == focusedScope
                && entry.window.isTileCandidate
                && HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
        }
        let activeHiddenWindowIDs = Set(activeHiddenEntries.map(\.window.id))
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })

        if tickFullscreen.contains(where: { $0.entry.window.id == focusedWindowID }),
           let target = fullscreenSizedRestoreTarget(for: focusedEntry.window.frame.cgRect, on: display) {
            let restoreStartedAt = Date()
            let restoredFrame = service.setFrame(target, of: focusedEntry.window)
            let restored = restoredFrame == nil ? 0 : 1
            if let restoredFrame {
                recordObservedFrame(restoredFrame, of: focusedWindowID)
            }
            let restoreMs = Date().timeIntervalSince(restoreStartedAt) * 1000
            let hideStartedAt = Date()
            let hiddenInactive = hideInactiveStageWindows(in: snapshot, onlyDisplayID: focusedScope.displayID)
            let hideMs = Date().timeIntervalSince(hideStartedAt) * 1000

            priorityWindowIDs = []
            manualResizeApplyAfter = nil

            events.append(RoadieEvent(type: "stage_focus_fullscreen_restore", details: [
                "hiddenActive": String(activeHiddenEntries.count),
                "focusedWindowID": String(focusedWindowID.rawValue),
                "focusedDisplayID": focusedScope.displayID.rawValue,
                "restored": String(restored),
                "hiddenInactive": String(hiddenInactive),
                "restoreMs": String(format: "%.1f", restoreMs),
                "hideMs": String(format: "%.1f", hideMs),
                "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000)
            ]))

            return MaintenanceTick(
                commands: restored + hiddenInactive,
                applied: restored + hiddenInactive,
                clamped: 0,
                failed: restored == 0 ? 1 : 0
            )
        }

        let planStartedAt = Date()
        let rawPlan = ApplyPlan(commands: plannedCommands(from: snapshot, priorityWindowIDs: activeHiddenWindowIDs)
            .commands
            .filter { windowsByID[$0.window.id]?.scope == focusedScope })
        var plan = suppressKnownUnmovableFrames(in: rawPlan, snapshot: snapshot)
        // Le plan du scope peut être retenu (plein écran, refus connu) : la fenêtre focalisée
        // redevient visible quand même, sinon le maintien resterait bloqué sur elle.
        if !plan.commands.contains(where: { $0.window.id == focusedWindowID }) {
            let planned = rawPlan.commands.first { $0.window.id == focusedWindowID }?.frame.cgRect
            let target = planned.flatMap { HiddenWindowPlacement.isHidden($0, in: snapshot.displays) ? nil : $0 }
                ?? centeredVisibleFrame(for: focusedEntry.window.frame.cgRect, on: display)
            let command = ApplyCommand(window: focusedEntry.window, frame: Rect(target))
            if failedFrames[focusedWindowID.rawValue]?.matches(command: command) != true {
                plan.commands.append(command)
            }
        }
        let planMs = Date().timeIntervalSince(planStartedAt) * 1000

        let applyStartedAt = Date()
        var application = PlanApplication(
            result: ApplyResult.empty,
            commands: 0
        )
        if !plan.commands.isEmpty {
            application = applyRepairingClamps(plan, in: snapshot, source: "stage_focus_restore")
            for item in application.result.items where item.status != .failed {
                recordObservedFrame((item.actual ?? item.requested).cgRect, of: item.windowID)
            }
        }
        let applyMs = Date().timeIntervalSince(applyStartedAt) * 1000

        let hideStartedAt = Date()
        let hiddenInactive = hideInactiveStageWindows(in: snapshot, onlyDisplayID: focusedScope.displayID)
        let hideMs = Date().timeIntervalSince(hideStartedAt) * 1000
        guard application.commands > 0 || hiddenInactive > 0 else { return nil }

        priorityWindowIDs = []
        manualResizeApplyAfter = nil

        events.append(RoadieEvent(type: "stage_focus_restore", details: [
            "hiddenActive": String(activeHiddenEntries.count),
            "scopes": "\(focusedScope.displayID.rawValue)/\(focusedScope.desktopID.rawValue)/\(focusedScope.stageID.rawValue)",
            "commands": String(application.commands),
            "applied": String(application.result.applied),
            "clamped": String(application.result.clamped),
            "failed": String(application.result.failed),
            "hiddenInactive": String(hiddenInactive),
            "focusedWindowID": String(focusedWindowID.rawValue),
            "focusedDisplayID": focusedScope.displayID.rawValue,
            "planMs": String(format: "%.1f", planMs),
            "applyMs": String(format: "%.1f", applyMs),
            "hideMs": String(format: "%.1f", hideMs),
            "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000)
        ]))

        return MaintenanceTick(
            commands: application.commands + hiddenInactive,
            applied: application.result.applied + hiddenInactive,
            clamped: application.result.clamped,
            failed: application.result.failed
        )
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

    private func restoreVisiblePinnedWindows(in snapshot: DaemonSnapshot) -> Int {
        var applied = 0
        for entry in snapshot.windows {
            guard let pin = entry.pin,
                  let activeScope = snapshot.state.activeScope(on: pin.homeScope.displayID),
                  pin.visibility(in: activeScope).shouldBeVisible,
                  HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays)
            else { continue }

            if service.setFrame(pin.lastFrame.cgRect, of: entry.window) != nil {
                applied += 1
            }
        }
        return applied
    }
}

/// Déplacement d'une fenêtre vers la stage de son écran physique, avec sa place d'origine.
private struct ReconciledDisplayMove {
    struct Origin {
        var member: PersistentStageMember
        var index: Int
        var wasFocused: Bool
        var previousFocusedWindowID: WindowID?

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
        }
    }

    var window: WindowSnapshot
    var source: StageScope
    var target: StageScope
    var origin: Origin?
}

private struct RulePlacementDestination {
    var display: DisplaySnapshot
    var scope: StageScope
    var follow: Bool
}

/// Refus de taille mémorisé : l'application a gardé `actual` quand Roadie demandait `requested`.
/// Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004).
private struct ClampedFrame {
    var requested: Rect
    var actual: Rect
    var recordedAt: Date

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

/// Échec d'application mémorisé. Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004).
private struct FailedFrame {
    var requested: Rect
    var observedAtFailure: Rect
    var recordedAt: Date

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedAtFailure, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

private struct RevertedAppliedFrame {
    var requested: Rect
    var observedBeforeApply: Rect
    var appliedAt: Date

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedBeforeApply, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

private extension PersistentStageState {
    func activeScopeEquivalent(on displayID: DisplayID) -> StageScope {
        let desktopID = currentDesktopID(for: displayID)
        let stageID = scopes.first { $0.displayID == displayID && $0.desktopID == desktopID }?.activeStageID
            ?? StageID(rawValue: "1")
        return StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
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
// MARK: - Temporary Focus-Jitter Guard
// Keep focus-only geometry jitter from mouse clicks from forcing a full relayout.
