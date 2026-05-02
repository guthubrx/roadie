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
        // ne pas écraser. L'utilisateur a peut-être démarré V3 avant un V2 leftover.
        if let contents = try? fm.contentsOfDirectory(atPath: target.path),
           !contents.isEmpty {
            // V3 déjà peuplée → la legacy est leftover, on ne touche pas.
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
        let legacyCurrent = target.appendingPathComponent("current.txt")
        let newCurrent = primaryRoot.appendingPathComponent("current.toml")
        if let raw = try? String(contentsOf: legacyCurrent, encoding: .utf8),
           let savedID = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let toml = """
            current_desktop_id = \(savedID)
            last_updated = "\(ISO8601DateFormatter().string(from: Date()))"
            """
            try? toml.write(to: newCurrent, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: legacyCurrent)
        }

        return count
    }
}
