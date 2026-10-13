import Foundation
import os

/// Helper centralisant le pattern de persistance JSON atomique avec creation de repertoire.
/// Reduit la duplication entre StageStore, LayoutIntentStore, RestoreSafetyService, etc.
///
/// Regles (SPEC-016) :
/// - lectures simples sans verrou (cf. `load`) ;
/// - modifications en transaction exclusive (`mutate`, FR-013) ;
/// - aucune reecriture si la valeur (`mutate`) ou les octets (`writeThrowing`) sont inchanges (FR-014) ;
/// - fichier illisible conserve en `.corrupt-<horodatage>` et jamais ecrase (FR-015) ;
/// - valeur decodee gardee en cache par chemin et par processus, revalidee par la signature
///   du fichier (SPEC-017 A7) : un fichier inchange n'est ni relu ni decode.
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
        let result = read(type, from: url)
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
    ///   aucune exception (seules les erreurs de `body` sont propagees). Le resultat de `body` est
    ///   donc rendu meme si rien n'a ete persiste : un appelant qui doit le savoir utilise
    ///   `mutateChecked` (REL-021).
    /// - Fichier illisible : `body` travaille sur `defaultValue`, rien n'est ecrit (FR-015).
    /// - Le signalement (copie, stderr, evenement) a lieu apres la sortie du verrou.
    /// - Valeur inchangee (`Equatable`) : ni encodage ni ecriture (FR-014). Fichier absent : la valeur
    ///   est ecrite, comme avant. Apres une ecriture, la valeur et la signature du nouveau fichier
    ///   sont publiees dans le cache avant la liberation du verrou (A7).
    @discardableResult
    static func mutate<T: Codable & Equatable, R>(
        _ type: T.Type,
        at url: URL,
        default defaultValue: T,
        label: String,
        _ body: (inout T) throws -> R
    ) rethrows -> R {
        try mutateCore(type, at: url, default: defaultValue, label: label, onFailure: { fputs("roadie: \($0)\n", stderr) }, body)
    }

    /// Erreur de persistance rendue par `mutateChecked` : la modification n'est pas sur disque.
    struct PersistenceError: Error, CustomStringConvertible {
        let description: String
    }

    /// Message d'une commande dont l'état n'a pas été écrit (REL-021), journalisé sur stderr.
    /// « failed » donne au CLI un code de sortie non nul (`CLICommandRouter.actionExitCode`).
    static func commandFailureMessage(_ command: String, _ error: Error) -> String {
        fputs("roadie: \(command): \(error)\n", stderr)
        return "\(command): failed, \(error)"
    }

    /// Comme `mutate`, mais une modification non persistee (verrou impossible, fichier illisible,
    /// ecriture en echec) leve `PersistenceError` au lieu d'un succes silencieux (REL-021).
    /// Verrou impossible ou fichier illisible : `body` n'est pas execute. Ecriture en echec :
    /// `body` a ete execute, son resultat est perdu et le fichier d'origine reste intact.
    @discardableResult
    static func mutateChecked<T: Codable & Equatable, R>(
        _ type: T.Type,
        at url: URL,
        default defaultValue: T,
        label: String,
        _ body: (inout T) throws -> R
    ) throws -> R {
        try mutateCore(
            type, at: url, default: defaultValue, label: label,
            onFailure: { throw PersistenceError(description: $0) },
            body
        )
    }

    /// Corps commun. `onFailure` recoit le message d'un echec de persistance : `mutate` le
    /// journalise et continue, `mutateChecked` leve.
    private static func mutateCore<T: Codable & Equatable, R>(
        _ type: T.Type,
        at url: URL,
        default defaultValue: T,
        label: String,
        onFailure: (String) throws -> Void,
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
            try onFailure("\(label) not persisted, lock failed: \(error)")
            var value = load(type, from: url, default: defaultValue)
            return try body(&value)
        }
        defer { lock.release() }

        let original: T?
        switch read(type, from: url) {
        case .loaded(let loaded):
            original = loaded
        case .missing:
            original = nil
        case .corrupt(let error):
            corruptError = error
            try onFailure("\(label) not persisted, state file is unreadable")
            var fallback = defaultValue
            return try body(&fallback)
        }
        var value = original ?? defaultValue
        let output = try body(&value)
        guard original != value else { return output }
        do {
            try writeLocked(value, to: url, existing: nil)
            publish(value, at: url, signature: FileSignature(path: url.path))
        } catch {
            try onFailure("failed to persist \(label): \(error)")
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

    /// Lecture par la signature (A7) : `fstat` sur le descripteur ouvert ; valeur en cache si la
    /// signature est egale, sinon octets lus depuis CE descripteur, decodes et mis en cache.
    /// Un fichier absent ou illisible n'est pas mis en cache.
    // O(1) si inchange, O(taille du fichier) sinon.
    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> LoadResult<T> {
        let cached = cache.withLockUnchecked { $0[url.path] }
        let known = cached.flatMap { $0.value is T ? $0.signature : nil }
        switch readSigned(url, unless: known) {
        case .missing:
            return .missing
        case .failed(let error):
            return .corrupt(error)
        case .unchanged:
            // `known` non nil implique une valeur de type T en cache.
            return .loaded(cached!.value as! T)
        case .read(let signature, let data):
            do {
                let value = try JSONDecoder().decode(type, from: data)
                publish(value, at: url, signature: signature)
                return .loaded(value)
            } catch {
                return .corrupt(error)
            }
        }
    }

    /// Ouvre `url`, lit sa signature par `fstat`, puis ses octets depuis le meme descripteur,
    /// sauf si la signature vaut `known`. Lire par le descripteur garantit que les octets
    /// correspondent a la signature, meme si un rename remplace le fichier entre-temps.
    static func readSigned(_ url: URL, unless known: FileSignature?) -> SignedRead {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            let code = errno
            if code == ENOENT { return .missing }
            return .failed(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            return .failed(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
        }
        let signature = FileSignature(info)
        if signature == known { return .unchanged(signature) }
        do {
            return .read(signature, try handle.readToEnd() ?? Data())
        } catch {
            return .failed(error)
        }
    }

    enum SignedRead {
        case missing
        case failed(Error)
        case unchanged(FileSignature)
        case read(FileSignature, Data)
    }

    /// Cache par chemin : derniere valeur decodee et signature du fichier dont elle vient.
    /// La valeur est un type valeur copie ; l'acces passe par le verrou interne.
    private struct CacheEntry {
        var signature: FileSignature
        var value: Any
    }

    private static let cache = OSAllocatedUnfairLock(uncheckedState: [String: CacheEntry]())

    /// Publie (valeur, signature). Sans signature (stat en echec), l'entree est retiree :
    /// la lecture suivante relira le fichier.
    private static func publish<T>(_ value: T, at url: URL, signature: FileSignature?) {
        cache.withLockUnchecked { entries in
            entries[url.path] = signature.map { CacheEntry(signature: $0, value: value) }
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

/// Signature d'un fichier (SPEC-017 A7) : date de modification en ns, taille et inode.
/// L'ecriture atomique (rename) change l'inode ; une ecriture en place change la date ou la taille.
struct FileSignature: Equatable, Sendable {
    var modifiedSeconds: Int64
    var modifiedNanoseconds: Int64
    var size: Int64
    var inode: UInt64

    init(_ info: stat) {
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        size = Int64(info.st_size)
        inode = UInt64(info.st_ino)
    }

    /// Signature par chemin ; nil si le fichier est absent.
    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        self.init(info)
    }
}
