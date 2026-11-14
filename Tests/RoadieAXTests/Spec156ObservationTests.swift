import Foundation
import os
import Testing
import RoadieCore
@testable import RoadieAX

struct Spec156ObservationTests {
    @Test func slowApplicationsOverlapWithinABoundedNumberOfWorkers() {
        let windows = (1...12).map { id in
            WindowSnapshot(id: WindowID(rawValue: UInt32(id)), pid: Int32(id), appName: "Fixture",
                bundleID: "fixture.\(id)", title: "Fixture", frame: Rect(x: 0, y: 0, width: 300, height: 200),
                isOnScreen: true, isTileCandidate: true)
        }
        let state = OSAllocatedUnfairLock(initialState: (active: 0, peak: 0))
        let start = Date()
        let result = LiveSystemSnapshotProvider.observeWindowGroups(windows) { group in
            state.withLock { $0.active += 1; $0.peak = max($0.active, $0.peak) }
            Thread.sleep(forTimeInterval: 0.02)
            defer { state.withLock { $0.active -= 1 } }
            return group.map { var window = $0; window.subrole = "observed"; return window }
        }
        let peak = state.withLock { $0.peak }
        print("SPEC156 AX batch: ms=\(Int(Date().timeIntervalSince(start) * 1000)) peak=\(peak)")
        #expect(peak > 1)
        #expect(peak <= 4)
        #expect(result.map(\.id) == windows.map(\.id))
        #expect(result.allSatisfy { $0.subrole == "observed" })
    }

    @Test func windowsFromOneApplicationStayInOneOrderedGroup() {
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "Fixture",
            bundleID: "fixture", title: "Fixture", frame: Rect(x: 0, y: 0, width: 300, height: 200),
            isOnScreen: true, isTileCandidate: true)
        var second = window; second.id = WindowID(rawValue: 2)
        let sizes = OSAllocatedUnfairLock(initialState: [Int]())
        let result = LiveSystemSnapshotProvider.observeWindowGroups([window, second]) { group in
            sizes.withLock { $0.append(group.count) }
            return group
        }
        #expect(sizes.withLock { $0 } == [2])
        #expect(result == [window, second])
        #expect(LiveSystemSnapshotProvider.observeWindowGroups([]) { $0 }.isEmpty)
    }
}
