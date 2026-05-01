import Foundation

/// Migration automatique V1 → V2 (FR-023).
///
/// Au premier boot V2 avec `multi_desktop.enabled = true`, si l'utilisateur a un
/// dossier V1 `~/.config/roadies/stages/` peuplé et que `~/.config/roadies/desktops/`
/// n'existe pas, on déplace les stages vers `desktops/<current-uuid>/stages/` et on
/// crée un backup horodaté `stages.v1-backup-YYYYMMDD/` pour rollback.
public enum DesktopMigration {

    public struct Result: Sendable {
        public let migrated: Bool
        public let backupPath: String?
        public let movedFiles: Int
    }

    /// Lance la migration. `currentUUID` est l'UUID du desktop sur lequel se trouve
    /// l'utilisateur au boot — les stages V1 lui sont rattachés (research.md décision 4).
    /// No-op si la migration n'a pas lieu d'être (déjà V2, ou pas de stages V1).
    @discardableResult
    public static func runIfNeeded(currentUUID: String) -> Result {
        let home = NSString(string: "~").expandingTildeInPath
        let v1Dir = "\(home)/.config/roadies/stages"
        let v2Root = "\(home)/.config/roadies/desktops"
        let fm = FileManager.default

        let v1Exists = fm.fileExists(atPath: v1Dir)
        let v2Exists = fm.fileExists(atPath: v2Root)
        guard v1Exists, !v2Exists else {
            return Result(migrated: false, backupPath: nil, movedFiles: 0)
        }

        // Backup horodaté avant tout déplacement.
        let stamp = ISO8601DateFormatter.dayStamp(from: Date())
        let backup = "\(home)/.config/roadies/stages.v1-backup-\(stamp)"
        do {
            try fm.copyItem(atPath: v1Dir, toPath: backup)
        } catch {
            logWarn("v1→v2 backup failed",
                    ["err": "\(error)"])
            return Result(migrated: false, backupPath: nil, movedFiles: 0)
        }

        // Crée la structure V2 et déplace les fichiers du desktop courant.
        let perDesktopStages = "\(v2Root)/\(currentUUID)/stages"
        try? fm.createDirectory(atPath: perDesktopStages, withIntermediateDirectories: true)
        var moved = 0
        if let entries = try? fm.contentsOfDirectory(atPath: v1Dir) {
            for entry in entries where entry.hasSuffix(".toml") {
                let from = "\(v1Dir)/\(entry)"
                let to = "\(perDesktopStages)/\(entry)"
                if (try? fm.moveItem(atPath: from, toPath: to)) != nil {
                    moved += 1
                }
            }
        }
        // Supprime le dossier V1 vide (le backup conserve l'original).
        try? fm.removeItem(atPath: v1Dir)
        logInfo("v1→v2 migration done",
                ["moved": String(moved),
                 "backup": backup,
                 "current_uuid": currentUUID])
        return Result(migrated: true, backupPath: backup, movedFiles: moved)
    }
}

private extension ISO8601DateFormatter {
    static func dayStamp(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
