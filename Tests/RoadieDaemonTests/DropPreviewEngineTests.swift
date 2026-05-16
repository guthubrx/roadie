import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private final class DropPreviewProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let displaysValue: [DisplaySnapshot]
    private let windowsValue: [WindowSnapshot]

    init(displays: [DisplaySnapshot], windows: [WindowSnapshot]) {
        self.displaysValue = displays
        self.windowsValue = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        displaysValue
    }

    func windows() -> [WindowSnapshot] {
        windowsValue
    }
}

@Suite
struct DropPreviewEngineTests {
    @Test
    func mutableBspDragSplitsTargetWindowLocally() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let target = previewWindow(1, title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500))
        let source = previewWindow(2, title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500))
        let stageStore = StageStore(path: tempPreviewPath())
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: display.id,
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .mutableBsp,
                            members: [target, source].map {
                                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                            }
                        ),
                    ]
                ),
            ],
            activeDisplayID: display.id
        ))
        let service = SnapshotService(
            provider: DropPreviewProvider(displays: [display], windows: [target, source]),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: stageStore
        )
        let engine = DropPreviewEngine(service: service)

        let candidate = engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 250, y: 420))

        #expect(candidate?.operation == .insertDown)
        #expect(candidate?.frame == CGRect(x: 0, y: 255, width: 1000, height: 245))
        #expect(candidate?.placements[target.id] == Rect(x: 0, y: 0, width: 1000, height: 245))
        #expect(candidate?.placements[source.id] == Rect(x: 0, y: 255, width: 1000, height: 245))
    }

    @Test
    func mutableBspDragReflowsPeerIntoFreedSpace() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let target = previewWindow(1, title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500))
        let peer = previewWindow(2, title: "top-right", frame: Rect(x: 505, y: 0, width: 495, height: 245))
        let source = previewWindow(3, title: "bottom-right", frame: Rect(x: 505, y: 255, width: 495, height: 245))
        let stageStore = StageStore(path: tempPreviewPath())
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: display.id,
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .mutableBsp,
                            members: [target, peer, source].map {
                                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                            }
                        ),
                    ]
                ),
            ],
            activeDisplayID: display.id
        ))
        let service = SnapshotService(
            provider: DropPreviewProvider(displays: [display], windows: [target, peer, source]),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: stageStore
        )
        let engine = DropPreviewEngine(service: service)

        let candidate = engine.candidate(sourceWindowID: source.id, atAXPoint: CGPoint(x: 250, y: 420))

        #expect(candidate?.operation == .insertDown)
        #expect(candidate?.placements.keys.sorted { $0.rawValue < $1.rawValue } == [target.id, peer.id, source.id])
        #expect(candidate?.placements[target.id] == Rect(x: 0, y: 0, width: 495, height: 245))
        #expect(candidate?.placements[source.id] == Rect(x: 0, y: 255, width: 495, height: 245))
        #expect(candidate?.placements[peer.id] == Rect(x: 505, y: 0, width: 495, height: 500))
    }
}

private func previewWindow(_ rawID: UInt32, title: String, frame: Rect) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: rawID),
        pid: Int32(rawID + 10),
        appName: "App\(rawID)",
        bundleID: "app.\(rawID)",
        title: title,
        frame: frame,
        isOnScreen: true,
        isTileCandidate: true,
        subrole: "AXStandardWindow",
        role: "AXWindow",
        furniture: WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, hasMinimizeButton: true, isResizable: true)
    )
}

private func tempPreviewPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("roadie-drop-preview-\(UUID().uuidString).json")
        .path
}
