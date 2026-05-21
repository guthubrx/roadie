import CoreGraphics
import RoadieAX

enum HiddenWindowPlacement {
    static func frame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let visible = display.visibleFrame.cgRect
        let virtualMaxX = displays.map { $0.visibleFrame.cgRect.maxX }.max() ?? visible.maxX
        let y = min(max(frame.minY, visible.minY), visible.maxY - 1)
        return CGRect(
            x: virtualMaxX - 1,
            y: y,
            width: frame.width,
            height: frame.height
        ).integral
    }

    static func isHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        isPreferred(frame, among: displays) || isLegacyBottomCorner(frame, in: displays)
    }

    static func isPreferred(_ frame: CGRect, among displays: [DisplaySnapshot]) -> Bool {
        guard let virtualMaxX = displays.map({ $0.visibleFrame.cgRect.maxX }).max() else {
            return false
        }
        return abs(frame.minX - (virtualMaxX - 1)) <= 8
    }

    private static func isLegacyBottomCorner(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        displays.contains { display in
            let visible = display.visibleFrame.cgRect
            let nearBottomEdge = abs(frame.minY - (visible.maxY - 1)) <= 64
            let nearLeftEdge = abs(frame.maxX - (visible.minX + 1)) <= 4
            let nearRightEdge = abs(frame.minX - (visible.maxX - 1)) <= 4
            return nearBottomEdge && (nearLeftEdge || nearRightEdge)
        }
    }
}
