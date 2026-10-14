import ApplicationServices
import Foundation
import Testing
@testable import RoadieAX

/// REL-010 : le focus ne doit annoncer un succès que si AXRaise a réellement réussi.
@Suite
struct Audit022LotJAXTests {
    @Test
    func onlySuccessIsReportedAsSucceeded() {
        let registry = AXUnresponsiveApps(now: { Date() })
        #expect(registry.noteSucceeded(.success, pid: 1))
        for error in [AXError.failure, .invalidUIElement, .actionUnsupported, .attributeUnsupported, .noValue, .cannotComplete] {
            #expect(!registry.noteSucceeded(error, pid: 1), "\(error) ne doit pas compter comme un succès")
        }
    }

    @Test
    func onlyTimeoutSetsApplicationAside() {
        let registry = AXUnresponsiveApps(now: { Date() })
        for error in [AXError.failure, .invalidUIElement, .actionUnsupported] {
            _ = registry.noteSucceeded(error, pid: 5)
        }
        #expect(!registry.isQuarantined(5))
        _ = registry.noteSucceeded(.cannotComplete, pid: 5)
        #expect(registry.isQuarantined(5))
    }
}
