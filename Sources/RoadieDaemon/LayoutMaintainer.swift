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
    private let ruleEngine: WindowRuleEngine?
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

    public init(
        service: SnapshotService = SnapshotService(),
        events: EventLog = EventLog(),
        intervalSeconds: TimeInterval = 0.5,
        ruleEngine: WindowRuleEngine? = LayoutMaintainer.defaultRuleEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.events = events
        self.intervalSeconds = intervalSeconds
        self.commandIntentHoldSeconds = max(4, intervalSeconds * 10)
        self.manualResizeDebounceSeconds = max(0.35, intervalSeconds * 0.9)
        self.ruleEngine = ruleEngine
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
        evaluateRules(in: snapshot)

        let restoredPins = restoreVisiblePinnedWindows(in: snapshot)
        if restoredPins > 0 {
            events.append(RoadieEvent(type: "window.pin_restored", details: ["applied": String(restoredPins)]))
            return MaintenanceTick(commands: restoredPins, applied: restoredPins, clamped: 0, failed: 0)
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
        let plan = suppressKnownUnmovableFrames(in: service.applyPlan(from: snapshot, priorityWindowIDs: priorityWindowIDs))
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
        let plan = suppressKnownUnmovableFrames(in: service.applyPlan(from: snapshot, priorityWindowIDs: priorityWindowIDs))
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

    private func evaluateRules(in snapshot: DaemonSnapshot) {
        guard let ruleEngine else { return }
        guard ruleEngine.validationErrors.isEmpty else {
            appendRuleFailedEvents(ruleEngine.validationErrors)
            return
        }
        for entry in snapshot.windows where entry.window.isOnScreen {
            let context = WindowRuleMatchContext(
                display: entry.scope?.displayID.rawValue,
                desktop: entry.scope.map { String($0.desktopID.rawValue) },
                stage: entry.scope?.stageID.rawValue
            )
            let application = ruleEngine.evaluate(window: entry.window, context: context)
            appendRuleEvents(application, window: entry.window)
        }
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

    private func ruleActionPayload(_ application: WindowRuleApplication) -> [String: AutomationPayload] {
        var payload: [String: AutomationPayload] = [:]
        payload["excluded"] = .bool(application.excluded)
        if let assignDesktop = application.assignDesktop {
            payload["assignDesktop"] = .string(assignDesktop)
        }
        if let assignStage = application.assignStage {
            payload["assignStage"] = .string(assignStage)
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

    private func suppressKnownUnmovableFrames(in plan: ApplyPlan) -> ApplyPlan {
        let cutoff = now().addingTimeInterval(-max(3, intervalSeconds * 8))
        return ApplyPlan(commands: plan.commands.filter { command in
            if let known = clampedFrames[command.window.id.rawValue],
               known.matches(command: command) {
                return false
            }
            if let known = failedFrames[command.window.id.rawValue],
               known.failedAt >= cutoff,
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
                failedFrames[item.windowID.rawValue] = FailedFrame(requested: item.requested, failedAt: now())
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
            if service.hasMatchingCommandIntent(scope: scope, in: snapshot) {
                service.touchCommandIntent(scope: scope, at: now)
                result.insert(scope)
                continue
            }
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
                  !isHiddenCorner(entry.window.frame.cgRect, in: snapshot.displays)
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
    var failedAt: Date

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame)
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
