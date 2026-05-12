import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct PersistentStageStateTests {
    private func member(_ raw: UInt32, title: String = "w") -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: raw),
            bundleID: "com.test",
            title: title,
            frame: Rect(x: 0, y: 0, width: 100, height: 100)
        )
    }

    private func window(_ raw: UInt32, title: String = "w", x: Double = 0) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: raw),
            pid: Int32(raw),
            appName: "Test",
            bundleID: "com.test",
            title: title,
            frame: Rect(x: x, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    private func stateWith(scopes: [PersistentStageScope]) -> PersistentStageState {
        PersistentStageState(scopes: scopes)
    }

    @Test
    func stageScopeReturnsNilWhenWindowAbsent() {
        let state = stateWith(scopes: [])
        #expect(state.stageScope(for: WindowID(rawValue: 1)) == nil)
    }

    @Test
    func stageScopeFindsWindowAcrossScopes() {
        let stage1 = PersistentStage(id: StageID(rawValue: "1"), members: [member(10), member(20)])
        let stage2 = PersistentStage(id: StageID(rawValue: "2"), members: [member(30)])
        let scopeA = PersistentStageScope(displayID: DisplayID(rawValue: "A"), stages: [stage1])
        let scopeB = PersistentStageScope(displayID: DisplayID(rawValue: "B"), stages: [stage2])
        let state = stateWith(scopes: [scopeA, scopeB])

        let r1 = state.stageScope(for: WindowID(rawValue: 20))
        #expect(r1?.displayID == DisplayID(rawValue: "A"))
        #expect(r1?.stageID == StageID(rawValue: "1"))

        let r2 = state.stageScope(for: WindowID(rawValue: 30))
        #expect(r2?.displayID == DisplayID(rawValue: "B"))
        #expect(r2?.stageID == StageID(rawValue: "2"))
    }

    @Test
    func stageScopeIndexReturnsAllMappings() {
        let stage1 = PersistentStage(id: StageID(rawValue: "1"), members: [member(10), member(20)])
        let stage2 = PersistentStage(id: StageID(rawValue: "2"), members: [member(30)])
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "A"), stages: [stage1, stage2])
        let state = stateWith(scopes: [scope])

        let index = state.stageScopeIndex()
        #expect(index.count == 3)
        #expect(index[WindowID(rawValue: 10)]?.stageID == StageID(rawValue: "1"))
        #expect(index[WindowID(rawValue: 20)]?.stageID == StageID(rawValue: "1"))
        #expect(index[WindowID(rawValue: 30)]?.stageID == StageID(rawValue: "2"))
    }

    @Test
    func stageScopeIndexAndStageScopeAreEquivalent() {
        let stage = PersistentStage(id: StageID(rawValue: "1"), members: [member(1), member(2), member(3)])
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "main"), stages: [stage])
        let state = stateWith(scopes: [scope])
        let index = state.stageScopeIndex()
        for raw: UInt32 in [1, 2, 3, 99] {
            let id = WindowID(rawValue: raw)
            #expect(index[id] == state.stageScope(for: id))
        }
    }

    @Test
    func emptyStageScopeIndexForEmptyState() {
        let state = PersistentStageState()
        #expect(state.stageScopeIndex().isEmpty)
    }

    @Test
    func reconcileWindowIDsKeepsStageMembershipAcrossRuntimeIDChange() {
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "main"), activeStageID: StageID(rawValue: "1"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                member(10, title: "Terminal"),
            ]),
            PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: WindowID(rawValue: 20), previousFocusedWindowID: WindowID(rawValue: 10), members: [
                member(20, title: "Browser"),
            ], groups: [
                WindowGroup(id: "g", windowIDs: [WindowID(rawValue: 20), WindowID(rawValue: 10)], activeWindowID: WindowID(rawValue: 20)),
            ]),
        ])
        var state = stateWith(scopes: [scope])

        state.reconcileWindowIDs(with: [
            window(110, title: "Terminal"),
            window(220, title: "Browser"),
        ])

        let index = state.stageScopeIndex()
        #expect(index[WindowID(rawValue: 110)]?.stageID == StageID(rawValue: "1"))
        #expect(index[WindowID(rawValue: 220)]?.stageID == StageID(rawValue: "2"))
        #expect(index[WindowID(rawValue: 10)] == nil)
        #expect(index[WindowID(rawValue: 20)] == nil)
        let stage2 = state.scopes[0].stages.first { $0.id == StageID(rawValue: "2") }
        #expect(stage2?.focusedWindowID == WindowID(rawValue: 220))
        #expect(stage2?.previousFocusedWindowID == WindowID(rawValue: 110))
        #expect(stage2?.groups.first?.windowIDs == [WindowID(rawValue: 220), WindowID(rawValue: 110)])
        #expect(stage2?.groups.first?.activeWindowID == WindowID(rawValue: 220))
    }

    @Test
    func reconcileWindowIDsAvoidsAmbiguousDuplicateTitles() {
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "main"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                member(10, title: "Default"),
            ]),
        ])
        var state = stateWith(scopes: [scope])

        state.reconcileWindowIDs(with: [
            window(110, title: "Default", x: 1_000),
            window(120, title: "Default", x: 2_000),
        ])

        let index = state.stageScopeIndex()
        #expect(index[WindowID(rawValue: 10)]?.stageID == StageID(rawValue: "1"))
        #expect(index[WindowID(rawValue: 110)] == nil)
        #expect(index[WindowID(rawValue: 120)] == nil)
    }

    @Test
    func missingWindowPinsDecodeAsEmptyList() throws {
        let data = #"{"scopes":[]}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PersistentStageState.self, from: data)

        #expect(decoded.windowPins.isEmpty)
    }

    @Test
    func missingPinPresentationsDecodeAsEmptyList() throws {
        let data = #"{"scopes":[],"windowPins":[]}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PersistentStageState.self, from: data)

        #expect(decoded.pinPresentations.isEmpty)
    }

    @Test
    func setPinKeepsSinglePinPerWindowAndCanChangeScope() {
        let home = StageScope(
            displayID: DisplayID(rawValue: "main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        var state = PersistentStageState()

        let first = state.setPin(window: window(10, title: "Doc"), homeScope: home, pinScope: .desktop)
        let second = state.setPin(window: window(10, title: "Doc"), homeScope: home, pinScope: .allDesktops)

        #expect(first.created)
        #expect(second.created == false)
        #expect(second.scopeChanged)
        #expect(state.windowPins.count == 1)
        #expect(state.pin(for: WindowID(rawValue: 10))?.pinScope == .allDesktops)
    }

    @Test
    func removeAndPrunePinsCleanPersistentState() {
        let home = StageScope(
            displayID: DisplayID(rawValue: "main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        var state = PersistentStageState()
        state.setPin(window: window(10), homeScope: home, pinScope: .desktop)
        state.setPin(window: window(20), homeScope: home, pinScope: .allDesktops)

        let removed = state.removePin(windowID: WindowID(rawValue: 10))
        let pruned = state.pruneMissingPins(keeping: [WindowID(rawValue: 99)])

        #expect(removed?.windowID == WindowID(rawValue: 10))
        #expect(pruned.map(\.windowID) == [WindowID(rawValue: 20)])
        #expect(state.windowPins.isEmpty)
    }

    @Test
    func pinPresentationIsUniqueAndRemovedWithPin() {
        let home = StageScope(
            displayID: DisplayID(rawValue: "main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        var state = PersistentStageState()
        state.setPin(window: window(10), homeScope: home, pinScope: .desktop)

        state.setPinPresentation(
            windowID: WindowID(rawValue: 10),
            presentation: .collapsed,
            restoreFrame: Rect(x: 1, y: 2, width: 300, height: 200),
            proxyFrame: Rect(x: 1, y: 2, width: 160, height: 28)
        )
        state.setPinPresentation(
            windowID: WindowID(rawValue: 10),
            presentation: .visible,
            restoreFrame: nil,
            proxyFrame: nil
        )

        #expect(state.pinPresentations.count == 1)
        #expect(state.pinPresentation(for: WindowID(rawValue: 10))?.presentation == .visible)

        _ = state.removePin(windowID: WindowID(rawValue: 10))

        #expect(state.pinPresentations.isEmpty)
    }

    @Test
    func pinningDoesNotDuplicateStageMembership() {
        let home = StageScope(
            displayID: DisplayID(rawValue: "main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let scope = PersistentStageScope(displayID: home.displayID, stages: [
            PersistentStage(id: home.stageID, members: [member(10)]),
            PersistentStage(id: StageID(rawValue: "2"), members: [])
        ])
        var state = PersistentStageState(scopes: [scope])

        state.setPin(window: window(10), homeScope: home, pinScope: .desktop)

        let memberships = state.scopes.flatMap(\.stages).flatMap(\.members).filter { $0.windowID == WindowID(rawValue: 10) }
        #expect(memberships.count == 1)
        #expect(state.windowPins.count == 1)
    }
}
