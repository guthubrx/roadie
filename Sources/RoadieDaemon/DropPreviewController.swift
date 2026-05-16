import AppKit
import Foundation
import RoadieAX
import RoadieCore

@MainActor
final class DropPreviewController {
    private let engine: DropPreviewEngine
    private let overlay = DropPreviewOverlayWindow()
    private var lastCandidate: DropPreviewCandidate?

    init(engine: DropPreviewEngine = DropPreviewEngine()) {
        self.engine = engine
    }

    var candidate: DropPreviewCandidate? {
        lastCandidate
    }

    @discardableResult
    func update(sourceWindowID: WindowID, at point: CGPoint, displayID: DisplayID? = nil) -> DropPreviewCandidate? {
        guard let candidate = engine.candidate(sourceWindowID: sourceWindowID, at: point, displayID: displayID) else {
            hide()
            return nil
        }
        lastCandidate = candidate
        overlay.show(candidate)
        return candidate
    }

    func hide() {
        lastCandidate = nil
        overlay.hide()
    }
}

struct DropPreviewCandidate: Equatable {
    var sourceWindowID: WindowID
    var displayID: DisplayID
    var scope: StageScope
    var orderedWindowIDs: [WindowID]
    var placements: [WindowID: Rect]
    var frame: CGRect
    var operation: DropPreviewOperation
}

enum DropPreviewOperation: String, Equatable {
    case append
    case insertLeft
    case insertRight
    case insertUp
    case insertDown
    case swap

    var tint: NSColor {
        switch self {
        case .swap:
            return NSColor.systemOrange
        default:
            return NSColor.systemGreen
        }
    }
}

struct DropPreviewEngine {
    private let service: SnapshotService

    init(service: SnapshotService = SnapshotService()) {
        self.service = service
    }

    func candidate(sourceWindowID: WindowID, at point: CGPoint, displayID forcedDisplayID: DisplayID? = nil) -> DropPreviewCandidate? {
        let axPoint = ScreenCoordinate.nsPointToAX(point)
        return candidate(sourceWindowID: sourceWindowID, atAXPoint: axPoint, displayID: forcedDisplayID)
    }

    func candidate(sourceWindowID: WindowID, atAXPoint axPoint: CGPoint, displayID forcedDisplayID: DisplayID? = nil) -> DropPreviewCandidate? {
        let snapshot = service.snapshot()
        guard let display = display(containing: axPoint, forcedDisplayID: forcedDisplayID, in: snapshot.displays),
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope),
              stage.mode != .float,
              snapshot.windows.contains(where: {
                  $0.window.id == sourceWindowID
                      && $0.scope == scope
                      && WindowDragReorderEligibility.accepts($0.window)
              })
        else { return nil }

        let activeEntries = snapshot.windows.filter { entry in
            entry.scope == scope && entry.window.isTileCandidate
        }
        var ordered = service.orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
        if !ordered.contains(sourceWindowID) {
            ordered.append(sourceWindowID)
        }

        let target = activeEntries
            .filter { $0.window.id != sourceWindowID && $0.window.frame.cgRect.contains(axPoint) }
            .sorted { $0.window.frame.cgRect.area < $1.window.frame.cgRect.area }
            .first

        var placements: [WindowID: CGRect] = [:]
        let operation: DropPreviewOperation
        if let target {
            operation = dropOperation(at: axPoint, in: target.window.frame.cgRect, sourceIsActive: activeEntries.contains { $0.window.id == sourceWindowID })
            ordered = reordered(ordered, sourceID: sourceWindowID, targetID: target.window.id, operation: operation)
            if stage.mode == .mutableBsp {
                placements = reflowingTargetPlacements(
                    sourceID: sourceWindowID,
                    target: target.window,
                    operation: operation,
                    activeEntries: activeEntries,
                    display: display
                ) ?? [:]
            } else {
                placements = structuralPlacements(
                    sourceID: sourceWindowID,
                    target: target.window,
                    operation: operation,
                    activeEntries: activeEntries,
                    display: display
                ) ?? [:]
            }
        } else {
            operation = .append
            ordered = ordered.filter { $0 != sourceWindowID } + [sourceWindowID]
        }

