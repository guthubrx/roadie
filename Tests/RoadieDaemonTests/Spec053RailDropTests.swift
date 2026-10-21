import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec053RailDropTests {
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "fixture", title: "Test",
                              frame: Rect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test
    func removingAMiddleCardLeavesNoHoleAfterRepeatedDrops() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: "[fx.rail]\nrenderer = \"parallax-45\""))
        config.headerPosition = .hidden
        config.stagesPosition = .center
        config.slotHeight = 112
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hole053-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        let display = DisplayID(rawValue: "hole053")
        panel.position(on: screen, displayID: display, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        let stages = (1...9).map { PersistentStage(id: StageID(rawValue: String($0)), members: [member(UInt32($0))]) }
        var scope = PersistentStageScope(displayID: display, stages: stages)
        for count in [9, 8, 9, 7, 8] {
            let removedIndices = 3..<(3 + stages.count - count)
            scope.stages = stages.enumerated().filter { !removedIndices.contains($0.offset) }.map(\.element)
            panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:],
                liveWindowIDs: Set(scope.stages.flatMap(\.members).map(\.windowID))), displayName: "Test",
                config: config, thumbnails: RailThumbnailStore(), recordingStatus: nil, recordingIndicatorBottomOffset: 0)
            let cards = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            #expect(cards.count == count)
            for (above, below) in zip(cards, cards.dropFirst()) {
                #expect(abs(above.frame.minY - below.frame.maxY - config.layoutSpacing) < 0.5)
                #expect(above.layer?.opacity == 1)
            }
        }
    }

    @Test
    func fillingAnEmptyCardDoesNotMoveTheDestinations() {
        let empty = PersistentStage(id: StageID(rawValue: "reserved"), name: "Reserve")
        let occupied = PersistentStage(id: StageID(rawValue: "work"), name: "Work", members: [member(1)])
        var scope = PersistentStageScope(displayID: DisplayID(rawValue: "fixture"), stages: [empty, occupied])
        let before = StagePresentationOrder(scope: scope, liveWindowIDs: [WindowID(rawValue: 1)]).visibleStageIDs
        scope.stages[0].members = [member(2)]
        let after = StagePresentationOrder(scope: scope, liveWindowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]).visibleStageIDs
        #expect(after == before)
    }

    @Test(arguments: ["Perso", String(repeating: "Nom très long ", count: 20)])
    func onlyNamedEmptyDestinationsRenderWithTheirNameWhenLabelsAreDisabled(name: String) throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig()
        config.stageLabel.enabled = false
        config.slotHeight = 112
        let stage = PersistentStage(id: StageID(rawValue: "named"), name: name)
        let anonymous = PersistentStage(id: StageID(rawValue: "3"), name: "Stage 3")
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "empty053"), stages: [stage, anonymous])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("empty053-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:], liveWindowIDs: []),
                     displayName: "Test", config: config, thumbnails: RailThumbnailStore(),
                     recordingStatus: nil, recordingIndicatorBottomOffset: 0)
        let cards = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        #expect(cards.map(\.stageID) == [stage.id])
        let card = try #require(cards.first)
        let withoutName = StageCardView(stage: PersistentStage(id: stage.id), displayLabel: "", isActive: false,
                                       accent: .systemGreen, config: config, presentationStates: [:], thumbnails: [:])
        #expect(try #require(card.snapshotImage()?.tiffRepresentation) != withoutName.snapshotImage()?.tiffRepresentation)
        let point = panel.convertPoint(toScreen: card.convert(CGPoint(x: 40, y: card.bounds.midY), to: nil))
        #expect(panel.windowDropTarget(at: point)?.stageID == stage.id)
        #expect(panel.windowDropTarget(at: point)?.stageInsertion == nil)
    }

    @Test(arguments: ["parallax-45", "stacked-previews", "mosaic", "icons-only"])
    func freeAreasSelectTopMiddleAndBottomAndScrollingKeepsTheSameTarget(renderer: String) throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: "[fx.rail]\nrenderer = \"\(renderer)\""))
        config.headerPosition = .hidden
        config.stagesPosition = .top
        config.slotHeight = 80
        let stages = [
            PersistentStage(id: StageID(rawValue: "7")),
            PersistentStage(id: StageID(rawValue: "a"), name: "A", members: [member(1)]),
            PersistentStage(id: StageID(rawValue: "b"), name: "B", members: [member(2)])
        ]
        var scope = PersistentStageScope(displayID: DisplayID(rawValue: "fixture"), stages: stages)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail053-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        func render() {
            panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:],
                liveWindowIDs: Set(scope.stages.flatMap(\.members).map(\.windowID))), displayName: "Test",
                config: config, thumbnails: RailThumbnailStore(), recordingStatus: nil, recordingIndicatorBottomOffset: 0)
        }
        render()
        let cards = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        let last = try #require(cards.last)
        let point = panel.convertPoint(toScreen: panel.stack.convert(CGPoint(x: 50, y: last.frame.minY - 12), to: nil))
        let target = try #require(panel.windowDropTarget(at: point))
        #expect(target.stageID == stages[0].id)
        #expect(target.stageInsertion == .end)
        let top = panel.convertPoint(toScreen: panel.stack.convert(CGPoint(x: 50, y: cards[0].frame.maxY + 6), to: nil))
        let between = panel.convertPoint(toScreen: panel.stack.convert(
            CGPoint(x: 50, y: (cards[0].frame.minY + cards[1].frame.maxY) / 2), to: nil))
        #expect(panel.windowDropTarget(at: top)?.stageInsertion == .before(stages[1].id))
        #expect(panel.windowDropTarget(at: between)?.stageInsertion == .before(stages[2].id))
        #expect(panel.showWindowDropPreview(at: between)?.stageInsertion == .before(stages[2].id))
        #expect(panel.windowDropTarget(at: between)?.stageInsertion == .before(stages[2].id))
        let preview = try #require(panel.stack.subviews.compactMap { $0 as? RailWindowDropPreviewView }.first)
        #expect(preview.hitTest(.zero) == nil)
        panel.hideWindowDropPreview()
        // Une vraie carte reste une affectation à sa stage, sans réordonnancement.
        let cardPoint = panel.convertPoint(toScreen: last.convert(CGPoint(x: 40, y: last.bounds.midY), to: nil))
        #expect(panel.windowDropTarget(at: cardPoint)?.stageID == last.stageID)
        #expect(panel.windowDropTarget(at: cardPoint)?.stageInsertion == nil)
        scope.stages += (3...30).map { PersistentStage(id: StageID(rawValue: "n\($0)"), name: "N\($0)", members: [member(UInt32($0))]) }
        render()
        let scrolled = try #require(panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }.last)
        panel.stack.scrollToVisible(scrolled.frame)
        let scrolledPoint = panel.convertPoint(toScreen: scrolled.convert(CGPoint(x: 40, y: scrolled.bounds.midY), to: nil))
        #expect(panel.windowDropTarget(at: scrolledPoint)?.stageID == scrolled.stageID)
    }

    @Test(arguments: [false, true], [1, 2, 99])
    func freeAreaDropPersistsTheStagePositionOnTheSameOrAnotherDisplay(crossDisplay: Bool, position: Int) throws {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let targetDisplay = crossDisplay ? side : main
        let moved = powerWindow(1, x: 100)
        let other = powerWindow(2, x: crossDisplay ? 1100 : 400)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved, other])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("assign053-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let occupied = PersistentStage(id: StageID(rawValue: "occupied"), name: "Work", members: [member(2)])
        let source = PersistentStage(id: StageID(rawValue: "source"), name: "Source", members: [member(1)])
        let slot = PersistentStage(id: StageID(rawValue: "7"))
        var scopes = [PersistentStageScope(displayID: targetDisplay.id, activeStageID: occupied.id,
                                          stages: [slot, occupied] + (crossDisplay ? [] : [source]))]
        if crossDisplay { scopes.append(PersistentStageScope(displayID: main.id, activeStageID: source.id, stages: [source])) }
        store.save(PersistentStageState(scopes: scopes, activeDisplayID: main.id))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(), stageStore: store, events: EventLog(path: directory.appendingPathComponent("snapshot.jsonl").path))
        let command = StageCommandService(service: service, store: store,
            events: EventLog(path: directory.appendingPathComponent("commands.jsonl").path))
        let remaining = scopes[0].stages.filter { $0.id != slot.id }
        let insertion: StageInsertion = position <= remaining.count ? .before(remaining[position - 1].id) : .end
        // La liste affichée est figée, mais une autre action peut encore changer le store.
        let background = PersistentStage(id: StageID(rawValue: "background"), name: "Background")
        scopes[0].stages.insert(background, at: 0)
        store.save(PersistentStageState(scopes: scopes, activeDisplayID: main.id))
        let result = command.assign(windowID: moved.id, to: slot.id.rawValue, displayID: targetDisplay.id,
                                    insertionIndex: 0, stageInsertion: insertion, focusAssignedWindow: false)
        #expect(result.changed)
        let state = StageStore(path: store.fileURL.path).state()
        let destination = try #require(state.scopes.first { $0.displayID == targetDisplay.id })
        let expectedIndex = min(position, destination.stages.count - 1)
        #expect(destination.stages[expectedIndex].id == slot.id)
        #expect(destination.stages[expectedIndex].members.map(\.windowID) == [moved.id])
        #expect(destination.stages.first { $0.id == occupied.id }?.members.map(\.windowID) == [other.id])
        #expect(state.scopes.flatMap(\.stages).flatMap(\.members).filter { $0.windowID == moved.id }.count == 1)
    }

    @Test(arguments: ["occupied", "renamed", "missing_anchor"])
    func changedDestinationIsRejectedWithoutLosingOrMovingAnyMember(change: String) throws {
        let display = powerDisplay("conflict053")
        let moved = powerWindow(1, x: 100)
        let other = powerWindow(2, x: 500)
        let provider = PowerUserProvider(displays: [display], windows: [moved, other])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("conflict053-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let source = PersistentStage(id: StageID(rawValue: "source"), name: "Source", members: [member(1)])
        var slot = PersistentStage(id: StageID(rawValue: "7"))
        if change == "occupied" { slot.members = [member(2)] }
        if change == "renamed" { slot.name = "Renamed by user" }
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id, activeStageID: source.id,
            stages: [source, slot])], activeDisplayID: display.id))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(), stageStore: store,
            events: EventLog(path: directory.appendingPathComponent("snapshot.jsonl").path), persistStateChanges: false)
        let bytes = try Data(contentsOf: store.fileURL)
        let result = StageCommandService(service: service, store: store,
            events: EventLog(path: directory.appendingPathComponent("commands.jsonl").path))
            .assign(windowID: moved.id, to: slot.id.rawValue, displayID: display.id, insertionIndex: 0,
                    stageInsertion: change == "missing_anchor" ? .before(StageID(rawValue: "deleted")) : .end,
                    focusAssignedWindow: false)
        #expect(!result.changed)
        #expect(result.outcome == .failed)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
    }
}
