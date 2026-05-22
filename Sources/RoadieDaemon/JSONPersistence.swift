import Foundation

/// Helper centralisant le pattern de persistance JSON atomique avec creation de repertoire.
/// Reduit la duplication entre StageStore, LayoutIntentStore, RestoreSafetyService, etc.
enum JSONPersistence {
    /// Charge un Codable depuis l'URL ; retourne `defaultValue` si le fichier n'existe pas
    /// ou si le decoding echoue.
    ///
    /// IMPORTANT : aucune prise de verrou en lecture. Les writes utilisent `.atomic`
    /// (ecriture dans un fichier temporaire puis rename(2), operation atomique POSIX) :
    /// un lecteur voit donc toujours soit l'ancien fichier complet, soit le nouveau
    /// complet, jamais un etat partiel. Prendre un LOCK_SH ici provoquait une famine
    /// du writer (tiler) car les composants lecteurs (border 120ms, focus-mouse 100ms)
    /// tenaient le shared lock quasi en permanence, empechant le LOCK_EX du writer.
    static func load<T: Decodable>(_ type: T.Type, from url: URL, default defaultValue: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        return (try? JSONDecoder().decode(type, from: data)) ?? defaultValue
    }

    /// Persiste un Codable a l'URL en mode atomique (cree le repertoire parent si besoin).
    /// En cas d'erreur, ecrit un message sur stderr avec le `label` fourni.
    static func write<T: Encodable>(_ value: T, to url: URL, label: String) {
        do {
            try writeThrowing(value, to: url)
        } catch {
            fputs("roadie: failed to persist \(label): \(error)\n", stderr)
        }
    }

    /// Variante throwing avec encoder configurable (utile pour `iso8601` et autres).
    /// Acquire un verrou exclusif inter-process pendant tout l'encode+write. Resout
    /// les race conditions cross-process en mode atomique SPEC-011 (cf. FileLock).
    static func writeThrowing<T: Encodable>(
        _ value: T,
        to url: URL,
        configure: (JSONEncoder) -> Void = { _ in }
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lockPath = FileLock.lockPath(for: url)
        try FileLock.withLock(path: lockPath, mode: .exclusive) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            configure(encoder)
            try encoder.encode(value).write(to: url, options: .atomic)
        }
    }

    /// Variante load throwing avec decoder configurable (utile pour `iso8601`).
    /// Aucune prise de verrou en lecture (cf. `load`).
    static func loadThrowing<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        configure: (JSONDecoder) -> Void = { _ in }
    ) throws -> T {
        let decoder = JSONDecoder()
        configure(decoder)
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}
