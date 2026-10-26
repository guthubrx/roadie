import Foundation
@testable import RoadieAX
import Testing

/// SPEC-086 : une passe lente nomme l'application qui a fait attendre ses appels AX.
struct Spec086AXCallTimingsTests {
    @Test
    func slowestApplicationIsReportedFirstThenForgotten() {
        let timings = AXCallTimings()
        let fast: pid_t = 999_991
        let slow: pid_t = 999_992
        timings.measure(fast) { Thread.sleep(forTimeInterval: 0.01) }
        timings.measure(slow) { Thread.sleep(forTimeInterval: 0.05) }
        timings.measure(slow) { Thread.sleep(forTimeInterval: 0.05) }

        let report = timings.drainSlowest(minimumSeconds: 0.05, limit: 3)

        #expect(report.hasPrefix("pid 999992 0."))
        #expect(report.hasSuffix("s/2"))
        #expect(!report.contains("999991"))
        #expect(timings.drainSlowest(minimumSeconds: 0, limit: 3).isEmpty)
    }
}
