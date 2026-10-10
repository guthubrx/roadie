import Foundation
import os

/// Helper centralisant le pattern de persistance JSON atomique avec creation de repertoire.
/// Reduit la duplication entre StageStore, LayoutIntentStore, RestoreSafetyService, etc.
///
/// Regles (SPEC-016) :
/// - lectures simples sans verrou (cf. `load`) ;
/// - modifications en transaction exclusive (`mutate`, FR-013) ;
/// - aucune reecriture si les octets encodes sont identiques au fichier (FR-014) ;
/// - fichier illisible conserve en `.corrupt-<horodatage>` et jamais ecrase (FR-015).
enum JSONPersistence {
    enum LoadResult<T> {
        case missing
        case loaded(T)
        case corrupt(Error)
    }

    /// Charge un Codable depuis l'URL ; retourne `defaultValue` si le fichier n'existe pas
    /// ou s'il est illisible (dans ce cas il est mis de cote et signale, cf. `reportCorrupt`).
    ///
    /// IMPORTANT : aucune prise de verrou en lecture. Les writes utilisent `.atomic`
    /// (ecriture dans un fichier temporaire puis rename(2), operation atomique POSIX) :
    /// un lecteur voit donc toujours soit l'ancien fichier complet, soit le nouveau
    /// complet, jamais un etat partiel. Prendre un LOCK_SH ici provoquait une famine
    /// du writer (tiler) car les composants lecteurs (border 120ms, focus-mouse 100ms)
    /// tenaient le shared lock quasi en permanence, empechant le LOCK_EX du writer.
    static func load<T: Decodable>(_ type: T.Type, from url: URL, default defaultValue: T) -> T {
        if case .loaded(let value) = loadResult(type, from: url) { return value }
        return defaultValue
    }

    /// Distingue fichier absent, charge ou illisible (SPEC-016 R2). Sans verrou.
    static func loadResult<T: Decodable>(_ type: T.Type, from url: URL) -> LoadResult<T> {
        let result = read(type, from: url).result
        if case .corrupt(let error) = result {
            reportCorrupt(url: url, error: error)
        }
        return result
    }

    /// Transaction lecture-modification-ecriture sous verrou exclusif `FileLock` (SPEC-016 FR-013).
    ///
    /// - Pas de transaction imbriquee : flock(2) est lie au descripteur ouvert. Un second verrou
    ///   sur le meme fichier pris depuis `body` (via `mutate`, `writeThrowing` ou un store) ouvrirait
    ///   un autre descripteur et bloquerait le processus sur lui-meme.
    /// - Erreurs d'I/O (verrou, encodage, ecriture) : journalisees sur stderr, rien n'est ecrit,
    ///   aucune exception (seules les erreurs de `body` sont propagees).
    /// - Fichier illisible : `body` travaille sur `defaultValue`, rien n'est ecrit (FR-015).
    /// - Le signalement (copie, stderr, evenement) a lieu apres la sortie du verrou.
    @discardableResult
    static func mutate<T: Codable, R>(
        _ type: T.Type,
        at url: URL,
        default defaultValue: T,
        label: String,
        _ body: (inout T) throws -> R
    ) rethrows -> R {
        var corruptError: Error?
        // Declare avant le verrou : s'execute apres sa liberation (ordre inverse des defer).
        defer {
            if let corruptError { reportCorrupt(url: url, error: corruptError) }
        }
        let lock = FileLock(path: FileLock.lockPath(for: url))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try lock.acquire(mode: .exclusive)
        } catch {
            fputs("roadie: \(label) not persisted, lock failed: \(error)\n", stderr)
            var value = load(type, from: url, default: defaultValue)
            return try body(&value)
        }
        defer { lock.release() }

        let (result, existing) = read(type, from: url)
        var value: T
        switch result {
        case .loaded(let loaded):
            value = loaded
        case .missing:
            value = defaultValue
        case .corrupt(let error):
            corruptError = error
            fputs("roadie: \(label) not persisted, state file is unreadable\n", stderr)
            var fallback = defaultValue
            return try body(&fallback)
        }
        let output = try body(&value)
        do {
            try writeLocked(value, to: url, existing: existing)
        } catch {
            fputs("roadie: failed to persist \(label): \(error)\n", stderr)
        }
        return output
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
    /// Acquiert le verrou exclusif inter-process pendant tout l'encode+write (cf. FileLock).
    /// Ne pas appeler depuis `mutate` sur le meme fichier (verrou non reentrant).
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
            try writeLocked(value, to: url, existing: try? Data(contentsOf: url), configure: configure)
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

    // MARK: - Interne

    /// Ecriture avec verrou DEJA tenu par l'appelant. Aucune ecriture si les octets sont
    /// identiques a `existing` (FR-014).
    private static func writeLocked<T: Encodable>(
        _ value: T,
        to url: URL,
        existing: Data?,
        configure: (JSONEncoder) -> Void = { _ in }
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        configure(encoder)
        let data = try encoder.encode(value)
        guard data != existing else { return }
        try data.write(to: url, options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> (result: LoadResult<T>, data: Data?) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return (.missing, nil) }
            return (.corrupt(error), nil)
        }
        do {
            return (.loaded(try JSONDecoder().decode(type, from: data)), data)
        } catch {
            return (.corrupt(error), data)
        }
    }

    /// Signatures (chemin, date, taille) deja signalees par ce processus : evite de repeter
    /// la copie, stderr et l'evenement a chaque lecture d'un meme fichier illisible.
    private static let reportedCorruptions = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Copie le fichier illisible en `<nom>.corrupt-<horodatage>`, ecrit sur stderr et emet
    /// `state.load_failed` (FR-015). L'horodatage est la date de modification du fichier :
    /// plusieurs processus produisent donc la meme copie, creee une seule fois.
    private static func reportCorrupt(url: URL, error: Error) {
        let manager = FileManager.default
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date ?? Date()
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        let signature = "\(url.path)|\(modified.timeIntervalSince1970)|\(size)"
        let isNew = reportedCorruptions.withLock { $0.insert(signature).inserted }
        guard isNew else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupPath = "\(url.path).corrupt-\(formatter.string(from: modified))"
        if !manager.fileExists(atPath: backupPath) {
            do {
                try manager.copyItem(atPath: url.path, toPath: backupPath)
            } catch {
                fputs("roadie: failed to back up unreadable \(url.path): \(error)\n", stderr)
            }
        }
        fputs("roadie: unreadable state file \(url.path) kept as \(backupPath); writes refused until it loads: \(error)\n", stderr)
        EventLog().append(RoadieEvent(type: "state.load_failed", details: [
            "path": url.path,
            "backup": backupPath,
            "error": String(describing: error),
        ]))
    }
}
