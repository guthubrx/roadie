import Foundation
import RoadieCore

/// Grammaire objet → verbe → destination du lanceur (SPEC-074), logique pure.

/// L'objet choisi à la première étape.
enum LauncherSubject: Equatable, Sendable {
    case app(LauncherApp)
    case target(RoadieTarget)
    /// Fichier ou dossier trouvé par Spotlight (SPEC-077).
    case file(LauncherFile)
    /// Projet gardé (SPEC-080), par son nom.
    case project(String)

    var title: String {
        switch self {
        case .app(let app): app.name
        case .target(let target): target.subtitle.isEmpty ? target.title : "\(target.title) · \(target.subtitle)"
        case .file(let file): file.name
        case .project(let name): name
        }
    }

    var rankingKey: String {
        switch self {
        case .app(let app): app.rankingKey
        case .target(let target): LauncherList.rankingKey(target)
        case .file(let file): file.rankingKey
        case .project(let name): "project:\(LauncherMatch.fold(name))"
        }
    }

    /// Nom de l'application : celui de l'application, ou celui que porte une fenêtre ; d'un fichier, son nom.
    var appName: String {
        switch self {
        case .app(let app): app.name
        case .target(let target): target.title
        case .file(let file): file.name
        case .project(let name): name
        }
    }
}

/// État de tuilage d'une fenêtre, pour choisir ses verbes de flottement (SPEC-075).
struct LauncherTilingState: Equatable, Sendable {
    /// Flotte dans sa stage par « Faire flotter » (SPEC-047).
    var pinned: Bool
    /// Tuilée par Roadie.
    var tiled: Bool
    /// Choix durable de son application.
    var rule: WindowTilingChoice?
}

/// Les verbes, regroupés par type d'objet. `needsDestination` : la troisième étape suit.
enum LauncherVerb: String, CaseIterable, Sendable {
    // Application
    case open, newWindow, openIn, gatherIn, hide, quit
    // Application et fenêtre : vers la stage active, sans changer la stage affichée (SPEC-075).
    case bringHere
    // Fenêtre
    case focus, sendTo, float, fullscreen, minimize, close
    // Fenêtre : tuilage de cette fenêtre ou de toute son application (SPEC-075).
    case tileWindow, floatAlways, tileAlways, clearTilingRule
    // Fichier (SPEC-077).
    case reveal, quickLook, copyPath
    // Projets (SPEC-080) : stage gardée, rouverte, supprimée.
    case saveProject, reopenProject, deleteProject
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
        case .bringHere: "Amener ici"
        case .float: "Faire flotter cette fenêtre"
        case .tileWindow: "Remettre cette fenêtre au tuilage"
        case .floatAlways: "Toujours faire flotter l'application"
        case .tileAlways: "Toujours tuiler l'application"
        case .clearTilingRule: "Retirer la règle de flottement"
        case .reveal: "Montrer dans le Finder"
        case .quickLook: "Aperçu (Quick Look)"
        case .copyPath: "Copier le chemin"
        case .saveProject: "Enregistrer comme projet"
        case .reopenProject: "Rouvrir le projet"
        case .deleteProject: "Supprimer le projet"
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

    /// Titre affiché : les verbes « toujours » nomment l'application (« Toujours faire flotter Firefox »).
    func title(app: String) -> String {
        switch self {
        case .floatAlways: "Toujours faire flotter \(app)"
        case .tileAlways: "Toujours tuiler \(app)"
        case .clearTilingRule: "Retirer la règle de flottement de \(app)"
        default: title
        }
    }

    var needsDestination: Bool { [.openIn, .gatherIn, .sendTo, .moveTo].contains(self) }

