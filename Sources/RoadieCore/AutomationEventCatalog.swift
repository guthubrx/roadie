public struct AutomationEventCatalog: Equatable, Sendable {
    public var eventTypes: [String]

    public init(eventTypes: [String] = Self.minimumEventTypes) {
        self.eventTypes = eventTypes
    }

    public func contains(_ eventType: String) -> Bool {
        eventTypes.contains(eventType)
    }

    public func eventTypes(in scope: AutomationScope) -> [String] {
        eventTypes.filter { $0.hasPrefix("\(scope.rawValue).") }
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
        "window.pin_added",
        "window.pin_scope_changed",
        "window.pin_removed",
        "window.pin_pruned",
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
        "config.reload_failed",
        "restore.snapshot_written",
        "restore.exit_completed",
        "restore.crash_detected",
        "restore.crash_completed",
        "restore.apply_started",
        "restore.apply_completed",
        "restore.apply_failed",
        "performance.summary_requested",
        "performance.recent_requested",
        "performance.thresholds_requested",
        "layout.width_adjust_requested",
        "layout.width_adjust_applied",
        "layout.width_adjust_rejected",
        "cleanup.completed",
        "titlebar_context_menu.shown",
        "titlebar_context_menu.ignored",
        "titlebar_context_menu.action",
        "titlebar_context_menu.failed",
        "state.snapshot"
    ]
}
