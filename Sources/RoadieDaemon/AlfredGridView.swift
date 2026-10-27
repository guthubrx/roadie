import Foundation

/// Grille d'un workflow (SPEC-092) : tuiles, réglages d'affichage de la brique `userinterface.grid`,
/// variables du schéma au moment de la grille. La barre l'affiche ; Retour repart de la grille avec la
/// tuile choisie (entrée de genre `.grid`, `objectUID` = la brique).
struct AlfredGridView: Equatable, Sendable {
    var entry: AlfredEntry
    var columns: Int
    var showTitles = true
    var showSubtitles = true
    var titlesInFooter = false
    var subtitlesInFooter = false
    var filterable = true
    var items: [AlfredItem]
    var preselect: String?
    var variables: [String: String]

    /// `columncount` borné de 1 à 12 ; 5 sans réglage.
    static func columns(_ value: Int?) -> Int { min(12, max(1, value ?? 5)) }

    /// Une tuile se choisit au clavier si elle a un titre ou une icône : les espaceurs d'Alfred
    /// (titre vide, sans icône) restent vides. O(1).
    static func isSelectable(_ item: AlfredItem) -> Bool {
        !item.title.trimmingCharacters(in: .whitespaces).isEmpty || item.icon != nil
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"]

    /// Liste de chemins (source « objet », research R8) : un par argument ou par ligne ; une image
    /// montre son contenu, un autre fichier son icône. O(n).
    static func fileItems(_ arguments: [String]) -> [AlfredItem] {
        arguments.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { raw in
                let path = NSString(string: raw).expandingTildeInPath
                let isImage = imageExtensions.contains((path as NSString).pathExtension.lowercased())
                var item = AlfredItem(title: (path as NSString).lastPathComponent, subtitle: (path as NSString).abbreviatingWithTildeInPath,
                                      arg: [path], icon: isImage ? .image(path) : .fileIcon(path))
                item.isFile = true
                item.quickLookURL = path
                return item
            }
    }

    /// Vue d'une brique Grille : réglages de l'objet (surcharge comprise), tuiles d'une réponse JSON
    /// ou d'une liste de chemins. O(n).
    static func make(object: AlfredObject, workflow: AlfredWorkflow, response: AlfredScriptFilterResponse,
                     variables: [String: String]) -> AlfredGridView {
        var entry = AlfredEntry(workflowID: workflow.id, workflowName: workflow.name, objectUID: object.uid, kind: .grid, keyword: "",
                                withSpace: false, argument: .none, title: workflow.name, subtitle: "", icon: workflow.icon(for: object.uid))
        entry.folder = workflow.folder.path
        entry.filtersResults = object.config["filterable"]?.bool ?? true
        // Filtre de la grille : mots dans n'importe quel ordre (aide d'Alfred, research R1).
        entry.filterMode = 2
        return AlfredGridView(entry: entry, columns: columns(object.int("columncount")),
                              showTitles: object.config["showtitles"]?.bool ?? true,
                              showSubtitles: object.config["showsubtitles"]?.bool ?? true,
                              titlesInFooter: object.bool("titlesinfooter"), subtitlesInFooter: object.bool("subtitlesinfooter"),
                              filterable: entry.filtersResults, items: response.items, preselect: response.preselect,
                              variables: variables.merging(response.variables) { $1 })
    }

    /// Tuile voisine choisissable : rang ± 1 (← →) ou ± colonnes (↑ ↓), espaceurs sautés ; nil au bord.
    /// O(n / |step|) au pire, n tuiles.
    static func neighbour(of index: Int, step: Int, count: Int, selectable: (Int) -> Bool) -> Int? {
        guard step != 0 else { return nil }
        var next = index + step
        while next >= 0, next < count {
            if selectable(next) { return next }
            next += step
        }
        return nil
    }
}
