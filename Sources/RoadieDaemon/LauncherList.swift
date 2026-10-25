import Foundation

/// Liste du lanceur dans la barre de recherche (SPEC-073), logique pure. Sections fixes :
/// Applications, Fenêtres, Stages et bureaux, À l'écran (cibles du mode recherche). Chaque section
/// est triée par le classement appris puis par l'appariement ; la sélection par défaut est la
/// meilleure ligne de toutes les sections, pour que Retour fasse ce que l'utilisateur fait d'habitude.
struct LauncherList: Equatable, Sendable {
    enum Row: Equatable, Sendable {
        case header(String)
        case app(LauncherApp, detail: String)
        case target(RoadieTarget)
        case file(LauncherFile)
        /// Phrase reconnue (SPEC-079) : l'action et ce qu'elle annonce.
        case phrase(LauncherAction, String)
        /// Abréviation tapée (SPEC-079) : son nom, l'action, ce qu'elle annonce.
        case alias(String, LauncherAction, String)

        /// Identité unique d'une ligne choisissable : sert à la sélection.
        var id: String? {
            switch self {
            case .header: nil
            case .app(let app, _): app.rankingKey
            case .target(let target): "target:\(target.id)"
            case .file(let file): file.rankingKey
            case .phrase: "phrase"
            case .alias(let name, _, _): "alias:\(name)"
            }
        }

        /// Clé du classement appris, partagée par les fenêtres d'une même application.
        var rankingKey: String? {
            switch self {
            case .header: nil
            case .app(let app, _): app.rankingKey
            case .target(let target): LauncherList.rankingKey(target)
            case .file(let file): file.rankingKey
            case .phrase(let action, _), .alias(_, let action, _): action.subject.rankingKey
            }
        }
    }

    enum Section: Int, CaseIterable, Sendable {
        case applications, windows, files, places, screen

        var title: String {
            switch self {
            case .applications: "Applications"
            case .windows: "Fenêtres"
            case .files: "Fichiers"
            case .places: "Stages et bureaux"
            case .screen: "À l'écran"
            }
        }

        /// Lignes montrées au plus : la barre garde une hauteur raisonnable.
        var limit: Int {
            switch self {
            case .applications, .windows: 4
            case .files: 5
            case .places, .screen: 3
            }
        }

        static func of(_ kind: TargetKind) -> Section {
            switch kind {
            case .window: .windows
            case .stage, .desktop, .display, .bookmark: .places
            case .appElement, .gridCell: .screen
            }
        }
    }

    private(set) var rows: [Row] = []
    /// Identité de la meilleure ligne, nil sans résultat.
    private(set) var best: String?

    static let empty = LauncherList(query: "", apps: [], details: [:], targets: [], ranking: LauncherRanking(), now: Date())

    /// État affiché à côté d'une application (ouverte, stage et bureau de sa fenêtre).
    static func detail(running: Bool, location: String?) -> String {
        guard running else { return "Application" }
        return location.map { "Ouverte · \($0)" } ?? "Ouverte"
    }

