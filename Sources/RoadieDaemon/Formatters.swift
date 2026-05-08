import Foundation
import RoadieAX
import RoadieCore

public enum TextFormatter {
    public static func windows(_ windows: [ScopedWindowSnapshot]) -> String {
        let scopedWindows = windows.filter { $0.scope != nil }
        guard !scopedWindows.isEmpty else { return "No tileable windows found." }
        var lines = ["WID\tPID\tAPP\tTITLE\tSCOPE\tFRAME"]
        for entry in scopedWindows {
            let window = entry.window
            let scope = entry.scope?.description ?? "-"
            let frame = "\(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.width))x\(Int(window.frame.height))"
            lines.append("\(window.id.rawValue)\t\(window.pid)\t\(window.appName)\t\(window.title)\t\(scope)\t\(frame)")
        }
        return lines.joined(separator: "\n")
    }

    public static func displays(_ displays: [DisplaySnapshot], state: PersistentStageState? = nil) -> String {
        guard !displays.isEmpty else { return "No displays found." }
        var lines = ["ACTIVE\tINDEX\tMAIN\tNAME\tUUID\tFRAME"]
        for display in displays {
            let main = display.isMain ? "*" : ""
            let active = display.id == state?.activeDisplayID ? "*" : ""
            let frame = "\(Int(display.frame.x)),\(Int(display.frame.y)) \(Int(display.frame.width))x\(Int(display.frame.height))"
            lines.append("\(active)\t\(display.index)\t\(main)\t\(display.name)\t\(display.id.rawValue)\t\(frame)")
        }
        return lines.joined(separator: "\n")
    }

    public static func currentDisplay(_ snapshot: DaemonSnapshot, state: PersistentStageState? = nil) -> String {
        let activeDisplay = state?.activeDisplayID.flatMap { id in
            snapshot.displays.first { $0.id == id }
        }
        guard let display = activeDisplay ?? displayContainingFocusedWindow(in: snapshot) ?? snapshot.displays.first else {
            return "No displays found."
        }
        let frame = "\(Int(display.frame.x)),\(Int(display.frame.y)) \(Int(display.frame.width))x\(Int(display.frame.height))"
        return [
            "INDEX\tMAIN\tNAME\tUUID\tFRAME",
            "\(display.index)\t\(display.isMain ? "*" : "")\t\(display.name)\t\(display.id.rawValue)\t\(frame)"
        ].joined(separator: "\n")
    }

    public static func permissions(_ permissions: PermissionSnapshot) -> String {
        "accessibilityTrusted=\(permissions.accessibilityTrusted)"
    }

    public static func focusStatus(_ snapshot: DaemonSnapshot) -> String {
        guard let focusedWindowID = snapshot.focusedWindowID else {
            return "No focused tileable window."
        }
        guard let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }) else {
            return "Focused window \(focusedWindowID.rawValue) is not tileable."
        }
        let window = entry.window
        let scope = entry.scope?.description ?? "-"
        let frame = "\(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.width))x\(Int(window.frame.height))"
        return [
            "WID\tAPP\tTITLE\tSCOPE\tFRAME",
            "\(window.id.rawValue)\t\(window.appName)\t\(window.title)\t\(scope)\t\(frame)"
        ].joined(separator: "\n")
    }

    public static func doctor(snapshot: DaemonSnapshot, plan: ApplyPlan, persistentState: PersistentStageState? = nil) -> String {
        let tileable = snapshot.windows.filter { $0.window.isTileCandidate && $0.scope != nil }
        let focused = snapshot.focusedWindowID.map(String.init(describing:)) ?? "-"
        let activeDisplayID = persistentState?.activeDisplayID ?? displayContainingFocusedWindow(in: snapshot)?.id
        let activeDisplay = activeDisplayID.flatMap { id in snapshot.displays.first { $0.id == id } }
        let activeDesktop = activeDisplayID.flatMap { persistentState?.currentDesktopID(for: $0).rawValue }
        let activeStage = activeDisplayID.flatMap { displayID -> String? in
            let desktopID = persistentState?.currentDesktopID(for: displayID) ?? DesktopID(rawValue: 1)
            return persistentState?
                .scopes
                .first { $0.displayID == displayID && $0.desktopID == desktopID }?
                .activeStageID
                .rawValue
        }
        let status = snapshot.permissions.accessibilityTrusted && !snapshot.displays.isEmpty ? "ok" : "needs-attention"
        return [
            "status=\(status)",
            "accessibilityTrusted=\(snapshot.permissions.accessibilityTrusted)",
            "displays=\(snapshot.displays.count)",
            "activeDisplay=\(activeDisplay?.index.description ?? "-") \(activeDisplay?.name ?? "-")",
            "activeDesktop=\(activeDesktop.map(String.init) ?? "-")",
            "activeStage=\(activeStage ?? "-")",
            "tileableWindows=\(tileable.count)",
            "focusedWindow=\(focused)",
            "pendingLayoutCommands=\(plan.commands.count)"
        ].joined(separator: "\n")
    }

    public static func selfTest(_ report: SelfTestReport) -> String {
        let status = report.failed ? "fail" : "ok"
        var lines = ["status=\(status)"]
        for check in report.checks {
            lines.append("\(check.level.rawValue)\t\(check.name)\t\(check.message)")
        }
        return lines.joined(separator: "\n")
    }

    public static func stateAudit(_ report: StateAuditReport) -> String {
        let status = report.failed ? "fail" : "ok"
        var lines = ["status=\(status)"]
        for check in report.checks {
            lines.append("\(check.level.rawValue)\t\(check.name)\t\(check.message)")
        }
        return lines.joined(separator: "\n")
    }

    public static func stateHeal(_ report: StateHealReport) -> String {
        var lines = ["repaired=\(report.repaired)"]
        lines.append(contentsOf: stateAudit(report.audit).split(separator: "\n").map(String.init))
        return lines.joined(separator: "\n")
    }

    public static func configValidation(_ report: ConfigValidationReport) -> String {
        let status = report.hasErrors ? "error" : "ok"
        var lines = ["status=\(status)"]
        for item in report.items {
            lines.append("\(item.level.rawValue)\t\(item.path)\t\(item.message)")
        }
        return lines.joined(separator: "\n")
    }

    public static func applyPlan(_ plan: ApplyPlan) -> String {
        guard !plan.commands.isEmpty else { return "No layout commands." }
        var lines = ["WID\tAPP\tTITLE\tFRAME"]
        for command in plan.commands {
            let frame = command.frame
            lines.append("\(command.window.id.rawValue)\t\(command.window.appName)\t\(command.window.title)\t\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))")
        }
        return lines.joined(separator: "\n")
    }

    public static func applyResult(_ result: ApplyResult) -> String {
        var lines = ["attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)"]
        for item in result.items where item.status != .applied {
            let actual = item.actual.map { "\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
            let requested = "\(Int(item.requested.x)),\(Int(item.requested.y)) \(Int(item.requested.width))x\(Int(item.requested.height))"
            lines.append("wid=\(item.windowID.rawValue) status=\(item.status.rawValue) requested=\(requested) actual=\(actual)")
        }
        return lines.joined(separator: "\n")
    }

    private static func displayContainingFocusedWindow(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        guard let focusedWindowID = snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID })
        else { return nil }
        if let displayID = entry.scope?.displayID {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first { $0.frame.cgRect.contains(entry.window.frame.center) }
    }
}
