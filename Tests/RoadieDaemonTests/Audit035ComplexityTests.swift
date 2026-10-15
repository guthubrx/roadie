import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

struct Audit035ComplexityTests {
    @Test
    func measurePerWindowFrameUpdates() {
        guard ProcessInfo.processInfo.environment["ROADIE_AUDIT_BENCHMARK"] == "1" else { return }
        for count in [200, 800, 1_600] {
            let windows = (1...count).map { raw in
                WindowSnapshot(id: WindowID(rawValue: UInt32(raw)), pid: 1, appName: "Synthetic", bundleID: "test",
                               title: "", frame: Rect(x: Double(raw), y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true)
            }
            let members = windows.map { PersistentStageMember(windowID: $0.id, bundleID: "test", title: "", frame: .init(x: 0, y: 0, width: 100, height: 100)) }
            let original = PersistentStageScope(displayID: DisplayID(rawValue: "synthetic"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: members)
            ])
            var measurements: [Double] = []
            for _ in 0..<4 {
                var scope = original
                let start = ContinuousClock.now
                for window in windows { scope.updateFrame(window: window) }
                let elapsed = start.duration(to: .now).components
                measurements.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                #expect(scope.stages[0].members.last?.frame.x == Double(count))
            }
            print("AUDIT035_UPDATE_FRAME windows=\(count) milliseconds=\(Array(measurements.dropFirst()))")
        }
    }
}
