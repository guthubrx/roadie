import AppKit
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@MainActor
struct Spec071LivePreviewTests {
    private let a = DisplayID(rawValue: "A")
    private let b = DisplayID(rawValue: "B")
    private func scope(_ display: DisplayID, _ desktop: Int, _ stage: String) -> StageScope {
        StageScope(displayID: display, desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage))
    }

    /// A : bureau 1 (stages a, b), bureau 2 (stage c). B : bureau 1 (stage d).
    private func model() -> OverviewModel {
        let layout: [(UInt32, DisplayID, Int, String)] = [(1, a, 1, "a"), (2, a, 1, "a"), (3, a, 1, "b"), (4, a, 2, "c"), (5, b, 1, "d")]
        let entries = layout.map { id, display, desktop, stage in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: id), pid: 1, appName: "App", bundleID: "fixture", title: "F\(id)",
                                                       frame: Rect(x: 0, y: 0, width: 900, height: 600), isOnScreen: true, isTileCandidate: true),
                                scope: scope(display, desktop, stage), stageName: stage.uppercased())
        }
        let displays = [a, b].enumerated().map { index, id in
            DisplaySnapshot(id: id, index: index, name: id.rawValue, frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
                            visibleFrame: Rect(x: 0, y: 0, width: 1728, height: 1080), isMain: index == 0)
        }
        return OverviewModel(entries: entries, displays: displays, state: PersistentStageState())
    }

    private func names(_ model: OverviewModel, _ display: DisplayID) -> [String] {
        model.displays.first { $0.id == display }?.desktops.map(\.name) ?? []
    }
    private func windows(_ model: OverviewModel, _ display: DisplayID, _ desktop: Int) -> [UInt32] {
        model.displays.first { $0.id == display }?.desktops.first { $0.id.desktopID == DesktopID(rawValue: desktop) }?
            .entries.map(\.id.rawValue) ?? []
    }

    @Test func previewReordersAndRenumbersDesktops() {
        let base = model()
        let swapped = base.previewing(.desktop(source: OverviewDesktopID(displayID: a, desktopID: DesktopID(rawValue: 2)), display: a, target: DesktopID(rawValue: 1)))
        #expect(names(swapped, a) == ["Bureau 1", "Bureau 2"])
        #expect(swapped.displays[0].desktops.map(\.id.desktopID.rawValue) == [2, 1])
        let moved = base.previewing(.desktop(source: OverviewDesktopID(displayID: a, desktopID: DesktopID(rawValue: 1)), display: b, target: DesktopID(rawValue: 1)))
        #expect(names(moved, a) == ["Bureau 1"])
        #expect(names(moved, b) == ["Bureau 1", "Bureau 2"])
        #expect(moved.displays[1].desktops.first?.entries.map(\.id.rawValue) == [1, 2, 3])
    }

    @Test func previewMovesStagesAndWindowsIntoNewContainers() {
        let base = model()
        let stage = base.previewing(.stage(source: scope(a, 1, "b"), display: b, desktop: DesktopID(rawValue: 1), before: StageID(rawValue: "d")))
        #expect(windows(stage, b, 1) == [3, 5])
        #expect(windows(stage, a, 1) == [1, 2])
        let newStage = base.previewing(.windowToNewStage(WindowID(rawValue: 1), display: a, desktop: DesktopID(rawValue: 2)))
        #expect(windows(newStage, a, 2) == [4, 1])
        #expect(newStage.displays[0].desktops[1].stages.last?.name == "Nouvelle stage")
        let newDesktop = base.previewing(.windowToNewDesktop(WindowID(rawValue: 5), display: a))
        #expect(names(newDesktop, a).last == "Nouveau bureau")
        #expect(windows(newDesktop, a, 3) == [5])
        let stageDesktop = base.previewing(.stageToNewDesktop(source: scope(a, 1, "a"), display: b))
        #expect(windows(stageDesktop, b, 2) == [1, 2])
    }

    private func canvas() -> OverviewCanvas {
        let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        var config = OverviewConfig()
        config.loupe = false
        canvas.config = config
        canvas.model = model()
        canvas.viewport = CGSize(width: 1600, height: 1000)
        canvas.rebuild()
        return canvas
    }

    @Test func emptyZonesCreateContainers() throws {
        let canvas = canvas()
        // L’écran B garde du vide sous son unique bureau ; la colonne de A est pleine.
        let lastB = try #require(canvas.plan.desktops.last { $0.desktop.id.displayID == b })
        #expect(canvas.newDesktopZone(at: CGPoint(x: lastB.frame.midX, y: lastB.frame.maxY + 40)) == b)
        #expect(canvas.newDesktopZone(at: CGPoint(x: lastB.frame.midX, y: lastB.frame.midY)) == nil)
    }

    @Test func compositionIsCenteredVertically() throws {
        let plan = canvas().plan
        let top = try #require(plan.displays.map(\.frame.minY).min())
        let bottom = try #require(plan.desktops.map(\.frame.maxY).max())
        #expect(abs(top - (1000 - bottom)) < 2)
    }
}
