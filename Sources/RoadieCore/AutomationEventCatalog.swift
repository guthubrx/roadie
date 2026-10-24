public struct AutomationEventCatalog: Equatable, Sendable {
    public var eventTypes: [String]

    public init(eventTypes: [String] = Self.minimumEventTypes + Self.layoutEventTypes + Self.obsoleteEventTypes) {
        self.eventTypes = eventTypes
    }

    public func contains(_ eventType: String) -> Bool {
        eventTypes.contains(eventType)
    }

    /// Vrai pour un type qui n'est plus émis mais reste lisible dans les anciens journaux.
    public func isObsolete(_ eventType: String) -> Bool {
        Self.obsoleteEventTypes.contains(eventType)
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
        "window.bookmark_set",
        "window.bookmark_focused",
        "window.switcher_focused",
        "window.switcher_focus_failed",
        "overview.state",
        "overview.input",
        "overview.hotkey",
        "overview.activation_failed",
        "switcher.session",
        "switcher.hotkey",
        "switcher.action",
        "switcher.activate",
        "window.bookmark_focus_failed",
        "window.bookmark_removed",
        "window.bookmark_pruned",
        "display.added",
        "display.removed",
        "display.focused",
        "display.parking_started",
        "display.parking_restored",
        "display.parking_ambiguous",
        "display.parking_noop",
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
        "rule.placement_applied",
        "rule.placement_skipped",
        "rule.placement_deferred",
        "rule.affinity_saved",
        "rule.affinity_removed",
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
        "state.snapshot",
        "state.load_failed",
        // Rupture du flux `events subscribe` : des événements ont pu être perdus (REL-018).
        "events.gap"
    ]

    /// Événements de placement de la SPEC-017 (contrat `layout-events.md`). Noms plats, comme `layout_apply`.
    public static let layoutEventTypes: [String] = [
        "layout_echo_ignored",
        "layout_app_response_accepted",
        "layout_external_change_reverted",
        "layout_paused_mission_control",
        "layout_resumed_mission_control",
        "layout_manual_gesture",
        "window_gesture_target",
        "layout_stable",
        "space_transition_guard",
        "space_did_change",
        "state_migrated"
    ]

    /// OBSOLÈTES depuis la SPEC-017 : ne sont plus émis (suppression de `mutableBsp`), conservés pour
    /// que `roadie events subscribe --type` et la lecture des anciens journaux continuent de fonctionner.
    public static let obsoleteEventTypes: [String] = [
        "mutable_bsp_geometry_adopted",
        "mutable_bsp_order_repaired",
        "mutable_bsp_resize_propagated"
    ]
}
