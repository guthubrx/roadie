import Foundation
import RoadieCore

/// Migration one-shot des fichiers V1 flat (`<stagesDir>/<id>.toml`) vers
/// la structure nested V2 (`<stagesDir>/<displayUUID>/1/<id>.toml`).
/// Idempotente : retourne nil si déjà migrée ou sans objet.
public final class MigrationV1V2 {

    // MARK: - Types publics

    public struct Report: Codable, Sendable {
        public let migratedCount: Int
        public let backupPath: String
        public let targetDisplayUUID: String
        public let durationMs: Int
    }

    public enum MigrationError: Error {
        case diskFull
        case permissionDenied(path: String)
        case partialMigration(count: Int, remaining: [String])
    }

    // MARK: - Stockage

    private let stagesDir: String
    private let mainDisplayUUID: String

    public init(stagesDir: String, mainDisplayUUID: String) {
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        self.mainDisplayUUID = mainDisplayUUID
    }

    // MARK: - Point d'entrée

    /// Exécute la migration si nécessaire.
    /// Retourne un Report si la migration a été effectuée, nil sinon.
    public func runIfNeeded() throws -> Report? {
        let backupPath = stagesDir + ".v1.bak"

        // SPEC-018 fix : avant 2026-05-03, on skippait dès que backup existait.
        // Mais des V1 sources pouvaient subsister non migrées (ex: V2 cible vide créée
        // par boot précédent + dst exists block move). On vérifie maintenant aussi qu'il
        // n'y a plus rien à migrer côté V1 source. Si backup ET V1 vide → vraiment idempotent.
        let candidates = collectTopLevelTOML()
        if FileManager.default.fileExists(atPath: backupPath) && candidates.isEmpty {
            logInfo("migration_v1v2_skipped_backup_exists", ["backup": backupPath])
            return nil
        }
        if FileManager.default.fileExists(atPath: backupPath) && !candidates.isEmpty {
            // Backup existant ET V1 source non vide : archive le backup ancien (timestamp)
            // pour permettre une nouvelle migration. Le backup ancien n'est PAS perdu.
            let timestamp = Int(Date().timeIntervalSince1970)
            let archivedBackup = "\(backupPath).archived-\(timestamp)"
            do {
                try FileManager.default.moveItem(atPath: backupPath, toPath: archivedBackup)
                logInfo("migration_v1v2_archived_old_backup",
                        ["from": backupPath, "to": archivedBackup,
                         "remaining_v1_candidates": String(candidates.count)])
            } catch {
                logWarn("migration_v1v2_archive_failed",
                        ["backup": backupPath, "error": "\(error)"])
                return nil  // ne pas casser le boot
            }
        }

        if candidates.isEmpty {
            logInfo("migration_v1v2_skipped_nothing_to_migrate", ["dir": stagesDir])
            return nil
        }

        let start = Date()
        try createBackup(at: backupPath)
        let count = try migrateFiles(candidates)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        let report = Report(
            migratedCount: count,
            backupPath: backupPath,
            targetDisplayUUID: mainDisplayUUID,
            durationMs: durationMs
        )
        logInfo("migration_v1v2_done", [
            "count": String(count),
            "display": mainDisplayUUID,
            "ms": String(durationMs),
        ])
        return report
    }

    // MARK: - Helpers privés

    /// Collecte uniquement les fichiers `.toml` au top-level (pas de récursion).
    private func collectTopLevelTOML() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: stagesDir)
        else { return [] }
        return entries.filter { entry in
            guard entry.hasSuffix(".toml") && entry != "active.toml" else { return false }
            // Vérifier que c'est bien un fichier (pas un sous-dossier nommé .toml)
            let fullPath = "\(stagesDir)/\(entry)"
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            return !isDir.boolValue
        }
    }

    private func createBackup(at backupPath: String) throws {
        do {
            try FileManager.default.copyItem(atPath: stagesDir, toPath: backupPath)
        } catch let error as NSError {
            throw mapCocoaError(error, path: backupPath)
        }
    }

    /// SPEC-018 fix : un stage TOML est "vide" si son champ `members` est inline `[]`
    /// (pas d'`[[members]]` array of tables). Heuristique simple grep — suffisante pour
    /// détecter les V2 cibles créées vides par un boot précédent que la migration a foiré.
    private func isStageFileEmpty(_ path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false  // si on ne peut pas lire, ne pas écraser
        }
        // `members = []` (inline empty) ET pas de `[[members]]` (array of tables)
        return content.contains("members = []") && !content.contains("[[members]]")
    }

    private func migrateFiles(_ candidates: [String]) throws -> Int {
        let targetDir = "\(stagesDir)/\(mainDisplayUUID)/1"
        do {
            try FileManager.default.createDirectory(
                atPath: targetDir, withIntermediateDirectories: true)
        } catch let error as NSError {
            throw mapCocoaError(error, path: targetDir)
        }

        var moved: [String] = []
        var failed: [String] = []

        for filename in candidates {
            let src = "\(stagesDir)/\(filename)"
            let dst = "\(targetDir)/\(filename)"
            // SPEC-018 fix : si dst existe (créé par un boot précédent qui a aussi
            // tenté la migration), check son état avant move.
            // - dst vide (members []) → V1 source contient les vraies données →
            //   supprimer dst et écraser. Comportement antérieur : moveItem échouait
            //   → V1 source restait, V2 cible vide gardée → données invisibles.
            // - dst plein → V2 cible a déjà été peuplée (manuellement ou par autre
            //   path) → ne pas écraser. Backup V1 source en `.legacy.<TS>` pour ne
            //   rien perdre, puis log warn.
            if FileManager.default.fileExists(atPath: dst) {
                if isStageFileEmpty(dst) {
                    do {
                        try FileManager.default.removeItem(atPath: dst)
                        logInfo("migration_v1v2_removed_empty_dst",
                                ["file": filename, "dst": dst])
                    } catch {
                        logWarn("migration_v1v2_remove_empty_dst_failed",
                                ["file": filename, "err": "\(error)"])
                        failed.append(filename)
                        continue
                    }
                } else {
                    // V2 cible plein → préserver V1 source via backup horodaté pour
                    // permettre intervention manuelle (merge).
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let backup = "\(src).legacy.\(timestamp)"
                    try? FileManager.default.moveItem(atPath: src, toPath: backup)
                    logWarn("migration_v1v2_dst_already_populated_v1_backed_up",
                            ["file": filename, "v1_backup": backup, "v2_dst": dst])
                    continue
                }
            }
            do {
                try FileManager.default.moveItem(atPath: src, toPath: dst)
                moved.append(filename)
            } catch let error as NSError {
                logWarn("migration_v1v2_move_failed",
                        ["file": filename, "err": error.localizedDescription])
                failed.append(filename)
            }
        }

        if !failed.isEmpty {
            throw MigrationError.partialMigration(count: moved.count, remaining: failed)
        }
        return moved.count
    }

    private func mapCocoaError(_ error: NSError, path: String) -> MigrationError {
        switch error.code {
        case NSFileWriteOutOfSpaceError: return .diskFull
        case NSFileWriteNoPermissionError: return .permissionDenied(path: path)
        default: return .permissionDenied(path: path)
        }
    }
}
