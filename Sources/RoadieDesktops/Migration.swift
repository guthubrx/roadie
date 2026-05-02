import Foundation
import TOMLKit
import CoreGraphics
import RoadieCore

// MARK: - Migration SPEC-011 (US6, T052-T053, FR-021-FR-022)
//
// Deux fonctions d'entrée :
//   1. archiveSpec003LegacyDirs  — archive les dossiers UUID issus de SPEC-003 deprecated.
//   2. migrateV1ToV2             — migration des stages V1 vers desktop/1/state.toml.
//
// Appelées au boot daemon avant DesktopRegistry.load() (T054).

/// Pattern UUID natif Mac Space (SPEC-003, 36 chars hex).
private let uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

/// Détecte si `name` ressemble à un UUID v4 Mac Space (pattern SPEC-003).
private func looksLikeUUID(_ name: String) -> Bool {
    (try? NSRegularExpression(pattern: uuidPattern))
        .map { $0.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil }
        ?? false
}

// MARK: - Archive SPEC-003 (T053, FR-022)

/// Renomme les dossiers UUID issus de SPEC-003 en `.archived-spec003-<UUID>`.
/// Appeler avant `migrateV1ToV2` pour que la migration ne trouve pas de desktops
/// SPEC-003 et reparte de zéro.
/// No-op si aucun dossier UUID trouvé.
public func archiveSpec003LegacyDirs(desktopsDir: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: desktopsDir.path) else { return }

    let entries = (try? fm.contentsOfDirectory(
        at: desktopsDir, includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles)) ?? []

    for entry in entries {
        let name = entry.lastPathComponent
        guard looksLikeUUID(name) else { continue }
        let archived = desktopsDir.appendingPathComponent(".archived-spec003-\(name)")
        do {
            try fm.moveItem(at: entry, to: archived)
            logWarn("SPEC-003 state archived",
                    ["src": name, "dest": ".archived-spec003-\(name)"])
        } catch {
            logWarn("SPEC-003 archive failed",
                    ["entry": name, "error": "\(error)"])
        }
    }
}

// MARK: - Migration V1 → V2 (T052, FR-021)

/// Migre les stages V1 (`stagesDir/*.toml`) vers `desktopsDir/1/state.toml`.
/// - No-op si `stagesDir` est absent ou vide.
/// - No-op si `desktopsDir/1/state.toml` existe déjà (idempotence : 2e boot).
/// - En cas de succès : loggue info. `stagesDir` est conservé read-only pour rollback.
public func migrateV1ToV2(stagesDir: URL, desktopsDir: URL) async throws {
    let fm = FileManager.default

    // No-op : stagesDir absent ou vide
    guard fm.fileExists(atPath: stagesDir.path) else { return }
    let stageFiles = (try? fm.contentsOfDirectory(atPath: stagesDir.path))
        .map { $0.filter { $0.hasSuffix(".toml") && $0 != "active.toml" } }
        ?? []
    guard !stageFiles.isEmpty else { return }

    // Idempotence : desktops/1/state.toml existe → déjà migré
    let targetFile = desktopsDir.appendingPathComponent("1/state.toml")
    guard !fm.fileExists(atPath: targetFile.path) else { return }

    // Lire les stages V1
    var desktopStages: [DesktopStage] = []
    var allWindows: [WindowEntry] = []

    let sortedFiles = stageFiles.sorted()
    for (idx, fileName) in sortedFiles.enumerated() {
        let path = stagesDir.appendingPathComponent(fileName)
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { continue }

        let stageID = idx + 1
        let windows = extractWindowsFromV1Stage(raw)
        let cgwids = windows.map { $0.cgwid }
        let stageName = (fileName as NSString).deletingPathExtension
        desktopStages.append(DesktopStage(id: stageID, label: stageName, windows: cgwids))
        for var w in windows {
            w.stageID = stageID
            if !allWindows.contains(where: { $0.cgwid == w.cgwid }) {
                allWindows.append(w)
            }
        }
    }

    let desktop = RoadieDesktop(
        id: 1,
        label: nil,
        layout: .bsp,
        activeStageID: 1,
        stages: desktopStages.isEmpty ? [DesktopStage(id: 1)] : desktopStages,
        windows: allWindows
    )

    // H3 : garantir l'existence du répertoire desktopsDir avant la migration
    // pour que save() ne soit pas le premier créateur du parent (race potentielle
    // si plusieurs appels concurrents au boot, e.g. test harness).
    do {
        try FileManager.default.createDirectory(
            at: desktopsDir, withIntermediateDirectories: true)
    } catch {
        throw DesktopRegistryError.saveFailure("migration mkdir failed: \(error)")
    }
    let registry = DesktopRegistry(
        configDir: desktopsDir.deletingLastPathComponent(),
        count: 1
    )
    try await registry.save(desktop)

    logInfo("V1→V2 migration complete",
            ["stages": String(desktopStages.count),
             "windows": String(allWindows.count)])
}

// MARK: - Extraction fenêtres V1 (format TOMLKit)

/// Lit les `StageMember` d'un fichier stage V1 (TOML TOMLKit — clés cg_window_id, etc.)
/// et les convertit en `WindowEntry` pour SPEC-011.
private func extractWindowsFromV1Stage(_ toml: String) -> [WindowEntry] {
    guard let table = try? TOMLTable(string: toml),
          let members = table["members"]?.array else { return [] }
    var entries: [WindowEntry] = []
    for item in members {
        guard let t = item.table,
              let cgwid64 = t["cg_window_id"]?.int, cgwid64 > 0 else { continue }
        let bundleID = t["bundle_id"]?.string ?? ""
        let title = t["title_hint"]?.string ?? ""
        let frame: CGRect
        if let sf = t["saved_frame"]?.table,
           let x = sf["x"]?.double, let y = sf["y"]?.double,
           let w = sf["w"]?.double, let h = sf["h"]?.double {
            frame = CGRect(x: x, y: y, width: w, height: h)
        } else {
            frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        }
        entries.append(WindowEntry(
            cgwid: UInt32(cgwid64),
            bundleID: bundleID,
            title: title,
            expectedFrame: frame,
            stageID: 1   // sera mis à jour par le caller
        ))
    }
    return entries
}