        let plan = service.layoutPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, priorityWindowIDs: [sourceWindowID])
        if placements.isEmpty {
            placements = plan.placements
        }
        guard let frame = placements[sourceWindowID], !frame.isEmpty else { return nil }
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: ordered,
            placements: Dictionary(uniqueKeysWithValues: placements.map { ($0.key, Rect($0.value.integral)) }),
            frame: frame.integral,
            operation: operation
        )
    }

    private func display(containing point: CGPoint, forcedDisplayID: DisplayID?, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let forced = forcedDisplayID {
            return displays.first { $0.id == forced && $0.frame.cgRect.contains(point) }
        }
        return displays.first { $0.frame.cgRect.contains(point) }
    }

    private func dropOperation(at point: CGPoint, in frame: CGRect, sourceIsActive: Bool) -> DropPreviewOperation {
        let unitX = (point.x - frame.minX) / max(1, frame.width)
        let unitY = (point.y - frame.minY) / max(1, frame.height)
        let edge: CGFloat = 0.28
        if unitX < edge { return .insertLeft }
        if unitX > 1 - edge { return .insertRight }
        if unitY < edge { return .insertUp }
        if unitY > 1 - edge { return .insertDown }
        return sourceIsActive ? .swap : .insertRight
    }

    private func reordered(
        _ orderedWindowIDs: [WindowID],
        sourceID: WindowID,
        targetID: WindowID,
        operation: DropPreviewOperation
    ) -> [WindowID] {
        var result = orderedWindowIDs
        guard let targetIndex = result.firstIndex(of: targetID) else { return result }
        if operation == .swap, let sourceIndex = result.firstIndex(of: sourceID) {
            result.swapAt(sourceIndex, targetIndex)
            return result
        }

        result.removeAll { $0 == sourceID }
        let adjustedTargetIndex = result.firstIndex(of: targetID) ?? min(targetIndex, result.count)
        let insertionIndex: Int
        switch operation {
        case .insertLeft, .insertUp:
            insertionIndex = adjustedTargetIndex
        case .insertRight, .insertDown, .append, .swap:
            insertionIndex = min(adjustedTargetIndex + 1, result.count)
        }
        result.insert(sourceID, at: insertionIndex)
        return result
    }

    private func structuralPlacements(
        sourceID: WindowID,
        target: WindowSnapshot,
        operation: DropPreviewOperation,
        activeEntries: [ScopedWindowSnapshot],
        display: DisplaySnapshot
    ) -> [WindowID: CGRect]? {
        guard operation != .swap, operation != .append else { return nil }
        let horizontal: Bool
        switch operation {
        case .insertLeft, .insertUp:
            horizontal = operation == .insertLeft
        case .insertRight, .insertDown:
            horizontal = operation == .insertRight
        case .append, .swap:
            return nil
        }
        guard let sourceFrame = activeEntries.first(where: { $0.window.id == sourceID })?.window.frame.cgRect,
              let container = union(activeEntries.map { $0.window.frame.cgRect })
        else { return nil }

        let gap = CGFloat(service.innerGap())
        let targetSideIDs = Set(activeEntries.compactMap { entry -> WindowID? in
            guard entry.window.id != sourceID,
                  isOnTargetSide(entry.window.frame.cgRect, from: sourceFrame, operation: operation)
            else { return nil }
            return entry.window.id
        })
        var targetGroupWindows = activeEntries.map(\.window).filter { targetSideIDs.contains($0.id) || $0.id == target.id }
        targetGroupWindows.removeAll { $0.id == sourceID }
        let sourceGroupWindows = activeEntries.map(\.window).filter { entry in
            entry.id != sourceID && !targetGroupWindows.contains(where: { $0.id == entry.id })
        }
        guard !targetGroupWindows.isEmpty, !sourceGroupWindows.isEmpty else { return nil }

        let targetGroup = orderedTargetGroup(
            sourceID: sourceID,
            targetID: target.id,
            peers: spatiallySorted(targetGroupWindows, in: union(targetGroupWindows.map { $0.frame.cgRect }) ?? target.frame.cgRect),
            operation: operation
        )
        let sourceGroup = spatiallySorted(sourceGroupWindows, in: union(sourceGroupWindows.map { $0.frame.cgRect }) ?? sourceFrame)
        let targetFirst = operation == .insertLeft || operation == .insertUp
        let rects = split(container, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: 1)
        let targetRect = targetFirst ? rects.first : rects.second
        let sourceRect = targetFirst ? rects.second : rects.first

        var result: [WindowID: CGRect] = [:]
        result.merge(planGroup(targetGroup, in: targetRect, horizontal: !horizontal, gap: gap)) { _, rhs in rhs }
        result.merge(planGroup(sourceGroup, in: sourceRect, horizontal: !horizontal, gap: gap)) { _, rhs in rhs }
        return result
    }

    private func reflowingTargetPlacements(
        sourceID: WindowID,
        target: WindowSnapshot,
        operation: DropPreviewOperation,
        activeEntries: [ScopedWindowSnapshot],
        display: DisplaySnapshot
    ) -> [WindowID: CGRect]? {
        guard operation != .swap, operation != .append else { return nil }

        let horizontal: Bool
        let sourceFirst: Bool
        switch operation {
        case .insertLeft:
            horizontal = true
            sourceFirst = true
        case .insertRight:
            horizontal = true
            sourceFirst = false
        case .insertUp:
            horizontal = false
            sourceFirst = true
        case .insertDown:
            horizontal = false
            sourceFirst = false
        case .append, .swap:
            return nil
        }

        let gap = CGFloat(service.innerGap())
        let windows = activeEntries.map(\.window)
        let peers = windows.filter { $0.id != sourceID }
        guard peers.contains(where: { $0.id == target.id }) else { return nil }
        let container = union(windows.map { $0.frame.cgRect })
            ?? display.visibleFrame.cgRect
        let orderedGroups = spatiallySortedWindows(peers, in: container).map { window -> DropReflowGroup in
            window.id == target.id
                ? .pair(sourceID: sourceID, targetID: target.id, horizontal: horizontal, sourceFirst: sourceFirst, targetFrame: target.frame.cgRect)
                : .single(id: window.id, frame: window.frame.cgRect)
        }
        let result = planReflowGroups(orderedGroups, in: container, gap: gap)
        let expectedIDs = Set(windows.map(\.id))
        guard Set(result.keys) == expectedIDs else { return nil }
        return result
    }

    private func planReflowGroups(_ groups: [DropReflowGroup], in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = groups.first else { return [:] }
        guard groups.count > 1 else {
            return first.placements(in: rect.integral, gap: gap)
        }

        let leftCount = groups.count / 2
        let left = Array(groups.prefix(leftCount))
        let right = Array(groups.dropFirst(leftCount))
        let horizontal = rect.width >= rect.height
        let ratio = splitRatio(left: left, right: right, rect: rect, horizontal: horizontal, gap: gap)
        let firstCount = max(1, Int((ratio * 100).rounded()))
        let secondCount = max(1, 100 - firstCount)
        let parts = split(rect, horizontally: horizontal, gap: gap, firstCount: firstCount, secondCount: secondCount)
        var result = planReflowGroups(left, in: parts.first, gap: gap)
        result.merge(planReflowGroups(right, in: parts.second, gap: gap)) { _, rhs in rhs }
        return result
    }

    private func splitRatio(left: [DropReflowGroup], right: [DropReflowGroup], rect: CGRect, horizontal: Bool, gap: CGFloat) -> CGFloat {
        guard let leftFrame = union(left.map(\.observedFrame)),
              let rightFrame = union(right.map(\.observedFrame))
        else { return 0.5 }
        let usableExtent = horizontal ? rect.width - gap : rect.height - gap
        guard usableExtent > 0 else { return 0.5 }
        if managedSplitLooksUsable(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal) {
            let edge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
            return (edge / usableExtent).clamped(to: 0.1...0.9)
        }
        let leftExtent = horizontal ? leftFrame.width : leftFrame.height
        let rightExtent = horizontal ? rightFrame.width : rightFrame.height
        let total = leftExtent + rightExtent
        guard total > 0 else { return 0.5 }
        return (leftExtent / total).clamped(to: 0.1...0.9)
    }

    private func managedSplitLooksUsable(leftFrame: CGRect, rightFrame: CGRect, rect: CGRect, horizontal: Bool) -> Bool {
        let tolerance = CGFloat(24)
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX, tolerance: tolerance)
                && rightFrame.maxX.isClose(to: rect.maxX, tolerance: tolerance)
                && leftFrame.maxX <= rightFrame.minX + tolerance
        }
        return leftFrame.minY.isClose(to: rect.minY, tolerance: tolerance)
            && rightFrame.maxY.isClose(to: rect.maxY, tolerance: tolerance)
            && leftFrame.maxY <= rightFrame.minY + tolerance
    }

    private func orderedTargetGroup(sourceID: WindowID, targetID: WindowID, peers: [WindowID], operation: DropPreviewOperation) -> [WindowID] {
        var result = peers.filter { $0 != sourceID }
        guard let targetIndex = result.firstIndex(of: targetID) else {
            return [sourceID] + result
        }
        result.removeAll { $0 == sourceID }
        switch operation {
        case .insertLeft, .insertUp:
            result.insert(sourceID, at: targetIndex)
        case .insertRight, .insertDown:
            result.insert(sourceID, at: min(targetIndex + 1, result.count))
        case .append, .swap:
            result.append(sourceID)
        }
        return result
    }

    private func spatiallySorted(_ windows: [WindowSnapshot], in container: CGRect) -> [WindowID] {
        spatiallySortedWindows(windows, in: container).map(\.id)
    }

    private func spatiallySortedWindows(_ windows: [WindowSnapshot], in container: CGRect) -> [WindowSnapshot] {
        let horizontal = container.width >= container.height
        return windows.sorted { lhs, rhs in
            if horizontal {
                if abs(lhs.frame.cgRect.midX - rhs.frame.cgRect.midX) > 48 {
                    return lhs.frame.cgRect.midX < rhs.frame.cgRect.midX
                }
                return lhs.frame.cgRect.midY < rhs.frame.cgRect.midY
            }
            if abs(lhs.frame.cgRect.midY - rhs.frame.cgRect.midY) > 48 {
                return lhs.frame.cgRect.midY < rhs.frame.cgRect.midY
            }
            return lhs.frame.cgRect.midX < rhs.frame.cgRect.midX
        }
    }

    private func union(_ frames: [CGRect]) -> CGRect? {
        guard var result = frames.first else { return nil }
        for frame in frames.dropFirst() {
            result = result.union(frame)
        }
        return result
    }

    private func isOnTargetSide(_ candidate: CGRect, from source: CGRect, operation: DropPreviewOperation) -> Bool {
        switch operation {
        case .insertLeft:
            return candidate.midX < source.midX
        case .insertRight:
            return candidate.midX > source.midX
        case .insertUp:
            return candidate.midY < source.midY
        case .insertDown:
            return candidate.midY > source.midY
        case .append, .swap:
            return false
        }
    }

    private func split(
        _ rect: CGRect,
        horizontally: Bool,
        gap: CGFloat,
        firstCount: Int,
        secondCount: Int
    ) -> (first: CGRect, second: CGRect) {
        let total = CGFloat(firstCount + secondCount)
        let ratio = total > 0 ? CGFloat(firstCount) / total : 0.5
        if horizontally {
            let usable = max(0, rect.width - gap)
            let firstWidth = floor(usable * ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + gap, y: rect.minY, width: usable - firstWidth, height: rect.height)
            )
        }

        let usable = max(0, rect.height - gap)
        let firstHeight = floor(usable * ratio)
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
            CGRect(x: rect.minX, y: rect.minY + firstHeight + gap, width: rect.width, height: usable - firstHeight)
        )
    }

    private func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = windowIDs.first else { return [:] }
        guard windowIDs.count > 1 else { return [first: rect.integral] }

        let parts = split(rect, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: windowIDs.count - 1)
        var placements = [first: parts.first.integral]
        placements.merge(planGroup(Array(windowIDs.dropFirst()), in: parts.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        return placements
    }
}

