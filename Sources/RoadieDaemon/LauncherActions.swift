import Foundation
import RoadieCore

/// Grammaire objet → verbe → destination du lanceur (SPEC-074), logique pure.

/// L'objet choisi à la première étape.
enum LauncherSubject: Equatable, Sendable {
    case app(LauncherApp)
    case target(RoadieTarget)

    var title: String {
        switch self {
        case .app(let app): app.name
        case .target(let target): target.subtitle.isEmpty ? target.title : "\(target.title) · \(target.subtitle)"
        }
    }

    var rankingKey: String {
        switch self {
        case .app(let app): app.rankingKey
        case .target(let target): LauncherList.rankingKey(target)
        }
    }
}

/// Les verbes, regroupés par type d'objet. `needsDestination` : la troisième étape suit.
enum LauncherVerb: String, CaseIterable, Sendable {
    // Application
    case open, newWindow, openIn, gatherIn, hide, quit
    // Fenêtre
    case focus, sendTo, float, fullscreen, minimize, close
    // Stage, bureau
    case show, moveTo
    // Cible à l'écran
    case click, doubleClick, rightClick, commandClick

    var title: String {
        switch self {
        case .open: "Ouvrir ou aller à sa fenêtre"
        case .newWindow: "Nouvelle fenêtre ici"
        case .openIn: "Ouvrir dans…"
        case .gatherIn: "Réunir ses fenêtres dans…"
        case .hide: "Masquer l'application"
        case .quit: "Quitter l'application"
        case .focus: "Aller à la fenêtre"
        case .sendTo: "Envoyer vers…"
        case .float: "Faire flotter ou remettre au tuilage"
        case .fullscreen: "Plein écran"
        case .minimize: "Réduire"
        case .close: "Fermer la fenêtre"
        case .show: "Afficher"
        case .moveTo: "Déplacer vers…"
        case .click: "Clic"
        case .doubleClick: "Double-clic"
        case .rightClick: "Clic droit"
        case .commandClick: "Cmd-clic (nouvel onglet)"
        }
    }

    /// Titre court d'une ligne de destination directe : « Ouvrir dans Perso ».
    var destinationPrefix: String {
        switch self {
        case .openIn: "Ouvrir dans"
        case .gatherIn: "Réunir dans"
        case .sendTo: "Envoyer vers"
        case .moveTo: "Déplacer vers"
        default: title
        }
    }

    var needsDestination: Bool { [.openIn, .gatherIn, .sendTo, .moveTo].contains(self) }

    /// Verbes proposés pour un objet, le verbe par défaut en premier. O(1).
    static func verbs(for subject: LauncherSubject) -> [LauncherVerb] {
        switch subject {
        case .app: return [.open, .openIn, .newWindow, .gatherIn, .hide, .quit]
        case .target(let target):
            switch target.kind {
            case .window: return [.focus, .sendTo, .float, .fullscreen, .minimize, .close]
            case .stage: return [.show, .moveTo]
            case .desktop: return [.show, .moveTo]
            case .display, .bookmark: return [.show]
            case .appElement, .gridCell: return [.click, .doubleClick, .rightClick, .commandClick]
            }
        }
    }

    /// Verbe dont les destinations sont proposées directement dès la deuxième étape.
    static func primaryDestinationVerb(for subject: LauncherSubject) -> LauncherVerb? {
        verbs(for: subject).first(where: \.needsDestination)
    }
}

/// Une destination de la troisième étape.
struct LauncherDestination: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case stage(StageScope)
        case desktop(DisplayID, DesktopID)
        case display(DisplayID)
        /// Stage à créer dans ce bureau ; nom facultatif (unique dans tout Roadie, SPEC-067).
        case newStage(name: String?, DisplayID, DesktopID)
    }

    let kind: Kind
    let title: String
    let detail: String

    var id: String {
        switch kind {
        case .stage(let scope): "stage:\(scope.description)"
        case .desktop(let display, let desktop): "desktop:\(display.rawValue)/\(desktop.rawValue)"
        case .display(let display): "display:\(display.rawValue)"
        case .newStage(let name, let display, let desktop): "new:\(display.rawValue)/\(desktop.rawValue)/\(name ?? "")"
        }
    }

    fileprivate var category: Category {
        switch kind {
        case .stage: .stage
        case .desktop: .desktop
        case .display: .display
        case .newStage: .newStage
        }
    }

    fileprivate enum Category { case stage, desktop, display, newStage }

    /// Destinations acceptées par un verbe pour un objet. O(1).
    fileprivate static func accepts(_ category: Category, verb: LauncherVerb, subject: LauncherSubject) -> Bool {
        switch verb {
        case .openIn, .gatherIn: return category == .stage || category == .newStage
        case .sendTo: return true
        case .moveTo:
            if case .target(let target) = subject, target.kind == .desktop { return category == .display }
            return category == .desktop || category == .display
        default: return false
        }
    }
}

