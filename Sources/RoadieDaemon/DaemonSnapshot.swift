import Foundation
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

public struct ScopedWindowSnapshot: Equatable, Codable, Sendable {
    public var window: WindowSnapshot
    public var scope: StageScope?

    public init(window: WindowSnapshot, scope: StageScope?) {
        self.window = window
        self.scope = scope
    }
}

public struct SnapshotService {
    private let provider: any SystemSnapshotProviding
    private let frameWriter: any WindowFrameWriting
    private let config: RoadieConfig
    private let intentStore: LayoutIntentStore
    private let stageStore: StageStore

    public init(
        provider: any SystemSnapshotProviding = LiveSystemSnapshotProvider(),
        frameWriter: any WindowFrameWriting = AXWindowFrameWriter(),
        config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig(),
        intentStore: LayoutIntentStore = LayoutIntentStore(),
        stageStore: StageStore = StageStore()
    ) {
        self.provider = provider
        self.frameWriter = frameWriter
        self.config = config
        self.intentStore = intentStore
        self.stageStore = stageStore
    }

    public func snapshot(promptForPermissions: Bool = false) -> DaemonSnapshot {
        let permissions = provider.permissions(prompt: promptForPermissions)
        let displays = provider.displays()
        let windows = provider.windows()
        let providerFocusedID = provider.focusedWindowID()
        var persistedStages = stageStore.state()
        let liveDisplayIDs = Set(displays.map(\.id))
        intentStore.prune(keepingDisplayIDs: liveDisplayIDs)
        if let activeDisplayID = persistedStages.activeDisplayID,
           !liveDisplayIDs.contains(activeDisplayID) {
            persistedStages.activeDisplayID = fallbackDisplayID(
                in: displays,
                persistedStages: persistedStages,
                focusedWindowID: providerFocusedID,
                windows: windows
            )
        }
        if let fallbackDisplayID = fallbackDisplayID(
            in: displays,
            persistedStages: persistedStages,
            focusedWindowID: providerFocusedID,
            windows: windows
        ) {
            persistedStages.migrateDisconnectedDisplays(keeping: liveDisplayIDs, fallbackDisplayID: fallbackDisplayID)
        }
        let liveWindowIDs = Set(windows.compactMap { window in
            window.isTileCandidate && !config.exclusions.floatingBundles.contains(window.bundleID) ? window.id : nil
        })
        persistedStages.pruneMissingWindows(keeping: liveWindowIDs)
        var state = RoadieState()
        var scopedWindows: [ScopedWindowSnapshot] = []

        for display in displays {
            state.ensureDisplay(display.id)
            let currentDesktopID = persistedStages.currentDesktopID(for: display.id)
            var persistentScope = persistedStages.scope(displayID: display.id, desktopID: currentDesktopID)
            persistentScope.applyConfiguredStages(config.stageManager)
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
        for window in windows {
            guard window.isTileCandidate && !config.exclusions.floatingBundles.contains(window.bundleID) else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            let knownScope = persistedStages.stageScope(for: window.id)
            guard let displayID = knownScope?.displayID ?? displayID(containing: window.frame.center, in: displays) ?? fallbackDisplayID else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            if knownScope == nil {
                var persistentScope = persistedStages.scope(
                    displayID: displayID,
                    desktopID: persistedStages.currentDesktopID(for: displayID)
                )
                persistentScope.assign(window: window, to: persistentScope.activeStageID)
                persistedStages.update(persistentScope)
            } else if !isHidden(window.frame.cgRect, in: displays) {
                var persistentScope = persistedStages.scope(
                    displayID: displayID,
                    desktopID: knownScope?.desktopID ?? persistedStages.currentDesktopID(for: displayID)
                )
                persistentScope.updateFrame(window: window)
                persistedStages.update(persistentScope)
            }
            let scope = StageScope(
                displayID: displayID,
                desktopID: knownScope?.desktopID ?? persistedStages.currentDesktopID(for: displayID),
                stageID: knownScope?.stageID ?? persistedStages.scope(displayID: displayID, desktopID: persistedStages.currentDesktopID(for: displayID)).activeStageID
            )
            let persistedStage = persistedStages.scopes
                .first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages
                .first { $0.id == scope.stageID }
            try? state.createStage(
                id: scope.stageID,
                name: "Stage \(scope.stageID.rawValue)",
                mode: persistedStage?.mode ?? config.tiling.defaultStrategy,
                in: scope.displayID,
                desktopID: scope.desktopID
            )
            try? state.setMode(persistedStage?.mode ?? config.tiling.defaultStrategy, for: scope)
            try? state.assignWindow(window.id, to: scope)
            scopedWindows.append(ScopedWindowSnapshot(window: window, scope: scope))
        }
        var focusedID: WindowID?
        if let providerFocusedID,
           let focusedScope = scopedWindows.first(where: { $0.window.id == providerFocusedID })?.scope,
           state.activeScope(on: focusedScope.displayID) == focusedScope {
            var persistentScope = persistedStages.scope(displayID: focusedScope.displayID, desktopID: focusedScope.desktopID)
            persistentScope.setFocusedWindow(providerFocusedID, in: focusedScope.stageID)
            persistedStages.update(persistentScope)
            persistedStages.focusDisplay(focusedScope.displayID)
            try? state.setFocusedWindow(providerFocusedID, for: focusedScope)
            focusedID = providerFocusedID
        } else {
            focusedID = activeFocusedWindowID(in: state, scopedWindows: scopedWindows, displays: displays)
        }
        stageStore.save(persistedStages)

        return DaemonSnapshot(
            permissions: permissions,
            displays: displays,
            windows: scopedWindows,
            state: state,
            focusedWindowID: focusedID
        )
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
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

    private func isHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        if frame.maxX < -1000 || frame.minX < -10000 {
            return true
        }
        return displays.contains { display in
            let visible = display.visibleFrame.cgRect
            let nearBottomEdge = abs(frame.minY - (visible.maxY - 1)) <= 64
            let nearLeftEdge = abs(frame.maxX - (visible.minX + 1)) <= 4
            let nearRightEdge = abs(frame.minX - (visible.maxX - 1)) <= 4
            return nearBottomEdge && (nearLeftEdge || nearRightEdge)
        }
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
            if effectiveMode != .float, let intent = validIntent(for: scope, from: snapshot) {
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

    func orderedWindowIDs(
        in scope: StageScope,
        from snapshot: DaemonSnapshot,
        mode: WindowManagementMode? = nil
    ) -> [WindowID] {
        guard let stage = snapshot.state.stage(scope: scope),
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return [] }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        let effectiveMode = mode ?? stage.mode
        guard effectiveMode == .bsp else { return stage.windowIDs }

        return spatiallyOrdered(stage.windowIDs, frames: currentFrames, container: display.visibleFrame.cgRect)
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
        source: LayoutIntent.Source
    ) {
        intentStore.save(LayoutIntent(scope: scope, windowIDs: windowIDs, placements: placements, source: source))
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
        focusedWindowID: WindowID? = nil
    ) -> Bool {
        guard let intent = intentStore.intent(for: scope) else { return false }
        return intent.placements.allSatisfy { id, frame in
            guard let observed = frames[id.rawValue] else { return false }
            if id == focusedWindowID {
                return isLikelyFocusWindowChromeDelta(observed, baseline: frame) || observed.isClose(to: frame, positionTolerance: 12, sizeTolerance: 36)
            }
            return observed.isClose(to: frame, positionTolerance: 8, sizeTolerance: 8)
        }
    }

    func hasMatchingCommandIntent(scope: StageScope, in snapshot: DaemonSnapshot) -> Bool {
        guard let intent = intentStore.intent(for: scope),
              intent.source == .command
        else { return false }

        let focusedWindowID = focusedWindowID()

        let currentFrames: [WindowID: Rect] = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry in
            guard entry.scope == scope else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        guard Set(currentFrames.keys) == Set(intent.windowIDs) else { return false }

        return intent.placements.allSatisfy { id, frame in
            guard let observed = currentFrames[id] else { return false }
            if id == focusedWindowID {
                return isLikelyFocusWindowChromeDelta(observed, baseline: frame) || observed.isClose(to: frame, positionTolerance: 12, sizeTolerance: 36)
            }
            return observed.isClose(to: frame, positionTolerance: 4, sizeTolerance: 4)
        }
    }

    func touchCommandIntent(scope: StageScope, at date: Date = Date()) {
        intentStore.touch(scope: scope, at: date)
    }

    func hasRecentCommandIntent(scope: StageScope, since date: Date) -> Bool {
        guard let intent = intentStore.intent(for: scope) else { return false }
        return intent.source == .command && intent.createdAt >= date
    }

    func applyPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        mode: WindowManagementMode? = nil,
        priorityWindowIDs: Set<WindowID> = []
    ) -> ApplyPlan {
        guard let stage = snapshot.state.stage(scope: scope),
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return ApplyPlan(commands: []) }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
            windowsByID[id].map { (id, $0.frame.cgRect) }
        })
        let effectiveMode = mode ?? stage.mode
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: effectiveMode,
            container: display.visibleFrame.cgRect,
            windowIDs: orderedWindowIDs,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: stage.windowIDs.count),
            innerGap: config.tiling.gapsInner
        ))
        let currentPlan = LayoutPlan(placements: currentFrames)

        let commands = LayoutDiff.commands(previous: currentPlan, next: plan).compactMap { command -> ApplyCommand? in
            guard let window = windowsByID[command.windowID] else { return nil }
            return ApplyCommand(window: window, frame: Rect(command.frame))
        }
        return ApplyPlan(commands: commands)
    }

    private func validIntent(for scope: StageScope, from snapshot: DaemonSnapshot) -> LayoutIntent? {
        guard let intent = intentStore.intent(for: scope) else { return nil }
        let scopedIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate ? entry.window.id : nil
        })
        guard scopedIDs == Set(intent.windowIDs) else {
            intentStore.remove(scope: scope)
            return nil
        }
        if intent.source == .command,
           isRecentCommandIntent(intent),
           hasCommandIntentShape(for: intent, snapshot: snapshot, scope: scope) {
            return intent
        }
        guard intentStillTilesCurrentContainer(intent, scope: scope, from: snapshot) else {
            intentStore.remove(scope: scope)
            return nil
        }
        return intent
    }

    private func intentStillTilesCurrentContainer(
        _ intent: LayoutIntent,
        scope: StageScope,
        from snapshot: DaemonSnapshot
    ) -> Bool {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }),
              !intent.windowIDs.isEmpty
        else { return false }

        let targetArea = canonicalTiledArea(for: intent, display: display)
        guard targetArea > 0 else { return false }

        let container = display.visibleFrame.cgRect.inset(by: outerGaps(windowCount: intent.windowIDs.count))
        let frames = intent.windowIDs.compactMap { intent.placements[$0]?.cgRect }
        guard frames.count == intent.windowIDs.count else { return false }
        guard frames.allSatisfy({ container.contains($0, tolerance: 4) }) else { return false }
        guard !framesContainSignificantOverlap(frames) else { return false }
        guard framesHaveReasonableTileSizes(frames, in: container) else { return false }

        let intentArea = frames.reduce(CGFloat(0)) { $0 + $1.area }
        return intentArea >= targetArea * 0.95
    }

    private func framesHaveReasonableTileSizes(_ frames: [CGRect], in container: CGRect) -> Bool {
        guard frames.count > 1 else { return true }
        let minimumSide = max(120, min(container.width, container.height) * 0.18)
        return frames.allSatisfy { frame in
            frame.width >= minimumSide && frame.height >= minimumSide
        }
    }

    private func hasCommandIntentShape(
        for intent: LayoutIntent,
        snapshot: DaemonSnapshot,
        scope: StageScope
    ) -> Bool {
        let tolerance: Double = 32
        let scopedFrames = snapshot.windows.compactMap { entry -> (WindowID, CGRect)? in
            guard entry.scope == scope,
                  intent.placements[entry.window.id] != nil
            else { return nil }
            return (entry.window.id, entry.window.frame.cgRect)
        }
        for (id, observed) in scopedFrames {
            guard let target = intent.placements[id]?.cgRect,
                  abs(observed.minX - target.minX) <= tolerance,
                  abs(observed.minY - target.minY) <= tolerance,
                  abs(observed.width - target.width) <= tolerance,
                  abs(observed.height - target.height) <= tolerance
            else { return false }
        }
        return true
    }

    private func isRecentCommandIntent(_ intent: LayoutIntent) -> Bool {
        let now = Date()
        let freshness = TimeInterval(5)
        return now.timeIntervalSince(intent.createdAt) <= freshness
    }

    private func canonicalTiledArea(for intent: LayoutIntent, display: DisplaySnapshot) -> CGFloat {
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: intent.scope,
            mode: config.tiling.defaultStrategy,
            container: display.visibleFrame.cgRect,
            windowIDs: intent.windowIDs,
            splitPolicy: config.tiling.splitPolicy,
            outerGaps: outerGaps(windowCount: intent.windowIDs.count),
            innerGap: config.tiling.gapsInner
        ))
        return plan.placements.values.reduce(CGFloat(0)) { $0 + $1.area }
    }

    private func framesContainSignificantOverlap(_ frames: [CGRect]) -> Bool {
        guard frames.count > 1 else { return false }
        for index in frames.indices {
            for otherIndex in frames.index(after: index)..<frames.endIndex {
                if frames[index].intersection(frames[otherIndex]).area > 16 {
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
        return dx <= 8 && (dy <= 12 || dh <= 12) && (dw <= 2 && dh <= 80)
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
                status: actualRect.isClose(to: command.frame) ? .applied : .clamped,
                requested: command.frame,
                actual: actualRect
            ))
        }
        let applied = items.filter { $0.status == .applied }.count
        let clamped = items.filter { $0.status == .clamped }.count
        let failed = items.filter { $0.status == .failed }.count
        return ApplyResult(
            attempted: plan.commands.count,
            applied: applied,
            clamped: clamped,
            failed: failed,
            items: items
        )
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        frameWriter.focus(window)
    }

    func reset(_ window: WindowSnapshot) -> Bool {
        frameWriter.reset(window)
    }

    func focusedWindowID() -> WindowID? {
        provider.focusedWindowID()
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        frameWriter.setFrame(frame, of: window)
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
            if abs(lhsFrame.midX - rhsFrame.midX) > 48 {
                return lhsFrame.midX < rhsFrame.midX
            }
            if abs(lhsFrame.midY - rhsFrame.midY) > 48 {
                return lhsFrame.midY < rhsFrame.midY
            }
        } else {
            if abs(lhsFrame.midY - rhsFrame.midY) > 48 {
                return lhsFrame.midY < rhsFrame.midY
            }
            if abs(lhsFrame.midX - rhsFrame.midX) > 48 {
                return lhsFrame.midX < rhsFrame.midX
            }
        }
        return lhs < rhs
    }

    func rects(for windowIDs: [WindowID], in frames: [WindowID: CGRect]) -> [CGRect] {
        windowIDs.compactMap { frames[$0] }
    }

    func outerGaps(windowCount: Int) -> Insets {
        var top = config.tiling.gapsOuterTop ?? config.tiling.gapsOuter
        var right = config.tiling.gapsOuterRight ?? config.tiling.gapsOuter
        var bottom = config.tiling.gapsOuterBottom ?? config.tiling.gapsOuter
        var left = config.tiling.gapsOuterLeft ?? config.tiling.gapsOuter

        if config.tiling.smartGapsSolo && windowCount == 1 {
            let sides = config.tiling.smartGapsSoloSides
            if sides.contains(.top) { top = 0 }
            if sides.contains(.right) { right = 0 }
            if sides.contains(.bottom) { bottom = 0 }
            if sides.contains(.left) { left = 0 }
        }

        return Insets(top: top, right: right, bottom: bottom, left: left)
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
}
