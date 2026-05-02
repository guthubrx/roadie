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

        // Idempotence : backup déjà présent → déjà migré.
        if FileManager.default.fileExists(atPath: backupPath) {
            logInfo("migration_v1v2_skipped_backup_exists", ["backup": backupPath])
            return nil
        }

        let candidates = collectTopLevelTOML()
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
