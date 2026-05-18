import CoreGraphics
import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct TargetMacroServiceTests {
    @Test
    func nearestTargetPrefersSmallestContainingFrame() {
        let large = RoadieTarget(
            id: "window:1",
            kind: .window,
            title: "Large",
            source: .roadie,
            frame: Rect(x: 0, y: 0, width: 500, height: 500),
            actions: [.focus]
        )
        let small = RoadieTarget(
            id: "app:button",
            kind: .appElement,
            title: "Button",
            source: .app,
            frame: Rect(x: 10, y: 10, width: 30, height: 30),
            actions: [.click]
        )

        let target = TargetMacroService.nearestTarget(at: CGPoint(x: 20, y: 20), targets: [large, small])

        #expect(target?.id == "app:button")
    }

    @Test
    func macroRecordingRoundTripsAsJSON() throws {
        let recording = TargetMacroRecording(
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 0),
            durationSeconds: 1,
            events: [
                TargetMacroEvent(
                    t: 0.1,
                    kind: .mouseUp,
                    point: CGPointCodable(CGPoint(x: 10, y: 20)),
                    modifiers: 0,
                    gridPath: "AAA"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recording)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TargetMacroRecording.self, from: data)

        #expect(decoded == recording)
    }
}
