import Foundation
import CoreGraphics
import RoadieCore

// MARK: - DesktopPersistence (SPEC-013 FR-014/FR-015)

/// Persistance per-display pour SPEC-013.
///
/// Arborescence :
/// ```
/// ~/.config/roadies/displays/<displayUUID>/
///   ├── current.toml         (current_desktop_id)
///   └── desktops/<id>/
///       └── state.toml       (windows assignées au desktop N de cet écran)
/// ```
///
/// Format `state.toml` minimal : compatible SPEC-011 (réutilisé). Stocke par
/// fenêtre : cgwid, bundle_id, title_prefix, expected_frame, display_uuid.
public enum DesktopPersistence {
    /// Snapshot d'une fenêtre persistée pour matching au rebranchement.
    public struct WindowSnapshot: Equatable, Sendable {
        public let cgwid: UInt32
        public let bundleID: String
        public let titlePrefix: String
        public let expectedFrame: CGRect

        public init(cgwid: UInt32, bundleID: String, titlePrefix: String, expectedFrame: CGRect) {
            self.cgwid = cgwid
            self.bundleID = bundleID
            self.titlePrefix = titlePrefix
            self.expectedFrame = expectedFrame
        }
    }

    /// Sauvegarde le current desktop d'un display.
    /// Les erreurs FS sont loggées (pas levées) : la persistance est best-effort
    /// pour ne pas bloquer le focus, mais reste diagnosable via les logs.
    public static func saveCurrent(configDir: URL, displayUUID: String, currentID: Int) {
        let dir = configDir.appendingPathComponent("displays/\(displayUUID)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logWarn("DesktopPersistence.saveCurrent mkdir failed",
                    ["uuid": displayUUID, "error": "\(error)"])
            return
        }
        let toml = """
        current_desktop_id = \(currentID)
        last_updated = "\(ISO8601DateFormatter().string(from: Date()))"
        """
        let target = dir.appendingPathComponent("current.toml")
        do {
            try toml.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            logWarn("DesktopPersistence.saveCurrent write failed",
                    ["uuid": displayUUID, "currentID": String(currentID), "error": "\(error)"])
        }
    }

    /// Lit le current desktop d'un display ; nil si absent ou corrompu.
    public static func loadCurrent(configDir: URL, displayUUID: String) -> Int? {
        let url = configDir
            .appendingPathComponent("displays/\(displayUUID)")
            .appendingPathComponent("current.toml")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("current_desktop_id") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                if let v = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return v
                }
            }
        }
        return nil
    }

    /// Sauvegarde la liste des fenêtres assignées à `desktopID` du display.
    /// Format minimaliste pour matching au rebranchement.
    public static func saveDesktopWindows(configDir: URL,
                                          displayUUID: String,
                                          desktopID: Int,
                                          windows: [WindowSnapshot]) {
        let dir = configDir
            .appendingPathComponent("displays/\(displayUUID)")
            .appendingPathComponent("desktops/\(desktopID)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logWarn("DesktopPersistence.saveDesktopWindows mkdir failed",
                    ["uuid": displayUUID,
                     "desktopID": String(desktopID),
                     "error": "\(error)"])
            return
        }
        var lines: [String] = []
        for w in windows {
            // Escape minimal : titre clamped à 80 chars, antislashes/double-quotes échappés.
            let safeTitle = w.titlePrefix
                .prefix(80)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("[[windows]]")
            lines.append("cgwid = \(w.cgwid)")
            lines.append("bundle_id = \"\(w.bundleID)\"")
            lines.append("title_prefix = \"\(safeTitle)\"")
            lines.append(String(format: "expected_frame = [%.1f, %.1f, %.1f, %.1f]",
                                w.expectedFrame.origin.x,
                                w.expectedFrame.origin.y,
                                w.expectedFrame.size.width,
                                w.expectedFrame.size.height))
            lines.append("display_uuid = \"\(displayUUID)\"")
            lines.append("")
        }
        let toml = lines.joined(separator: "\n")
        let target = dir.appendingPathComponent("state.toml")
        do {
            try toml.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            logWarn("DesktopPersistence.saveDesktopWindows write failed",
                    ["uuid": displayUUID,
                     "desktopID": String(desktopID),
                     "windowCount": String(windows.count),
                     "error": "\(error)"])
        }
    }

    /// Lit la liste des fenêtres persistées pour `desktopID` du display.
    /// Parser TOML minimaliste (format propre auto-écrit, pas un cas général).
    /// Logue un warn récapitulatif si certains blocs `[[windows]]` ont été
    /// rejetés (cgwid manquant ou expected_frame illisible) — le silence
    /// rendrait un debug de recovery quasi-impossible.
    public static func loadDesktopWindows(configDir: URL,
                                          displayUUID: String,
                                          desktopID: Int) -> [WindowSnapshot] {
        let url = configDir
            .appendingPathComponent("displays/\(displayUUID)")
            .appendingPathComponent("desktops/\(desktopID)")
            .appendingPathComponent("state.toml")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [WindowSnapshot] = []
        var currentCgwid: UInt32 = 0
        var currentBundle = ""
        var currentTitle = ""
        var currentFrame = CGRect.zero
        var inWindow = false
        var droppedBlocks = 0
        func flushBlock() {
            if inWindow {
                if currentCgwid != 0 {
                    result.append(WindowSnapshot(cgwid: currentCgwid,
                                                 bundleID: currentBundle,
                                                 titlePrefix: currentTitle,
                                                 expectedFrame: currentFrame))
                } else {
                    droppedBlocks += 1
                }
            }
        }
        for line in raw.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l == "[[windows]]" {
                flushBlock()
                inWindow = true
                currentCgwid = 0
                currentBundle = ""
                currentTitle = ""
                currentFrame = .zero
            } else if l.hasPrefix("cgwid") {
                if let v = parseIntField(l) { currentCgwid = UInt32(v) }
            } else if l.hasPrefix("bundle_id") {
                currentBundle = parseStringField(l) ?? ""
            } else if l.hasPrefix("title_prefix") {
                currentTitle = parseStringField(l) ?? ""
            } else if l.hasPrefix("expected_frame") {
                if let arr = parseFloatArrayField(l), arr.count == 4 {
                    currentFrame = CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
                }
            }
        }
        flushBlock()
        if droppedBlocks > 0 {
            logWarn("DesktopPersistence.loadDesktopWindows skipped malformed blocks",
                    ["uuid": displayUUID,
                     "desktopID": String(desktopID),
                     "dropped": String(droppedBlocks),
                     "kept": String(result.count)])
        }
        return result
    }

    private static func parseIntField(_ line: String) -> Int? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Int(parts[1].trimmingCharacters(in: .whitespaces))
    }

    private static func parseStringField(_ line: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let val = parts[1].trimmingCharacters(in: .whitespaces)
        guard val.hasPrefix("\"") && val.hasSuffix("\"") else { return nil }
        let inner = String(val.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func parseFloatArrayField(_ line: String) -> [Double]? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let val = parts[1].trimmingCharacters(in: .whitespaces)
        guard val.hasPrefix("[") && val.hasSuffix("]") else { return nil }
        let inner = String(val.dropFirst().dropLast())
        return inner.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
    }
}
