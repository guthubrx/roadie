import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PowerUserLayoutCommandTests {
    @Test
    func layoutFlattenAndSplitReturnCommandResults() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer)
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let flatten = commands.flatten()
        let split = commands.split("horizontal")

        #expect(flatten.message.contains("layout flatten"))
        #expect(split.message.contains("layout split horizontal"))
    }

    @Test
    func layoutSplitVerticalStacksWindowsTopToBottom() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0, y: 0, width: 300, height: 300),
            powerWindow(2, x: 350, y: 0, width: 300, height: 300),
            powerWindow(3, x: 700, y: 0, width: 300, height: 300),
        ])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsInner: 4))
        )
        _ = service.snapshot()

        let result = LayoutCommandService(service: service).split("vertical")

        #expect(result.changed)
        #expect(writer.frames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 1000, height: 264))
        #expect(writer.frames[WindowID(rawValue: 2)] == Rect(x: 0, y: 268, width: 1000, height: 264))
        #expect(writer.frames[WindowID(rawValue: 3)] == Rect(x: 0, y: 536, width: 1000, height: 264))
    }

    @Test
    func mutableBspToggleSplitFlipsOnlyActiveNeighborPair() {
        let left = powerWindow(1, x: 0, y: 0, width: 495, height: 500)
        let right = powerWindow(2, x: 505, y: 0, width: 495, height: 500)
        let untouched = powerWindow(3, x: 0, y: 510, width: 1000, height: 290)
        let provider = PowerUserProvider(windows: [left, right, untouched])
        provider.focusedID = right.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("layout-toggle-split"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: DisplayID(rawValue: "display-main"),
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .mutableBsp,
                            focusedWindowID: right.id,
                            members: [left, right, untouched].map {
                                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                            }
                        ),
                    ]
                ),
            ],
            activeDisplayID: DisplayID(rawValue: "display-main")
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsInner: 10)),
            stageStore: store
        )

        let result = LayoutCommandService(service: service).toggleSplit()

        #expect(result.changed)
        #expect(result.message.contains("layout toggle-split vertical"))
        #expect(writer.frames[left.id] == Rect(x: 0, y: 0, width: 1000, height: 245))
        #expect(writer.frames[right.id] == Rect(x: 0, y: 255, width: 1000, height: 245))
        #expect(writer.frames[untouched.id] == nil)
    }

    @Test
    func toggleSplitRequiresMutableBsp() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0, y: 0, width: 495, height: 500),
            powerWindow(2, x: 505, y: 0, width: 495, height: 500),
        ])
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp))
        )
        _ = service.snapshot()

        let result = LayoutCommandService(service: service).toggleSplit()

        #expect(!result.changed)
        #expect(result.message.contains("requires mutableBsp"))
    }

    @Test
    func toggleSplitUsesFocusedDisplayInsteadOfFirstDisplay() {
        let leftDisplay = powerDisplay("left-display", index: 1, x: 0)
        let rightDisplay = powerDisplay("right-display", index: 2, x: 1100)
        let leftDisplayWindow = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let rightLeft = powerWindow(2, x: 1100, y: 0, width: 495, height: 500)
        let rightRight = powerWindow(3, x: 1605, y: 0, width: 495, height: 500)
        let provider = PowerUserProvider(
            displays: [leftDisplay, rightDisplay],
            windows: [leftDisplayWindow, rightLeft, rightRight]
        )
        provider.focusedID = rightRight.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("layout-toggle-focused-display"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: leftDisplay.id,
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .bsp,
                            focusedWindowID: leftDisplayWindow.id,
                            members: [
                                PersistentStageMember(windowID: leftDisplayWindow.id, bundleID: leftDisplayWindow.bundleID, title: leftDisplayWindow.title, frame: leftDisplayWindow.frame),
                            ]
                        ),
                    ]
                ),
                PersistentStageScope(
                    displayID: rightDisplay.id,
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .mutableBsp,
                            focusedWindowID: rightRight.id,
                            members: [rightLeft, rightRight].map {
                                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                            }
                        ),
                    ]
                ),
            ],
            activeDisplayID: rightDisplay.id
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsInner: 10)),
            stageStore: store
        )

        let result = LayoutCommandService(service: service).toggleSplit()

        #expect(result.changed)
        #expect(writer.frames[rightLeft.id] == Rect(x: 1100, y: 0, width: 1000, height: 245))
        #expect(writer.frames[rightRight.id] == Rect(x: 1100, y: 255, width: 1000, height: 245))
        #expect(writer.frames[leftDisplayWindow.id] == nil)
    }

    @Test
    func layoutInsertAndZoomParentApplyFrames() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer)
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let insert = commands.insert(.right)
        let zoom = commands.zoomParent()

        #expect(insert.message.contains("layout insert right"))
        #expect(zoom.message.contains("layout zoom-parent"))
        #expect(!writer.frames.isEmpty)
    }
}
