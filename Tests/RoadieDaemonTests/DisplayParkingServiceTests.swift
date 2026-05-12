import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct DisplayParkingServiceTests {
    private func display(
        _ id: String,
        x: Double = 0,
        isMain: Bool = false,
        index: Int = 0,
        name: String? = nil
    ) -> DisplaySnapshot {
        let frame = Rect(x: x, y: 0, width: 1920, height: 1080)
        return DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: index,
            name: name ?? id,
            frame: frame,
            visibleFrame: frame,
            isMain: isMain
        )
    }

    private func member(_ raw: UInt32, title: String = "w") -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: raw),
            bundleID: "com.test",
            title: title,
            frame: Rect(x: 0, y: 0, width: 100, height: 100)
        )
    }

    private func window(_ raw: UInt32, title: String = "w") -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: raw),
            pid: Int32(raw),
            appName: "Test",
            bundleID: "com.test",
            title: title,
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    @Test
    func serviceCanReturnStableNoopReport() {
        var state = PersistentStageState()
        let report = DisplayParkingService().transition(state: &state, liveDisplays: [], windows: [])

        #expect(report.kind == .noop)
        #expect(report.reason == .alreadyStable)
    }

    @Test
    func parksNonEmptyStagesAsDistinctStagesOnHostDisplay() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host", members: [member(1)]),
                ]),
                PersistentStageScope(displayID: goneID, activeStageID: StageID(rawValue: "3"), stages: [
                    PersistentStage(id: StageID(rawValue: "2"), name: "Docs", members: [member(20)]),
                    PersistentStage(id: StageID(rawValue: "3"), name: "Code", members: [member(30)]),
                    PersistentStage(id: StageID(rawValue: "4"), name: "Empty"),
                ]),
            ],
            activeDisplayID: hostID
        )

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true)],
            windows: [],
            now: Date(timeIntervalSince1970: 100)
        )

        let host = state.scopes.first { $0.displayID == hostID }
        let parked = host?.stages.filter { $0.parkingState == .parked } ?? []

        #expect(report.kind == .park)
        #expect(report.reason == .displayRemoved)
        #expect(report.originDisplayID == goneID)
        #expect(report.hostDisplayID == hostID)
        #expect(report.parkedStageCount == 2)
        #expect(parked.map(\.name) == ["Docs", "Code"])
        #expect(parked.map(\.members.count) == [1, 1])
        #expect(Set(parked.map(\.id)).count == 2)
        #expect(parked.allSatisfy { $0.hostDisplayID == hostID })
    }

    @Test
    func doesNotMergeDisconnectedDisplayIntoActiveStage() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host", members: [member(1)]),
                ]),
                PersistentStageScope(displayID: goneID, stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "External", members: [member(20), member(21)]),
                ]),
            ],
            activeDisplayID: hostID
        )

        _ = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        let host = state.scopes.first { $0.displayID == hostID }
        #expect(host?.stages.first { $0.id == StageID(rawValue: "1") }?.members.map(\.windowID) == [WindowID(rawValue: 1)])
        #expect(host?.stages.filter { $0.parkingState == .parked }.count == 1)
    }

    @Test
    func defersParkingWhenDisconnectedStageWindowsAreNotVisible() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "fullscreen-space")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host", members: [member(1)]),
                ]),
                PersistentStageScope(displayID: goneID, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "2"), name: "Preserve", members: [member(20)]),
                ]),
            ],
            activeDisplayID: hostID
        )

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true)],
            windows: [window(1)],
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(report.kind == .noop)
        #expect(report.reason == .deferredUntilStable)
        #expect(state.scopes.first { $0.displayID == goneID }?.memberIDs(in: StageID(rawValue: "2")) == [WindowID(rawValue: 20)])
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.filter { $0.parkingState == .parked }.isEmpty == true)
    }

    @Test
    func preservesNameModeFocusGroupsAndRelativeOrderWhenParking() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        let firstID = WindowID(rawValue: 20)
        let secondID = WindowID(rawValue: 21)
        let group = WindowGroup(id: "g", windowIDs: [firstID, secondID], activeWindowID: secondID)
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID),
                PersistentStageScope(displayID: goneID, activeStageID: StageID(rawValue: "code"), stages: [
                    PersistentStage(id: StageID(rawValue: "docs"), name: "Docs", mode: .float, members: [member(10)]),
                    PersistentStage(
                        id: StageID(rawValue: "code"),
                        name: "Code",
                        mode: .masterStack,
                        focusedWindowID: secondID,
                        previousFocusedWindowID: firstID,
                        members: [member(20), member(21)],
                        groups: [group]
                    ),
                ]),
            ],
            activeDisplayID: hostID
        )

        _ = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        let hostScope = state.scopes.first { $0.displayID == hostID }
        let parked: [PersistentStage] = hostScope?.stages.filter { $0.parkingState == .parked } ?? []

        #expect(parked.map { $0.name } == ["Docs", "Code"])
        #expect(parked.map { $0.mode } == [WindowManagementMode.float, WindowManagementMode.masterStack])
        #expect(parked[1].focusedWindowID == secondID)
        #expect(parked[1].previousFocusedWindowID == firstID)
        #expect(parked[1].groups == [group])
        #expect(parked[1].origin?.stageID == StageID(rawValue: "code"))
    }

    @Test
    func keepsEmptyDisconnectedStagesAsHiddenRestorableMetadata() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID),
                PersistentStageScope(displayID: goneID, stages: [
                    PersistentStage(id: StageID(rawValue: "empty"), name: "Later"),
                ]),
            ],
            activeDisplayID: hostID
        )

        let report = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        #expect(report.kind == .noop)
        #expect(report.reason == .noParkedStages)
        #expect(state.scopes.contains { $0.displayID == goneID })
        #expect(state.scopes.first { $0.displayID == goneID }?.stages.first?.name == "Later")
    }

    @Test
    func prunesEmptyParkedResiduesWithoutDroppingUserEmptyStages() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        let logicalID = LogicalDisplayID(displayID: goneID)
        let origin = StageOrigin(
            logicalDisplayID: logicalID,
            displayID: goneID,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "docs"),
            position: 1,
            nameAtParking: "Docs",
            parkedAt: Date(timeIntervalSince1970: 100)
        )
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host"),
                    PersistentStage(
                        id: StageID(rawValue: "parked-external-docs"),
                        name: "Docs",
                        parkingState: .parked,
                        origin: origin,
                        hostDisplayID: hostID
                    ),
                ]),
                PersistentStageScope(displayID: goneID, logicalDisplayID: logicalID, stages: [
                    PersistentStage(
                        id: StageID(rawValue: "docs"),
                        name: "Docs",
                        parkingState: .parked,
                        origin: origin,
                        hostDisplayID: hostID
                    ),
                    PersistentStage(id: StageID(rawValue: "later"), name: "Later"),
                ]),
            ],
            activeDisplayID: hostID
        )

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true)],
            windows: []
        )

        #expect(report.kind == .noop)
        #expect(report.reason == .noParkedStages)
        #expect(state.scopes.flatMap(\.stages).contains { $0.parkingState == .parked } == false)
        #expect(state.scopes.first { $0.displayID == goneID }?.stages.first { $0.id == StageID(rawValue: "later") }?.name == "Later")
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.map(\.name) == ["Host"])
    }

    @Test
    func preservesHostActiveStageAndNativeStageOrderWhenParking() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "b"), stages: [
                    PersistentStage(id: StageID(rawValue: "a"), name: "A"),
                    PersistentStage(id: StageID(rawValue: "b"), name: "B"),
                ]),
                PersistentStageScope(displayID: goneID, stages: [
                    PersistentStage(id: StageID(rawValue: "x"), name: "X", members: [member(10)]),
                ]),
            ],
            activeDisplayID: hostID
        )

        _ = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        let host = state.scopes.first { $0.displayID == hostID }
        #expect(host?.activeStageID == StageID(rawValue: "b"))
        #expect(host?.stages.map(\.name) == ["A", "B", "X"])
    }

    @Test
    func restoresParkedStagesToRecognizedDisplay() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external")
        var state = parkedState(hostID: hostID, originID: externalID)

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), display("external", x: 1920, index: 1)],
            windows: [],
            now: Date(timeIntervalSince1970: 200)
        )

        let restored = state.scopes.first { $0.displayID == externalID }?.stages.filter { $0.parkingState == .restored } ?? []
        let hostParked = state.scopes.first { $0.displayID == hostID }?.stages.filter { $0.parkingState == .parked } ?? []

        #expect(report.kind == .restore)
        #expect(report.reason == .displayRestored)
        #expect(report.restoredDisplayID == externalID)
        #expect(report.restoredStageCount == 1)
        #expect(restored.map { $0.name } == ["Docs"])
        #expect(restored.first?.origin?.displayID == externalID)
        #expect(restored.first?.restoredAt == Date(timeIntervalSince1970: 200))
        #expect(hostParked.isEmpty)
    }

    @Test
    func restoresCurrentParkedStateInsteadOfOriginalSnapshot() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external")
        var state = parkedState(hostID: hostID, originID: externalID)
        guard let hostIndex = state.scopes.firstIndex(where: { $0.displayID == hostID }),
              let parkedIndex = state.scopes[hostIndex].stages.firstIndex(where: { $0.parkingState == .parked })
        else {
            Issue.record("Missing parked fixture")
            return
        }
        state.scopes[hostIndex].stages[parkedIndex].name = "Renamed while parked"
        state.scopes[hostIndex].stages[parkedIndex].mode = .masterStack
        state.scopes[hostIndex].stages[parkedIndex].members.append(member(99, title: "new"))

        _ = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), display("external", x: 1920, index: 1)],
            windows: []
        )

        let restored = state.scopes.first { $0.displayID == externalID }?.stages.first { $0.parkingState == .restored }
        #expect(restored?.name == "Renamed while parked")
        #expect(restored?.mode == .masterStack)
        #expect(restored?.members.map(\.windowID).contains(WindowID(rawValue: 99)) == true)
    }

    @Test
    func refusesAutomaticRestoreWhenDisplayMatchIsAmbiguous() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external")
        var state = parkedState(hostID: hostID, originID: externalID, previousDisplayID: nil)
        let first = display("new-a", x: 1920, index: 1, name: "External")
        let second = display("new-b", x: 1920, index: 2, name: "External")

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), first, second],
            windows: []
        )

        #expect(report.kind == .ambiguous)
        #expect(report.reason == .ambiguousMatch)
        #expect(report.candidateDisplayIDs == [first.id, second.id])
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.contains { $0.parkingState == .parked } == true)
    }

    @Test
    func restoresDisplayWhenSystemDisplayIDChangedButFingerprintMatches() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external-old")
        let newExternalID = DisplayID(rawValue: "external-new")
        var state = parkedState(hostID: hostID, originID: externalID, previousDisplayID: nil)

        let report = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), display("external-new", x: 1920, index: 1, name: "External")],
            windows: []
        )

        #expect(report.kind == .restore)
        #expect(report.restoredDisplayID == newExternalID)
        #expect(state.scopes.first { $0.displayID == newExternalID }?.stages.contains { $0.parkingState == .restored } == true)
    }

    @Test
    func preservesRenameReorderMoveAndModeChangesMadeWhileParked() {
        let hostID = DisplayID(rawValue: "built-in")
        let externalID = DisplayID(rawValue: "external")
        var state = parkedState(hostID: hostID, originID: externalID)
        guard let hostIndex = state.scopes.firstIndex(where: { $0.displayID == hostID }),
              let parkedIndex = state.scopes[hostIndex].stages.firstIndex(where: { $0.parkingState == .parked })
        else {
            Issue.record("Missing parked fixture")
            return
        }
        let movedMember = member(44, title: "Moved")
        state.scopes[hostIndex].stages[parkedIndex].name = "Current"
        state.scopes[hostIndex].stages[parkedIndex].mode = .float
        state.scopes[hostIndex].stages[parkedIndex].members = [movedMember]
        let reordered = state.scopes[hostIndex].reorderStage(state.scopes[hostIndex].stages[parkedIndex].id, to: 1)
        #expect(reordered)

        _ = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), display("external", x: 1920, index: 1)],
            windows: []
        )

        let restoredScope = state.scopes.first { $0.displayID == externalID }
        let restored = restoredScope?.stages.first { $0.parkingState == .restored }
        #expect(restored?.name == "Current")
        #expect(restored?.mode == .float)
        #expect(restored?.members == [movedMember])
    }

    @Test
    func debouncesDisplayChangeNotificationsBeforeParking() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID),
                PersistentStageScope(displayID: goneID, stages: [
                    PersistentStage(id: StageID(rawValue: "docs"), name: "Docs", members: [member(10)]),
                ]),
            ],
            activeDisplayID: hostID
        )

        let first = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])
        let second = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        let parked = state.scopes.first { $0.displayID == hostID }?.stages.filter { $0.parkingState == .parked } ?? []
        #expect(first.kind == .park)
        #expect(second.kind == .noop)
        #expect(parked.count == 1)
    }

    @Test
    func keepsParkedStagesVisibleWhenWindowMoveFails() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID),
                PersistentStageScope(displayID: goneID, stages: [
                    PersistentStage(id: StageID(rawValue: "docs"), name: "Docs", members: [member(10)]),
                ]),
            ],
            activeDisplayID: hostID
        )

        _ = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])

        let parked = state.scopes.first { $0.displayID == hostID }?.stages.first { $0.parkingState == .parked }
        #expect(parked?.members.map(\.windowID) == [WindowID(rawValue: 10)])
        #expect(parked?.hostDisplayID == hostID)
    }

    @Test
    func parkingAndRestoreCompleteWithinConfiguredFiveSecondBudget() {
        let hostID = DisplayID(rawValue: "built-in")
        let goneID = DisplayID(rawValue: "external")
        var stages: [PersistentStage] = []
        for index in 1...50 {
            stages.append(PersistentStage(
                id: StageID(rawValue: "s\(index)"),
                name: "S\(index)",
                members: [member(UInt32(index))]
            ))
        }
        var state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID),
                PersistentStageScope(displayID: goneID, stages: stages),
            ],
            activeDisplayID: hostID
        )

        let start = Date()
        _ = DisplayParkingService().transition(state: &state, liveDisplays: [display("built-in", isMain: true)], windows: [])
        _ = DisplayParkingService().transition(
            state: &state,
            liveDisplays: [display("built-in", isMain: true), display("external", x: 1920, index: 1)],
            windows: []
        )

        #expect(Date().timeIntervalSince(start) < 5.0)
    }

    private func parkedState(
        hostID: DisplayID,
        originID: DisplayID,
        previousDisplayID: DisplayID? = DisplayID(rawValue: "external")
    ) -> PersistentStageState {
        let logicalID = LogicalDisplayID(displayID: originID)
        let origin = StageOrigin(
            logicalDisplayID: logicalID,
            displayID: originID,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "docs"),
            position: 1,
            nameAtParking: "Docs",
            parkedAt: Date(timeIntervalSince1970: 100)
        )
        let fingerprint = DisplayFingerprint(
            nameKey: "external",
            sizeKey: "1920x1080",
            visibleSizeKey: "1920x1080",
            positionKey: "1920:0",
            mainHint: false,
            previousDisplayID: previousDisplayID
        )
        return PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Host"),
                    PersistentStage(
                        id: StageID(rawValue: "parked-external-docs"),
                        name: "Docs",
                        mode: .bsp,
                        parkingState: .parked,
                        origin: origin,
                        hostDisplayID: hostID,
                        members: [member(20)]
                    ),
                ]),
                PersistentStageScope(
                    displayID: originID,
                    logicalDisplayID: logicalID,
                    lastKnownDisplayFingerprint: fingerprint,
                    stages: [
                        PersistentStage(id: StageID(rawValue: "docs"), name: "Docs", parkingState: .parked, origin: origin, hostDisplayID: hostID),
                    ]
                ),
            ],
            activeDisplayID: hostID
        )
    }
}
