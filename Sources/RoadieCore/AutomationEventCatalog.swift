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
        "config.reload_requested",
        "config.reload_applied",
        "config.reload_failed",
        "config.active_preserved",
        "control_center.opened",
        "control_center.action_invoked",
        "control_center.settings_saved",
        "control_center.settings_failed",
        "restore.snapshot_written",
        "restore.exit_started",
        "restore.exit_completed",
        "restore.crash_detected",
        "restore.crash_completed",
        "restore.failed",
        "transient.detected",
        "transient.cleared",
        "transient.recovery_attempted",
        "transient.recovery_failed",
        "layout_identity.snapshot_written",
        "layout_identity.restore_started",
        "layout_identity.restore_applied",
        "layout_identity.restore_skipped",
        "layout_identity.conflict_detected",
        "layout.width_adjust_requested",
        "layout.width_adjust_applied",
        "layout.width_adjust_rejected",
        "performance.interaction_completed",
        "performance.threshold_breached",
        "state.snapshot"
    ]
}
