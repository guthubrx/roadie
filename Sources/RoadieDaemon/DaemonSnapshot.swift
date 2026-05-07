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

    public init(
        permissions: PermissionSnapshot,
        displays: [DisplaySnapshot],
        windows: [ScopedWindowSnapshot],
        state: RoadieState
    ) {
        self.permissions = permissions
        self.displays = displays
        self.windows = windows
        self.state = state
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

    public init(
        provider: any SystemSnapshotProviding = LiveSystemSnapshotProvider(),
        frameWriter: any WindowFrameWriting = AXWindowFrameWriter(),
        config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
    ) {
        self.provider = provider
        self.frameWriter = frameWriter
        self.config = config
    }

    public func snapshot(promptForPermissions: Bool = false) -> DaemonSnapshot {
        let permissions = provider.permissions(prompt: promptForPermissions)
        let displays = provider.displays()
        let windows = provider.windows()
        var state = RoadieState()
        var scopedWindows: [ScopedWindowSnapshot] = []

        for display in displays {
            state.ensureDisplay(display.id)
        }

        let fallbackDisplayID = displays.first?.id
        for window in windows {
            guard window.isTileCandidate && !config.exclusions.floatingBundles.contains(window.bundleID) else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            guard let displayID = displayID(containing: window.frame.center, in: displays) ?? fallbackDisplayID else {
                scopedWindows.append(ScopedWindowSnapshot(window: window, scope: nil))
                continue
            }
            let scope = StageScope(
                displayID: displayID,
                desktopID: DesktopID(rawValue: 1),
                stageID: StageID(rawValue: "1")
            )
            try? state.assignWindow(window.id, to: scope)
            scopedWindows.append(ScopedWindowSnapshot(window: window, scope: scope))
        }

        return DaemonSnapshot(
            permissions: permissions,
            displays: displays,
            windows: scopedWindows,
            state: state
        )
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
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
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope)
            else { continue }

            let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
            let currentFrames = Dictionary(uniqueKeysWithValues: stage.windowIDs.compactMap { id in
                windowsByID[id].map { (id, $0.frame.cgRect) }
            })
            let effectiveMode = mode ?? config.tiling.defaultStrategy
            let orderedWindowIDs = effectiveMode == .bsp
                ? spatiallyOrdered(stage.windowIDs, frames: currentFrames, container: display.visibleFrame.cgRect)
                : stage.windowIDs
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

            for command in LayoutDiff.commands(previous: currentPlan, next: plan) {
                guard let window = windowsByID[command.windowID] else { continue }
                commands.append(ApplyCommand(window: window, frame: Rect(command.frame)))
            }
        }
        return ApplyPlan(commands: commands)
    }

    func apply(_ plan: ApplyPlan) -> ApplyResult {
        var items: [ApplyResultItem] = []
        for command in plan.commands {
            guard let actual = frameWriter.setFrame(command.frame.cgRect, of: command.window) else {
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
}
