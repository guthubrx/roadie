import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec056AccessibilityBatchTests {
    @Test func allApplicationsAreReadWithBoundedConcurrency() async {
        let counter = Spec056AXCounter()
        let requests = Dictionary(uniqueKeysWithValues: (1...17).map {
            (Int32($0), Set([WindowID(rawValue: UInt32($0))]))
        })
        let states = await WindowSwitcherService.loadAccessibilityStates(byPID: requests) { pid, ids in
            counter.begin(pid)
            defer { counter.end() }
            Thread.sleep(forTimeInterval: 0.002)
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, WindowSwitcherAXState(isMinimized: pid == 17)) })
        }
        #expect(states.count == 17)
        #expect(states[WindowID(rawValue: 17)]?.isMinimized == true)
        #expect(counter.seen == Set(requests.keys))
        #expect(counter.maximum <= 4)
    }
}

private final class Spec056AXCounter: @unchecked Sendable {
    let lock = NSLock()
    var active = 0
    var maximum = 0
    var seen = Set<Int32>()
    func begin(_ pid: Int32) { lock.withLock { active += 1; maximum = max(maximum, active); seen.insert(pid) } }
    func end() { lock.withLock { active -= 1 } }
}
