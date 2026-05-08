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
}
