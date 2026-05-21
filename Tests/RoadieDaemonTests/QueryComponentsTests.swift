import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct QueryComponentsTests {
    @Test
    func queryComponentsReturnsArrayPayload() {
        let service = AutomationQueryService()
        let result = service.query("components")
        #expect(result.kind == "components")
        if case .array = result.data {
            // ok
        } else {
            Issue.record("expected .array payload, got \(result.data)")
        }
    }

    @Test
    func queryComponentsIncludesAcquiredLock() throws {
        let component = "spec011-query-\(UUID().uuidString.prefix(8))"
        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        defer { lock.release() }

        let result = AutomationQueryService().query("components")
        guard case .array(let entries) = result.data else {
            Issue.record("expected .array payload")
            return
        }
        let match = entries.first { entry in
            if case .object(let dict) = entry, case .string(let name) = dict["component"], name == component {
                return true
            }
            return false
        }
        #expect(match != nil)
        guard case .object(let dict) = match,
              case .int(let pid) = dict["pid"]
        else {
            Issue.record("expected entry with integer pid")
            return
        }
        #expect(pid == Int(ProcessInfo.processInfo.processIdentifier))
    }
}
