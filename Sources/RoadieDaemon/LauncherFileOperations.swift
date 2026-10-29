import AppKit
import CryptoKit
import Foundation
import RoadieCore
import UniformTypeIdentifiers

/// Opérations des verbes de fichier de la barre (session 131), comme les actions d'Alfred : copier ou déplacer vers
/// un dossier, corbeille, alias, informations, étiquettes. Rien n'est écrasé : « en remplaçant » met d'abord
/// l'homonyme à la corbeille, et la corbeille est la seule suppression proposée. Logique testable ; la corbeille est
/// injectée pour que les tests ne touchent pas celle de l'utilisateur.
enum LauncherFileOperations {
    /// Mise à la corbeille d'un élément ; celle de macOS par défaut.
    typealias Trasher = @Sendable (URL) throws -> Void
    static let systemTrash: Trasher = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Bilan d'une opération sur une ou plusieurs sources : chemins obtenus, échecs par source (raison lisible).
    struct Report: Equatable {
        var done: [String] = []
        var failures: [String: String] = [:]
        var succeeded: Bool { failures.isEmpty && !done.isEmpty }
    }

    /// Copie (`move` faux) ou déplace chaque source dans `folder`. Un homonyme refuse l'opération, sauf `replace`,
    /// qui le met d'abord à la corbeille. Un dossier ne va jamais dans lui-même. O(s) opérations de fichier.
    static func transfer(_ sources: [String], to folder: String, move: Bool, replace: Bool,
                         trash: Trasher = systemTrash, files: FileManager = .default) -> Report {
        var report = Report()
        let destination = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            for source in sources { report.failures[source] = tr("dossier introuvable", "folder not found") }
            return report
        }
        for source in sources {
            let from = URL(fileURLWithPath: source).standardizedFileURL
            let target = destination.appendingPathComponent(from.lastPathComponent)
            guard files.fileExists(atPath: from.path) else { report.failures[source] = tr("introuvable", "not found"); continue }
            if target.path == from.path { report.failures[source] = tr("déjà dans ce dossier", "already in this folder"); continue }
            if target.path.hasPrefix(from.path + "/") { report.failures[source] = tr("dossier dans lui-même", "folder into itself"); continue }
            do {
                if files.fileExists(atPath: target.path) {
                    guard replace else { report.failures[source] = tr("un élément du même nom existe", "an item with this name exists"); continue }
                    try trash(target)
                }
                if move { try files.moveItem(at: from, to: target) } else { try files.copyItem(at: from, to: target) }
                report.done.append(target.path)
            } catch {
                report.failures[source] = error.localizedDescription
            }
        }
        return report
    }

    /// Met chaque source à la corbeille. O(s).
    static func trashItems(_ sources: [String], trash: Trasher = systemTrash) -> Report {
        var report = Report()
        for source in sources {
            do { try trash(URL(fileURLWithPath: source)); report.done.append(source) }
            catch { report.failures[source] = error.localizedDescription }
        }
        return report
    }

    /// Alias du Finder à côté de la source : « nom alias », puis « nom alias 2 »… s'il existe déjà. O(n) essais de nom.
    static func makeAlias(_ source: String, files: FileManager = .default) throws -> String {
        let url = URL(fileURLWithPath: source)
        let folder = url.deletingLastPathComponent()
        let base = url.lastPathComponent + " " + tr("alias", "alias")
        var candidate = folder.appendingPathComponent(base)
        var index = 2
        while files.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(index)")
            index += 1
        }
        let data = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: candidate)
        return candidate.path
    }

    /// Fiche d'un élément : type, taille, dates et empreinte SHA-256 (fichier ordinaire seulement).
    struct Info: Equatable {
        var kind: String
        var typeIdentifier: String
        var mimeType: String?
        var size: Int64
        var created: Date?
        var modified: Date?
        var sha256: String?

        /// Lignes affichées, chacune copiable : libellé puis valeur. O(1).
        var lines: [(label: String, value: String)] {
            let format = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            var lines = [(tr("Type", "Kind"), kind), ("UTI", typeIdentifier)]
            if let mimeType { lines.append(("MIME", mimeType)) }
            lines.append((tr("Taille", "Size"), "\(format) (\(size) " + tr("octets", "bytes") + ")"))
            let dates = DateFormatter()
            dates.dateStyle = .medium
            dates.timeStyle = .short
            if let created { lines.append((tr("Créé", "Created"), dates.string(from: created))) }
            if let modified { lines.append((tr("Modifié", "Modified"), dates.string(from: modified))) }
            if let sha256 { lines.append(("SHA-256", sha256)) }
            return lines
        }
    }

    /// Fiche d'un élément ; taille d'un dossier : somme de ses fichiers, 50 000 au plus. O(f) pour un dossier,
    /// O(octets) pour l'empreinte d'un fichier, lu par blocs de 1 Mio.
    static func info(_ path: String, files: FileManager = .default) throws -> Info {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .localizedTypeDescriptionKey, .fileSizeKey,
                                                      .creationDateKey, .contentModificationDateKey, .isDirectoryKey])
        let type = values.contentType ?? .data
        var size = Int64(values.fileSize ?? 0)
        var hash: String?
        if values.isDirectory == true {
            size = folderSize(url, files: files)
        } else {
            hash = try sha256(path)
        }
        return Info(kind: values.localizedTypeDescription ?? type.identifier, typeIdentifier: type.identifier,
                    mimeType: type.preferredMIMEType, size: size, created: values.creationDate,
                    modified: values.contentModificationDate, sha256: hash)
    }

    private static func folderSize(_ url: URL, files: FileManager) -> Int64 {
        guard let walker = files.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let item as URL in walker {
            count += 1
            if count > 50_000 { break }
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Empreinte SHA-256 en hexadécimal, lue par blocs. O(octets).
    static func sha256(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Étiquettes du Finder d'un élément. O(1).
    static func tags(_ path: String) -> [String] {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    /// Ajoute l'étiquette à chaque source, ou la retire si toutes l'ont déjà, comme une case à cocher. O(s).
    static func toggleTag(_ tag: String, on sources: [String]) -> Report {
        var report = Report()
        let remove = !sources.isEmpty && sources.allSatisfy { tags($0).contains(tag) }
        for source in sources {
            var current = tags(source)
            if remove { current.removeAll { $0 == tag } } else if !current.contains(tag) { current.append(tag) }
            do {
                try (URL(fileURLWithPath: source) as NSURL).setResourceValue(current, forKey: .tagNamesKey)
                report.done.append(source)
            } catch {
                report.failures[source] = error.localizedDescription
            }
        }
        return report
    }

    /// Étiquettes proposées : celles de l'élément d'abord, puis les couleurs du Finder, sans doublon. O(t).
    static func tagChoices(for sources: [String], finderLabels: [String] = NSWorkspace.shared.fileLabels) -> [String] {
        var seen = Set<String>()
        let present = sources.flatMap(tags)
        return (present + finderLabels.filter { !$0.isEmpty && $0 != "None" && $0 != tr("Aucune", "None") })
            .filter { seen.insert($0).inserted }
    }

    /// Fichiers placés dans le presse-papiers, collables dans le Finder. O(s).
    static func copyToPasteboard(_ paths: [String], pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
    }

    /// Paquet (application, bibliothèque…) : un dossier que le Finder montre comme un fichier. O(1).
    static func isPackage(_ path: String) -> Bool { NSWorkspace.shared.isFilePackage(atPath: path) }

    /// Applications qui savent ouvrir le fichier, l'application par défaut en premier. O(a).
    static func applications(for path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)
        let all = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seen = Set<String>()
        return ([preferred].compactMap { $0 } + all).map(\.path).filter { seen.insert($0).inserted }
    }
}

extension LauncherFileOperations {
    /// Dossiers proposés comme destination : le chemin tapé s'il désigne un dossier, puis les dossiers habituels
    /// (dossier personnel, Bureau, Documents, Téléchargements), puis les dossiers récents ; sans doublon ni dossier
    /// d'une source. Titre : nom du dossier ; détail : son emplacement abrégé. O(r).
    static func folderDestinations(typed: String, recent: [String], excluding sources: [String] = [],
                                   home: String = NSHomeDirectory(),
                                   isFolder: (String) -> Bool = { path in
                                       var directory: ObjCBool = false
                                       return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
                                   }) -> [LauncherDestination] {
        let standard = ["", "Desktop", "Documents", "Downloads"].map { $0.isEmpty ? home : (home as NSString).appendingPathComponent($0) }
        var candidates: [String] = []
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            candidates.append(((trimmed as NSString).expandingTildeInPath as NSString).standardizingPath)
        }
        candidates += standard + recent
        let sourceFolders = Set(sources.map { ($0 as NSString).deletingLastPathComponent })
        var seen = Set<String>()
        return candidates.compactMap { path in
            let clean = (path as NSString).standardizingPath
            guard !sourceFolders.contains(clean), isFolder(clean), seen.insert(clean).inserted else { return nil }
            let name = clean == home ? (clean as NSString).lastPathComponent : FileManager.default.displayName(atPath: clean)
            let parent = ((clean as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
            return LauncherDestination(kind: .folder(clean), title: name, detail: parent,
                                       aliases: [(clean as NSString).abbreviatingWithTildeInPath, clean])
        }
    }

    /// Applications qui ouvrent le premier fichier, l'application par défaut en premier. O(a).
    static func applicationDestinations(for paths: [String]) -> [LauncherDestination] {
        guard let first = paths.first else { return [] }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: first))?.path
        return applications(for: first).map { path in
            let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            return LauncherDestination(kind: .application(path), title: name, detail: path == preferred ? tr("par défaut", "default") : "")
        }
    }

    /// Étiquettes proposées : cochées si tous les fichiers l'ont déjà (le choix la retire). O(t).
    static func tagDestinations(for paths: [String]) -> [LauncherDestination] {
        tagChoices(for: paths).map { tag in
            let present = !paths.isEmpty && paths.allSatisfy { tags($0).contains(tag) }
            return LauncherDestination(kind: .tag(tag), title: tag, detail: present ? tr("✓ retirer", "✓ remove") : "")
        }
    }
}
