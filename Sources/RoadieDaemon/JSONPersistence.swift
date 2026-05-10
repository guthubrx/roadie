import Foundation

/// Helper centralisant le pattern de persistance JSON atomique avec creation de repertoire.
/// Reduit la duplication entre StageStore, LayoutIntentStore, RestoreSafetyService, etc.
enum JSONPersistence {
    /// Charge un Codable depuis l'URL ; retourne `defaultValue` si le fichier n'existe pas
    /// ou si le decoding echoue.
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
    static func writeThrowing<T: Encodable>(
        _ value: T,
        to url: URL,
        configure: (JSONEncoder) -> Void = { _ in }
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        configure(encoder)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// Variante load throwing avec decoder configurable (utile pour `iso8601`).
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
