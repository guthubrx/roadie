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
        let snapshot = service.snapshot()
        let axPoint = ScreenCoordinate.nsPointToAX(point)
        guard let display = display(containing: axPoint, forcedDisplayID: forcedDisplayID, in: snapshot.displays),
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope),
              stage.mode != .float,
              snapshot.windows.contains(where: { $0.window.id == sourceWindowID && $0.window.isTileCandidate })
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

        let operation: DropPreviewOperation
        if let target {
            operation = dropOperation(at: axPoint, in: target.window.frame.cgRect, sourceIsActive: activeEntries.contains { $0.window.id == sourceWindowID })
            ordered = reordered(ordered, sourceID: sourceWindowID, targetID: target.window.id, operation: operation)
        } else {
            operation = .append
            ordered = ordered.filter { $0 != sourceWindowID } + [sourceWindowID]
        }

        let plan = service.layoutPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, priorityWindowIDs: [sourceWindowID])
        guard let frame = plan.placements[sourceWindowID], !frame.isEmpty else { return nil }
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: ordered,
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
        if let candidate = preview.update(sourceWindowID: drag.windowID, at: point, displayID: drag.displayID),
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
        defer { preview.hide() }
        guard drag.didDrag,
              let candidate = preview.update(sourceWindowID: drag.windowID, at: point, displayID: drag.displayID)
        else { return }
        let result = commandService.place(
            windowID: candidate.sourceWindowID,
            displayID: candidate.displayID,
            orderedWindowIDs: candidate.orderedWindowIDs
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
                  entry.window.isTileCandidate,
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

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
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
