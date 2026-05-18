import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public enum TargetGridAction: String, Codable, Equatable, Sendable {
    case click
    case doubleClick = "double-click"
    case rightClick = "right-click"
    case move
    case scrollUp = "scroll-up"
    case scrollDown = "scroll-down"
    case drag
}

public struct TargetGridDisplay: Codable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var name: String
    public var frame: Rect

    public init(display: DisplaySnapshot) {
        self.id = display.id.rawValue
        self.index = display.index
        self.name = display.name
        self.frame = display.visibleFrame
    }
}

public struct TargetGridCell: Codable, Equatable, Sendable {
    public var path: String
    public var label: String
    public var depth: Int
    public var row: Int
    public var column: Int
    public var frame: Rect
    public var center: CGPointCodable
    public var display: TargetGridDisplay
}

public struct CGPointCodable: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct TargetGridReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var display: TargetGridDisplay
    public var scope: TargetGridScope
    public var rootFrame: Rect
    public var rows: Int
    public var columns: Int
    public var maxDepth: Int
    public var parentPath: String
    public var cells: [TargetGridCell]
    public var error: String?

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        display: TargetGridDisplay,
        scope: TargetGridScope = .display,
        rootFrame: Rect? = nil,
        rows: Int,
        columns: Int,
        maxDepth: Int,
        parentPath: String,
        cells: [TargetGridCell],
        error: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.display = display
        self.scope = scope
        self.rootFrame = rootFrame ?? display.frame
        self.rows = rows
        self.columns = columns
        self.maxDepth = maxDepth
        self.parentPath = parentPath
        self.cells = cells
        self.error = error
    }
}

public struct TargetGridRoot: Equatable, Sendable {
    public var display: DisplaySnapshot
    public var scope: TargetGridScope
    public var frame: Rect

    public init(display: DisplaySnapshot, scope: TargetGridScope, frame: Rect) {
        self.display = display
        self.scope = scope
        self.frame = frame
    }
}

