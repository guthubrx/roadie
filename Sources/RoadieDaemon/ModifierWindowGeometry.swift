import CoreGraphics
import RoadieAX
import RoadieCore
import RoadieTiler

enum ModifierWindowOperation: String, Sendable {
    case move, resize

    static func resolve(flags: CGEventFlags, config: TilingConfig) -> Self? {
        let relevant = flags.rawValue & (CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        if config.dragResizeModifier != .disabled, relevant == config.dragResizeModifier.mask { return .resize }
        if config.dragMoveModifier != .disabled, relevant == config.dragMoveModifier.mask { return .move }
        return nil
    }
}

/// Le coin est fixé au début ; le mouvement ne demande ensuite que quatre additions.
struct ModifierWindowGeometry {
    let frame: CGRect
    let origin: CGPoint
    let operation: ModifierWindowOperation
    let edges: Set<BSPEdge>
    let minimum: CGSize

    init(frame: CGRect, origin: CGPoint, operation: ModifierWindowOperation,
         available: Set<BSPEdge> = [.left, .right, .up, .down], minimum: CGSize = CGSize(width: 80, height: 80)) {
        self.frame = frame; self.origin = origin; self.operation = operation
        self.minimum = CGSize(width: min(frame.width, max(1, minimum.width)), height: min(frame.height, max(1, minimum.height)))
        func choose(_ first: BSPEdge, _ second: BSPEdge, preferFirst: Bool) -> BSPEdge? {
            if preferFirst, available.contains(first) { return first }
            if available.contains(second) { return second }
            return available.contains(first) ? first : nil
        }
        edges = Set([choose(.left, .right, preferFirst: origin.x < frame.midX),
                     choose(.up, .down, preferFirst: origin.y < frame.midY)].compactMap { $0 })
    }

    func target(at point: CGPoint) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let dx = point.x - origin.x, dy = point.y - origin.y
        if operation == .move { return frame.offsetBy(dx: dx, dy: dy) }
        var result = frame
        if edges.contains(.left) { result.origin.x = min(frame.minX + dx, frame.maxX - minimum.width); result.size.width = frame.maxX - result.minX }
        if edges.contains(.right) { result.size.width = max(minimum.width, frame.width + dx) }
        if edges.contains(.up) { result.origin.y = min(frame.minY + dy, frame.maxY - minimum.height); result.size.height = frame.maxY - result.minY }
        if edges.contains(.down) { result.size.height = max(minimum.height, frame.height + dy) }
        return result
    }
}
