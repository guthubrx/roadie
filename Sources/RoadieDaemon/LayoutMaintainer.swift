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
    private var cachedRuleEngine: WindowRuleEngine?
    private var cachedRulesVersion: String?
    private var clampedFrames: [UInt32: ClampedFrame] = [:]
    private var failedFrames: [UInt32: FailedFrame] = [:]
    private var revertedAppliedFrames: [UInt32: RevertedAppliedFrame] = [:]
    private var lastObservedFrames: [UInt32: Rect]?
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
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.events = events
        self.intervalSeconds = intervalSeconds
        self.commandIntentHoldSeconds = max(4, intervalSeconds * 10)
        self.manualResizeDebounceSeconds = max(0.35, intervalSeconds * 0.9)
        self.displayDriftReconcileHoldSeconds = max(8, intervalSeconds * 16)
        self.stageMembershipSettleSeconds = max(2, intervalSeconds * 4)
        self.staticRuleEngine = ruleEngine
        self.store = store ?? service.effectiveStageStore
        self.dragActivity = dragActivity
        self.commandActivity = commandActivity
        self.now = now
    }

    public func tick() -> MaintenanceTick {
        let snapshot = service.snapshot()
        guard snapshot.permissions.accessibilityTrusted else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        let tickNow = now()
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
            displayTopologySettlesUntil = tickNow.addingTimeInterval(max(1.5, intervalSeconds * 4))
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
        let missingMemberReclaimScopes = activeTiledScopesWithRecentMissingMembers(in: snapshot, now: tickNow)
        if let activeUntil = commandActivity.activeUntil(now: tickNow) {
            if missingMemberReclaimScopes.isEmpty {
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                lastObservedFrames = scopedFrames(in: snapshot)
                if lastCommandActivitySuppressedAt.map({ tickNow.timeIntervalSince($0) > 1.0 }) ?? true {
                    lastCommandActivitySuppressedAt = tickNow
                    events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: [
                        "activeUntil": String(activeUntil.timeIntervalSince1970)
                    ]))
                }
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            } else {
                events.append(RoadieEvent(type: "layout_command_activity_suppressed", details: [
                    "activeUntil": String(activeUntil.timeIntervalSince1970),
                    "bypassedForMissingReclaim": "true",
                    "scopes": missingMemberReclaimScopes.map(\.description).sorted().joined(separator: ",")
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
            settlingLayoutScopes: settlingLayoutScopes
        ) {
            return focusRestore
        }

        let reanchoredFullscreenSized = reanchorScreenDominantFullscreenSizedWindows(in: snapshot)
        if reanchoredFullscreenSized > 0 {
            lastObservedFrames = scopedFrames(in: service.snapshot(followFocus: false))
            events.append(RoadieEvent(type: "fullscreen_sized_windows_reanchored", details: [
                "applied": String(reanchoredFullscreenSized)
            ]))
            return MaintenanceTick(commands: reanchoredFullscreenSized, applied: reanchoredFullscreenSized, clamped: 0, failed: 0)
        }

        let hiddenFullscreenSiblings = hideActiveStageSiblingsOfFullscreenWindows(in: snapshot)
        if hiddenFullscreenSiblings > 0 {
            lastObservedFrames = scopedFrames(in: service.snapshot(followFocus: false))
            events.append(RoadieEvent(type: "fullscreen_stage_siblings_hidden", details: [
                "applied": String(hiddenFullscreenSiblings)
            ]))
            return MaintenanceTick(commands: hiddenFullscreenSiblings, applied: hiddenFullscreenSiblings, clamped: 0, failed: 0)
        }

        let activeProtectedFullscreenScopes = Set(fullscreenLikeEntries(in: snapshot, nativeOnly: true).compactMap { item -> StageScope? in
            guard let scope = item.entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope
            else { return nil }
            return scope
        })
        if !activeProtectedFullscreenScopes.isEmpty {
            lastObservedFrames = scopedFrames(in: snapshot)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }

        let hiddenInactive = hideInactiveStageWindows(in: snapshot)
        if hiddenInactive > 0 {
            events.append(RoadieEvent(type: "stage_hide_inactive", details: ["applied": String(hiddenInactive)]))
            return MaintenanceTick(commands: hiddenInactive, applied: hiddenInactive, clamped: 0, failed: 0)
        }

        let observedFrames = observedFramesForChurn
        let changedWindowIDs = changedWindowIDsForChurn
        let now = now()
        let cutoff = now.addingTimeInterval(-commandIntentHoldSeconds)

        if !changedWindowIDs.isEmpty {
            if changedFramesMatchSavedIntent(in: snapshot, frames: observedFrames, changedWindowIDs: changedWindowIDs) {
                lastObservedFrames = observedFrames
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }

            if suppressFullscreenLikeChanges(in: snapshot, frames: observedFrames, changedWindowIDs: changedWindowIDs) {
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }

            if let tick = adoptManualDisplayMoves(in: snapshot, changedWindowIDs: changedWindowIDs) {
                lastObservedFrames = scopedFrames(in: service.snapshot(followFocus: false))
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                return tick
            }

            let settlingChangedScopes = activeTiledScopes(
                for: changedWindowIDs,
                in: snapshot
            ).intersection(settlingLayoutScopes)
            if !settlingChangedScopes.isEmpty {
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                lastObservedFrames = observedFrames
                appendStageMembershipSettlingEvent(scopes: settlingChangedScopes)
                return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
            }

            let modeledScopes = authoritativeModelScopes(for: changedWindowIDs, in: snapshot)
            if !modeledScopes.isEmpty {
                priorityWindowIDs = []
                manualResizeApplyAfter = nil
                let tick = applyPlan(from: snapshot, observedFrames: observedFrames, excluding: [])
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

        if let tick = reconcileStableVisibleDisplayDrift(in: snapshot) {
            return tick
        }

        if !settlingLayoutScopes.isEmpty {
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastObservedFrames = observedFrames
            appendStageMembershipSettlingEvent(scopes: settlingLayoutScopes)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }

        if let manualResizeApplyAfter, now < manualResizeApplyAfter {
            lastObservedFrames = observedFrames
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }
        manualResizeApplyAfter = nil

        let commandProtectedScopes = priorityWindowIDs.isEmpty
            ? recentCommandScopes(in: snapshot, since: cutoff, now: now)
            : []
        let strictCommandProtectedScopes = strictAuthoritativeScopes(commandProtectedScopes, in: snapshot)
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
                    excluding: remainingProtectedScopes.union(settlingLayoutScopes)
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
                excluding: strictCommandProtectedScopes.union(settlingLayoutScopes),
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
            )
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
                    excluding: remainingProtectedScopes.union(settlingLayoutScopes)
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
                excluding: protectedScopes.union(settlingLayoutScopes),
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
            in: service.applyPlan(from: planningSnapshot, priorityWindowIDs: priorityWindowIDs),
            snapshot: planningSnapshot
        )
        let protectedMutableScopes = priorityWindowIDs.isEmpty
            ? stableVisibleMutableBspScopes(in: planningSnapshot)
            : []
        let protectedLayoutScopes = protectedMutableScopes.union(settlingLayoutScopes)
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
        if !settlingLayoutScopes.isEmpty && filteredPlan.commands.count != plan.commands.count {
            appendStageMembershipSettlingEvent(scopes: settlingLayoutScopes)
        }
        guard !filteredPlan.commands.isEmpty else {
            persistCurrentLayoutIntents(in: planningSnapshot)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        var result = service.apply(filteredPlan)
        result = stabilizeClampedPositions(result, from: filteredPlan, in: planningSnapshot)
        let repairPlan = clampedSiblingRepairPlan(from: result, in: planningSnapshot)
        if !repairPlan.commands.isEmpty {
            var repairResult = service.apply(repairPlan)
            repairResult = stabilizeClampedPositions(repairResult, from: repairPlan, in: planningSnapshot)
            result = result.merged(with: repairResult)
            events.append(RoadieEvent(type: "layout_clamped_scope_repaired", details: [
                "commands": String(repairPlan.commands.count),
                "windowIDs": repairPlan.commands
                    .map { String($0.window.id.rawValue) }
                    .sorted()
                    .joined(separator: ",")
                ]))
        }
        let isolated = isolateFocusedWindowInInfeasibleClampedScopes(from: result, in: planningSnapshot)
        if result.clamped == 0 && result.failed == 0 {
            persistLayoutIntent(in: planningSnapshot, result: result)
        }
        if result.applied > 0 || result.clamped > 0 || result.failed > 0 {
            lastMutableBspSuppressionSignature = nil
        }
        record(result, from: ApplyPlan(commands: filteredPlan.commands + repairPlan.commands))
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(filteredPlan.commands.count + repairPlan.commands.count + isolated),
            "applied": String(result.applied + isolated),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "priorityWindowIDs": priorityWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ",")
        ]))
        appendItemEvents(result)
        let appliedFrames = framesAfterApplying(result, fallback: planningObservedFrames)
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = appliedFrames
        return MaintenanceTick(
            commands: filteredPlan.commands.count + isolated,
            applied: result.applied + isolated,
            clamped: result.clamped,
            failed: result.failed
        )
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
            in: service.applyPlan(from: planningSnapshot, priorityWindowIDs: priorityWindowIDs),
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
        lastObservedFrames = observedFrames
        var result = service.apply(filtered)
        result = stabilizeClampedPositions(result, from: filtered, in: planningSnapshot)
        let repairPlan = clampedSiblingRepairPlan(from: result, in: planningSnapshot)
        if !repairPlan.commands.isEmpty {
            var repairResult = service.apply(repairPlan)
            repairResult = stabilizeClampedPositions(repairResult, from: repairPlan, in: planningSnapshot)
            result = result.merged(with: repairResult)
            events.append(RoadieEvent(type: "layout_clamped_scope_repaired", details: [
                "commands": String(repairPlan.commands.count),
                "windowIDs": repairPlan.commands
                    .map { String($0.window.id.rawValue) }
                    .sorted()
                    .joined(separator: ",")
                ]))
        }
        let isolated = isolateFocusedWindowInInfeasibleClampedScopes(from: result, in: planningSnapshot)
        if result.clamped == 0 && result.failed == 0 {
            persistLayoutIntent(in: planningSnapshot, result: result)
        }
        record(result, from: ApplyPlan(commands: filtered.commands + repairPlan.commands))
        appendItemEvents(result)
        lastObservedFrames = framesAfterApplying(result, fallback: observedFrames)
        return MaintenanceTick(
            commands: filtered.commands.count + repairPlan.commands.count + isolated,
            applied: result.applied + isolated,
            clamped: result.clamped,
            failed: result.failed
        )
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
        guard let config = try? RoadieConfigLoader.load(), !config.rules.isEmpty else {
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

        var state = store.state()
        if state.suppressesRulePlacement(windowID: entry.window.id, ruleID: application.matchedRuleID) {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, reason: "manual placement override")
            return false
        }
        guard let destination = resolvePlacementDestination(application, entry: entry, snapshot: snapshot, state: &state) else {
            appendPlacementEvent("rule.placement_deferred", application: application, entry: entry, reason: "destination unavailable")
            return false
        }
        if entry.scope == destination.scope {
            appendPlacementEvent("rule.placement_skipped", application: application, entry: entry, destination: destination.scope, reason: "already on target")
            return false
        }

        let sourceScope = entry.scope
        var targetScope = state.scope(displayID: destination.scope.displayID, desktopID: destination.scope.desktopID)
        targetScope.ensureStage(destination.scope.stageID)
        if destination.follow {
            targetScope.activeStageID = destination.scope.stageID
            state.switchDesktop(displayID: destination.scope.displayID, to: destination.scope.desktopID)
            state.focusDisplay(destination.scope.displayID)
        }
        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: entry.window.id)
        }
        targetScope.assign(window: entry.window, to: destination.scope.stageID)
        state.update(targetScope)
        state.updatePinHomeScope(windowID: entry.window.id, to: destination.scope)
        store.save(state)

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: destination.scope)

        if !destination.follow {
            let activeScope = state.activeScopeEquivalent(on: destination.scope.displayID)
            if activeScope != destination.scope {
                _ = service.setFrame(hiddenFrame(for: entry.window.frame.cgRect, on: destination.display, among: snapshot.displays), of: entry.window)
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
        var state = store.state()
        var adopted: [(window: WindowSnapshot, source: StageScope, target: StageScope, removedPin: PersistentWindowPin?)] = []

        for entry in snapshot.windows where changedWindowIDs.contains(entry.window.id) {
            guard let sourceScope = entry.scope,
                  entry.window.isOnScreen,
                  entry.window.isTileCandidate,
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
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

        guard !adopted.isEmpty else { return nil }
        store.save(state)

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
            in: service.applyPlan(from: updatedSnapshot, priorityWindowIDs: Set(adopted.map(\.window.id))),
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
        let cutoff = now().addingTimeInterval(-max(3, intervalSeconds * 8))
        let fullscreenItems = fullscreenLikeEntries(in: snapshot, nativeOnly: true)
        let fullscreenWindowIDs = Set(fullscreenItems.map(\.entry.window.id))
        let fullscreenScopes = Set(fullscreenItems.compactMap(\.entry.scope))
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
        return ApplyPlan(commands: plan.commands.filter { command in
            if fullscreenWindowIDs.contains(command.window.id) {
                return false
            }
            if let scope = windowsByID[command.window.id]?.scope,
               fullscreenScopes.contains(scope) {
                return false
            }
            if let known = clampedFrames[command.window.id.rawValue],
               known.matches(command: command) {
                return false
            }
            if let known = failedFrames[command.window.id.rawValue],
               known.matches(command: command) {
                return false
            }
            if let known = revertedAppliedFrames[command.window.id.rawValue],
               known.appliedAt >= cutoff,
               known.matches(command: command) {
                return false
            }
            return true
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

    private func suppressFullscreenLikeChanges(
        in snapshot: DaemonSnapshot,
        frames: [UInt32: Rect],
        changedWindowIDs: Set<WindowID>
    ) -> Bool {
        let entries = fullscreenLikeEntries(in: snapshot, windowIDs: changedWindowIDs, nativeOnly: true)
        if entries.isEmpty {
            let protectedScopes = Set(fullscreenLikeEntries(in: snapshot, nativeOnly: true).compactMap(\.entry.scope))
            guard !protectedScopes.isEmpty else { return false }
            let changedProtectedScopeEntries = snapshot.windows.filter { entry in
                guard changedWindowIDs.contains(entry.window.id),
                      let scope = entry.scope
                else { return false }
                return protectedScopes.contains(scope)
            }
            guard !changedProtectedScopeEntries.isEmpty else { return false }

            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastObservedFrames = frames
            events.append(RoadieEvent(type: "fullscreen_scope_change_suppressed", details: [
                "windowIDs": changedProtectedScopeEntries
                    .map { String($0.window.id.rawValue) }
                    .sorted()
                    .joined(separator: ","),
                "scopes": protectedScopes
                    .map(\.description)
                    .sorted()
                    .joined(separator: ",")
            ]))
            return true
        }
        removeLayoutIntents(for: Set(entries.map(\.entry.window.id)), in: snapshot)
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = frames
        for item in entries {
            events.append(RoadieEvent(type: "fullscreen_layout_suppressed", scope: item.entry.scope, details: [
                "windowID": String(item.entry.window.id.rawValue),
                "app": item.entry.window.appName,
                "displayID": item.display.id.rawValue
            ]))
        }
        return true
    }

    private func fullscreenLikeEntries(
        in snapshot: DaemonSnapshot,
        windowIDs: Set<WindowID>? = nil,
        nativeOnly: Bool = false
    ) -> [(entry: ScopedWindowSnapshot, display: DisplaySnapshot)] {
        snapshot.windows.compactMap { entry in
            guard entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  windowIDs.map({ $0.contains(entry.window.id) }) ?? true,
                  let display = display(for: entry, in: snapshot),
                  isFullscreenLike(entry, on: display, nativeOnly: nativeOnly)
            else { return nil }
            return (entry, display)
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

    private func isFullscreenLike(
        _ entry: ScopedWindowSnapshot,
        on display: DisplaySnapshot,
        nativeOnly: Bool = false
    ) -> Bool {
        if entry.window.furniture?.isNativeFullscreen == true {
            return true
        }
        guard !nativeOnly else {
            return isCommandFullscreenLike(entry, on: display)
        }
        let frame = entry.window.frame.cgRect
        if isMaximizedLike(frame, on: display) {
            return true
        }
        guard let known = clampedFrames[entry.window.id.rawValue] else {
            return isScreenDominantFullscreenSized(frame, on: display)
        }
        return clampedFrameIsFullscreenSized(known, current: frame, on: display)
    }

    private func isCommandFullscreenLike(_ entry: ScopedWindowSnapshot, on display: DisplaySnapshot) -> Bool {
        guard let scope = entry.scope,
              let intent = service.commandLayoutIntent(scope: scope),
              intent.windowIDs.contains(entry.window.id)
        else { return false }

        let frame = entry.window.frame.cgRect
        return frameSizeIsClose(frame, display.visibleFrame.cgRect, tolerance: 48)
            || frameSizeIsClose(frame, display.frame.cgRect, tolerance: 48)
    }

    private func isMaximizedLike(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        framesAreClose(frame, display.visibleFrame.cgRect, tolerance: 48)
            || framesAreClose(frame, display.frame.cgRect, tolerance: 48)
    }

    private func clampedFrameIsFullscreenSized(
        _ known: ClampedFrame,
        current: CGRect,
        on display: DisplaySnapshot
    ) -> Bool {
        let actual = known.actual.cgRect
        let currentStillMatchesClamp = abs(current.width - actual.width) <= 24
            && abs(current.height - actual.height) <= 24
        guard currentStillMatchesClamp else { return false }
        return frameSizeIsClose(actual, display.visibleFrame.cgRect, tolerance: 48)
            || frameSizeIsClose(actual, display.frame.cgRect, tolerance: 48)
    }

    private func isScreenDominantFullscreenSized(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        let visible = display.visibleFrame.cgRect
        let displayFrame = display.frame.cgRect
        guard frameSizeIsClose(frame, visible, tolerance: 48)
                || frameSizeIsClose(frame, displayFrame, tolerance: 48)
        else { return false }

        let overlap = frame.intersection(visible)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let visibleArea = max(1, visible.width * visible.height)
        let overlapArea = overlap.width * overlap.height
        return overlapArea / visibleArea >= 0.5
    }

    private func fullscreenSizedReanchorTarget(
        for frame: CGRect,
        on display: DisplaySnapshot
    ) -> CGRect? {
        guard !isMaximizedLike(frame, on: display),
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
        if frameSizeIsClose(frame, visible, tolerance: 48) {
            target = visible
        } else if frameSizeIsClose(frame, displayFrame, tolerance: 48) {
            target = displayFrame
        } else {
            return nil
        }
        guard !framesAreClose(frame, target, tolerance: 8) else { return nil }
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
                    clampedFrames[item.windowID.rawValue] = ClampedFrame(requested: item.requested, actual: actual)
                }
                revertedAppliedFrames.removeValue(forKey: item.windowID.rawValue)
            case .applied:
                clampedFrames.removeValue(forKey: item.windowID.rawValue)
                failedFrames.removeValue(forKey: item.windowID.rawValue)
                if let command = commandsByID[item.windowID],
                   !command.window.frame.isClose(to: item.requested, positionTolerance: 1, sizeTolerance: 1) {
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
                        failedAt: now()
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
            guard !actual.isClose(to: anchored, positionTolerance: 2, sizeTolerance: 2),
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
                      !window.frame.isClose(to: Rect(target), positionTolerance: 2, sizeTolerance: 2)
                else { continue }
                commands.append(ApplyCommand(window: window, frame: Rect(target)))
            }
        }

        return ApplyPlan(commands: commands)
    }

    private func isolateFocusedWindowInInfeasibleClampedScopes(
        from result: ApplyResult,
        in snapshot: DaemonSnapshot
    ) -> Int {
        let clampedItems = result.items.filter { $0.status == .clamped && $0.actual != nil }
        guard clampedItems.count >= 2 else { return 0 }

        let entriesByID = snapshot.windows.reduce(into: [WindowID: ScopedWindowSnapshot]()) { result, entry in
            result[entry.window.id] = entry
        }
        let clampedScopes = Dictionary(grouping: clampedItems) { item in
            entriesByID[item.windowID]?.scope
        }

        var applied = 0
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
                    && !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays)
            }
            guard entries.count > 1 else { continue }

            let frames = framesAfterApplying(result, fallback: scopedFrames(in: snapshot))
            let liveFrames = entries.reduce(into: [WindowID: CGRect]()) { result, entry in
                if let frame = frames[entry.window.id.rawValue]?.cgRect {
                    result[entry.window.id] = frame
                } else {
                    result[entry.window.id] = entry.window.frame.cgRect
                }
            }
            guard clampedFramesCannotShareContainer(
                liveFrames.map(\.value),
                visibleFrame: display.visibleFrame.cgRect,
                innerGap: CGFloat(service.innerGap())
            ) else { continue }

            let keepID = focusedWindowIDToKeep(in: entries, snapshot: snapshot)
            var hiddenIDs: [String] = []
            for entry in entries where entry.window.id != keepID {
                let frame = hiddenFrame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
                if service.setFrame(frame, of: entry.window) != nil {
                    applied += 1
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

        return applied
    }

    private func clampedFramesCannotShareContainer(
        _ frames: [CGRect],
        visibleFrame: CGRect,
        innerGap: CGFloat
    ) -> Bool {
        guard frames.count > 1 else { return false }
        let gapTotal = max(0, innerGap) * CGFloat(frames.count - 1)
        let horizontalNeeded = frames.reduce(CGFloat(0)) { $0 + $1.width } + gapTotal
        let verticalNeeded = frames.reduce(CGFloat(0)) { $0 + $1.height } + gapTotal
        return horizontalNeeded > visibleFrame.width + 16
            && verticalNeeded > visibleFrame.height + 16
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
        if blocker.height >= visibleFrame.height * 0.5 {
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
        if blocker.width >= visibleFrame.width * 0.5 {
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
            .filter { $0.width >= 120 && $0.height >= 120 }
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

        if frameSizeIsClose(actualRect, bounds, tolerance: 48) {
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
        if actual.width <= visible.width + 48,
           actual.height <= visible.height + 48 {
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

    private func persistCurrentLayoutIntents(in snapshot: DaemonSnapshot) {
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id) else { continue }
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
            if let previous = lastActiveTiledStageMembershipSignatures[scope],
               previous != signature {
                candidateScopes.insert(scope)
            } else if !lastActiveTiledStageMembershipSignatures.isEmpty,
                      lastActiveTiledStageMembershipSignatures[scope] == nil {
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
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
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
            in: service.applyPlan(from: snapshot, priorityWindowIDs: changedWindowIDs),
            snapshot: snapshot
        )
        let rawPlan = planByPreservingOrthogonalResizeAxis(
            planned,
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
        resizeAxes: [WindowID: MutableResizeAxes]?,
        windowsByID: [WindowID: ScopedWindowSnapshot],
        scopes: Set<StageScope>
    ) -> ApplyPlan {
        guard let axis = resizeAxes?.values.first,
              let previous = lastObservedFrames
        else { return plan }

        return ApplyPlan(commands: plan.commands.map { command in
            guard let scope = windowsByID[command.window.id]?.scope,
                  scopes.contains(scope),
                  let previousFrame = previous[command.window.id.rawValue]
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
        _ windowIDs: Set<WindowID>,
        in snapshot: DaemonSnapshot
    ) -> [WindowID: MutableResizeAxes]? {
        let pairs = windowIDs.compactMap { id -> (WindowID, MutableResizeAxes)? in
            resizeAxesFor(id, in: snapshot).map { (id, $0) }
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }

    private func resizeAxesFor(
        _ windowID: WindowID,
        in snapshot: DaemonSnapshot
    ) -> MutableResizeAxes? {
        guard let previous = lastObservedFrames?[windowID.rawValue],
              let current = snapshot.windows.first(where: { $0.window.id == windowID })?.window.frame
        else { return nil }

        let horizontalDelta = abs(current.x - previous.x) + abs(current.width - previous.width)
        let verticalDelta = abs(current.y - previous.y) + abs(current.height - previous.height)
        let threshold = Double(16)

        if horizontalDelta > threshold,
           verticalDelta <= max(24, horizontalDelta * 0.35) {
            return .horizontal
        }
        if verticalDelta > threshold,
           horizontalDelta <= max(24, verticalDelta * 0.35) {
            return .vertical
        }
        return nil
    }

    private func snapshotByPreservingOrthogonalResizeAxis(
        in snapshot: DaemonSnapshot,
        resizeAxes: [WindowID: MutableResizeAxes]?
    ) -> DaemonSnapshot {
        guard let resizeAxes, let previous = lastObservedFrames else { return snapshot }
        return DaemonSnapshot(
            permissions: snapshot.permissions,
            displays: snapshot.displays,
            windows: snapshot.windows.map { entry in
                guard let axis = resizeAxes[entry.window.id],
                      let previousFrame = previous[entry.window.id.rawValue]
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

    private func resizeAxesEventValue(_ axes: [WindowID: MutableResizeAxes]?) -> String {
        guard let axes, !axes.isEmpty else { return "" }
        return axes.keys.sorted().map { id in
            "\(id.rawValue):\(axes[id]?.rawValue ?? "")"
        }.joined(separator: ",")
    }

    private func reconcileStableVisibleDisplayDrift(in snapshot: DaemonSnapshot) -> MaintenanceTick? {
        let tickNow = now()
        if let lastDisplayTopologyChangedAt,
           tickNow.timeIntervalSince(lastDisplayTopologyChangedAt) < displayDriftReconcileHoldSeconds
        {
            return nil
        }

        let originalState = store.state()
        var state = originalState
        var reconciled: [(window: WindowSnapshot, source: StageScope, target: StageScope)] = []

        for entry in snapshot.windows {
            guard let sourceScope = entry.scope,
                  entry.pin == nil,
                  entry.window.isOnScreen,
                  entry.window.isTileCandidate,
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
                  !state.suppressesRulePlacement(windowID: entry.window.id, ruleID: nil),
                  let physicalDisplay = snapshot.displays.first(where: { $0.frame.cgRect.contains(entry.window.frame.center) }),
                  physicalDisplay.id != sourceScope.displayID
            else { continue }

            let targetDesktopID = state.currentDesktopID(for: physicalDisplay.id)
            var targetScope = state.scope(
                displayID: physicalDisplay.id,
                desktopID: targetDesktopID,
                defaultMode: service.effectiveConfig.tiling.defaultStrategy
            )
            let targetStageID = targetScope.activeStageID
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: entry.window.id)
            }
            targetScope = state.scope(
                displayID: physicalDisplay.id,
                desktopID: targetDesktopID,
                defaultMode: service.effectiveConfig.tiling.defaultStrategy
            )
            targetScope.assign(
                window: entry.window,
                to: targetStageID,
                defaultMode: service.effectiveConfig.tiling.defaultStrategy
            )
            state.update(targetScope)
            reconciled.append((
                entry.window,
                sourceScope,
                StageScope(displayID: physicalDisplay.id, desktopID: targetDesktopID, stageID: targetStageID)
            ))
        }

        guard !reconciled.isEmpty else { return nil }
        store.save(state)

        let updatedSnapshot = service.snapshot(followFocus: false)
        let plan = suppressKnownUnmovableFrames(
            in: service.applyPlan(from: updatedSnapshot, priorityWindowIDs: Set(reconciled.map(\.window.id))),
            snapshot: updatedSnapshot
        )
        let result = service.apply(plan)
        record(result, from: plan)
        appendItemEvents(result)
        if result.failed > 0 {
            store.save(originalState)
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
                    && !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays)
            }) else { return nil }
            guard stableMutableBspFramesLookUsable(entries.map(\.window.frame.cgRect), on: display) else {
                return nil
            }

            return scope
        })
    }

    private func stableMutableBspFramesLookUsable(_ frames: [CGRect], on display: DisplaySnapshot) -> Bool {
        let container = display.visibleFrame.cgRect
        guard frames.allSatisfy({ container.insetBy(dx: -24, dy: -24).contains($0) }) else {
            return false
        }
        guard frames.count > 1 else { return true }
        for index in frames.indices {
            for otherIndex in frames.index(after: index)..<frames.endIndex {
                let intersection = frames[index].intersection(frames[otherIndex])
                if max(0, intersection.width) * max(0, intersection.height) > 16 {
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
            if !frame.isClose(to: previousFrame, positionTolerance: 16, sizeTolerance: 16) {
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
                positionTolerance: 16,
                sizeTolerance: 16,
                focusedPositionTolerance: 16,
                focusedSizeTolerance: 16,
                allowFocusChromeDelta: false
            )
        })
    }

    private func hideInactiveStageWindows(in snapshot: DaemonSnapshot, onlyDisplayID: DisplayID? = nil) -> Int {
        var applied = 0
        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  onlyDisplayID.map({ scope.displayID == $0 }) ?? true,
                  let activeScope = snapshot.state.activeScope(on: scope.displayID),
                  scope != activeScope,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !isPreferredHiddenCorner(entry.window.frame.cgRect, among: snapshot.displays),
                  !isFullscreenLike(entry, on: display)
            else { continue }
            if entry.pin?.visibility(in: activeScope).shouldBeVisible == true {
                continue
            }

            let frame = hiddenFrame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            if service.setFrame(frame, of: entry.window) != nil {
                applied += 1
            }
        }
        return applied
    }

    private func hideActiveStageSiblingsOfFullscreenWindows(in snapshot: DaemonSnapshot) -> Int {
        let fullscreenItems = fullscreenLikeEntries(in: snapshot, nativeOnly: true)
            .filter { item in
                guard let scope = item.entry.scope else { return false }
                return snapshot.state.activeScope(on: scope.displayID) == scope
            }
        guard !fullscreenItems.isEmpty else { return 0 }

        let fullscreenWindowIDs = Set(fullscreenItems.map(\.entry.window.id))
        let fullscreenScopes = Set(fullscreenItems.compactMap(\.entry.scope))
        var applied = 0

        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  fullscreenScopes.contains(scope),
                  !fullscreenWindowIDs.contains(entry.window.id),
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
                  !isFullscreenLike(entry, on: display, nativeOnly: true)
            else { continue }

            let frame = hiddenFrame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            if service.setFrame(frame, of: entry.window) != nil {
                applied += 1
            }
        }
        return applied
    }

    private func reanchorScreenDominantFullscreenSizedWindows(in snapshot: DaemonSnapshot) -> Int {
        var applied = 0
        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  isFullscreenLike(entry, on: display, nativeOnly: true),
                  let target = fullscreenSizedReanchorTarget(for: entry.window.frame.cgRect, on: display)
            else { continue }

            if service.setFrame(target, of: entry.window) != nil {
                applied += 1
            }
        }
        return applied
    }

    private func restoreFocusedActiveStageIfNeeded(
        in snapshot: DaemonSnapshot,
        settlingLayoutScopes: Set<StageScope>
    ) -> MaintenanceTick? {
        let startedAt = Date()
        guard let focusedWindowID = snapshot.focusedWindowID,
              let focusedEntry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              let focusedScope = focusedEntry.scope,
              snapshot.state.activeScope(on: focusedScope.displayID) == focusedScope,
              focusedEntry.window.isTileCandidate,
              isHiddenCorner(focusedEntry.window.frame.cgRect, in: snapshot.displays)
        else { return nil }

        let activeHiddenEntries = snapshot.windows.filter { entry in
            guard let scope = entry.scope,
                  scope == focusedScope,
                  entry.window.isTileCandidate,
                  isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays)
            else { return false }
            return true
        }

        let activeHiddenScopes = Set(activeHiddenEntries.compactMap(\.scope))
        let activeHiddenWindowIDs = Set(activeHiddenEntries.map(\.window.id))
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
        let observedFrames = scopedFrames(in: snapshot)

        let settlingHiddenScopes = activeHiddenScopes.intersection(settlingLayoutScopes)
        let recentMissingHiddenScopes = activeHiddenScopes.filter {
            persistentStageHasRecentMissingMember(scope: $0, in: store.state(), now: now())
        }
        let protectedHiddenScopes = settlingHiddenScopes.union(recentMissingHiddenScopes)
        if !protectedHiddenScopes.isEmpty {
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastObservedFrames = observedFrames
            appendStageMembershipSettlingEvent(scopes: protectedHiddenScopes)
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }

        if let display = snapshot.displays.first(where: { $0.id == focusedScope.displayID }),
           isFullscreenLike(focusedEntry, on: display, nativeOnly: true),
           let target = fullscreenSizedRestoreTarget(for: focusedEntry.window.frame.cgRect, on: display) {
            let restoreStartedAt = Date()
            let restored = service.setFrame(target, of: focusedEntry.window) != nil ? 1 : 0
            let restoreMs = Date().timeIntervalSince(restoreStartedAt) * 1000
            let hideStartedAt = Date()
            let hiddenInactive = hideInactiveStageWindows(in: snapshot, onlyDisplayID: focusedScope.displayID)
            let hideMs = Date().timeIntervalSince(hideStartedAt) * 1000

            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            lastObservedFrames = scopedFrames(in: service.snapshot(followFocus: false))

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
        let rawPlan = suppressKnownUnmovableFrames(
            in: service.applyPlan(from: snapshot, priorityWindowIDs: activeHiddenWindowIDs),
            snapshot: snapshot
        )
        let plan = ApplyPlan(commands: rawPlan.commands.filter { command in
            guard let scope = windowsByID[command.window.id]?.scope else { return false }
            return activeHiddenScopes.contains(scope)
        })
        let planMs = Date().timeIntervalSince(planStartedAt) * 1000

        let applyStartedAt = Date()
        var result = ApplyResult(attempted: 0, applied: 0, clamped: 0, failed: 0, items: [])
        var repairPlan = ApplyPlan(commands: [])
        var isolated = 0
        if !plan.commands.isEmpty {
            result = service.apply(plan)
            result = stabilizeClampedPositions(result, from: plan, in: snapshot)
            repairPlan = clampedSiblingRepairPlan(from: result, in: snapshot)
            if !repairPlan.commands.isEmpty {
                var repairResult = service.apply(repairPlan)
                repairResult = stabilizeClampedPositions(repairResult, from: repairPlan, in: snapshot)
                result = result.merged(with: repairResult)
                events.append(RoadieEvent(type: "layout_clamped_scope_repaired", details: [
                    "commands": String(repairPlan.commands.count),
                    "windowIDs": repairPlan.commands
                        .map { String($0.window.id.rawValue) }
                        .sorted()
                        .joined(separator: ","),
                    "source": "stage_focus_restore"
                ]))
            }
            isolated = isolateFocusedWindowInInfeasibleClampedScopes(from: result, in: snapshot)
            record(result, from: ApplyPlan(commands: plan.commands + repairPlan.commands))
            appendItemEvents(result)
            if isolated > 0 {
                result.applied += isolated
            }
        }
        let applyMs = Date().timeIntervalSince(applyStartedAt) * 1000

        let hideStartedAt = Date()
        let hiddenInactive = hideInactiveStageWindows(in: snapshot, onlyDisplayID: focusedScope.displayID)
        let hideMs = Date().timeIntervalSince(hideStartedAt) * 1000

        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        let appliedFrames = framesAfterApplying(result, fallback: observedFrames)
        lastObservedFrames = hiddenInactive > 0
            ? scopedFrames(in: service.snapshot(followFocus: false))
            : appliedFrames

        events.append(RoadieEvent(type: "stage_focus_restore", details: [
            "hiddenActive": String(activeHiddenEntries.count),
            "scopes": activeHiddenScopes
                .map { "\($0.displayID.rawValue)/\($0.desktopID.rawValue)/\($0.stageID.rawValue)" }
                .sorted()
                .joined(separator: ","),
            "commands": String(plan.commands.count + repairPlan.commands.count + isolated),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "hiddenInactive": String(hiddenInactive),
            "focusedWindowID": String(focusedWindowID.rawValue),
            "focusedDisplayID": focusedScope.displayID.rawValue,
            "planMs": String(format: "%.1f", planMs),
            "applyMs": String(format: "%.1f", applyMs),
            "hideMs": String(format: "%.1f", hideMs),
            "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000)
        ]))

        return MaintenanceTick(
            commands: plan.commands.count + repairPlan.commands.count + isolated + hiddenInactive,
            applied: result.applied + hiddenInactive,
            clamped: result.clamped,
            failed: result.failed
        )
    }

    private func restoreVisiblePinnedWindows(in snapshot: DaemonSnapshot) -> Int {
        var applied = 0
        for entry in snapshot.windows {
            guard let pin = entry.pin,
                  let activeScope = snapshot.state.activeScope(on: pin.homeScope.displayID),
                  pin.visibility(in: activeScope).shouldBeVisible,
                  isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays)
            else { continue }

            if service.setFrame(pin.lastFrame.cgRect, of: entry.window) != nil {
                applied += 1
            }
        }
        return applied
    }

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        HiddenWindowPlacement.frame(for: frame, on: display, among: displays)
    }

    private func isHiddenCorner(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        HiddenWindowPlacement.isHidden(frame, in: displays)
    }

    private func isPreferredHiddenCorner(_ frame: CGRect, among displays: [DisplaySnapshot]) -> Bool {
        HiddenWindowPlacement.isPreferred(frame, among: displays)
    }
}

private struct RulePlacementDestination {
    var display: DisplaySnapshot
    var scope: StageScope
    var follow: Bool
}

private struct ClampedFrame {
    var requested: Rect
    var actual: Rect

    func matches(command: ApplyCommand) -> Bool {
        if command.window.frame.isClose(to: actual, positionTolerance: 8, sizeTolerance: 8),
           requested.isClose(to: command.frame) {
            return true
        }
        if impossibleKnownMinimumIsStillRequested(by: command) {
            return true
        }
        let currentLooksLikeClampedMinimum = abs(command.window.frame.width - actual.width) <= 24
            && abs(command.window.frame.height - actual.height) <= 24
        guard currentLooksLikeClampedMinimum,
              requested.isClose(to: command.frame, positionTolerance: 64, sizeTolerance: 24)
        else {
            return sameImpossibleAxisIsStillRequested(by: command)
        }
        return command.frame.width <= command.window.frame.width + 8
            && command.frame.height <= command.window.frame.height + 8
    }

    func shouldExcludeFromLayout(window: WindowSnapshot) -> Bool {
        let currentStillMatchesClamp = abs(window.frame.width - actual.width) <= 24
            && abs(window.frame.height - actual.height) <= 24
        guard currentStillMatchesClamp else { return false }

        return requestedGrowthWasRejected(requested: requested.width, actual: actual.width)
            || requestedGrowthWasRejected(requested: requested.height, actual: actual.height)
    }

    private func sameImpossibleAxisIsStillRequested(by command: ApplyCommand) -> Bool {
        let currentStillMatchesClamp = abs(command.window.frame.width - actual.width) <= 24
            && abs(command.window.frame.height - actual.height) <= 24
        guard currentStillMatchesClamp else { return false }

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
        let widthMinimumStillRelevant = command.window.frame.width >= actual.width - 24
            && requestedShrinkWasRejected(requested: command.frame.width, actual: actual.width)
        let heightMinimumStillRelevant = command.window.frame.height >= actual.height - 24
            && requestedShrinkWasRejected(requested: command.frame.height, actual: actual.height)
        return widthMinimumStillRelevant || heightMinimumStillRelevant
    }

    private func requestedGrowthWasRejected(requested: Double, actual: Double) -> Bool {
        let tolerance = max(64, actual * 0.35)
        return requested > actual + tolerance
    }

    private func requestedShrinkWasRejected(requested: Double, actual: Double) -> Bool {
        requested < actual - 24
    }
}

private struct FailedFrame {
    var requested: Rect
    var observedAtFailure: Rect
    var failedAt: Date

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame)
            && command.window.frame.isClose(to: observedAtFailure, positionTolerance: 4, sizeTolerance: 4)
    }
}

private struct RevertedAppliedFrame {
    var requested: Rect
    var observedBeforeApply: Rect
    var appliedAt: Date

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame)
            && command.window.frame.isClose(to: observedBeforeApply, positionTolerance: 4, sizeTolerance: 4)
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
    func isClose(to other: Rect, positionTolerance: Double = 48, sizeTolerance: Double = 48) -> Bool {
        abs(x - other.x) <= positionTolerance
            && abs(y - other.y) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
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
