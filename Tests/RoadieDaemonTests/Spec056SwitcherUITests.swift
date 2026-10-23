import CoreGraphics
import RoadieCore
import Testing
@testable import RoadieDaemon

struct Spec056SwitcherSessionTests {
    private func session(
        stayOpen: Bool = false,
        fromHotkey: Bool = true,
        heldAtStart: Bool = true,
        backwards: Bool = false
    ) -> WindowSwitcherSessionState {
        WindowSwitcherSessionState(stayOpen: stayOpen, fromHotkey: fromHotkey, heldAtStart: heldAtStart, backwards: backwards)
    }

    @Test func quickTapAcceptsAsSoonAsTheTargetIsReady() {
        var state = session(heldAtStart: false)
        let ready = state.ready()
        #expect(ready == .acceptImmediately(steps: []))
    }

    @Test func releaseAfterPresentationAcceptsTheTarget() {
        var state = session()
        let ready = state.ready()
        #expect(ready == .present(steps: []))
        let heldAgain = state.modifiers(held: true)
        #expect(!heldAgain)
        let released = state.modifiers(held: false)
        #expect(released)
    }

    @Test func releaseDuringAcquisitionAcceptsWhenReady() {
        var state = session()
        let early = state.modifiers(held: false)
        #expect(!early)
        let ready = state.ready()
        #expect(ready == .acceptImmediately(steps: []))
    }

    @Test func stayOpenKeepsThePanelAfterRelease() {
        var state = session(stayOpen: true)
        let early = state.modifiers(held: false)
        #expect(!early)
        let ready = state.ready()
        #expect(ready == .present(steps: []))
    }

    @Test func searchKeepsThePanelOpenAfterRelease() {
        var state = session()
        _ = state.ready()
        state.searchChanged(isEmpty: false)
        #expect(state.persistent)
        let released = state.modifiers(held: false)
        #expect(!released)
    }

    @Test func clearingTheSearchRestoresReleaseAccept() {
        var state = session()
        _ = state.ready()
        state.searchChanged(isEmpty: false)
        state.searchChanged(isEmpty: true)
        #expect(!state.persistent)
        let released = state.modifiers(held: false)
        #expect(released)
    }

    @Test func explicitConfirmDuringAcquisitionIsKeptForReady() {
        var state = session()
        let early = state.confirm()
        #expect(!early)
        let ready = state.ready()
        #expect(ready == .acceptImmediately(steps: []))
    }

    @Test func confirmWhilePresentedAcceptsNow() {
        var state = session()
        _ = state.ready()
        #expect(state.confirm())
    }

    @Test func stepsDuringAcquisitionAreQueuedInOrder() {
        var state = session()
        #expect(!state.step(backwards: false))
        #expect(!state.step(backwards: true))
        let ready = state.ready()
        #expect(ready == .present(steps: [false, true]))
    }

    @Test func backwardsStartQueuesTheFirstStep() {
        var state = session(backwards: true)
        let ready = state.ready()
        #expect(ready == .present(steps: [true]))
    }

    @Test func stepsWhilePresentedApplyDirectly() {
        var state = session()
        _ = state.ready()
        #expect(state.step(backwards: false))
        #expect(state.queuedSteps.isEmpty)
    }

    @Test func closeBeforeLoadingKeepsALateLoadClosed() {
        var state = session()
        state.close()
        let late = state.ready()
        #expect(late == nil)
        #expect(!state.step(backwards: false))
        #expect(!state.confirm())
    }

    @Test func closeWhilePresentedStopsReleaseAndConfirm() {
        var state = session()
        _ = state.ready()
        state.close()
        let released = state.modifiers(held: false)
        #expect(!released)
        #expect(!state.confirm())
    }
}

struct Spec056SwitcherLayoutTests {
    private func appearance(style: String = "thumbnails", autoSize: Bool = true, width: Double = 220) -> WindowSwitcherAppearance {
        WindowSwitcherAppearance(config: WindowSwitcherConfig(style: style, autoSize: autoSize, thumbnailWidth: width))
    }

    @Test func unknownStyleFallsBackToThumbnails() {
        #expect(WindowSwitcherStyle.from("inconnu") == .thumbnails)
    }

    @Test func emptyEntriesHaveNoFrames() {
        let layout = WindowSwitcherGrid.layout(count: 0, appearance: appearance(), available: 800)
        #expect(layout.frames.isEmpty)
        #expect(layout.contentSize == .zero)
    }

    @Test func autoSizeKeepsBaseWidthWhenItFits() {
        let layout = WindowSwitcherGrid.layout(count: 3, appearance: appearance(), available: 800)
        #expect(layout.columns == 3)
        #expect(layout.cardSize.width == 220)
        #expect(layout.frames[1].minX == 232)
    }

    @Test func autoSizeShrinksCardsToFillTheRow() {
        let layout = WindowSwitcherGrid.layout(count: 4, appearance: appearance(), available: 400)
        #expect(layout.columns == 3)
        #expect(layout.cardSize.width < 220)
        #expect(layout.cardSize.width >= 120)
    }

    @Test func manualWidthWrapsByBaseWidth() {
        let layout = WindowSwitcherGrid.layout(count: 5, appearance: appearance(autoSize: false), available: 500)
        #expect(layout.columns == 2)
        #expect(layout.frames.count == 5)
        #expect(layout.frames[4].minY == 2 * (layout.cardSize.height + WindowSwitcherGrid.spacing))
    }

    @Test func manualWidthIsClampedToSupportedRange() {
        let layout = WindowSwitcherGrid.layout(count: 2, appearance: appearance(autoSize: false, width: 900), available: 1000)
        #expect(layout.cardSize.width == 400)
    }

    @Test func listUsesOneFullWidthColumn() {
        let layout = WindowSwitcherGrid.layout(count: 4, appearance: appearance(style: "list"), available: 600)
        #expect(layout.columns == 1)
        #expect(layout.cardSize.width == 600)
        #expect(layout.frames.count == 4)
    }

    @Test func iconsUseFontDrivenWidth() {
        let layout = WindowSwitcherGrid.layout(count: 4, appearance: appearance(style: "icons"), available: 600)
        #expect(layout.cardSize.width == 120)
        #expect(layout.columns == 4)
    }

    @Test func imageHeightKeepsSixteenByNineRatio() {
        #expect(WindowSwitcherGrid.imageHeight(cardWidth: 200) == 103.5)
    }
}