public enum WindowDragReorderEligibility {
    public static func accepts(_ window: WindowSnapshot) -> Bool {
        guard window.isTileCandidate else { return false }
        if let furniture = window.furniture {
            guard !furniture.isModal else { return false }
            guard furniture.isResizable else { return false }
        }
        if let subrole = window.subrole, subrole != "AXStandardWindow" {
            return false
        }
        return true
    }
}

@MainActor
final class WindowDragReorderController {
    private let preview: DropPreviewController
    private let commandService: StageCommandService
    private let events: EventLog
    private var pending: PendingWindowDrag?

    init(
        preview: DropPreviewController,
        commandService: StageCommandService = StageCommandService(),
        events: EventLog = EventLog()
    ) {
        self.preview = preview
        self.commandService = commandService
        self.events = events
    }

    var hasActiveDrag: Bool {
        pending != nil
    }

    func activeDraggedWindowIDForDrop() -> WindowID? {
        guard let pending, pending.didDrag else { return nil }
        return pending.windowID
    }

    func cancelPendingDrag() {
        pending = nil
        preview.hide()
        WindowDragActivity.shared.finish()
    }

    func handleMouseDown(at point: CGPoint) {
        preview.hide()
        guard let source = sourceWindowForDragStart(at: point) else {
            pending = nil
            return
        }
        pending = PendingWindowDrag(windowID: source.window.id, displayID: source.scope.displayID, startPoint: point, didDrag: false)
    }