/// Ce que le lanceur exécute : un objet, un verbe, une destination si le verbe en demande une.
struct LauncherAction: Equatable, Sendable {
    let subject: LauncherSubject
    let verb: LauncherVerb
    let destination: LauncherDestination?
}

/// Liste des deuxième et troisième étapes : verbes de l'objet (et ses destinations directes dès
/// qu'on tape un nom), puis destinations du verbe choisi. O(v + d × q × t).
struct LauncherActionList: Equatable, Sendable {
    enum Row: Equatable, Sendable {
        case header(String)
        case verb(LauncherVerb)
        case destination(LauncherVerb, LauncherDestination)

        var id: String? {
            switch self {
            case .header: nil
            case .verb(let verb): "verb:\(verb.rawValue)"
            case .destination(let verb, let destination): "destination:\(verb.rawValue):\(destination.id)"
            }
        }
    }

    /// Destinations montrées au plus avant la création d'une stage.
    static let destinationLimit = 6

    private(set) var rows: [Row] = []
    private(set) var best: String?

    /// Deuxième étape. `newStageHome` : bureau où une nouvelle stage est créée (celui affiché).
    static func verbs(for subject: LauncherSubject, query: String, destinations: [LauncherDestination],
                      newStageHome: (DisplayID, DesktopID)) -> LauncherActionList {
        var list = LauncherActionList()
        list.rows.append(.header("\(subject.title) ›"))
        let folded = LauncherMatch.fold(query)
        let verbs = LauncherVerb.verbs(for: subject).filter { folded.isEmpty || LauncherMatch.score(query, in: $0.title) != nil }
        list.rows.append(contentsOf: verbs.map(Row.verb))
        if !folded.isEmpty, let primary = LauncherVerb.primaryDestinationVerb(for: subject) {
            let direct = matching(destinations, verb: primary, subject: subject, query: query, newStageHome: newStageHome)
            if !direct.isEmpty {
                list.rows.append(.header("Destinations"))
                list.rows.append(contentsOf: direct.map { .destination(primary, $0) })
            }
        }
        // Un verbe nommé passe devant une destination ; sans verbe, la première destination.
        list.best = list.rows.lazy.compactMap(\.id).first
        return list
    }

    /// Troisième étape : destinations acceptées par le verbe, filtrées par la saisie.
    static func destinations(for subject: LauncherSubject, verb: LauncherVerb, query: String,
                             destinations: [LauncherDestination], newStageHome: (DisplayID, DesktopID)) -> LauncherActionList {
        var list = LauncherActionList()
        list.rows.append(.header("\(subject.title) › \(verb.destinationPrefix)"))
        list.rows.append(contentsOf: matching(destinations, verb: verb, subject: subject, query: query, newStageHome: newStageHome)
            .map { .destination(verb, $0) })
        list.best = list.rows.lazy.compactMap(\.id).first
        return list
    }

    /// Destinations du verbe, la plus proche de la saisie d'abord, puis la création d'une stage :
    /// nommée d'après la saisie si aucune stage ne porte déjà ce nom, anonyme sinon. O(d × q × t).
    private static func matching(_ all: [LauncherDestination], verb: LauncherVerb, subject: LauncherSubject,
                                 query: String, newStageHome: (DisplayID, DesktopID)) -> [LauncherDestination] {
        let own = ownStage(of: subject)
        let accepted = all.filter { LauncherDestination.accepts($0.category, verb: verb, subject: subject) && $0.kind != own.map { .stage($0) } }
        let folded = LauncherMatch.fold(query)
        var found: [LauncherDestination]
        if folded.isEmpty {
            found = Array(accepted.prefix(destinationLimit))
        } else {
            let scored = accepted.compactMap { destination in LauncherMatch.score(query, in: destination.title).map { (destination, $0) } }
            found = scored.sorted { $0.1 > $1.1 }.prefix(destinationLimit).map(\.0)
        }
        guard LauncherDestination.accepts(.newStage, verb: verb, subject: subject) else { return found }
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = all.contains { destination in
            if case .stage = destination.kind { return LauncherMatch.fold(destination.title) == folded }
            return false
        }
        let named = !name.isEmpty && !taken
        found.append(LauncherDestination(kind: .newStage(name: named ? name : nil, newStageHome.0, newStageHome.1),
                                         title: named ? "Nouvelle stage « \(name) »" : "Nouvelle stage",
                                         detail: "bureau \(newStageHome.1.rawValue)"))
        return found
    }

    /// Stage où se trouve déjà l'objet : pas proposée comme destination.
    private static func ownStage(of subject: LauncherSubject) -> StageScope? {
        guard case .target(let target) = subject, let display = target.scope.displayId, let desktop = target.scope.desktopId,
              let stage = target.scope.stageId else { return nil }
        return StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage))
    }

    func neighbour(of id: String?, step: Int) -> String? {
        let ids = rows.compactMap(\.id)
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return step > 0 ? ids.first : ids.last }
        return ids[(index + step + ids.count) % ids.count]
    }

    func row(for id: String?) -> Row? { id.flatMap { id in rows.first { $0.id == id } } }
}