    /// Emplacement d'une application fermée, dossier personnel abrégé en `~`, comme Alfred.
    static func shortPath(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// Clé d'une cible : type et titre ; le titre d'une fenêtre est le nom de son application.
    static func rankingKey(_ target: RoadieTarget) -> String { "target:\(target.kind.rawValue):\(target.title)" }

    /// `targets` : correspondances du mode recherche, déjà filtrées et ordonnées. `details` : état des
    /// applications par identifiant. O(a × q × t + n log n), a applications, n lignes retenues.
    /// `context` : stage active (SPEC-076) ; ses choix passent avant ceux faits ailleurs. `files` : réponses de
    /// Spotlight, les plus récentes d'abord (SPEC-077) ; une espace en tête ne garde qu'elles.
    init(query rawQuery: String, apps: [LauncherApp], details: [String: String], targets: [RoadieTarget],
         ranking: LauncherRanking, now: Date, context: String? = nil, files: [LauncherFile] = []) {
        let filesOnly = LauncherFileRules.filesOnly(rawQuery)
        let query = filesOnly ? LauncherFileRules.needle(rawQuery) : rawQuery
        guard !LauncherMatch.fold(query).isEmpty else { return }
        struct Candidate { let row: Row; let id: String; let key: String; let section: Section; let score: Int; let name: String; var order = 0 }
        var candidates: [Candidate] = []
        for (order, file) in files.enumerated() {
            // Spotlight a trouvé le nom par « contient » : retenu même si l'appariement est faible.
            let score = LauncherMatch.score(query, in: file.name) ?? 1
            candidates.append(Candidate(row: .file(file), id: file.rankingKey, key: file.rankingKey, section: .files,
                                        score: score, name: file.name, order: order))
        }
        for app in filesOnly ? [] : apps {
            let score = ([app.name] + app.alternateNames).compactMap { LauncherMatch.score(query, in: $0) }.max()
                ?? (ranking.exactUses(app.rankingKey, query: query) > 0 ? 1 : nil)
            guard let score else { continue }
            candidates.append(Candidate(row: .app(app, detail: details[app.bundleID] ?? Self.shortPath(app.path)), id: app.rankingKey, key: app.rankingKey,
                                        section: .applications, score: score, name: app.name))
        }
        for target in filesOnly ? [] : targets {
            // Trouvée par le texte de ses enfants seulement (lien web) : retenue, en dernier.
            let score = [target.title, target.subtitle].compactMap { LauncherMatch.score(query, in: $0) }.max() ?? 1
            candidates.append(Candidate(row: .target(target), id: "target:\(target.id)", key: Self.rankingKey(target),
                                        section: Section.of(target.kind), score: score, name: target.title))
        }
        // Ordre : choix appris pour cette requête dans cette stage, puis partout, puis pour une requête
        // plus longue, puis l'appariement, puis la fréquence-récence dans cette stage, puis partout,
        // puis la section et le nom (SPEC-076 R1).
        func before(_ a: Candidate, _ b: Candidate) -> Bool {
            let local = (ranking.exactUses(a.key, query: query, context: context), ranking.exactUses(b.key, query: query, context: context))
            if local.0 != local.1 { return local.0 > local.1 }
            let exact = (ranking.exactUses(a.key, query: query), ranking.exactUses(b.key, query: query))
            if exact.0 != exact.1 { return exact.0 > exact.1 }
            let prefix = (ranking.prefixUses(a.key, query: query), ranking.prefixUses(b.key, query: query))
            if prefix.0 != prefix.1 { return prefix.0 > prefix.1 }
            if a.score != b.score { return a.score > b.score }
            let here = (ranking.frecency(a.key, at: now, context: context), ranking.frecency(b.key, at: now, context: context))
            if here.0 != here.1 { return here.0 > here.1 }
            let used = (ranking.frecency(a.key, at: now), ranking.frecency(b.key, at: now))
            if used.0 != used.1 { return used.0 > used.1 }
            // Fichiers : l'ordre de Spotlight, du plus récemment utilisé au plus ancien.
            if a.order != b.order { return a.order < b.order }
            if a.section != b.section { return a.section.rawValue < b.section.rawValue }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let grouped = Dictionary(grouping: candidates, by: \.section)
        var bestCandidate: Candidate?
        for section in Section.allCases {
            // Cibles à l'écran : l'ordre du mode recherche (écran du pointeur d'abord) est gardé.
            let all = grouped[section] ?? []
            guard !all.isEmpty else { continue }
            let sorted = section == .screen ? all : all.sorted(by: before)
            let shown = sorted.prefix(section.limit)
            rows.append(.header(section == .screen ? "\(section.title) · \(all.count)" : section.title))
            rows.append(contentsOf: shown.map(\.row))
            if let top = section == .screen ? all.min(by: before) : shown.first,
               bestCandidate.map({ before(top, $0) }) ?? true {
                bestCandidate = top
            }
        }
        // Meilleure cible à l'écran hors des lignes montrées : ajoutée à sa section pour rester visible.
        if let bestCandidate, !rows.contains(where: { $0.id == bestCandidate.id }) {
            rows.append(bestCandidate.row)
        }
        best = bestCandidate?.id
    }

    /// Ligne choisissable suivante (`step` = 1) ou précédente (-1), en boucle ; nil sans ligne. O(n).
    func neighbour(of id: String?, step: Int) -> String? {
        let ids = rows.compactMap(\.id)
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return step > 0 ? ids.first : ids.last }
        return ids[(index + step + ids.count) % ids.count]
    }

    func row(for id: String?) -> Row? { id.flatMap { id in rows.first { $0.id == id } } }

    /// Phrase ou abréviation en tête, sous son titre, et choisie par défaut (SPEC-079). O(n).
    mutating func prepend(_ row: Row, header: String) {
        rows.insert(contentsOf: [.header(header), row], at: 0)
        best = row.id
    }
}
