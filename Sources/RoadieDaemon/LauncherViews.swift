import Foundation
import RoadieCore

/// Présentation des résultats de la barre (session 099) : liste, grille ou grandes tuiles.
enum LauncherViewMode: String, Codable, Equatable, Sendable, CaseIterable {
    case list, grid, large

    /// Présentation suivante : liste → grille → grandes tuiles → liste. O(1).
    var next: LauncherViewMode {
        switch self {
        case .list: .grid
        case .grid: .large
        case .large: .list
        }
    }

    /// Icône du chip.
    var symbol: String {
        switch self {
        case .list: "☰"
        case .grid: "▦"
        case .large: "▣"
        }
    }

    var title: String {
        switch self {
        case .list: tr("Liste", "List")
        case .grid: tr("Grille", "Grid")
        case .large: tr("Grandes tuiles", "Large tiles")
        }
    }

    /// Colonnes ; nil pour la liste.
    var columns: Int? {
        switch self {
        case .list: nil
        case .grid: 7
        case .large: 4
        }
    }
}

/// Résultats dont la présentation se choisit (FR-001) : un workflow, un dossier exploré ou les fichiers
/// de la recherche. `namesInFooter` : nom de la tuile choisie en pied (émojis) plutôt que sous chaque tuile.
struct LauncherViewSource: Equatable, Sendable {
    let key: String
    let namesInFooter: Bool

    static func workflow(_ entryID: String, itemsAreFiles: Bool) -> Self { Self(key: "wf:\(entryID)", namesInFooter: !itemsAreFiles) }
    static func folder(_ directory: String) -> Self { Self(key: "path:\(directory)", namesInFooter: false) }
    static let files = Self(key: "files", namesInFooter: false)
    /// Grille Apps (session 131, Launchpad d'Alfred 6) : en grille tant que l'utilisateur n'a rien choisi.
    static let apps = Self(key: "apps", namesInFooter: false)

    /// Lignes montrées dans une grille : sans titres de section ; pour les fichiers de la recherche, les
    /// fichiers seuls (applications et fenêtres restent dans la liste). O(n).
    func gridRows(_ rows: [LauncherList.Row]) -> [LauncherList.Row] {
        rows.filter { row in
            switch row {
            case .header: false
            case .file: true
            default: key != Self.files.key
            }
        }
    }
}

/// Présentations retenues par source (FR-007) : `~/.roadies/launcher-views.json`, 500 sources au plus,
/// les moins récemment choisies partent d'abord.
struct LauncherViewBook: Codable, Equatable, Sendable {
    struct Choice: Codable, Equatable, Sendable {
        var mode: LauncherViewMode
        var at: Date
    }

    static let maxSources = 500
    var choices: [String: Choice] = [:]

    func mode(for source: LauncherViewSource?) -> LauncherViewMode {
        source.flatMap { choices[$0.key]?.mode } ?? (source == .apps ? .grid : .list)
    }

    /// Retient le choix ; au-delà de la borne, le plus ancien part. O(s) au dépassement, O(1) sinon.
    mutating func set(_ mode: LauncherViewMode, for source: LauncherViewSource, at now: Date = Date()) {
        choices[source.key] = Choice(mode: mode, at: now)
        if choices.count > Self.maxSources, let oldest = choices.min(by: { $0.value.at < $1.value.at }) {
            choices[oldest.key] = nil
        }
    }
}

struct LauncherViewStore: Sendable {
    let url: URL

    init(url: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".roadies/launcher-views.json")) {
        self.url = url
    }

    func load() -> LauncherViewBook {
        guard let data = try? Data(contentsOf: url) else { return LauncherViewBook() }
        return (try? JSONDecoder.roadieViews.decode(LauncherViewBook.self, from: data)) ?? LauncherViewBook()
    }

    func save(_ book: LauncherViewBook) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.roadieViews.encode(book) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension JSONDecoder {
    static var roadieViews: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var roadieViews: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
}

/// Place de la barre déplacée à la souris (session 102) : centre en fractions de l'écran. Absente : place
/// par défaut de `bar_position`.
struct LauncherPositionStore: Sendable {
    private struct Saved: Codable { var x: Double; var y: Double }
    let path: String

    init(path: String = TestEnvironment.launcherFile("launcher-position.json")) {
        self.path = NSString(string: path).expandingTildeInPath
    }

    func load() -> SearchBarPlacement? {
        guard let data = FileManager.default.contents(atPath: path),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        return .custom(x: min(1, max(0, saved.x)), y: min(1, max(0, saved.y)))
    }

    /// nil efface la place retenue.
    func save(_ placement: SearchBarPlacement?) {
        guard case .custom(let x, let y)? = placement else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Saved(x: Double(x), y: Double(y))) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// Défilement de la barre (session 131) : points de défilement accumulés, convertis en pas de sélection. Positif :
/// vers le haut (ligne précédente), comme le contenu suit les doigts. O(1).
enum LauncherScroll {
    static let step = 22.0

    static func steps(accumulated: Double, delta: Double) -> (steps: Int, rest: Double) {
        let total = accumulated + delta
        let steps = Int(total / step)
        return (steps, total - Double(steps) * step)
    }
}
