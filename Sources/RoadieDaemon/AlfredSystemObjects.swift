import AppKit
import CoreServices
import Foundation
import RoadieCore

/// Briques d'Alfred liées au système (session 131) : Commande système, Commande Musique, Recherche dans le
/// dictionnaire, Filtre des applications ouvertes. Numéros relevés dans des workflows publics (research R2, R3) ; un
/// numéro hors table est refusé, jamais deviné. Logique pure, sauf la lecture du dictionnaire et des applications.
enum AlfredSystemObjects {
    /// `action.systemcommand` : numéro d'Alfred → identifiant de `LauncherSystemCommand`. O(1).
    static func systemCommandID(_ number: Int) -> String? {
        [1: "screensaver", 2: "show-trash", 3: "empty-trash", 4: "logout", 5: "sleep", 6: "lock", 7: "restart", 8: "shutdown",
         9: "quit-all", 10: "eject-all", 11: "sleep-displays", 12: "volume-up", 13: "volume-down", 14: "mute"][number]
    }

    /// `action.itunescommand` : numéro d'Alfred → script AppleScript pour Musique ; nil pour un numéro inconnu. O(1).
    static func musicScript(_ number: Int) -> String? {
        let body: String
        switch number {
        case 0: body = "activate"
        case 1: body = "playpause"
        case 2: body = "next track"
        case 3: body = "previous track"
        case 4: body = "set shuffle enabled to true\nplay library playlist 1"
        case 6: body = "set sound volume to (sound volume + 10)"
        case 7: body = "set sound volume to (sound volume - 10)"
        case 9...13: body = "set rating of current track to \((number - 8) * 20)"
        default: return nil
        }
        return "tell application \"Music\"\n\(body)\nend tell"
    }

    // MARK: Dictionnaire

    /// Définition du mot dans les dictionnaires actifs de macOS ; nil si aucun ne le connaît. O(1) appel.
    static func definition(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = CFRange(location: 0, length: (trimmed as NSString).length)
        return DCSCopyTextDefinition(nil, trimmed as CFString, range)?.takeRetainedValue() as String?
    }

    /// Lignes du dictionnaire : le mot tapé, puis, avec `showAllWords`, les mots qui le complètent (9 au plus) ;
    /// sous-titre : début de la définition. `definition` et `completions` sont injectables pour les tests. O(w).
    @MainActor
    static func dictionaryItems(_ query: String, showAllWords: Bool,
                                definition: (String) -> String? = AlfredSystemObjects.definition,
                                completions: @MainActor (String) -> [String] = AlfredSystemObjects.completions) -> [AlfredItem] {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        var words = [word]
        if showAllWords { words += completions(word).filter { $0.caseInsensitiveCompare(word) != .orderedSame }.prefix(9) }
        return words.map { candidate in
            var item = AlfredItem(uid: "dict:\(candidate)", title: candidate)
            item.subtitle = definition(candidate).map(firstLine) ?? tr("Aucune définition", "No definition")
            item.arg = [candidate]
            item.quickLookURL = "dict://\(candidate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? candidate)"
            return item
        }
    }

    /// Mots qui complètent le début tapé, par le correcteur de macOS. O(1) appel.
    @MainActor
    static func completions(_ prefix: String) -> [String] {
        let checker = NSSpellChecker.shared
        return checker.completions(forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length), in: prefix,
                                   language: nil, inSpellDocumentWithTag: 0) ?? []
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 140 ? String(line.prefix(139)) + "…" : line
    }

    // MARK: Applications ouvertes

    struct RunningApp: Equatable, Sendable {
        let name: String
        let path: String
        let bundleID: String
    }

    /// Applications ordinaires ouvertes. O(a).
    @MainActor
    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { app in
            guard let path = app.bundleURL?.path else { return nil }
            return RunningApp(name: app.localizedName ?? (path as NSString).lastPathComponent, path: path, bundleID: app.bundleIdentifier ?? "")
        }
    }

    /// Lignes du filtre : applications dont le nom correspond, meilleure correspondance d'abord. Argument : chemin
    /// (`outputtype` 0), nom (1) ou identifiant (2), précédé de `outputprefix`. O(a × t + a log a).
    static func runningAppItems(_ query: String, apps: [RunningApp], outputType: Int, prefix: String) -> [AlfredItem] {
        let scored: [(app: RunningApp, score: Int)] = apps.compactMap { app in
            if query.trimmingCharacters(in: .whitespaces).isEmpty { return (app, 0) }
            return LauncherMatch.score(query, in: app.name).map { (app, $0) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.app.name < $1.app.name }.map { entry in
            var item = AlfredItem(uid: "app:\(entry.app.bundleID)", title: entry.app.name)
            item.subtitle = (entry.app.path as NSString).abbreviatingWithTildeInPath
            item.icon = .fileIcon(entry.app.path)
            let value = switch outputType {
            case 1: entry.app.name
            case 2: entry.app.bundleID
            default: entry.app.path
            }
            item.arg = [prefix + value]
            return item
        }
    }
}
