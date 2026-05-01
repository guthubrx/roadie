import Foundation
import RoadieCore

enum OutputFormatter {
    static func print(response: Response) {
        if response.status == .error {
            let msg = response.errorMessage ?? "unknown error"
            let code = response.errorCode ?? "unknown"
            FileHandle.standardError.write("roadie: error [\(code)] \(msg)\n".data(using: .utf8) ?? Data())
            return
        }
        guard let payload = response.payload else { return }
        if let windows = payload["windows"]?.value as? [Any] {
            printWindowsList(windows)
            return
        }
        if let stages = payload["stages"]?.value as? [Any] {
            let current = payload["current"]?.value as? String ?? ""
            printStageList(stages, current: current)
            return
        }
        for (k, v) in payload.sorted(by: { $0.key < $1.key }) {
            Swift.print("\(k): \(v.value)")
        }
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        let trimmed = String(s.prefix(width))
        return trimmed + String(repeating: " ", count: max(0, width - trimmed.count))
    }

    private static func printWindowsList(_ items: [Any]) {
        Swift.print(pad("ID", 10) + pad("PID", 6) + pad("BUNDLE", 32) + pad("TITLE", 38) + pad("FRAME", 18) + "FLAGS")
        for item in items {
            guard let w = item as? [String: Any] else { continue }
            let id = String(w["id"] as? Int ?? 0)
            let pid = String(w["pid"] as? Int ?? 0)
            let bundle = (w["bundle"] as? String) ?? ""
            let title = (w["title"] as? String) ?? ""
            let frame = w["frame"] as? [Int] ?? [0, 0, 0, 0]
            let frameStr = "\(frame[0]),\(frame[1]) \(frame[2])x\(frame[3])"
            var flags: [String] = []
            if w["is_focused"] as? Bool ?? false { flags.append("focused") }
            flags.append((w["is_tiled"] as? Bool ?? false) ? "tiled" : "float")
            if let stage = w["stage"] as? String, !stage.isEmpty { flags.append("stage=\(stage)") }
            Swift.print(pad(id, 10) + pad(pid, 6) + pad(bundle, 32) + pad(title, 38) + pad(frameStr, 18) + flags.joined(separator: " "))
        }
    }

    private static func printStageList(_ items: [Any], current: String) {
        Swift.print("Current stage: \(current.isEmpty ? "(none)" : current)")
        for item in items {
            guard let s = item as? [String: Any] else { continue }
            let id = (s["id"] as? String) ?? ""
            let name = (s["display_name"] as? String) ?? ""
            let count = s["window_count"] as? Int ?? 0
            let prefix = id == current ? "* " : "  "
            Swift.print("\(prefix)\(id) (\(name)) — \(count) window(s)")
        }
    }
}
