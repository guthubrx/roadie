public struct AutomationEventCatalog: Equatable, Sendable {
    public var eventTypes: [String]

    public init(eventTypes: [String] = Self.minimumEventTypes) {
        self.eventTypes = eventTypes
    }

    public static let minimumEventTypes: [String] = [
        "application.launched",
        "application.terminated",
        "application.activated",
        "application.hidden",
        "application.visible",
        "window.created",
        "window.destroyed",
        "window.focused",
        "window.moved",
        "window.resized",
        "window.minimized",
        "window.deminimized",
        "window.title_changed",
        "window.floating_changed",
        "window.grouped",
        "window.ungrouped",
        "display.added",
        "display.removed",
        "display.focused",
        "desktop.changed",
        "desktop.created",
        "desktop.renamed",
        "stage.changed",
        "stage.created",
        "stage.hidden",
        "stage.visible",
        "layout.mode_changed",
        "layout.rebalanced",
        "layout.flattened",
        "layout.insert_target_changed",
        "layout.zoom_changed",
        "rule.matched",
        "rule.applied",
        "rule.skipped",
        "rule.failed",
        "command.received",
        "command.applied",
        "command.failed",
        "config.reloaded",
        "state.snapshot"
    ]
}
