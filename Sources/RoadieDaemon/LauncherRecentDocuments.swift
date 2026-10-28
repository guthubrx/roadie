import Foundation

/// Documents récents d'une application (session 116), comme « Recent Documents » d'Alfred : le menu
/// Fichier > Ouvrir récent de macOS, lu sans ouvrir l'application ni les fichiers.
/// - macOS : `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/
///   <identifiant en minuscules>.sfl4` (`.sfl3`, `.sfl2` avant), archive `NSKeyedArchiver` dont chaque élément porte un
///   signet de fichier (`Bookmark`), le plus récent d'abord.
/// - Microsoft Office : sa liste macOS reste vide ; ses documents sont dans `<identifiant>.securebookmarks.plist` de son
///   conteneur, avec leur date d'usage. Lu seulement pour les applications `com.microsoft.*`, à la demande : macOS peut
///   demander l'accès aux données d'une autre application.
enum LauncherRecentDocuments {
    struct Document: Equatable, Sendable {
        let path: String
        let lastUsed: Date?
        var name: String { (path as NSString).lastPathComponent }
    }

    static let limit = 20

    /// Destinations de la troisième étape : nom, dossier abrégé en `~`. O(n).
    static func destinations(_ documents: [Document]) -> [LauncherDestination] {
        documents.map { LauncherDestination(kind: .document($0.path), title: $0.name,
                                            detail: LauncherList.shortPath(($0.path as NSString).deletingLastPathComponent)) }
    }

    /// Documents qui existent encore, sans doublon, 20 au plus : Office par date d'usage, puis la liste de macOS.
    /// O(n) signets lus sans résolution.
    static func documents(bundleID: String, home: String = NSHomeDirectory(),
                          exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Document] {
        var seen: Set<String> = []
        var result: [Document] = []
        for document in office(bundleID: bundleID, home: home) + shared(bundleID: bundleID, home: home)
        where result.count < limit && exists(document.path) && seen.insert(document.path).inserted {
            result.append(document)
        }
        return result
    }

    /// Liste de macOS : la version la plus récente du fichier qui existe. O(n).
    static func shared(bundleID: String, home: String) -> [Document] {
        let folder = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments")
        for suffix in ["sfl4", "sfl3", "sfl2"] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(bundleID.lowercased()).\(suffix)")) else { continue }
            return sharedList(data)
        }
        return []
    }

    /// Éléments d'une archive `.sfl` : chemin lu dans le signet sans le résoudre (rien n'est monté ni ouvert). O(n).
    static func sharedList(_ data: Data) -> [Document] {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return [] }
        unarchiver.requiresSecureCoding = false
        let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any]
        unarchiver.finishDecoding()
        let items = root?["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let bookmark = item["Bookmark"] as? Data,
                  let path = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path else { return nil }
            return Document(path: path, lastUsed: nil)
        }
    }

    /// Liste d'Office, la plus récente d'abord. O(n log n).
    static func office(bundleID: String, home: String) -> [Document] {
        guard bundleID.lowercased().hasPrefix("com.microsoft.") else { return [] }
        let file = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).securebookmarks.plist")
        guard let plist = NSDictionary(contentsOf: file) as? [String: Any] else { return [] }
        return officeList(plist)
    }

    /// Clés : adresses `file://` ; valeur : `kLastUsedDateKey`. O(n log n).
    static func officeList(_ plist: [String: Any]) -> [Document] {
        plist.compactMap { key, value -> Document? in
            guard let url = URL(string: key), url.isFileURL else { return nil }
            return Document(path: url.path, lastUsed: (value as? [String: Any])?["kLastUsedDateKey"] as? Date)
        }
        .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }
}
