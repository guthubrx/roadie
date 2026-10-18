import AppKit
import Foundation
import os
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec041RailReorderPreviewTests {
    @Test func magnetismIsAdjustableAndDoesNotTrapDistantDestinations() {
        let ids = ["a", "hidden", "b", "c", "source"].map { StageID(rawValue: $0) }
        let targets: [(stageID: StageID, midY: CGFloat)] = [(ids[0], 300), (ids[2], 200), (ids[3], 100)]
        func position(_ y: CGFloat, previous: Int?, strength: CGFloat) -> Int? {
            RailPanel.persistentReorderPosition(pointY: y, targets: targets, orderedStageIDs: ids,
                                                sourceStageID: ids[4], previousPosition: previous, magnetism: strength)
        }
        #expect(position(298, previous: 1, strength: 50) == 1)
        #expect(position(280, previous: 1, strength: 50) == 3)
        #expect(position(280, previous: 1, strength: 100) == 1)
        #expect(position(198, previous: 3, strength: 0) == 4)
        #expect(position(198, previous: 3, strength: 50) == 3)
        #expect(position(180, previous: 3, strength: 50) == 4)
        #expect(position(180, previous: 3, strength: 100) == 3)
        #expect(position(160, previous: 3, strength: 100) == 4)
        #expect(position(202, previous: 4, strength: 50) == 4)
        #expect(position(220, previous: 4, strength: 50) == 3)
        #expect(position(220, previous: 4, strength: 100) == 4)
        #expect(position(240, previous: 4, strength: 100) == 3)
        #expect(position(400, previous: 4, strength: 100) == 1)
        #expect(position(0, previous: 1, strength: 100) == 5)
        #expect(position(198, previous: nil, strength: 100) == 4)
    }

    @Test func magnetismCanBeChangedFromSettingsAndTriggersReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail041-settings-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "".write(toFile: path, atomically: false, encoding: .utf8)
        let reloads = OSAllocatedUnfairLock(initialState: 0)
        let service = SettingsService(configPath: path, afterWrite: { reloads.withLock { $0 += 1 } })
        let before = RailSettings.load(path: path)
        #expect(before.stages.reorderMagnetism == 50)
        for strength in [0, 80, 100] {
            guard case .applied = service.set("rail.stages.reorder_magnetism", to: String(strength)) else {
                Issue.record("Aimantation non modifiable dans les paramètres")
                return
            }
            let after = RailSettings.load(path: path)
            #expect(after.stages.reorderMagnetism == Double(strength))
            #expect(RailVisualConfig.load(settings: after).reorderMagnetism == CGFloat(strength))
            #expect(after != before)
            #expect(after.statusLines != before.statusLines)
        }
        #expect(reloads.withLock { $0 } == 3)
        #expect(RailSettings.load(raw: "[fx.rail.stages]\nreorder_magnetism = 200").stages.reorderMagnetism == 100)
        #expect(RailSettings.load(raw: "[fx.rail.stages]\nreorder_magnetism = -1").stages.reorderMagnetism == 0)
    }

    @Test(arguments: ["Stage 42", "Personnel"])
    func previewRendersFutureNumberAndPreservesCustomName(name: String) throws {
        var config = RailVisualConfig()
        config.stageLabel.visibilitySeconds = 0
        config.stageLabel.enabled = true
        let stage = PersistentStage(id: StageID(rawValue: "42"), name: name)
        let original = StageCardView(stage: stage, displayLabel: name, isActive: false, accent: .systemBlue,
                                     config: config, presentationStates: [:], thumbnails: [:], position: 1)
        let before = try #require(original.snapshotImage()?.tiffRepresentation)
        let copy = original.reorderPreview(position: 3)
        let expected = StageCardView(stage: stage, displayLabel: name == "Stage 42" ? "Stage 3" : name,
                                     isActive: false, accent: .systemBlue, config: config,
                                     presentationStates: [:], thumbnails: [:], position: 3)
        let pixels = try #require(copy.snapshotImage()?.tiffRepresentation)
        #expect(pixels == expected.snapshotImage()?.tiffRepresentation)
        #expect(pixels != before)
        #expect(original.snapshotImage()?.tiffRepresentation == before)
    }

    @Test(arguments: ["icons-only", "stacked-previews", "parallax-45", "mosaic"], ["top", "center", "bottom"])
    func previewMatchesDropWithHiddenSlotsAndDifferentHeights(renderer: String, alignment: String) throws {
        let screen = try #require(NSScreen.screens.first)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail041-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: """
        [fx.rail]
        renderer = "\(renderer)"
        width = 150
        [fx.rail.stages]
        slot_height = 0
        gap = 13
        """))
        config.stagesPosition = try #require(RailStagesPosition(rawValue: alignment))
        config.headerPosition = .bottom
        func members(_ count: UInt32, start: UInt32) -> [PersistentStageMember] {
            (start..<(start + count)).map {
                PersistentStageMember(windowID: WindowID(rawValue: $0), bundleID: "com.example.preview",
                                      title: "Fenêtre \($0)", frame: Rect(x: 0, y: 0, width: 200, height: 100))
            }
        }
        let stages = [
            PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: members(1, start: 1)),
            PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2", members: []),
            PersistentStage(id: StageID(rawValue: "work"), name: "Travail", members: members(5, start: 2)),
            PersistentStage(id: StageID(rawValue: "reserve"), name: "Réserve", members: []),
        ]
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "preview"), stages: stages)
        let live = Set(stages.flatMap { $0.members.map(\.windowID) })
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        let stack = try #require(panel.contentView as? RailStackView)
        func render(_ value: PersistentStageScope) {
            panel.render(content: RailDisplayContent(scope: value, presentationStates: [:], liveWindowIDs: live),
                         displayName: "Écran de test", config: config, thumbnails: RailThumbnailStore(),
                         recordingStatus: nil, recordingIndicatorBottomOffset: 0)
            stack.layoutSubtreeIfNeeded()
        }
        // Aller en tête puis en fin, en incluant une carte nommée vide et une stage cachée.
        for toFront in [true, false] {
            render(scope)
            let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            #expect(cards.map(\.stageID.rawValue) == ["1", "work", "reserve"])
            let originalFrames = cards.map(\.frame)
            if renderer == "icons-only" { #expect(cards[0].frame.height != cards[1].frame.height) }
            let source = toFront ? cards[2] : cards[0]
            let target = toFront ? cards[0] : cards[2]
            let targetRect = stack.convert(target.previewDisplayFrames().first ?? target.bounds, from: target)
            let local = CGPoint(x: 50, y: targetRect.midY + (toFront ? 8 : -8))
            let point = panel.convertPoint(toScreen: stack.convert(local, to: nil))
            let position = try #require(panel.stageReorderPosition(at: point, sourceStageID: source.stageID))
            #expect(position == (toFront ? 1 : 4))
            panel.showStageReorderPreview(at: point, sourceStageID: source.stageID)
            let overlay = try #require(stack.subviews.compactMap { $0 as? RailStageReorderPreviewView }.first)
            stack.layoutSubtreeIfNeeded()
            let projected = overlay.subviews.compactMap { $0 as? StageCardView }
            let frames = projected.map(\.frame)
            #expect(cards.map(\.frame) == originalFrames)
            #expect(panel.stageReorderPosition(at: point, sourceStageID: source.stageID) == position)
            #expect(projected.first(where: { $0.stageID == source.stageID })?.alphaValue == 0.5)
            #expect(overlay.hitTest(local) == nil)
            let jitter = CGPoint(x: local.x, y: targetRect.midY + (toFront ? -2 : 2))
            let jitterPoint = panel.convertPoint(toScreen: stack.convert(jitter, to: nil))
            panel.showStageReorderPreview(at: jitterPoint, sourceStageID: source.stageID)
            #expect(panel.stageReorderPosition(at: jitterPoint, sourceStageID: source.stageID) == position)
            #expect(overlay.superview === stack)
            // Une autre destination puis le retour ne doivent créer aucune nouvelle copie.
            let identities = Set(projected.map(ObjectIdentifier.init))
            let middleRect = stack.convert(cards[1].previewDisplayFrames().first ?? cards[1].bounds, from: cards[1])
            let otherPoint = panel.convertPoint(toScreen: stack.convert(CGPoint(x: 50, y: middleRect.midY), to: nil))
            panel.showStageReorderPreview(at: otherPoint, sourceStageID: source.stageID)
            #expect(Set(overlay.subviews.compactMap { $0 as? StageCardView }.map(ObjectIdentifier.init)) == identities)
            let returnPoint = panel.convertPoint(toScreen: stack.convert(
                CGPoint(x: 50, y: targetRect.midY + (toFront ? 48 : -48)), to: nil))
            panel.showStageReorderPreview(at: returnPoint, sourceStageID: source.stageID)
            #expect(overlay.position == position)
            #expect(overlay.subviews.compactMap { $0 as? StageCardView }.map(\.frame) == frames)
            projected.forEach { $0.needsDisplay = false }
            panel.refreshStageLabels()
            #expect(projected.allSatisfy { $0.needsDisplay })
            var changed = scope
            let reordered = changed.reorderStage(source.stageID, to: position)
            #expect(reordered)
            // render doit aussi effacer un aperçu encore ouvert.
            render(changed)
            let committed = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            #expect(committed.map(\.stageID) == projected.map(\.stageID))
            #expect(committed.map(\.frame) == frames)
            #expect(overlay.superview == nil)
            #expect(cards.allSatisfy { $0.layer?.opacity == 1 })
        }
        // Un rechargement du même panneau doit changer le comportement, sans accès à ses champs privés.
        for strength in [0.0, 100.0] {
            config.reorderMagnetism = CGFloat(strength)
            render(scope)
            let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            let target = stack.convert(cards[0].previewDisplayFrames().first ?? cards[0].bounds, from: cards[0])
            func screenPoint(_ dy: CGFloat) -> CGPoint {
                panel.convertPoint(toScreen: stack.convert(CGPoint(x: 50, y: target.midY + dy), to: nil))
            }
            panel.showStageReorderPreview(at: screenPoint(2), sourceStageID: cards[2].stageID)
            #expect(panel.stageReorderPosition(at: screenPoint(-2), sourceStageID: cards[2].stageID)
                    == (strength == 0 ? 3 : 1))
        }
        render(scope)
        let point = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.showStageReorderPreview(at: point, sourceStageID: StageID(rawValue: "missing"))
        #expect(stack.subviews.allSatisfy { !($0 is RailStageReorderPreviewView) })
        var single = scope
        single.stages = [stages[0]]
        render(single)
        #expect(panel.stageReorderPosition(at: point, sourceStageID: stages[0].id) == nil)
    }
}
