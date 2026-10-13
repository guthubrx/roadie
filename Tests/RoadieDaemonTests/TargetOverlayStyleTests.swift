import CoreGraphics
import Testing
import RoadieCore
@testable import RoadieDaemon

/// SPEC-023 R8 : taille des étiquettes réglable, dimensions proportionnelles.
@Suite
struct TargetOverlayStyleTests {
    private let screen = CGRect(x: 0, y: 0, width: 1280, height: 720)

    @Test
    func defaultSizeKeepsTheOriginalDimensions() {
        let style = TargetOverlayStyle.labels
        #expect(style.labelFontSize == 13)
        #expect(style.scale == 1)
        #expect(style.badgeSize(textWidth: 0) == CGSize(width: 28, height: 24))
        #expect(style.badgeSize(textWidth: 30) == CGSize(width: 46, height: 24))
        #expect(style.badgeCornerRadius == 8)
        #expect(style.badgeGap == 10)
        #expect(style.badgeInset == 6)
        #expect(style.badgePlacementSpacing == 6)
        #expect(style.badgeAvoidanceMargin == 4)
        #expect(style.badgeEdgeMargin == 4)
        #expect(TargetOverlayStyle.grid(TargetGridConfig()).scale == 1)
    }

    @Test(arguments: [8.0, 20.0, 48.0])
    func dimensionsFollowTheFontSize(size: Double) {
        let style = TargetOverlayStyle(labelFontSize: CGFloat(size))
        let scale = CGFloat(size) / 13
        #expect(style.scale == scale)
        #expect(style.badgeSize(textWidth: 0) == CGSize(width: 28 * scale, height: 24 * scale))
        #expect(style.badgeSize(textWidth: 100).width == 100 + 16 * scale)
        #expect(style.badgeCornerRadius == 8 * scale)
        #expect(style.badgeGap == 10 * scale)
        #expect(style.badgeInset == 6 * scale)
        #expect(style.badgePlacementSpacing == 6 * scale)
        #expect(style.badgeAvoidanceMargin == 4 * scale)
        #expect(style.badgeEdgeMargin == 4 * scale)
    }

    @Test
    func sizeOutsideTheRangeIsClamped() {
        #expect(TargetOverlayStyle(labelFontSize: 2).labelFontSize == 8)
        #expect(TargetOverlayStyle(labelFontSize: 90).labelFontSize == 48)
    }

    @Test
    func badgeStaysOnScreenForEverySize() throws {
        // Libellé de trois caractères en police à chasse fixe : environ 0,6 × taille par caractère.
        for size in stride(from: 8.0, through: 48.0, by: 1.0) {
            let style = TargetOverlayStyle(labelFontSize: CGFloat(size))
            let badge = style.badgeSize(textWidth: 3 * 0.6 * CGFloat(size))
            let corners = [
                CGPoint(x: -500, y: -500), CGPoint(x: 1270, y: 715),
                CGPoint(x: -500, y: 715), CGPoint(x: 1270, y: -500), CGPoint(x: 600, y: 300),
            ]
            for origin in corners {
                let rect = style.clampedBadge(CGRect(origin: origin, size: badge), in: screen)
                #expect(screen.contains(rect), "taille \(size), origine \(origin)")
            }
        }
    }

    @Test
    func clampingAtThirteenPointsKeepsTheFourPointMargin() {
        let rect = TargetOverlayStyle.labels.clampedBadge(CGRect(x: -50, y: 900, width: 28, height: 24), in: screen)
        #expect(rect == CGRect(x: 4, y: 720 - 24 - 4, width: 28, height: 24))
    }
}
