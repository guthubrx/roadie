import AppKit
import Foundation
import RoadieAX

/// Fichier ou dossier trouvé par Spotlight pour le lanceur (SPEC-077).
struct LauncherFile: Equatable, Hashable, Sendable {
    let path: String
    let name: String
    let isFolder: Bool
    let lastUsed: Date?

    var rankingKey: String { "file:\(path)" }
    /// Dossier qui le contient, abrégé en `~`.
    var location: String { LauncherList.shortPath((path as NSString).deletingLastPathComponent) }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Règles de la recherche de fichiers, pures et testables. O(1) par chemin.
enum LauncherFileRules {
    /// Familles montrées par défaut, comme les « Extras » d'Alfred : dossiers, documents, textes, images.
    static let contentTypes = ["public.folder", "public.text", "public.image", "com.adobe.pdf",
                               "public.composite-content", "public.spreadsheet", "public.presentation"]
    static let limit = 40

    /// Saisie qui ne cherche que des fichiers : une espace ou une apostrophe en tête (recherche rapide).
    static func filesOnly(_ query: String) -> Bool { query.hasPrefix(" ") || query.hasPrefix("'") }

    /// Texte cherché : sans le préfixe de recherche rapide ni les espaces autour.
    static func needle(_ query: String) -> String {
        var text = query
        if filesOnly(text) { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 3 caractères au moins, 2 en recherche rapide : en deçà, trop de réponses pour être utiles.
    static func shouldSearch(_ query: String) -> Bool { needle(query).count >= (filesOnly(query) ? 2 : 3) }

    /// Dossier personnel hors `~/Library`, sans élément caché ni dépendances de projet.
    static func isShown(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        guard path.hasPrefix(home + "/"), !path.hasPrefix(home + "/Library/") else { return false }
        let relative = path.dropFirst(home.count + 1)
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "node_modules" }
    }

    static func predicate(_ needle: String) -> NSPredicate {
        let name = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(needle)*")
        let types = NSCompoundPredicate(orPredicateWithSubpredicates: contentTypes.map {
            NSPredicate(format: "kMDItemContentTypeTree == %@", $0)
        })
        return NSCompoundPredicate(andPredicateWithSubpredicates: [name, types])
    }

    /// Les plus récemment utilisés d'abord, puis par nom. O(f log f).
    static func ordered(_ files: [LauncherFile]) -> [LauncherFile] {
        files.sorted { a, b in
            if a.lastUsed != b.lastUsed { return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// Recherche Spotlight du lanceur : une requête à la fois, la précédente arrêtée, résultats rendus
/// sur le fil principal. 120 ms d'attente après la dernière frappe.
@MainActor
final class LauncherFileSearch {
    private var query: NSMetadataQuery?
    private var pending: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    func search(_ text: String, done: @escaping @MainActor ([LauncherFile]) -> Void) {
        cancel()
        guard LauncherFileRules.shouldSearch(text) else { done([]); return }
        let needle = LauncherFileRules.needle(text)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.start(needle, done: done) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func start(_ needle: String, done: @escaping @MainActor ([LauncherFile]) -> Void) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = LauncherFileRules.predicate(needle)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.query === query else { return }
                query.disableUpdates()
                var files: [LauncherFile] = []
                for index in 0..<query.resultCount where files.count < LauncherFileRules.limit {
                    guard let item = query.result(at: index) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          LauncherFileRules.isShown(path) else { continue }
                    let types = item.value(forAttribute: "kMDItemContentTypeTree") as? [String] ?? []
                    files.append(LauncherFile(path: path,
                                              name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? (path as NSString).lastPathComponent,
                                              isFolder: types.contains("public.folder"),
                                              lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date))
                }
                self.cancel()
                done(LauncherFileRules.ordered(files))
            }
        }
        self.query = query
        query.start()
    }
}

/// Fenêtre qui affiche déjà un fichier (SPEC-077 C). Lecture AX hors du fil principal, l'application par
/// défaut du fichier d'abord ; arrêt à la première trouvée. `exposing` : applications dont au moins une
/// fenêtre a donné un document, sans aucun chemin (relevé de compatibilité). O(w) lectures AX.
enum LauncherDocuments {
    static func window(showing path: String, in entries: [WindowSwitcherEntry],
                       preferredBundle: String?) async -> (window: WindowSwitcherEntry?, exposing: [String], scanned: String) {
        let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let groups = Dictionary(grouping: entries, by: \.window.pid)
            .sorted { ($0.value.first?.window.bundleID == preferredBundle ? 0 : 1) < ($1.value.first?.window.bundleID == preferredBundle ? 0 : 1) }
            .map(\.value)
        return await Task.detached(priority: .userInitiated) {
            var exposing: [String] = []
            // Fenêtres, éléments AX retrouvés, documents lus : de quoi voir où la chaîne s'arrête.
            var windows = 0, elementsFound = 0, documents = 0
            var statuses: [String: Int] = [:]
            for group in groups {
                guard let pid = group.first?.window.pid else { continue }
                let elements = axWindowElements(pid: pid)
                var exposes = false
                for entry in group {
                    windows += 1
                    guard let element = elements[CGWindowID(entry.id.rawValue)] else { continue }
                    elementsFound += 1
                    let read = axDocumentRead(element)
                    statuses["\(entry.window.bundleID):\(read.status)", default: 0] += 1
                    guard let document = read.path else { continue }
                    documents += 1
                    exposes = true
                    if document == target { return (entry, exposing, "\(windows)/\(elementsFound)/\(documents)") }
                }
                if exposes, let bundle = group.first?.window.bundleID { exposing.append(bundle) }
            }
            return (nil, exposing, "\(windows)/\(elementsFound)/\(documents) " + statuses.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        }.value
    }
}
