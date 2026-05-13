import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct WindowDragReorderEligibilityTests {
    @Test
    func acceptsRegularResizableStandardWindow() {
        let window = dragWindow(
            subrole: "AXStandardWindow",
            furniture: WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, hasMinimizeButton: true, isResizable: true)
        )

        #expect(WindowDragReorderEligibility.accepts(window))
    }

    @Test
    func rejectsModalAndNonResizableDialogs() {
        let modal = dragWindow(
            subrole: "AXStandardWindow",
            furniture: WindowFurniture(hasCloseButton: true, isModal: true, isResizable: true)
        )
        let nonResizable = dragWindow(
            subrole: "AXStandardWindow",
            furniture: WindowFurniture(hasCloseButton: true, isResizable: false)
        )

        #expect(WindowDragReorderEligibility.accepts(modal) == false)
        #expect(WindowDragReorderEligibility.accepts(nonResizable) == false)
    }

    @Test
    func rejectsNonStandardSubrolesEvenWhenRawTileCandidate() {
        let window = dragWindow(
            subrole: "AXDialog",
            furniture: WindowFurniture(hasCloseButton: true, isResizable: true)
        )

        #expect(WindowDragReorderEligibility.accepts(window) == false)
    }

    private func dragWindow(
        subrole: String?,
        furniture: WindowFurniture?,
        isTileCandidate: Bool = true
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: 42),
            pid: 42,
            appName: "Dialog Test",
            bundleID: "test.dialog",
            title: "Dialog",
            frame: Rect(x: 100, y: 100, width: 400, height: 260),
            isOnScreen: true,
            isTileCandidate: isTileCandidate,
            subrole: subrole,
            role: "AXWindow",
            furniture: furniture
        )
    }
}
