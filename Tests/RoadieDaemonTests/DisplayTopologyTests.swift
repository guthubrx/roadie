import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct DisplayTopologyTests {
    private func display(
        id: String,
        x: Double,
        y: Double,
        width: Double = 1920,
        height: Double = 1080,
        index: Int = 0,
        name: String? = nil,
        visibleWidth: Double? = nil,
        visibleHeight: Double? = nil,
        isMain: Bool = false
    ) -> DisplaySnapshot {
        let frame = Rect(x: x, y: y, width: width, height: height)
        let visibleFrame = Rect(x: x, y: y, width: visibleWidth ?? width, height: visibleHeight ?? height)
        return DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: index,
            name: name ?? id,
            frame: frame,
            visibleFrame: visibleFrame,
            isMain: isMain
        )
    }

    @Test
    func neighborToTheRightIsFoundWhenAlignedHorizontally() {
        let main = display(id: "main", x: 0, y: 0, isMain: true)
        let right = display(id: "right", x: 1920, y: 0, index: 1)
        let result = DisplayTopology.neighbor(from: main, direction: .right, in: [main, right])
        #expect(result?.id == right.id)
    }

    @Test
    func neighborToTheLeftIsFoundForCenterDisplay() {
        let left = display(id: "left", x: 0, y: 0)
        let middle = display(id: "middle", x: 1920, y: 0, index: 1, isMain: true)
        let right = display(id: "right", x: 3840, y: 0, index: 2)
        let result = DisplayTopology.neighbor(from: middle, direction: .left, in: [left, middle, right])
        #expect(result?.id == left.id)
    }

    @Test
    func returnsNilWhenNoDisplayInDirection() {
        let only = display(id: "only", x: 0, y: 0, isMain: true)
        let above = display(id: "above", x: 0, y: -1080)
        let result = DisplayTopology.neighbor(from: only, direction: .right, in: [only, above])
        #expect(result == nil)
    }

    @Test
    func diagonalDisplayIsRejected() {
        // Diagonal displays should NOT be considered neighbors (insufficient overlap).
        let main = display(id: "main", x: 0, y: 0)
        let diagonal = display(id: "diagonal", x: 1920, y: 1100) // Just below-right, no axial overlap
        let result = DisplayTopology.neighbor(from: main, direction: .right, in: [main, diagonal])
        #expect(result == nil)
    }

    @Test
    func excludesSelfFromCandidates() {
        let only = display(id: "only", x: 0, y: 0, isMain: true)
        let result = DisplayTopology.neighbor(from: only, direction: .right, in: [only])
        #expect(result == nil)
    }

    @Test
    func upDirectionFindsDisplayAbove() {
        let bottom = display(id: "bottom", x: 0, y: 1080)
        let top = display(id: "top", x: 0, y: 0)
        let result = DisplayTopology.neighbor(from: bottom, direction: .up, in: [top, bottom])
        #expect(result?.id == top.id)
    }

    @Test
    func fingerprintNormalizesStableDisplayShape() {
        let snapshot = display(
            id: "abc",
            x: 10.4,
            y: -0.2,
            width: 3008.2,
            height: 1692.1,
            name: "  LG   HDR 4K  ",
            visibleWidth: 3008,
            visibleHeight: 1647,
            isMain: true
        )

        let fingerprint = DisplayFingerprint(display: snapshot)

        #expect(fingerprint.nameKey == "lg hdr 4k")
        #expect(fingerprint.sizeKey == "3008x1692")
        #expect(fingerprint.visibleSizeKey == "3008x1647")
        #expect(fingerprint.positionKey == "10:0")
        #expect(fingerprint.mainHint)
        #expect(fingerprint.previousDisplayID == DisplayID(rawValue: "abc"))
    }

    @Test
    func recognizesDisplayByPreviousIDWhenAvailable() {
        let original = DisplayFingerprint(display: display(id: "external", x: 1920, y: 0, name: "LG HDR 4K"))
        let external = display(id: "external", x: 1920, y: 0, name: "Renamed")
        let builtIn = display(id: "builtin", x: 0, y: 0, name: "Built-in Display", isMain: true)

        let decision = DisplayTopology.recognizeDisplay(for: original, in: [builtIn, external])

        #expect(decision.displayID == external.id)
        #expect(decision.isAmbiguous == false)
    }

    @Test
    func refusesAmbiguousFingerprintMatch() {
        let original = DisplayFingerprint(display: display(id: "old", x: 1920, y: 0, name: "LG HDR 4K"))
        let first = display(id: "new-a", x: 1920, y: 0, name: "LG HDR 4K")
        let second = display(id: "new-b", x: 1920, y: 0, name: "LG HDR 4K")

        let decision = DisplayTopology.recognizeDisplay(for: original, in: [first, second])

        #expect(decision.displayID == nil)
        #expect(decision.isAmbiguous)
        #expect(decision.candidateDisplayIDs == [first.id, second.id])
    }
}