public struct TargetGridService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let config: TargetGridConfig

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        config: TargetGridConfig? = nil
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.config = config ?? service.effectiveConfig.experimental.targetGrid
    }

    public func report(displayIndex: Int? = nil, parentPath: String = "", scope: TargetGridScope? = nil) -> TargetGridReport {
        guard config.enabled else {
            return emptyReport(displayIndex: displayIndex, parentPath: parentPath, scope: scope ?? config.defaultScope, error: "target_grid_disabled")
        }
        let effectiveScope = scope ?? config.defaultScope
        guard let root = resolveRoot(displayIndex: displayIndex, scope: effectiveScope) else {
            return emptyReport(displayIndex: displayIndex, parentPath: parentPath, scope: effectiveScope, error: "unknown_grid_root")
        }
        return report(root: root, parentPath: parentPath)
    }

    public func report(root: TargetGridRoot, parentPath: String = "") -> TargetGridReport {
        let cells = Self.cells(
            display: root.display,
            rootFrame: root.frame,
            parentPath: parentPath,
            rows: config.rows,
            columns: config.columns,
            maxDepth: config.maxDepth,
            alphabet: config.hintCharacters
        )
        return TargetGridReport(
            display: TargetGridDisplay(display: root.display),
            scope: root.scope,
            rootFrame: root.frame,
            rows: config.rows,
            columns: config.columns,
            maxDepth: config.maxDepth,
            parentPath: parentPath,
            cells: cells
        )
    }

    public func targets(displayIndex: Int? = nil, parentPath: String = "", scope: TargetGridScope? = nil) -> TargetQueryReport {
        targets(report(displayIndex: displayIndex, parentPath: parentPath, scope: scope))
    }

    public func targets(root: TargetGridRoot, parentPath: String = "") -> TargetQueryReport {
        targets(report(root: root, parentPath: parentPath))
    }

    private func targets(_ grid: TargetGridReport) -> TargetQueryReport {
        let targets = grid.cells.map { cell in
            RoadieTarget(
                id: "grid:\(cell.display.id)/\(cell.path)",
                label: cell.label,
                kind: .gridCell,
                title: "Grid \(cell.path)",
                subtitle: "\(cell.display.name) \(grid.scope.rawValue) \(cell.row + 1),\(cell.column + 1)",
                source: .roadie,
                matchText: RoadieTarget.normalizedMatchText([cell.path, cell.label, cell.display.name]),
                scope: TargetScopeSnapshot(displayId: cell.display.id),
                frame: cell.frame,
                actions: [.click, .doubleClick, .rightClick, .inspect],
                diagnostics: ["grid_depth=\(cell.depth)", "display_index=\(cell.display.index)", "scope=\(grid.scope.rawValue)"]
            )
        }
        return TargetQueryReport(
            query: TargetQueryOptions(source: .roadie, maxResults: max(1, targets.count)),
            targets: targets,
            error: grid.error
        )
    }

    public func perform(_ action: TargetGridAction, path: String, to destinationPath: String? = nil, displayIndex: Int? = nil, scope: TargetGridScope? = nil) -> TargetActionResult {
        guard config.enabled else {
            return TargetActionResult(changed: false, message: "target_grid_disabled", error: "target_grid_disabled")
        }
        let effectiveScope = scope ?? config.defaultScope
        guard let root = resolveRoot(displayIndex: displayIndex, scope: effectiveScope) else {
            return TargetActionResult(changed: false, message: "grid: unknown root", error: "unknown_grid_root")
        }
        return perform(action, path: path, to: destinationPath, root: root)
    }

    public func perform(_ action: TargetGridAction, path: String, to destinationPath: String? = nil, root: TargetGridRoot) -> TargetActionResult {
        guard config.enabled else {
            return TargetActionResult(changed: false, message: "target_grid_disabled", error: "target_grid_disabled")
        }
        guard let source = Self.cell(
                display: root.display,
                rootFrame: root.frame,
                path: path,
                rows: config.rows,
                columns: config.columns,
                maxDepth: config.maxDepth,
                alphabet: config.hintCharacters
              )
        else {
            return TargetActionResult(changed: false, message: "grid: unknown path \(path)", error: "unknown_grid_path")
        }
        let point = source.center.cgPoint
        switch action {
        case .click:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
        case .doubleClick:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 2)
        case .rightClick:
            postClick(at: point, button: .right, down: .rightMouseDown, up: .rightMouseUp, clickCount: 1)
        case .move:
            CGWarpMouseCursorPosition(point)
        case .scrollUp:
            postScroll(at: point, delta: 6)
        case .scrollDown:
            postScroll(at: point, delta: -6)
        case .drag:
            guard let destinationPath,
                  let destination = Self.cell(
                    display: root.display,
                    rootFrame: root.frame,
                    path: destinationPath,
                    rows: config.rows,
                    columns: config.columns,
                    maxDepth: config.maxDepth,
                    alphabet: config.hintCharacters
                  )
            else {
                return TargetActionResult(changed: false, message: "grid drag: missing destination", error: "missing_destination")
            }
            postDrag(from: point, to: destination.center.cgPoint)
        }
        if config.actionDelayMs > 0 {
            Thread.sleep(forTimeInterval: TimeInterval(config.actionDelayMs) / 1000)
        }
        return TargetActionResult(changed: true, message: "grid \(action.rawValue) \(path) scope=\(root.scope.rawValue)")
    }

    public static func cells(
        display: DisplaySnapshot,
        rootFrame: Rect? = nil,
        parentPath: String,
        rows: Int,
        columns: Int,
        maxDepth: Int,
        alphabet: String
    ) -> [TargetGridCell] {
        let root = rootFrame?.cgRect ?? display.visibleFrame.cgRect
        guard let parentFrame = frame(for: parentPath, in: root, rows: rows, columns: columns, maxDepth: maxDepth, alphabet: alphabet) else {
            return []
        }
        let labels = TargetHintService.labels(count: rows * columns, alphabet: alphabet)
        var cells: [TargetGridCell] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let frame = CGRect(
                    x: parentFrame.minX + CGFloat(column) * parentFrame.width / CGFloat(columns),
                    y: parentFrame.minY + CGFloat(row) * parentFrame.height / CGFloat(rows),
                    width: parentFrame.width / CGFloat(columns),
                    height: parentFrame.height / CGFloat(rows)
                ).integral
                let label = labels[index]
                let path = parentPath + label
                cells.append(TargetGridCell(
                    path: path,
                    label: label,
                    depth: max(1, path.count),
                    row: row,
                    column: column,
                    frame: Rect(frame),
                    center: CGPointCodable(CGPoint(x: frame.midX, y: frame.midY)),
                    display: TargetGridDisplay(display: display)
                ))
            }
        }
        return cells
    }

    public static func cell(
        display: DisplaySnapshot,
        rootFrame: Rect? = nil,
        path: String,
        rows: Int,
        columns: Int,
        maxDepth: Int,
        alphabet: String
    ) -> TargetGridCell? {
        guard !path.isEmpty,
              let frame = frame(for: path, in: rootFrame?.cgRect ?? display.visibleFrame.cgRect, rows: rows, columns: columns, maxDepth: maxDepth, alphabet: alphabet),
              let last = pathLabels(rows: rows, columns: columns, alphabet: alphabet).firstIndex(of: String(path.suffix(1)))
        else { return nil }
        let row = last / columns
        let column = last % columns
        return TargetGridCell(
            path: path,
            label: String(path.suffix(1)),
            depth: path.count,
            row: row,
            column: column,
            frame: Rect(frame.integral),
            center: CGPointCodable(CGPoint(x: frame.midX, y: frame.midY)),
            display: TargetGridDisplay(display: display)
        )
    }

    public static func path(for point: CGPoint, display: DisplaySnapshot, rows: Int, columns: Int, maxDepth: Int, alphabet: String) -> String? {
        var frame = display.visibleFrame.cgRect
        guard frame.contains(point) else { return nil }
        let labels = pathLabels(rows: rows, columns: columns, alphabet: alphabet)
        var path = ""
        for _ in 0..<maxDepth {
            let cellWidth = frame.width / CGFloat(columns)
            let cellHeight = frame.height / CGFloat(rows)
            let column = min(columns - 1, max(0, Int((point.x - frame.minX) / cellWidth)))
            let row = min(rows - 1, max(0, Int((point.y - frame.minY) / cellHeight)))
            let index = row * columns + column
            path += labels[index]
            frame = CGRect(
                x: frame.minX + CGFloat(column) * cellWidth,
                y: frame.minY + CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
        }
        return path
    }

    private static func frame(for path: String, in root: CGRect, rows: Int, columns: Int, maxDepth: Int, alphabet: String) -> CGRect? {
        guard path.count <= maxDepth else { return nil }
        var frame = root
        let labels = pathLabels(rows: rows, columns: columns, alphabet: alphabet)
        for label in path.map({ String($0) }) {
            guard let index = labels.firstIndex(of: label) else { return nil }
            let row = index / columns
            let column = index % columns
            frame = CGRect(
                x: frame.minX + CGFloat(column) * frame.width / CGFloat(columns),
                y: frame.minY + CGFloat(row) * frame.height / CGFloat(rows),
                width: frame.width / CGFloat(columns),
                height: frame.height / CGFloat(rows)
            )
        }
        return frame
    }

    private static func pathLabels(rows: Int, columns: Int, alphabet: String) -> [String] {
        TargetHintService.labels(count: rows * columns, alphabet: alphabet)
    }

    public func root(displayIndex: Int? = nil, scope: TargetGridScope? = nil) -> TargetGridRoot? {
        resolveRoot(displayIndex: displayIndex, scope: scope ?? config.defaultScope)
    }

    private func resolveRoot(displayIndex: Int?, scope: TargetGridScope) -> TargetGridRoot? {
        let snapshot = service.snapshot(followFocus: false)
        guard let display = resolveDisplay(displayIndex: displayIndex, in: snapshot) else {
            return nil
        }
        switch scope {
        case .display:
            return TargetGridRoot(display: display, scope: .display, frame: display.visibleFrame)
        case .focusedWindow:
            let focusedID = service.focusedWindowID() ?? snapshot.focusedWindowID
            guard let focusedID,
                  let focused = snapshot.windows.first(where: { $0.window.id == focusedID })?.window,
                  let focusedDisplay = displayContaining(focused.frame, in: snapshot.displays) ?? resolveDisplay(displayIndex: displayIndex, in: snapshot)
            else {
                return TargetGridRoot(display: display, scope: .display, frame: display.visibleFrame)
            }
            let root = focused.frame.cgRect.intersection(focusedDisplay.visibleFrame.cgRect)
            guard !root.isNull, root.width > 8, root.height > 8 else {
                return TargetGridRoot(display: focusedDisplay, scope: .display, frame: focusedDisplay.visibleFrame)
            }
            return TargetGridRoot(display: focusedDisplay, scope: .focusedWindow, frame: Rect(root.integral))
        }
    }

    private func resolveDisplay(displayIndex: Int?, in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let displayIndex {
            return snapshot.displays.first { $0.index == displayIndex }
        }
        let state = stageStore.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        return snapshot.displays.first(where: \.isMain) ?? snapshot.displays.first
    }

    private func displayContaining(_ frame: Rect, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let rect = frame.cgRect
        return displays.max { lhs, rhs in
            intersectionArea(lhs.visibleFrame.cgRect, rect) < intersectionArea(rhs.visibleFrame.cgRect, rect)
        }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let rect = lhs.intersection(rhs)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
        return rect.width * rect.height
    }

    private func emptyReport(displayIndex: Int?, parentPath: String, scope: TargetGridScope, error: String) -> TargetGridReport {
        let snapshot = service.snapshot(followFocus: false)
        let display = resolveDisplay(displayIndex: displayIndex, in: snapshot) ?? DisplaySnapshot(
            id: DisplayID(rawValue: "unknown"),
            index: displayIndex ?? 0,
            name: "unknown",
            frame: Rect(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: Rect(x: 0, y: 0, width: 0, height: 0),
            isMain: false
        )
        return TargetGridReport(
            display: TargetGridDisplay(display: display),
            scope: scope,
            rootFrame: display.visibleFrame,
            rows: config.rows,
            columns: config.columns,
            maxDepth: config.maxDepth,
            parentPath: parentPath,
            cells: [],
            error: error
        )
    }

    private func postClick(
        at point: CGPoint,
        button: CGMouseButton,
        down: CGEventType,
        up: CGEventType,
        clickCount: Int64
    ) {
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)
        downEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        upEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }

    private func postScroll(at point: CGPoint, delta: Int32) {
        CGWarpMouseCursorPosition(point)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private func postDrag(from source: CGPoint, to destination: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: source, mouseButton: .left)
        let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: destination, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: destination, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        drag?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