    func handleMouseDragged(to point: CGPoint) {
        guard var drag = pending else { return }
        guard hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) > 8 else { return }
        drag.didDrag = true
        WindowDragActivity.shared.markActive(windowID: drag.windowID)
        if let candidate = preview.update(sourceWindowID: drag.windowID, at: point),
           candidate != drag.lastCandidate {
            events.append(RoadieEvent(type: "window_drag_preview", scope: candidate.scope, details: [
                "windowID": String(candidate.sourceWindowID.rawValue),
                "operation": candidate.operation.rawValue
            ]))
            drag.lastCandidate = candidate
        }
        pending = drag
    }

    func handleMouseUp(at point: CGPoint) {
        guard let drag = pending else { return }
        pending = nil
        defer {
            preview.hide()
            WindowDragActivity.shared.finish()
        }
        guard drag.didDrag,
              let candidate = preview.update(sourceWindowID: drag.windowID, at: point)
        else { return }
        let result = commandService.place(
            windowID: candidate.sourceWindowID,
            displayID: candidate.displayID,
            orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements
        )
        events.append(RoadieEvent(type: "window_drag_apply", scope: candidate.scope, details: [
            "windowID": String(candidate.sourceWindowID.rawValue),
            "operation": candidate.operation.rawValue,
            "changed": String(result.changed)
        ]))
    }

    private func sourceWindowForDragStart(at point: CGPoint) -> (window: WindowSnapshot, scope: StageScope)? {
        let snapshot = SnapshotService().snapshot()
        let axPoint = ScreenCoordinate.nsPointToAX(point)
        let candidates = snapshot.windows.compactMap { entry -> (WindowSnapshot, StageScope)? in
            guard let scope = entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  WindowDragReorderEligibility.accepts(entry.window),
                  titleBarHitRect(for: entry.window.frame.cgRect).contains(axPoint)
            else { return nil }
            return (entry.window, scope)
        }
        return candidates.sorted { $0.0.frame.cgRect.area < $1.0.frame.cgRect.area }.first
    }

    private func titleBarHitRect(for frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(44, frame.height))
    }
}