    /// Verbes proposés pour un objet, le verbe par défaut en premier. Fenêtre : ses verbes de flottement
    /// dépendent de `tiling` ; sans état connu, « Faire flotter » seul (bascule SPEC-047). O(1).
    static func verbs(for subject: LauncherSubject, tiling: LauncherTilingState? = nil) -> [LauncherVerb] {
        switch subject {
        case .app: return [.open, .openIn, .bringHere, .newWindow, .gatherIn, .hide, .quit]
        case .file: return [.open, .openIn, .bringHere, .reveal, .quickLook, .copyPath]
        case .project: return [.reopenProject, .deleteProject]
        case .target(let target):
            switch target.kind {
            case .window: return [.focus, .sendTo, .bringHere] + tilingVerbs(tiling) + [.fullscreen, .minimize, .close]
            case .stage: return [.show, .moveTo, .saveProject]
            case .desktop: return [.show, .moveTo]
            case .display, .bookmark: return [.show]
            case .appElement, .gridCell: return [.click, .doubleClick, .rightClick, .commandClick]
            }
        }
    }

    /// Cette fenêtre : flotter si elle est tuilée, revenir au tuilage si elle flotte par « Faire flotter ».
    /// Toute l'application : flotter sauf si c'est déjà son choix ; tuiler si elle flotte par sa règle ou
    /// par nature ; retirer la règle s'il y en a une. O(1).
    private static func tilingVerbs(_ tiling: LauncherTilingState?) -> [LauncherVerb] {
        guard let tiling else { return [.float] }
        var verbs: [LauncherVerb] = tiling.pinned ? [.tileWindow] : tiling.tiled ? [.float] : []
        if tiling.rule != .float { verbs.append(.floatAlways) }
        if tiling.rule == .float || (tiling.rule == nil && !tiling.tiled && !tiling.pinned) { verbs.append(.tileAlways) }
        if tiling.rule != nil { verbs.append(.clearTilingRule) }
        return verbs
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
/// `follow` : Roadie va ensuite à la fenêtre déplacée (variante ⌘ Retour).
struct LauncherAction: Equatable, Sendable {
    let subject: LauncherSubject
    let verb: LauncherVerb
    let destination: LauncherDestination?
    var follow = false
    /// Place de la fenêtre après l'action (phrase, abréviation, SPEC-079).
    var position: LauncherPosition?
}

extension LauncherDestination {
    /// Destinations d'un déplacement : bureau ou écran pour une stage, écran pour un bureau. O(1).
    static func acceptsMove(_ destination: LauncherDestination, of kind: TargetKind) -> Bool {
        switch (kind, destination.kind) {
        case (.stage, .desktop), (.stage, .display), (.desktop, .display): true
        default: false
        }
    }
}

/// Touches qui changent ce que fait Retour (SPEC-075).
enum LauncherModifier: Sendable {
    case command, option, control
}

/// Touche des raccourcis 1 à 9 (SPEC-085), lue dans `pick_modifier` ; Commande par défaut.
enum LauncherPickModifier: String, Sendable {
    case command, shift, alt, control

    init(config value: String) { self = LauncherPickModifier(rawValue: value) ?? .command }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .alt: "⌥"
        case .control: "⌃"
        }
    }
}

/// Ce que Retour fait quand une touche est tenue, et ce que la ligne annonce avant.
struct LauncherVariant: Equatable, Sendable {
    enum Effect: Equatable, Sendable {
        case action(LauncherAction)
        case webSearch(String)
    }

    let title: String
    let effect: Effect

