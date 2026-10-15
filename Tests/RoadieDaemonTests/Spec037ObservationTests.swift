import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieDaemon

@Suite struct Spec037ObservationTests {
    @Test func batchPreservesGroupsFocusHiddenMembersPinsAndBookmarks() {
        let screen = DisplayID(rawValue: "observations037")
        let scope = StageScope(displayID: screen, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "work"))
        let old = powerWindow(1, x: 100)
        let hidden = powerWindow(2, x: 200)
        let now = Date(timeIntervalSince1970: 10_000)
        var stage = PersistentStage(id: scope.stageID, name: "Work", mode: .spatialBsp,
            focusedWindowID: hidden.id, members: [old,hidden].map {
                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame,
                    presentationState: .maximized, missingSince: now.addingTimeInterval(-1), pid: $0.pid)
            })
        stage.groups = [WindowGroup(id: "group", windowIDs: [old.id,hidden.id], activeWindowID: hidden.id)]
        var state = PersistentStageState(scopes: [.init(displayID: screen, activeStageID: stage.id, stages: [stage])], activeDisplayID: screen)
        state.setPin(window: old, homeScope: scope, pinScope: .desktop, now: now.addingTimeInterval(-2))
        state.setBookmark(name: "saved", window: old, scope: scope, now: now.addingTimeInterval(-2))
        var fresh = old;fresh.frame.x = 350;fresh.title = "Changed"
        state.updateWindowObservations([old.id:fresh], scopes: [old.id:scope], now: now)
        let result = state.scopes[0].stages[0]
        #expect(result.members.map(\.windowID) == stage.members.map(\.windowID))
        #expect(result.members[1] == stage.members[1])
        #expect(result.members[0].frame == fresh.frame)
        #expect(result.members[0].missingSince == nil)
        #expect(result.members[0].lastSeenAt == now)
        #expect(result.members[0].presentationState == .maximized)
        #expect(result.focusedWindowID == stage.focusedWindowID && result.groups == stage.groups)
        #expect(state.windowPins[0].lastFrame == fresh.frame)
        #expect(state.windowBookmarks[0].frame == fresh.frame)
        let once = state
        state.updateWindowObservations([old.id:fresh], scopes: [old.id:scope], now: now.addingTimeInterval(10))
        #expect(state == once)
    }

    @Test func measureLegacyLoopAndBatchedObservations() {
        guard ProcessInfo.processInfo.environment["ROADIE_AUDIT_BENCHMARK"] == "1" else { return }
        let screen = DisplayID(rawValue: "benchmark037")
        let scope = StageScope(displayID: screen, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        for count in [20,200,800,1600] {
            let windows = (1...count).map { powerWindow(UInt32($0), x: Double($0)) }
            let original = PersistentStageState(scopes: [.init(displayID: screen, stages: [.init(id: scope.stageID,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: .init(x:0,y:0,width:1,height:1)) })])])
            var oldTimes:[Double]=[];var newTimes:[Double]=[]
            for round in 0..<4 {
                var legacy = original;var batch = original
                let oldStart = ContinuousClock.now
                for window in windows {
                    var stored = legacy.scope(displayID: screen)
                    stored.updateFrame(window: window)
                    legacy.update(stored)
                }
                let oldElapsed = oldStart.duration(to: .now).components
                let newStart = ContinuousClock.now
                batch.updateWindowObservations(Dictionary(windows.map { ($0.id,$0) }, uniquingKeysWith: { first,_ in first }),
                    scopes: Dictionary(windows.map { ($0.id,scope) }, uniquingKeysWith: { first,_ in first }))
                let newElapsed = newStart.duration(to: .now).components
                #expect(batch == legacy)
                if round > 0 {
                    oldTimes.append(Double(oldElapsed.seconds)*1000+Double(oldElapsed.attoseconds)/1e15)
                    newTimes.append(Double(newElapsed.seconds)*1000+Double(newElapsed.attoseconds)/1e15)
                }
            }
            print("SPEC037_OBSERVATIONS count=\(count) legacyMs=\(oldTimes) batchMs=\(newTimes)")
        }
    }
}