private struct PendingWindowDrag {
    var windowID: WindowID
    var displayID: DisplayID
    var startPoint: CGPoint
    var didDrag: Bool
    var lastCandidate: DropPreviewCandidate?
}

@MainActor
private final class DropPreviewOverlayWindow: NSPanel {
    private let previewView = DropPreviewOverlayView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        alphaValue = 0.92
        contentView = previewView
    }

    func show(_ candidate: DropPreviewCandidate) {
        let frame = ScreenCoordinate.axRectToNS(candidate.frame).insetBy(dx: -5, dy: -5)
        previewView.operation = candidate.operation
        setFrame(frame, display: true)
        orderFrontRegardless()
        previewView.needsDisplay = true
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
private final class DropPreviewOverlayView: NSView {
    var operation: DropPreviewOperation = .append

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 5, dy: 5)
        let color = operation.tint
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        color.withAlphaComponent(operation == .swap ? 0.20 : 0.15).setFill()
        path.fill()

        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()

        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 7, yRadius: 7)
        color.withAlphaComponent(0.36).setStroke()
        inner.lineWidth = 1
        inner.stroke()
    }
}

private enum DropReflowGroup {
    case single(id: WindowID, frame: CGRect)
    case pair(
        sourceID: WindowID,
        targetID: WindowID,
        horizontal: Bool,
        sourceFirst: Bool,
        targetFrame: CGRect
    )

    var observedFrame: CGRect {
        switch self {
        case .single(_, let frame):
            return frame
        case .pair(_, _, _, _, let targetFrame):
            return targetFrame
        }
    }

    func placements(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        switch self {
        case .single(let id, _):
            return [id: rect.integral]
        case .pair(let sourceID, let targetID, let horizontal, let sourceFirst, _):
            let parts = split(rect, horizontally: horizontal, gap: gap)
            let sourceRect = sourceFirst ? parts.first : parts.second
            let targetRect = sourceFirst ? parts.second : parts.first
            return [
                sourceID: sourceRect.integral,
                targetID: targetRect.integral
            ]
        }
    }

    private func split(_ rect: CGRect, horizontally: Bool, gap: CGFloat) -> (first: CGRect, second: CGRect) {
        if horizontally {
            let usable = max(0, rect.width - gap)
            let firstWidth = floor(usable / 2)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + gap, y: rect.minY, width: usable - firstWidth, height: rect.height)
            )
        }

        let usable = max(0, rect.height - gap)
        let firstHeight = floor(usable / 2)
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
            CGRect(x: rect.minX, y: rect.minY + firstHeight + gap, width: rect.width, height: usable - firstHeight)
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

private extension CGFloat {
    func isClose(to value: CGFloat, tolerance: CGFloat) -> Bool {
        abs(self - value) <= tolerance
    }

    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private enum ScreenCoordinate {
    static func nsPointToAX(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func axRectToNS(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }
}
