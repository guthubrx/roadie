import Foundation

/// Filtre de fichiers d'un workflow (SPEC-089 FR-006, research R4) : requête Spotlight traduite pour
/// `mdfind`, lancée comme un script (processus annulable, délai, plafond), réponse en lignes de fichiers.
enum AlfredFileFilter {
    static let defaultLimit = 40

    /// Requête Spotlight : champs en « ou » (« * » : tous les attributs), types (arborescence UTI) en
    /// « ou », les deux reliés par « et ». Guillemets de la saisie échappés. O(f + t).
    static func query(_ object: AlfredObject, argument: String) -> String {
        let text = argument.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var fields: [String] = []
        for case .dict(let field) in object.config["fields"]?.array ?? [] {
            let name = field["field"]?.string ?? "kMDItemDisplayName"
            let value = (field["value"]?.string ?? "{query}").replacingOccurrences(of: "{query}", with: text)
            let flags = "cd" + ((field["words"]?.bool ?? false) ? "w" : "")
            let clause = "\(name) == \"*\(value)*\"\(flags)"
            fields.append((field["not"]?.bool ?? false) ? "!(\(clause))" : clause)
        }
        if fields.isEmpty { fields = ["kMDItemDisplayName == \"*\(text)*\"cd"] }
        let types = (object.config["types"]?.array ?? []).compactMap(\.string).map { "kMDItemContentTypeTree == \"\($0)\"" }
        let named = "(" + fields.joined(separator: " || ") + ")"
        return types.isEmpty ? named : "\(named) && (\(types.joined(separator: " || ")))"
    }

    /// Script bash : `mdfind` dans les portées du workflow (dossier personnel sinon), limité. O(1).
    static func script(_ object: AlfredObject, argument: String) -> AlfredScript? {
        guard !argument.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let scopes = (object.config["scopes"]?.array ?? []).compactMap(\.string).map { NSString(string: $0).expandingTildeInPath }
        let limit = (object.int("limit") ?? 0) > 0 ? object.int("limit")! : defaultLimit
        let onlyIn = (scopes.isEmpty ? [NSHomeDirectory()] : scopes).map { "-onlyin \(shellQuoted($0))" }.joined(separator: " ")
        let source = "/usr/bin/mdfind \(onlyIn) \(shellQuoted(query(object, argument: argument))) | /usr/bin/head -n \(limit)"
        return AlfredScript(language: 0, source: source)
    }

    /// Une ligne par chemin : nom, dossier, icône du fichier, chemin en argument, aperçu possible.
    static func response(_ output: String) -> AlfredScriptFilterResponse {
        var response = AlfredScriptFilterResponse()
        response.items = output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }.map { path in
            var item = AlfredItem(uid: path, title: (path as NSString).lastPathComponent)
            item.subtitle = LauncherList.shortPath((path as NSString).deletingLastPathComponent)
            item.arg = [path]
            item.icon = .fileIcon(path)
            item.isFile = true
            item.quickLookURL = path
            return item
        }
        return response
    }

    static func shellQuoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
