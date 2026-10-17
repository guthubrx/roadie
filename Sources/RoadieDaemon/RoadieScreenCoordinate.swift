import AppKit
import CoreGraphics

enum RoadieScreenCoordinate {
    /// Position attachée à l'événement, même si le fil principal le traite plus tard.
    static func mouseEventPoint(_ event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location {
            return axRectToNS(CGRect(origin: point, size: .zero)).origin
        }
        // Événements AppKit locaux sans CGEvent : coordonnées relatives à leur fenêtre.
        return event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    static func nsPointToAX(_ point: CGPoint) -> CGPoint {
        nsPointToAX(point, screenFrames: NSScreen.screens.map(\.frame), primaryHeight: primaryHeight)
    }

    static func axRectToNS(_ rect: CGRect) -> CGRect {
        axRectToNS(rect, screenFrames: NSScreen.screens.map(\.frame), primaryHeight: primaryHeight)
    }

    static func nsPointToAX(_ point: CGPoint, screenFrames: [CGRect], primaryHeight: CGFloat) -> CGPoint {
        guard let mapping = screenMapping(containingNSPoint: point, screenFrames: screenFrames, primaryHeight: primaryHeight) else {
            return CGPoint(x: point.x, y: primaryHeight - point.y)
        }
        let localY = point.y - mapping.nsFrame.minY
        return CGPoint(x: point.x, y: mapping.axFrame.maxY - localY)
    }

    static func axRectToNS(_ rect: CGRect, screenFrames: [CGRect], primaryHeight: CGFloat) -> CGRect {
        guard let mapping = screenMapping(containingAXRect: rect, screenFrames: screenFrames, primaryHeight: primaryHeight) else {
            return CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
        }
        let localTop = rect.minY - mapping.axFrame.minY
        return CGRect(
            x: rect.minX,
            y: mapping.nsFrame.maxY - localTop - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    private struct ScreenMapping {
        var nsFrame: CGRect
        var axFrame: CGRect
    }

    private static func screenMapping(containingNSPoint point: CGPoint, screenFrames: [CGRect], primaryHeight: CGFloat) -> ScreenMapping? {
        let mappings = screenFrames.map { frame in
            ScreenMapping(
                nsFrame: frame,
                axFrame: CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            )
        }
        return mappings.first { $0.nsFrame.insetBy(dx: -64, dy: -64).contains(point) }
            ?? mappings.first
    }

    private static func screenMapping(containingAXRect rect: CGRect, screenFrames: [CGRect], primaryHeight: CGFloat) -> ScreenMapping? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let mappings = screenFrames.map { frame in
            ScreenMapping(
                nsFrame: frame,
                axFrame: CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            )
        }
        if let mapping = mappings.first(where: { $0.axFrame.insetBy(dx: -64, dy: -64).contains(center) }) {
            return mapping
        }
        if let mapping = mappings.max(by: { lhs, rhs in
            lhs.axFrame.intersection(rect).area < rhs.axFrame.intersection(rect).area
        }), mapping.axFrame.intersection(rect).area > 0 {
            return mapping
        }
        return mappings.max { lhs, rhs in
            lhs.axFrame.horizontalOverlap(with: rect) < rhs.axFrame.horizontalOverlap(with: rect)
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }

    func horizontalOverlap(with other: CGRect) -> CGFloat {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }
}
