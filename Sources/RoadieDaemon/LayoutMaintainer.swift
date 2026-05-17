import Foundation
import RoadieAX
import RoadieCore

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
    private let now: () -> Date
    private let staticRuleEngine: WindowRuleEngine?
    private let store: StageStore
    private let dragActivity: WindowDragActivity
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
    private var displayTopologySettlesUntil: Date?
    private var emittedRuleSkippedKeys: Set<String> = []
    private var emittedRuleAppliedKeys: Set<String> = []
    private var emittedRulePlacementIssueKeys: Set<String> = []
    private var observedRulePlacementWindowIDs: Set<WindowID> = []

    public init(
        service: SnapshotService = SnapshotService(),
        events: EventLog = EventLog(),
        intervalSeconds: TimeInterval = 0.5,
        ruleEngine: WindowRuleEngine? = nil,
        store: StageStore? = nil,
        dragActivity: WindowDragActivity = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.events = events
        self.intervalSeconds = intervalSeconds
        self.commandIntentHoldSeconds = max(4, intervalSeconds * 10)
        self.manualResizeDebounceSeconds = max(0.35, intervalSeconds * 0.9)
        self.staticRuleEngine = ruleEngine
        self.store = store ?? service.effectiveStageStore
        self.dragActivity = dragActivity
        self.now = now
    }

    public func tick() -> MaintenanceTick {
        let snapshot = service.snapshot()
        guard snapshot.permissions.accessibilityTrusted else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        let currentDisplaySignature = displaySignature(snapshot.displays)
        let tickNow = now()
        if let lastDisplaySignature, lastDisplaySignature != currentDisplaySignature {
            self.lastDisplaySignature = currentDisplaySignature
            displayTopologySettlesUntil = tickNow.addingTimeInterval(max(1.5, intervalSeconds * 4))
            lastObservedFrames = scopedFrames(in: snapshot)
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
            lastObservedFrames = scopedFrames(in: snapshot)
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
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

        if let focusRestore = restoreFocusedActiveStageIfNeeded(in: snapshot) {
            return focusRestore
        }

        let hiddenInactive = hideInactiveStageWindows(in: snapshot)
        if hiddenInactive > 0 {
            events.append(RoadieEvent(type: "stage_hide_inactive", details: ["applied": String(hiddenInactive)]))
            return MaintenanceTick(commands: hiddenInactive, applied: hiddenInactive, clamped: 0, failed: 0)
        }

        let observedFrames = scopedFrames(in: snapshot)
        let changedWindowIDs = changedWindows(in: observedFrames)
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

        if let manualResizeApplyAfter, now < manualResizeApplyAfter {
            lastObservedFrames = observedFrames
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }
        manualResizeApplyAfter = nil

        let commandProtectedScopes = recentCommandScopes(in: snapshot, since: cutoff, now: now, windowIDs: priorityWindowIDs)
        if !commandProtectedScopes.isEmpty {
            lastCommandIntentAt = now
            priorityWindowIDs = []
            manualResizeApplyAfter = nil
            let tick = applyPlan(from: snapshot, observedFrames: observedFrames, excluding: commandProtectedScopes)
            events.append(RoadieEvent(type: "manual_resize_suppressed_by_command_intent", details: [
                "scopes": commandProtectedScopes.map(\.description).sorted().joined(separator: ","),
                "unprotectedCommands": String(tick.commands)
            ]))
            return tick
        }

        if let lastCommandIntentAt,
           priorityWindowIDs.isEmpty,
           now.timeIntervalSince(lastCommandIntentAt) < commandIntentHoldSeconds
        {
            let protectedScopes = recentCommandScopes(in: snapshot, since: cutoff, now: now)
            priorityWindowIDs = []
            return applyPlan(from: snapshot, observedFrames: observedFrames, excluding: protectedScopes)
        }

        lastObservedFrames = observedFrames
        let plan = suppressKnownUnmovableFrames(
            in: service.applyPlan(from: snapshot, priorityWindowIDs: priorityWindowIDs),
            snapshot: snapshot
        )
        guard !plan.commands.isEmpty else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        var result = service.apply(plan)
        result = stabilizeClampedPositions(result, from: plan)
        if !priorityWindowIDs.isEmpty {
            persistLayoutIntent(in: snapshot, result: result)
        }
        record(result, from: plan)
        events.append(RoadieEvent(type: "layout_apply", details: [
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "priorityWindowIDs": priorityWindowIDs.map { String($0.rawValue) }.sorted().joined(separator: ",")
        ]))
        appendItemEvents(result)
        let appliedFrames = framesAfterApplying(result, fallback: observedFrames)
        priorityWindowIDs = []
        manualResizeApplyAfter = nil
        lastObservedFrames = appliedFrames
        return MaintenanceTick(
            commands: plan.commands.count,
            applied: result.applied,
            clamped: result.clamped,
            failed: result.failed
        )
    }

    private func applyPlan(
        from snapshot: DaemonSnapshot,
        observedFrames: [UInt32: Rect],
        excluding protectedScopes: Set<StageScope>
    ) -> MaintenanceTick {
        lastObservedFrames = observedFrames
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
        let plan = suppressKnownUnmovableFrames(
            in: service.applyPlan(from: snapshot, priorityWindowIDs: priorityWindowIDs),
            snapshot: snapshot
        )
        let filtered = ApplyPlan(commands: plan.commands.filter { command in
            guard let scope = windowsByID[command.window.id]?.scope else { return true }
            return !protectedScopes.contains(scope)
        })
        guard !filtered.commands.isEmpty else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        var result = service.apply(filtered)
        result = stabilizeClampedPositions(result, from: filtered)
        record(result, from: filtered)
        appendItemEvents(result)
        lastObservedFrames = framesAfterApplying(result, fallback: observedFrames)
        return MaintenanceTick(
            commands: filtered.commands.count,
            applied: result.applied,
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
        "\(suffix)|\(window.id.rawValue)|\(window.appName)|\(window.title)"
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
        let fullscreenWindowIDs = Set(fullscreenLikeEntries(in: snapshot).map(\.entry.window.id))
        return ApplyPlan(commands: plan.commands.filter { command in
            if fullscreenWindowIDs.contains(command.window.id) {
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

    private func suppressFullscreenLikeChanges(
        in snapshot: DaemonSnapshot,
        frames: [UInt32: Rect],
        changedWindowIDs: Set<WindowID>
    ) -> Bool {
        let entries = fullscreenLikeEntries(in: snapshot, windowIDs: changedWindowIDs)
        guard !entries.isEmpty else { return false }
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
        windowIDs: Set<WindowID>? = nil
    ) -> [(entry: ScopedWindowSnapshot, display: DisplaySnapshot)] {
        snapshot.windows.compactMap { entry in
            guard entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  windowIDs.map({ $0.contains(entry.window.id) }) ?? true,
                  let display = display(for: entry, in: snapshot),
                  isFullscreenLike(entry.window.frame.cgRect, on: display)
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

    private func isFullscreenLike(_ frame: CGRect, on display: DisplaySnapshot) -> Bool {
        framesAreClose(frame, display.visibleFrame.cgRect, tolerance: 48)
            || framesAreClose(frame, display.frame.cgRect, tolerance: 48)
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func record(_ result: ApplyResult, from plan: ApplyPlan) {
        let commandsByID = Dictionary(uniqueKeysWithValues: plan.commands.map { ($0.window.id, $0) })
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

    private func stabilizeClampedPositions(_ result: ApplyResult, from plan: ApplyPlan) -> ApplyResult {
        var stabilizedItems = result.items
        let commandsByID = Dictionary(uniqueKeysWithValues: plan.commands.map { ($0.window.id, $0) })

        for index in stabilizedItems.indices {
            var item = stabilizedItems[index]
            guard item.status == .clamped,
                  let actual = item.actual,
                  let command = commandsByID[item.windowID]
            else { continue }

            let anchored = Rect(
                x: item.requested.x,
                y: item.requested.y,
                width: actual.width,
                height: actual.height
            )
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
            service.saveLayoutIntent(scope: scope, windowIDs: stage.windowIDs, placements: placements)
        }
    }

    private func changedWindows(in frames: [UInt32: Rect]) -> Set<WindowID> {
        guard let previous = lastObservedFrames else { return [] }
        var result: Set<WindowID> = []
        for (id, frame) in frames {
            guard let previousFrame = previous[id] else { continue }
            if !frame.isClose(to: previousFrame, positionTolerance: 36, sizeTolerance: 36) {
                result.insert(WindowID(rawValue: id))
            }
        }
        return result
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

    private func hideInactiveStageWindows(in snapshot: DaemonSnapshot) -> Int {
        var applied = 0
        for entry in snapshot.windows {
            guard let scope = entry.scope,
                  let activeScope = snapshot.state.activeScope(on: scope.displayID),
                  scope != activeScope,
                  let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays),
                  !isFullscreenLike(entry.window.frame.cgRect, on: display)
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

    private func restoreFocusedActiveStageIfNeeded(in snapshot: DaemonSnapshot) -> MaintenanceTick? {
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
        if !plan.commands.isEmpty {
            result = service.apply(plan)
            result = stabilizeClampedPositions(result, from: plan)
            record(result, from: plan)
            appendItemEvents(result)
        }
        let applyMs = Date().timeIntervalSince(applyStartedAt) * 1000

        let hideStartedAt = Date()
        let hiddenInactive = hideInactiveStageWindows(in: snapshot)
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
            "commands": String(plan.commands.count),
            "applied": String(result.applied),
            "clamped": String(result.clamped),
            "failed": String(result.failed),
            "hiddenInactive": String(hiddenInactive),
            "planMs": String(format: "%.1f", planMs),
            "applyMs": String(format: "%.1f", applyMs),
            "hideMs": String(format: "%.1f", hideMs),
            "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000)
        ]))

        return MaintenanceTick(
            commands: plan.commands.count + hiddenInactive,
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
        let visible = display.visibleFrame.cgRect
        switch optimalHideCorner(for: display, among: displays) {
        case .bottomLeft:
            return CGRect(
                x: visible.minX + 1 - frame.width,
                y: visible.maxY - 1,
                width: frame.width,
                height: frame.height
            ).integral
        case .bottomRight:
            return CGRect(
                x: visible.maxX - 1,
                y: visible.maxY - 1,
                width: frame.width,
                height: frame.height
            ).integral
        }
    }

    private func optimalHideCorner(for display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> HideCorner {
        let frame = display.frame.cgRect
        let xOffset = frame.width * 0.1
        let yOffset = frame.height * 0.1
        let bottomLeft = CGPoint(x: frame.minX, y: frame.maxY)
        let bottomRight = CGPoint(x: frame.maxX, y: frame.maxY)

        let leftScore = overlapScore(points: [
            CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y - yOffset),
            CGPoint(x: bottomLeft.x + xOffset, y: bottomLeft.y + 2),
            CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y + 2),
        ], displays: displays)
        let rightScore = overlapScore(points: [
            CGPoint(x: bottomRight.x + 2, y: bottomRight.y - yOffset),
            CGPoint(x: bottomRight.x - xOffset, y: bottomRight.y + 2),
            CGPoint(x: bottomRight.x + 2, y: bottomRight.y + 2),
        ], displays: displays)
        return leftScore < rightScore ? .bottomLeft : .bottomRight
    }

    private func overlapScore(points: [CGPoint], displays: [DisplaySnapshot]) -> Int {
        points.enumerated().reduce(0) { score, item in
            let weight = item.offset == 2 ? 10 : 1
            let overlaps = displays.filter { $0.frame.cgRect.contains(item.element) }.count
            return score + weight * overlaps
        }
    }

    private func isHiddenCorner(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        displays.contains { display in
            let visible = display.visibleFrame.cgRect
            let nearBottomEdge = abs(frame.minY - (visible.maxY - 1)) <= 64
            let nearLeftEdge = abs(frame.maxX - (visible.minX + 1)) <= 4
            let nearRightEdge = abs(frame.minX - (visible.maxX - 1)) <= 4
            return nearBottomEdge && (nearLeftEdge || nearRightEdge)
        }
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
        requested.isClose(to: command.frame)
            && command.window.frame.isClose(to: actual)
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

private enum HideCorner {
    case bottomLeft
    case bottomRight
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
// MARK: - Temporary Focus-Jitter Guard
// Keep focus-only geometry jitter from mouse clicks from forcing a full relayout.
