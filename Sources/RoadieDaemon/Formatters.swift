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

    public static func displays(_ displays: [DisplaySnapshot]) -> String {
        guard !displays.isEmpty else { return "No displays found." }
        var lines = ["INDEX\tMAIN\tNAME\tUUID\tFRAME"]
        for display in displays {
            let main = display.isMain ? "*" : ""
            let frame = "\(Int(display.frame.x)),\(Int(display.frame.y)) \(Int(display.frame.width))x\(Int(display.frame.height))"
            lines.append("\(display.index)\t\(main)\t\(display.name)\t\(display.id.rawValue)\t\(frame)")
        }
        return lines.joined(separator: "\n")
    }

    public static func permissions(_ permissions: PermissionSnapshot) -> String {
        "accessibilityTrusted=\(permissions.accessibilityTrusted)"
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
}
