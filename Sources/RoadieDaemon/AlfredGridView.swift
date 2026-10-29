import Foundation
import RoadieCore

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
    /// Largeur sur hauteur de l'image d'une tuile (`imageaspect`, session 112) : 1 carré, 2/3 portrait, 3/2 paysage.
    var imageAspect: Double = 1
    /// « Sorting » d'Alfred : vrai si l'ordre est appris à l'usage (`fixedorder` faux et la réponse ne
    /// demande pas `skipknowledge`) ; seules les tuiles qui ont un `uid` changent de place (session 094).
    var learnsOrder = false
    var items: [AlfredItem]
    var preselect: String?
    var variables: [String: String]
    /// Texte d'attente (« Loading Text » d'Alfred, session 095) : non nil tant que le script de la
    /// grille tourne, ou message d'échec ; la barre montre alors cette ligne au lieu des tuiles.
    var loadingText: String?
    /// Vue d'attente : elle ouvre la barre ; la vue suivante (tuiles ou échec) remplace la grille ouverte.
    var isWaiting = false

    /// Texte d'attente d'une brique : le sien, sinon « Loading… ».
    static func loadingText(_ object: AlfredObject) -> String {
        let text = (object.string("loadingtext") ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? tr("Chargement…", "Loading…") : text
    }

    /// `imageaspect` d'Alfred : 0 Carré, 1 Portrait, 2 Paysage, dans l'ordre du menu de la brique Grille
    /// (Alfred 5, `AlfredWorkflowUserInterfaceGrid.nib`) ; carré pour une autre valeur. O(1).
    static func imageAspect(_ value: Int?) -> Double {
        switch value {
        case 1: 2.0 / 3
        case 2: 3.0 / 2
        default: 1
        }
    }

    /// `columncount` borné de 1 à 12 ; 5 sans réglage.
    static func columns(_ value: Int?) -> Int { min(12, max(1, value ?? 5)) }

    /// Une tuile se choisit au clavier si elle a un titre ou une icône : les espaceurs d'Alfred
    /// (titre vide, sans icône) restent vides. O(1).
    static func isSelectable(_ item: AlfredItem) -> Bool {
        !item.title.trimmingCharacters(in: .whitespaces).isEmpty || item.icon != nil
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"]

    /// Fichier image, montré par son contenu dans une grille. O(1).
    static func isImage(_ path: String) -> Bool { imageExtensions.contains((path as NSString).pathExtension.lowercased()) }

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
                              filterable: entry.filtersResults, imageAspect: imageAspect(object.int("imageaspect")),
                              learnsOrder: !(object.config["fixedorder"]?.bool ?? false) && !response.skipKnowledge,
                              items: response.items, preselect: response.preselect,
                              variables: variables.merging(response.variables) { $1 })
    }

    /// Ordre appris d'une grille (« Sorting » d'Alfred, session 094) : tuiles à `uid` d'abord par choix
    /// après cette saisie, ou, sans saisie, par fréquence-récence (un choix sans saisie n'enregistre
    /// aucune abréviation) ; ordre du script sinon (tri stable). O(n log n).
    static func learned(_ items: [AlfredItem], entryID: String, ranking: LauncherRanking, query: String, now: Date = Date()) -> [AlfredItem] {
        let typed = !LauncherMatch.fold(query).isEmpty
        func score(_ item: AlfredItem) -> Double {
            guard let uid = item.uid else { return 0 }
            let key = "\(entryID):\(uid)"
            return typed ? Double(ranking.exactUses(key, query: query)) : ranking.frecency(key, at: now) - 1
        }
        return items.enumerated().map { ($0.offset, $0.element, score($0.element)) }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
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
