import CoreGraphics
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
struct TargetSearchDismissalTests {
    private let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)

    private var search: TargetSearchBar {
        TargetSearchBar(query: "draft", matchCount: 1, properties: nil, isLoading: false)
    }

    private var command: TargetSearchBar {
        TargetSearchBar(query: "/", matchCount: 0, properties: nil, isLoading: false,
                        commandInput: "stage", suggestions: [SlashSuggestion(text: "stage", kind: .command)],
                        message: .error("Stage inconnu", usage: "stage <nom>"))
    }

    private func model() -> TargetSearchModel {
        let target = RoadieTarget(id: "drafts", label: "A", kind: .appElement, title: "Drafts", source: .app,
                                  frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: [.click])
        var model = TargetSearchModel(targets: [target])
        model.type("draft")
        return model
    }

    @Test(arguments: [false, true])
    func onlySearchObservesMouseDown(searchMode: Bool) {
        let mask = TargetSearchDismissal.eventMask(search: searchMode)
        #expect(mask & (1 << CGEventType.keyDown.rawValue) != 0)
        for type in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            #expect((mask & (1 << type.rawValue) != 0) == searchMode)
            #expect(TargetSearchDismissal.isMouseDown(type))
        }
        for type in [CGEventType.leftMouseUp, .rightMouseUp, .mouseMoved, .scrollWheel] {
            #expect(mask & (1 << type.rawValue) == 0)
            #expect(!TargetSearchDismissal.isMouseDown(type))
        }
    }

    @Test(arguments: [false, true])
    func inputAreaKeepsSearchOpenWithEitherLayout(commandLayout: Bool) {
        let layout = (commandLayout ? command : search).layout(in: screen, style: .labels)
        var model = model()
        #expect(!TargetSearchDismissal.cancelIfOutside(at: CGPoint(x: layout.bar.midX, y: layout.bar.midY),
                                                      layout: layout, model: &model))
        #expect(model.query == "draft")
        #expect(TargetSearchDismissal.cancelIfOutside(at: CGPoint(x: 1, y: 1), layout: layout, model: &model))
    }

    @Test
    func commandQueryClosesOnlyOutside() {
        var model = TargetSearchModel(targets: [])
        model.type("/stage")
        let layout = command.layout(in: screen, style: .labels)
        #expect(model.isCommandMode)
        #expect(!TargetSearchDismissal.cancelIfOutside(at: CGPoint(x: layout.bar.midX, y: layout.bar.midY),
                                                      layout: layout, model: &model))
        #expect(model.query == "/stage")
        #expect(TargetSearchDismissal.cancelIfOutside(at: CGPoint(x: 1, y: 1), layout: layout, model: &model))
    }

    @Test
    func suggestionsAndMessagesStayInsideButTheGapIsOutside() throws {
        let layout = command.layout(in: screen, style: .labels)
        let panel = try #require(layout.panel)
        #expect(!layout.suggestionRows.isEmpty)
        #expect(layout.messageRows.count == 2)
        for row in layout.suggestionRows + layout.messageRows {
            #expect(layout.contains(CGPoint(x: row.midX, y: row.midY)))
        }
        // Inclure également le fond et son padding, pas seulement les lignes de texte.
        #expect(layout.contains(CGPoint(x: panel.minX + 1, y: panel.minY + 1)))
        #expect(!layout.contains(CGPoint(x: layout.bar.midX, y: (layout.bar.maxY + panel.minY) / 2)))
        #expect(!layout.contains(CGPoint(x: panel.maxX + 1, y: panel.midY)))
    }

    @Test
    func removingCommandContentRemovesTheOldPanelHitArea() throws {
        let layout = command.layout(in: screen, style: .labels)
        let panel = try #require(layout.panel)
        #expect(!search.layout(in: screen, style: .labels).contains(CGPoint(x: panel.midX, y: panel.midY)))
    }

    @Test
    func liveFontSizesUseTheNewBarAndPanelAreas() throws {
        let original = command.layout(in: screen, style: .labels)
        let resized = command.layout(in: screen, style: TargetOverlayStyle(searchTextFontSize: 48, commandTextFontSize: 48))
        let barPoint = CGPoint(x: resized.bar.midX, y: original.bar.maxY + 2)
        #expect(resized.bar.contains(barPoint))
        let panel = try #require(resized.panel)
        let panelPoint = CGPoint(x: panel.midX, y: panel.maxY - 2)
        #expect(resized.contains(panelPoint))
        #expect(!original.contains(panelPoint))
    }

    @Test
    func outsideClickCancelsReturnBeforeItsDeadline() {
        var model = model()
        let now = Date()
        #expect(model.pressReturn(shift: false, command: false, at: now) == nil)
        #expect(model.isAwaitingSecondReturn)
        #expect(TargetSearchDismissal.cancelIfOutside(at: .zero, layout: search.layout(in: screen, style: .labels), model: &model))
        #expect(!model.isAwaitingSecondReturn)
        #expect(model.pendingReturn(at: now.addingTimeInterval(1)) == nil)
    }

    @Test
    func insideClickPreservesThePendingReturn() {
        var model = model()
        let now = Date()
        let layout = search.layout(in: screen, style: .labels)
        _ = model.pressReturn(shift: false, command: false, at: now)
        #expect(!TargetSearchDismissal.cancelIfOutside(at: CGPoint(x: layout.bar.midX, y: layout.bar.midY), layout: layout, model: &model))
        #expect(model.isAwaitingSecondReturn)
        #expect(model.pendingReturn(at: now.addingTimeInterval(1)) == .click)
    }

    @Test
    func missingOverlayDoesNotDismiss() {
        var model = model()
        #expect(!TargetSearchDismissal.cancelIfOutside(at: .zero, layout: nil, model: &model))
    }

    @Test
    func clicksAreMappedAcrossHorizontallyAndVerticallyOffsetDisplays() {
        let screens = [screen, CGRect(x: -1920, y: 350, width: 1920, height: 1080),
                       CGRect(x: 1280, y: -900, width: 1440, height: 900)]
        for barScreen in screens {
            let layout = command.layout(in: barScreen, style: .labels)
            let point = CGPoint(x: layout.bar.midX, y: layout.bar.midY)
            let axPoint = RoadieScreenCoordinate.nsPointToAX(point, screenFrames: screens, primaryHeight: screen.height)
            let converted = RoadieScreenCoordinate.axRectToNS(CGRect(origin: axPoint, size: .zero), screenFrames: screens,
                                                             primaryHeight: screen.height).origin
            #expect(layout.contains(converted))
            for otherScreen in screens where otherScreen != barScreen {
                #expect(!layout.contains(CGPoint(x: otherScreen.midX, y: otherScreen.midY)))
            }
        }
    }
}
