import Testing
import RoadieCore

@Suite
struct EventCatalogTests {
    @Test
    func spec002CatalogContainsMinimumAutomationEvents() {
        let catalog = AutomationEventCatalog()
        let required = [
            "window.created",
            "window.destroyed",
            "window.focused",
            "display.focused",
            "desktop.changed",
            "stage.changed",
            "layout.flattened",
            "rule.applied",
            "command.received",
            "command.applied",
            "command.failed",
            "restore.snapshot_written",
            "restore.exit_completed",
            "restore.crash_detected",
            "restore.crash_completed",
            "restore.apply_completed",
            "performance.summary_requested",
            "layout.width_adjust_applied",
            "state.snapshot"
        ]

        for eventType in required {
            #expect(catalog.eventTypes.contains(eventType))
        }
    }

    @Test
    func spec002CatalogEventTypesAreStableAndUnique() {
        let eventTypes = AutomationEventCatalog.minimumEventTypes

        #expect(Set(eventTypes).count == eventTypes.count)
        #expect(eventTypes.allSatisfy { !$0.isEmpty && $0.contains(".") })
        #expect(eventTypes.count >= 25)
    }

    @Test
    func spec002CatalogCanFilterByScope() {
        let catalog = AutomationEventCatalog()

        #expect(catalog.contains("window.focused"))
        #expect(catalog.eventTypes(in: .window).contains("window.created"))
        #expect(!catalog.eventTypes(in: .window).contains("desktop.changed"))
    }
}
