import CoreGraphics
import Testing
@testable import RoadieDaemon

@Suite
struct RoadieScreenCoordinateTests {
    @Test
    func convertsPrimaryScreenPointBetweenNSAndAXCoordinates() {
        let frames = [CGRect(x: 0, y: 0, width: 900, height: 600)]

        let ax = RoadieScreenCoordinate.nsPointToAX(
            CGPoint(x: 120, y: 80),
            screenFrames: frames,
            primaryHeight: 600
        )

        #expect(ax == CGPoint(x: 120, y: 520))
    }

    @Test
    func convertsExternalScreenAbovePrimaryBetweenNSAndAXCoordinates() {
        let frames = [
            CGRect(x: 0, y: 0, width: 900, height: 600),
            CGRect(x: 100, y: 600, width: 1200, height: 800),
        ]

        let ax = RoadieScreenCoordinate.nsPointToAX(
            CGPoint(x: 200, y: 700),
            screenFrames: frames,
            primaryHeight: 600
        )

        #expect(ax == CGPoint(x: 200, y: -100))
    }

    @Test
    func convertsAXRectBackToNSRectOnContainingScreen() {
        let frames = [CGRect(x: 0, y: 0, width: 900, height: 600)]

        let ns = RoadieScreenCoordinate.axRectToNS(
            CGRect(x: 100, y: 50, width: 200, height: 120),
            screenFrames: frames,
            primaryHeight: 600
        )

        #expect(ns == CGRect(x: 100, y: 430, width: 200, height: 120))
    }
}
