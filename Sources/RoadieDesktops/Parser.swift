import Foundation
import TOMLKit

/// Erreurs de parsing des fichiers state.toml.
public enum DesktopParseError: Error, Equatable {
    case invalidTOML(String)
    case missingField(String)
    case invalidValue(field: String, value: String)
}

// MARK: - Sérialisation → TOML texte

/// Sérialise un `RoadieDesktop` en texte TOML conforme au format data-model.md (R-004).
/// Format texte brut sans dépendance externe pour l'écriture.
public func serialize(_ desktop: RoadieDesktop) -> String {
    var lines: [String] = []
    lines.append("id = \(desktop.id)")
    if let label = desktop.label {
        lines.append("label = \"\(label)\"")
    } else {
        lines.append("label = \"\"")
    }
    lines.append("layout = \"\(desktop.layout.rawValue)\"")
    lines.append("gaps_outer = \(desktop.gapsOuter)")
    lines.append("gaps_inner = \(desktop.gapsInner)")
    lines.append("active_stage_id = \(desktop.activeStageID)")
    lines.append("")
    for stage in desktop.stages {
        lines.append("[[stages]]")
        lines.append("id = \(stage.id)")
        lines.append("label = \"\(stage.label ?? "")\"")
        let wins = stage.windows.map(String.init).joined(separator: ", ")
        lines.append("windows = [\(wins)]")
        lines.append("")
    }
    for win in desktop.windows {
        lines.append("[[windows]]")
        lines.append("cgwid = \(win.cgwid)")
        lines.append("bundle_id = \"\(win.bundleID)\"")
        lines.append("title = \"\(escapeTOMLString(win.title))\"")
        lines.append("expected_x = \(win.expectedFrame.origin.x)")
        lines.append("expected_y = \(win.expectedFrame.origin.y)")
        lines.append("expected_w = \(win.expectedFrame.size.width)")
        lines.append("expected_h = \(win.expectedFrame.size.height)")
        lines.append("stage_id = \(win.stageID)")
        // SPEC-012 FR-020 : n'écrire display_uuid que si renseigné (backward-compat)
        if let uuid = win.displayUUID {
            lines.append("display_uuid = \"\(uuid)\"")
        }
        lines.append("")
    }
    return lines.joined(separator: "\n")
}

/// Échappe les caractères spéciaux TOML dans une chaîne (basic string RFC 8259 §7).
/// M3 : couvre backslash, guillemet, et caractères de contrôle (\n, \r, \t, \0, \b, \f)
/// pour garantir un round-trip correct (e.g. titre "foo\nbar").
private func escapeTOMLString(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
     .replacingOccurrences(of: "\0", with: "\\u0000")
     .replacingOccurrences(of: "\u{08}", with: "\\b")
     .replacingOccurrences(of: "\u{0C}", with: "\\f")
}

// MARK: - Désérialisation TOML → RoadieDesktop

/// Parse un fichier state.toml en `RoadieDesktop`.
/// Throw `DesktopParseError` si le TOML est invalide ou si un champ obligatoire manque.
public func parseDesktop(from toml: String) throws -> RoadieDesktop {
    let table: TOMLTable
    do {
        table = try TOMLTable(string: toml)
    } catch {
        throw DesktopParseError.invalidTOML("\(error)")
    }

    guard let id = table["id"]?.int else {
        throw DesktopParseError.missingField("id")
    }
    let labelRaw = table["label"]?.string ?? ""
    let label: String? = labelRaw.isEmpty ? nil : labelRaw
    let layoutRaw = table["layout"]?.string ?? "bsp"
    let layout = DesktopLayout(rawValue: layoutRaw) ?? .bsp
    let gapsOuter = table["gaps_outer"]?.int ?? 8
    let gapsInner = table["gaps_inner"]?.int ?? 4
    let activeStageID = table["active_stage_id"]?.int ?? 1

    let stages = try parseStages(from: table)
    let windows = try parseWindows(from: table)

    return RoadieDesktop(
        id: id,
        label: label,
        layout: layout,
        gapsOuter: gapsOuter,
        gapsInner: gapsInner,
        activeStageID: activeStageID,
        stages: stages,
        windows: windows
    )
}

private func parseStages(from table: TOMLTable) throws -> [DesktopStage] {
    guard let rawStages = table["stages"]?.array else { return [DesktopStage(id: 1)] }
    var stages: [DesktopStage] = []
    for item in rawStages {
        guard let t = item.table else { continue }
        guard let id = t["id"]?.int else {
            throw DesktopParseError.missingField("stages[].id")
        }
        let label: String? = t["label"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let winIDs: [UInt32] = (t["windows"]?.array ?? []).compactMap {
            guard let v = $0.int, v >= 0 else { return nil }
            return UInt32(v)
        }
        stages.append(DesktopStage(id: id, label: label, windows: winIDs))
    }
    return stages.isEmpty ? [DesktopStage(id: 1)] : stages
}

private func parseWindows(from table: TOMLTable) throws -> [WindowEntry] {
    guard let rawWindows = table["windows"]?.array else { return [] }
    var entries: [WindowEntry] = []
    for item in rawWindows {
        guard let t = item.table else { continue }
        guard let cgwid = t["cgwid"]?.int, cgwid > 0 else {
            throw DesktopParseError.missingField("windows[].cgwid")
        }
        let bundleID = t["bundle_id"]?.string ?? ""
        let title = t["title"]?.string ?? ""
        let x = t["expected_x"]?.double ?? 0
        let y = t["expected_y"]?.double ?? 0
        let w = t["expected_w"]?.double ?? 800
        let h = t["expected_h"]?.double ?? 600
        let stageID = t["stage_id"]?.int ?? 1
        // SPEC-012 FR-020 : lecture tolérante — absence = nil (SPEC-011 compat)
        let displayUUID: String? = t["display_uuid"]?.string.flatMap {
            $0.isEmpty ? nil : $0
        }
        let frame = CGRect(x: x, y: y, width: w, height: h)
        entries.append(WindowEntry(
            cgwid: UInt32(cgwid),
            bundleID: bundleID,
            title: title,
            expectedFrame: frame,
            stageID: stageID,
            displayUUID: displayUUID
        ))
    }
    return entries
}
