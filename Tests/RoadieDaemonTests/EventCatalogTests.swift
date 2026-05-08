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

    @Test
    func spec003CatalogContainsControlSafetyEvents() {
        let catalog = AutomationEventCatalog()
        let required = [
            "config.reload_requested",
            "config.reload_applied",
            "config.reload_failed",
            "config.active_preserved",
            "control_center.opened",
            "control_center.action_invoked",
            "restore.snapshot_written",
            "restore.crash_detected",
            "transient.detected",
            "layout_identity.restore_applied",
            "layout.width_adjust_requested",
            "layout.width_adjust_rejected"
        ]

        for eventType in required {
            #expect(catalog.contains(eventType))
        }
    }
}
