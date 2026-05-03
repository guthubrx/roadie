import Foundation
import RoadieCore

// MARK: - DesktopMigration (SPEC-013 FR-021..FR-023)

/// Migration one-shot V2 → V3 du layout desktop persistant.
///
/// V2 : `~/.config/roadies/desktops/<id>/state.toml` + `desktops/current.txt`
/// V3 : `~/.config/roadies/displays/<primaryUUID>/desktops/<id>/state.toml`
///       `~/.config/roadies/displays/<primaryUUID>/current.toml`
///
/// Idempotent : si l'ancien dossier `desktops/` n'existe pas (ou a déjà été
/// migré), aucune action.
public enum DesktopMigration {
    /// - Returns: count de desktops migrés (0 si idempotent).
    /// - Throws: en cas d'erreur de filesystem non-récupérable. Best-effort sur
    ///   les sous-étapes (current.txt) — la migration principale (rename desktops/)
    ///   est l'unique source de fail blocant.
    @discardableResult
    public static func runIfNeeded(configDir: URL,
                                   primaryUUID: String) throws -> Int {
        let fm = FileManager.default
        let legacyDesktops = configDir.appendingPathComponent("desktops")
        let displaysRoot = configDir.appendingPathComponent("displays")
        let target = displaysRoot
            .appendingPathComponent(primaryUUID)
            .appendingPathComponent("desktops")

        // Idempotence : si l'ancien dossier n'existe pas, rien à faire.
        guard fm.fileExists(atPath: legacyDesktops.path) else { return 0 }

        // Idempotence stricte : si la cible existe déjà ET contient des state.toml,
        // V3 est la source de vérité. Le V2 leftover doit être archivé pour éviter
        // qu'il pollue les autres consumers (ex: desktop list qui lirait à tort le
        // legacy avec ses fantômes de sessions précédentes — incident 2026-05-03 :
        // legacy contenait 50+ windows et 3 stages dont une "Stage 13" fantôme,
        // alors que V3 ne voyait qu'1 window et 0 stages).
        //
        // Action : déplacer le V2 leftover vers `desktops.legacy.archived-<unixts>/`
        // pour préserver la donnée historique sans laisser le code la lire.
        if let contents = try? fm.contentsOfDirectory(atPath: target.path),
           !contents.isEmpty {
            let legacyCount = (try? fm.contentsOfDirectory(atPath: legacyDesktops.path))?
                .filter { Int($0) != nil }.count ?? 0
            let timestamp = Int(Date().timeIntervalSince1970)
            let archive = configDir.appendingPathComponent("desktops.legacy.archived-\(timestamp)")
            do {
                try fm.moveItem(at: legacyDesktops, to: archive)
                logInfo("DesktopMigration archived V2 leftover (V3 is source of truth)",
                        ["primaryUUID": primaryUUID,
                         "legacyDesktopsCount": String(legacyCount),
                         "archivedTo": archive.path])
            } catch {
                // Si le move échoue (perm, fs), on log warn et on laisse le legacy
                // (comportement antérieur). Pas blocant : V3 reste fonctionnel.
                logWarn("DesktopMigration: archive of V2 leftover failed",
                        ["primaryUUID": primaryUUID,
                         "legacyDesktopsCount": String(legacyCount),
                         "legacyPath": legacyDesktops.path,
                         "error": "\(error)"])
            }
            return 0
        }

        // Compter les desktops à migrer (= sous-dossiers numériques de legacyDesktops).
        let count = (try? fm.contentsOfDirectory(atPath: legacyDesktops.path))?
            .filter { Int($0) != nil }.count ?? 0

        // Créer la racine displays/<primaryUUID>/.
        let primaryRoot = displaysRoot.appendingPathComponent(primaryUUID)
        try fm.createDirectory(at: primaryRoot, withIntermediateDirectories: true)

        // Déplacer le dossier desktops/ → displays/<primaryUUID>/desktops.
        // moveItem est atomique sur même volume (rename(2) POSIX).
        try fm.moveItem(at: legacyDesktops, to: target)

        // Migrer current.txt → current.toml dans displays/<primaryUUID>/.
        // Best-effort : un échec ici ne fait pas tomber la migration principale,
        // mais doit être loggé (le current legacy est sinon perdu silencieusement).
        let legacyCurrent = target.appendingPathComponent("current.txt")
        let newCurrent = primaryRoot.appendingPathComponent("current.toml")
        if let raw = try? String(contentsOf: legacyCurrent, encoding: .utf8),
           let savedID = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let toml = """
            current_desktop_id = \(savedID)
            last_updated = "\(ISO8601DateFormatter().string(from: Date()))"
            """
            do {
                try toml.write(to: newCurrent, atomically: true, encoding: .utf8)
                try fm.removeItem(at: legacyCurrent)
            } catch {
                logWarn("DesktopMigration current.toml write failed",
                        ["primaryUUID": primaryUUID,
                         "savedID": String(savedID),
                         "error": "\(error)"])
            }
        }

        return count
    }
}
