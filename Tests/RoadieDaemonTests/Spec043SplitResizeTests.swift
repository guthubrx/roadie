import CoreGraphics
import Foundation
import Testing
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

@Suite @MainActor
struct Spec043SplitResizeTests {
    @Test(arguments: [true, false])
    func onlyAcceptedExplicitGripClaimsNativeGesture(accepted: Bool) throws {
        let handle = try handle()
        let input = UserInputActivity()
        var releases: [Bool] = []
        input.observeGestures(target: { _ in (2, CGRect(x: 505, y: -600, width: 495, height: 600)) },
                              onRelease: { releases.append($0) })
        let controller = SplitResizeController(presentationEnabled: false, onBegin: { _, _ in
            guard accepted else { return false }
            input.claimExplicitResize()
            return true
        }, onUpdate: { _, _ in }, onEnd: { _, _ in })
        controller.update(handles: [handle])
        input.mouseDown(at: handle.divider.position)
        #expect(input.currentGesture?.windowID == 2)
        #expect(controller.begin(handle: handle, at: handle.divider.position) == accepted)
        input.mouseDragged()
        input.mouseUp(leftButton: true)
        controller.end()
        let native = input.takeGesture()
        if accepted { #expect(native == nil) }
        else { #expect(native?.windowID == 2); #expect(native?.didDrag == true) }
        #expect(releases == [!accepted])
    }

    @Test
    func explicitResizeSupersedesOlderUnconsumedNativeGesture() {
        let input = UserInputActivity()
        input.observeGestures(target: { _ in (2, CGRect(x: 0, y: 0, width: 500, height: 500)) }, onRelease: { _ in })
        input.mouseDown(at: .zero)
        input.mouseDragged()
        input.mouseUp(leftButton: true)
        input.mouseDown(at: .zero)
        input.claimExplicitResize()
        #expect(input.currentGesture == nil)
        #expect(input.takeGesture() == nil)
        input.mouseUp(leftButton: true)
        #expect(input.takeGesture() == nil)
    }

    private func handle(display: String = "one", stage: String = "1", ratio: Double = 0.5, orientation: BSPOrientation = .vertical) throws -> SplitResizeHandle {
        let tree = BSPTree.split(orientation: orientation, ratio: ratio,
                                 first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2)))
        let divider = try #require(tree.dividers(in: CGRect(x: 0, y: -600, width: 1000, height: 600), innerGap: 10).first)
        return SplitResizeHandle(scope: StageScope(displayID: DisplayID(rawValue: display),
                                                  desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: stage)),
                                 divider: divider)
    }

    @Test
    func explicitGripPreservesClickOffsetAndEndsExactlyOnce() throws {
        let handle = try handle()
        var positions: [CGPoint] = []
        var endings: [Bool] = []
        let controller = SplitResizeController(presentationEnabled: false, onBegin: { _, _ in true },
                                               onUpdate: { _, point in positions.append(point) },
                                               onEnd: { _, cancelled in endings.append(cancelled) })
        controller.update(handles: [handle])
        #expect(!controller.begin(handle: handle, at: CGPoint(x: 400, y: -300)))
        #expect(controller.begin(handle: handle, at: CGPoint(x: 502, y: -300)))
        #expect(!controller.begin(handle: handle, at: CGPoint(x: 502, y: -300)))
        controller.drag(to: CGPoint(x: 602, y: -300))
        controller.end()
        controller.end()
        controller.stop()
        #expect(positions == [CGPoint(x: 600, y: -300)])
        #expect(endings == [false])
        #expect(!controller.isDragging)
    }

    @Test
    func refusedGestureNeverEmitsUpdateOrEnd() throws {
        let handle = try handle()
        var called = false
        let controller = SplitResizeController(presentationEnabled: false, onBegin: { _, _ in false },
                                               onUpdate: { _, _ in called = true }, onEnd: { _, _ in called = true })
        controller.update(handles: [handle])
        #expect(!controller.begin(handle: handle, at: handle.divider.position))
        controller.drag(to: .zero)
        controller.end()
        #expect(!called)
    }

    @Test(arguments: ["cancel", "buttonLost", "stop", "stage", "display", "orientation", "removed"])
    func interruptionAlwaysReleasesAcceptedGesture(reason: String) throws {
        let handle = try handle()
        var endings: [Bool] = []
        let controller = SplitResizeController(presentationEnabled: false, onBegin: { _, _ in true },
                                               onUpdate: { _, _ in }, onEnd: { _, flag in endings.append(flag) })
        controller.update(handles: [handle])
        #expect(controller.begin(handle: handle, at: handle.divider.position))
        switch reason {
        case "cancel": controller.cancel()
        case "buttonLost": controller.checkButton(isPressed: false)
        case "stop": controller.stop()
        case "stage": controller.update(handles: [try self.handle(stage: "2")])
        case "display": controller.update(handles: [try self.handle(display: "other")])
        case "orientation": controller.update(handles: [try self.handle(orientation: .horizontal)])
        default: controller.update(handles: [])
        }
        controller.end()
        #expect(!controller.isDragging)
        #expect(endings == [true])
    }

    @Test
    func refreshedRatioKeepsGestureAndItsInitialClickOffset() throws {
        let handle = try handle()
        var positions: [CGPoint] = []
        var endings: [Bool] = []
        let controller = SplitResizeController(presentationEnabled: false, onBegin: { _, _ in true },
                                               onUpdate: { _, point in positions.append(point) },
                                               onEnd: { _, flag in endings.append(flag) })
        controller.update(handles: [handle])
        #expect(controller.begin(handle: handle, at: CGPoint(x: 502, y: -300)))
        controller.update(handles: [try self.handle(ratio: 0.6)])
        controller.checkButton(isPressed: true)
        #expect(controller.isDragging)
        controller.drag(to: CGPoint(x: 650, y: -300))
        controller.end()
        #expect(positions == [CGPoint(x: 648, y: -300)])
        #expect(endings == [false])
    }

    @Test
    func coordinateConversionKeepsExternalScreenAboveAndToTheLeft() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 900, width: 1920, height: 1080)]
        let ax = CGRect(x: -1500, y: -900, width: 8, height: 500)
        let ns = RoadieScreenCoordinate.axRectToNS(ax, screenFrames: screens, primaryHeight: 900)
        #expect(ns == CGRect(x: -1500, y: 1300, width: 8, height: 500))
        let point = RoadieScreenCoordinate.nsPointToAX(CGPoint(x: ns.midX, y: ns.midY), screenFrames: screens, primaryHeight: 900)
        #expect(point == CGPoint(x: ax.midX, y: ax.midY))
    }
}
