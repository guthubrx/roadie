import CoreGraphics
import Testing
@testable import RoadieDaemon

/// SPEC-023 (correctif) : la fenêtre de réglages s'ouvre sur l'écran du pointeur, pas toujours sur le premier écran.
@Suite
struct SettingsWindowPlacementTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 950)
    private let external = CGRect(x: 1512, y: 146, width: 3200, height: 1654)
    private let size = CGSize(width: 860, height: 632)

    @Test
    func opensCenteredOnTheScreenUnderThePointer() {
        let onExternal = SettingsWindowController.centeredFrame(size: size, screens: [laptop, external], pointer: CGPoint(x: 2317, y: 1005))
        #expect(onExternal.midX == external.midX && onExternal.midY == external.midY)
        let onLaptop = SettingsWindowController.centeredFrame(size: size, screens: [laptop, external], pointer: CGPoint(x: 100, y: 100))
        #expect(onLaptop.midX == laptop.midX && onLaptop.midY == laptop.midY)
    }

    @Test
    func fallsBackToTheFirstScreenAndNeverExceedsTheScreen() {
        let outside = SettingsWindowController.centeredFrame(size: size, screens: [laptop, external], pointer: CGPoint(x: -500, y: -500))
        #expect(laptop.contains(outside))
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let fitted = SettingsWindowController.centeredFrame(size: size, screens: [small], pointer: CGPoint(x: 10, y: 10))
        #expect(fitted.width == 600 && fitted.height == 400 && small.contains(fitted))
        #expect(SettingsWindowController.centeredFrame(size: size, screens: [], pointer: .zero).size == size)
    }
}