    /// ⌘ : dans une nouvelle stage du bureau affiché, et Roadie y va. ⌥ : vers la stage active, sans
    /// changer la stage affichée. ⌃ : le texte tapé sur le web. Cibles à l'écran : ⌘ reste le ⌘-clic de
    /// la SPEC-021, donc pas de variante ici. nil : Retour fait l'action normale. O(1).
    static func of(_ subject: LauncherSubject, modifier: LauncherModifier, query: String,
                   newStageHome: (DisplayID, DesktopID), activeStage: StageScope?) -> LauncherVariant? {
        let window: RoadieTarget? = if case .target(let target) = subject, target.kind == .window { target } else { nil }
        // Un fichier se comporte comme une application : il s'ouvre, dans une stage ou ici.
        let isApp = switch subject {
        case .app, .file: true
        case .target, .project: false
        }
        switch modifier {
        case .control:
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : LauncherVariant(title: "⌃ ↩ Rechercher « \(text) » sur le web", effect: .webSearch(text))
        case .command:
            let fresh = LauncherDestination(kind: .newStage(name: nil, newStageHome.0, newStageHome.1),
                                            title: "Nouvelle stage", detail: "bureau \(newStageHome.1.rawValue)")
            if isApp {
                return LauncherVariant(title: "⌘ ↩ Ouvrir dans une nouvelle stage",
                                       effect: .action(LauncherAction(subject: subject, verb: .openIn, destination: fresh)))
            }
            guard window != nil else { return nil }
            return LauncherVariant(title: "⌘ ↩ Envoyer dans une nouvelle stage",
                                   effect: .action(LauncherAction(subject: subject, verb: .sendTo, destination: fresh, follow: true)))
        case .option:
            guard let activeStage, isApp || window != nil else { return nil }
            if window != nil, LauncherActionList.ownStage(of: subject) == activeStage { return nil }
            let here = LauncherDestination(kind: .stage(activeStage), title: "Stage active", detail: "")
            return LauncherVariant(title: "⌥ ↩ Amener ici, sans changer de stage",
                                   effect: .action(LauncherAction(subject: subject, verb: .bringHere, destination: here)))
        }
    }
}

/// Liste des deuxième et troisième étapes : verbes de l'objet (et ses destinations directes dès
/// qu'on tape un nom), puis destinations du verbe choisi. O(v + d × q × t).
struct LauncherActionList: Equatable, Sendable {
    enum Row: Equatable, Sendable {
        case header(String)
        case verb(LauncherVerb)
        case destination(LauncherVerb, LauncherDestination)
        /// Action sur fichier d'un workflow (SPEC-089 FR-003).
        case workflow(AlfredEntry)

        var id: String? {
            switch self {
            case .header: nil
            case .verb(let verb): "verb:\(verb.rawValue)"
            case .destination(let verb, let destination): "destination:\(verb.rawValue):\(destination.id)"
            case .workflow(let entry): "workflow:\(entry.id)"
            }
        }
    }

    /// Destinations montrées au plus avant la création d'une stage.
    static let destinationLimit = 6

    private(set) var rows: [Row] = []
    private(set) var best: String?

    /// Deuxième étape. `newStageHome` : bureau où une nouvelle stage est créée (celui affiché).
    static func verbs(for subject: LauncherSubject, query: String, destinations: [LauncherDestination],
                      newStageHome: (DisplayID, DesktopID), tiling: LauncherTilingState? = nil) -> LauncherActionList {
        var list = LauncherActionList()
        list.rows.append(.header("\(subject.title) ›"))
        let folded = LauncherMatch.fold(query)
        let verbs = LauncherVerb.verbs(for: subject, tiling: tiling)
            .filter { folded.isEmpty || LauncherMatch.score(query, in: $0.title(app: subject.appName)) != nil }
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
    static func ownStage(of subject: LauncherSubject) -> StageScope? {
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

    /// Actions de workflows sur l'objet, filtrées par la saisie, sous « Workflows » (SPEC-089). O(a).
    mutating func appendWorkflows(_ entries: [AlfredEntry], query: String) {
        let folded = LauncherMatch.fold(query)
        let shown = entries.filter { folded.isEmpty || LauncherMatch.score(query, in: $0.title) != nil }
        guard !shown.isEmpty else { return }
        rows.append(.header("Workflows"))
        rows.append(contentsOf: shown.map(Row.workflow))
        if best == nil { best = rows.lazy.compactMap(\.id).first }
    }
}
