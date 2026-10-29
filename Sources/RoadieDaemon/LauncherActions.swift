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
    /// Adresse tapée (SPEC-090).
    case url(URL)
    /// Texte tapé ou sélectionné dans l'application active (session 131).
    case text(String)
    /// Document ou onglet ouvert (SPEC-082), pour ses verbes (session 131).
    case openItem(LauncherOpenItem)

    var title: String {
        switch self {
        case .app(let app): app.name
        case .target(let target): target.subtitle.isEmpty ? target.title : "\(target.title) · \(target.subtitle)"
        case .file(let file): file.name
        case .project(let name): name
        case .url(let url): url.absoluteString
        case .text(let text): LauncherText.preview(text)
        case .openItem(let item): item.title
        }
    }

    var rankingKey: String {
        switch self {
        case .app(let app): app.rankingKey
        case .target(let target): LauncherList.rankingKey(target)
        case .file(let file): file.rankingKey
        case .project(let name): "project:\(LauncherMatch.fold(name))"
        case .url(let url): "url:\(url.host ?? url.absoluteString)"
        case .text: "text"
        case .openItem(let item): "open:\(item.kind.rawValue):\(item.bundleID)"
        }
    }

    /// Type d'objet dont l'ordre des verbes est appris (session 111) : `app`, `file`, `window`, `stage`…
    var verbKind: String {
        switch self {
        case .app: "app"
        case .file: "file"
        case .project: "project"
        case .url: "url"
        case .text: "text"
        case .openItem(let item): item.kind == .tab ? "tab" : "document"
        case .target(let target): target.kind.rawValue
        }
    }

    /// Nom de l'application : celui de l'application, ou celui que porte une fenêtre ; d'un fichier, son nom.
    var appName: String {
        switch self {
        case .app(let app): app.name
        case .target(let target): target.title
        case .file(let file): file.name
        case .project(let name): name
        case .url(let url): url.host ?? url.absoluteString
        case .text(let text): LauncherText.preview(text)
        case .openItem(let item): item.appName
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
    /// Session 105 : comme le Forcer à quitter de macOS.
    case forceQuit
    /// Session 116 : documents récents de l'application, choisis à la troisième étape.
    case recentDocuments
    // Application et fenêtre : vers la stage active, sans changer la stage affichée (SPEC-075).
    case bringHere
    // Fenêtre
    case focus, sendTo, float, fullscreen, minimize, close
    // Fenêtre : tuilage de cette fenêtre ou de toute son application (SPEC-075).
    case tileWindow, floatAlways, tileAlways, clearTilingRule
    // Fichier (SPEC-077).
    case reveal, quickLook, copyPath
    // Fichier, actions d'Alfred (session 131) : presse-papiers, copie et déplacement vers un dossier (en
    // remplaçant : l'homonyme part à la corbeille), ouvrir avec, e-mail, corbeille, alias, informations,
    // étiquette, parcourir dans la barre, terminal dans le dossier, contenu d'un paquet.
    case copyFile, copyTo, moveFileTo, copyReplace, moveReplace, openWith, email, trash, makeAlias, info, addTag
    case browse, terminalHere, packageContents
    // Texte et adresse (session 131).
    case copyText, webSearch, extractURLs, emailText, largeType
    // Onglet ouvert (session 131).
    case closeTab, copyURL, newWindowTab
    // Application (session 131) : relancer, quitter toutes les autres.
    case relaunch, quitOthers
    // Projets (SPEC-080) : stage gardée, rouverte, supprimée.
    case saveProject, reopenProject, deleteProject
    // Stage, bureau
    case show, moveTo
    // Cible à l'écran
    case click, doubleClick, rightClick, commandClick

    /// Nom du verbe en français et en anglais (session 126) ; la recherche accepte les deux.
    private var names: (fr: String, en: String) {
        switch self {
        case .open: ("Ouvrir ou aller à sa fenêtre", "Open or go to its window")
        case .newWindow: ("Nouvelle fenêtre ici", "New window here")
        case .openIn: ("Ouvrir dans…", "Open in…")
        case .gatherIn: ("Réunir ses fenêtres dans…", "Gather its windows in…")
        case .hide: ("Masquer l'application", "Hide app")
        case .quit: ("Quitter l'application", "Quit app")
        case .forceQuit: ("Forcer à quitter", "Force quit")
        case .recentDocuments: ("Documents récents…", "Recent documents…")
        case .focus: ("Aller à la fenêtre", "Go to window")
        case .sendTo: ("Envoyer vers…", "Send to…")
        case .bringHere: ("Amener ici", "Bring here")
        case .float: ("Faire flotter cette fenêtre", "Float this window")
        case .tileWindow: ("Remettre cette fenêtre au tuilage", "Tile this window again")
        case .floatAlways: ("Toujours faire flotter l'application", "Always float the app")
        case .tileAlways: ("Toujours tuiler l'application", "Always tile the app")
        case .clearTilingRule: ("Retirer la règle de flottement", "Remove the floating rule")
        case .reveal: ("Montrer dans le Finder", "Reveal in Finder")
        case .quickLook: ("Aperçu (Quick Look)", "Quick Look")
        case .copyPath: ("Copier le chemin", "Copy path")
        case .saveProject: ("Enregistrer comme projet", "Save as project")
        case .reopenProject: ("Rouvrir le projet", "Reopen project")
        case .deleteProject: ("Supprimer le projet", "Delete project")
        case .fullscreen: ("Plein écran", "Full screen")
        case .minimize: ("Réduire", "Minimize")
        case .close: ("Fermer la fenêtre", "Close window")
        case .show: ("Afficher", "Show")
        case .moveTo: ("Déplacer vers…", "Move to…")
        case .click: ("Clic", "Click")
        case .doubleClick: ("Double-clic", "Double-click")
        case .rightClick: ("Clic droit", "Right-click")
        case .commandClick: ("Cmd-clic (nouvel onglet)", "Cmd-click (new tab)")
        case .copyFile: ("Copier le fichier", "Copy file")
        case .copyTo: ("Copier vers…", "Copy to…")
        case .moveFileTo: ("Déplacer le fichier vers…", "Move file to…")
        case .copyReplace: ("Copier vers… en remplaçant", "Copy to… replacing")
        case .moveReplace: ("Déplacer vers… en remplaçant", "Move to… replacing")
        case .openWith: ("Ouvrir avec…", "Open with…")
        case .email: ("Envoyer par e-mail", "Send by email")
        case .trash: ("Mettre à la corbeille", "Move to Trash")
        case .makeAlias: ("Créer un alias", "Make alias")
        case .info: ("Informations", "Get info")
        case .addTag: ("Étiquette…", "Tag…")
        case .browse: ("Parcourir dans la barre", "Browse in the bar")
        case .terminalHere: ("Ouvrir un terminal ici", "Open Terminal here")
        case .packageContents: ("Afficher le contenu du paquet", "Show package contents")
        case .copyText: ("Copier", "Copy")
        case .webSearch: ("Chercher sur le web", "Search the web")
        case .extractURLs: ("Extraire les adresses", "Extract addresses")
        case .emailText: ("Envoyer par e-mail", "Send by email")
        case .largeType: ("Afficher en grand", "Show large type")
        case .closeTab: ("Fermer l'onglet", "Close tab")
        case .copyURL: ("Copier l'adresse", "Copy address")
        case .newWindowTab: ("Ouvrir dans une nouvelle fenêtre", "Open in a new window")
        case .relaunch: ("Relancer l'application", "Relaunch app")
        case .quitOthers: ("Quitter les autres applications", "Quit other apps")
        }
    }

    var title: String { tr(names.fr, names.en) }

    /// Titre court d'une ligne de destination directe : « Ouvrir dans Perso ».
    var destinationPrefix: String {
        switch self {
        case .openIn: tr("Ouvrir dans", "Open in")
        case .gatherIn: tr("Réunir dans", "Gather in")
        case .sendTo: tr("Envoyer vers", "Send to")
        case .moveTo: tr("Déplacer vers", "Move to")
        case .recentDocuments: tr("Ouvrir", "Open")
        case .copyTo: tr("Copier vers", "Copy to")
        case .moveFileTo: tr("Déplacer vers", "Move to")
        case .copyReplace: tr("Copier en remplaçant vers", "Copy replacing to")
        case .moveReplace: tr("Déplacer en remplaçant vers", "Move replacing to")
        case .openWith: tr("Ouvrir avec", "Open with")
        case .addTag: tr("Étiqueter", "Tag")
        default: title
        }
    }

    /// Titre de la troisième étape : « Word › Documents récents ».
    var destinationsTitle: String { self == .recentDocuments ? tr("Documents récents", "Recent documents") : destinationPrefix }

    /// Titres en français et en anglais : les verbes « toujours » nomment l'application
    /// (« Toujours faire flotter Firefox »). O(1).
    private func names(app: String) -> (fr: String, en: String) {
        switch self {
        case .floatAlways: ("Toujours faire flotter \(app)", "Always float \(app)")
        case .tileAlways: ("Toujours tuiler \(app)", "Always tile \(app)")
        case .clearTilingRule: ("Retirer la règle de flottement de \(app)", "Remove \(app)'s floating rule")
        default: names
        }
    }

    /// Titre affiché, dans la langue de l'interface.
    func title(app: String) -> String {
        let pair = names(app: app)
        return tr(pair.fr, pair.en)
    }

    /// Le verbe correspond à la saisie dans l'une ou l'autre langue (« close » trouve « Fermer la fenêtre »). O(t).
    func matches(_ query: String, app: String) -> Bool {
        let pair = names(app: app)
        return LauncherMatch.score(query, in: pair.fr) != nil || LauncherMatch.score(query, in: pair.en) != nil
    }

    var needsDestination: Bool {
        [.openIn, .gatherIn, .sendTo, .moveTo, .recentDocuments, .copyTo, .moveFileTo, .copyReplace, .moveReplace, .openWith, .addTag]
            .contains(self)
    }

    /// Clé du classement appris pour ce verbe sur ce type d'objet (session 111) : `verb:app:quit`.
    func rankingKey(for subject: LauncherSubject) -> String { "verb:\(subject.verbKind):\(rawValue)" }

    /// Verbes les plus choisis pour ce type d'objet d'abord, par fréquence-récence ; à égalité, l'ordre
    /// par défaut reste. O(v log v), v ≤ 12.
    static func learnedOrder(_ verbs: [LauncherVerb], for subject: LauncherSubject, ranking: LauncherRanking,
                             at now: Date = Date()) -> [LauncherVerb] {
        verbs.enumerated()
            .map { (verb: $0.element, index: $0.offset, score: ranking.frecency($0.element.rankingKey(for: subject), at: now)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.verb)
    }

    /// Verbes proposés pour un objet, le verbe par défaut en premier. Fenêtre : ses verbes de flottement
    /// dépendent de `tiling` ; sans état connu, « Faire flotter » seul (bascule SPEC-047). O(1).
    static func verbs(for subject: LauncherSubject, tiling: LauncherTilingState? = nil) -> [LauncherVerb] {
        switch subject {
        case .app: return [.open, .openIn, .bringHere, .newWindow, .recentDocuments, .gatherIn, .hide, .quit, .forceQuit, .relaunch, .quitOthers]
        case .file(let file):
            // Session 131 : actions d'Alfred sur un fichier ; un dossier se parcourt ou ouvre un terminal, un
            // paquet (application, bibliothèque) montre son contenu.
            var verbs: [LauncherVerb] = [.open, .openIn, .bringHere, .reveal, .quickLook, .copyPath, .copyFile, .copyTo, .moveFileTo,
                                         .copyReplace, .moveReplace, .openWith, .email, .trash, .makeAlias, .info, .addTag]
            if file.isFolder { verbs += [.browse, .terminalHere] }
            if LauncherFileOperations.isPackage(file.path) { verbs.append(.packageContents) }
            return verbs
        case .project: return [.reopenProject, .deleteProject]
        case .url: return [.open, .openIn, .bringHere, .copyPath, .emailText, .largeType]
        case .text: return [.copyText, .webSearch, .extractURLs, .emailText, .largeType]
        case .openItem(let item): return item.kind == .tab ? [.open, .closeTab, .copyURL, .newWindowTab] : [.open]
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
        /// Document récent d'une application (session 116), par son chemin.
        case document(String)
        /// Dossier où copier ou déplacer un fichier (session 131).
        case folder(String)
        /// Application qui ouvre un fichier (session 131), par son chemin.
        case application(String)
        /// Étiquette du Finder à ajouter ou retirer (session 131).
        case tag(String)

        /// Document récent : la ligne montre son seul nom, sans le verbe devant.
        var isDocument: Bool { if case .document = self { true } else { false } }
    }

    let kind: Kind
    let title: String
    let detail: String
    /// Autres noms qui la trouvent, dans l'autre langue (« Desktop 2 » pour « Bureau 2 », session 126).
    var aliases: [String] = []

    var id: String {
        switch kind {
        case .stage(let scope): "stage:\(scope.description)"
        case .desktop(let display, let desktop): "desktop:\(display.rawValue)/\(desktop.rawValue)"
        case .display(let display): "display:\(display.rawValue)"
        case .newStage(let name, let display, let desktop): "new:\(display.rawValue)/\(desktop.rawValue)/\(name ?? "")"
        case .document(let path): "document:\(path)"
        case .folder(let path): "folder:\(path)"
        case .application(let path): "application:\(path)"
        case .tag(let name): "tag:\(name)"
        }
    }

    fileprivate var category: Category {
        switch kind {
        case .stage: .stage
        case .desktop: .desktop
        case .display: .display
        case .newStage: .newStage
        case .document: .document
        case .folder: .folder
        case .application: .application
        case .tag: .tag
        }
    }

    fileprivate enum Category { case stage, desktop, display, newStage, document, folder, application, tag }

    /// Destinations acceptées par un verbe pour un objet. O(1).
    fileprivate static func accepts(_ category: Category, verb: LauncherVerb, subject: LauncherSubject) -> Bool {
        switch verb {
        case .openIn, .gatherIn: return category == .stage || category == .newStage
        case .sendTo: return [.stage, .desktop, .display, .newStage].contains(category)
        case .copyTo, .moveFileTo, .copyReplace, .moveReplace: return category == .folder
        case .openWith: return category == .application
        case .addTag: return category == .tag
        case .recentDocuments: return category == .document
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

/// Effet réglable de ⌘, ⌥ et ⌃ + Retour (session 131), comme les listes « Action Modifiers » d'Alfred.
enum LauncherReturnEffect: String, CaseIterable, Sendable {
    case newStage = "new-stage", here, send, web, copy, reveal, quicklook, verbs, none

    /// Valeur du réglage ; une valeur inconnue rend l'effet par défaut de la touche. O(1).
    init(config value: String, modifier: LauncherModifier) {
        self = LauncherReturnEffect(rawValue: value) ?? Self.defaultEffect(modifier)
    }

    /// Comportement de la session 075 : ⌘ nouvelle stage, ⌥ ici, ⌃ web.
    static func defaultEffect(_ modifier: LauncherModifier) -> LauncherReturnEffect {
        switch modifier {
        case .command: .newStage
        case .option: .here
        case .control: .web
        }
    }
}

/// Ce que Retour fait quand une touche est tenue, et ce que la ligne annonce avant.
struct LauncherVariant: Equatable, Sendable {
    enum Effect: Equatable, Sendable {
        case action(LauncherAction)
        case webSearch(String)
        /// Session 131 : copier un texte, ouvrir les verbes de l'objet.
        case copy(String)
        case verbs(LauncherSubject)
    }

    let title: String
    let effect: Effect

    /// Effet de la touche tenue sur l'objet de la ligne ; nil si l'effet ne s'applique pas à cet objet (Retour fait
    /// alors l'action normale). Nouvelle stage : dans une nouvelle stage du bureau affiché, et Roadie y va ; envoyer :
    /// la même sans y aller ; ici : vers la stage active sans changer la stage affichée ; web : le texte tapé sur le
    /// web. Cibles à l'écran : ⌘ reste le ⌘-clic de la SPEC-021. O(1).
    static func of(_ subject: LauncherSubject, modifier: LauncherModifier, query: String,
                   newStageHome: (DisplayID, DesktopID), activeStage: StageScope?,
                   effect: LauncherReturnEffect? = nil) -> LauncherVariant? {
        let effect = effect ?? LauncherReturnEffect.defaultEffect(modifier)
        let key = switch modifier {
        case .command: "⌘ ↩"
        case .option: "⌥ ↩"
        case .control: "⌃ ↩"
        }
        let window: RoadieTarget? = if case .target(let target) = subject, target.kind == .window { target } else { nil }
        // Un fichier se comporte comme une application : il s'ouvre, dans une stage ou ici.
        let isApp = switch subject {
        case .app, .file, .url: true
        case .target, .project, .text, .openItem: false
        }
        let fresh = LauncherDestination(kind: .newStage(name: nil, newStageHome.0, newStageHome.1),
                                        title: tr("Nouvelle stage", "New stage"), detail: tr("bureau", "desktop") + " \(newStageHome.1.rawValue)")
        switch effect {
        case .none:
            return nil
        case .web:
            let text = LauncherWeb.searchText(query)
            return text.isEmpty ? nil : LauncherVariant(title: tr("\(key) Rechercher « \(text) » sur le web", "\(key) Search the web for “\(text)”"),
                                                        effect: .webSearch(text))
        case .newStage, .send:
            let follow = effect == .newStage
            if isApp {
                return LauncherVariant(title: tr("\(key) Ouvrir dans une nouvelle stage", "\(key) Open in a new stage"),
                                       effect: .action(LauncherAction(subject: subject, verb: .openIn, destination: fresh)))
            }
            guard window != nil else { return nil }
            return LauncherVariant(title: follow ? tr("\(key) Envoyer dans une nouvelle stage", "\(key) Send to a new stage")
                                                 : tr("\(key) Envoyer dans une nouvelle stage, sans y aller", "\(key) Send to a new stage, stay here"),
                                   effect: .action(LauncherAction(subject: subject, verb: .sendTo, destination: fresh, follow: follow)))
        case .here:
            guard let activeStage, isApp || window != nil else { return nil }
            if window != nil, LauncherActionList.ownStage(of: subject) == activeStage { return nil }
            let here = LauncherDestination(kind: .stage(activeStage), title: tr("Stage active", "Active stage"), detail: "")
            return LauncherVariant(title: tr("\(key) Amener ici, sans changer de stage", "\(key) Bring here, stay on this stage"),
                                   effect: .action(LauncherAction(subject: subject, verb: .bringHere, destination: here)))
        case .copy:
            let text: String? = switch subject {
            case .app(let app): app.path
            case .file(let file): file.path
            case .url(let url): url.absoluteString
            case .target(let target): target.title
            case .text(let text): text
            case .openItem(let item): item.url ?? item.title
            case .project(let name): name
            }
            return text.map { LauncherVariant(title: tr("\(key) Copier", "\(key) Copy"), effect: .copy($0)) }
        case .reveal, .quicklook:
            let path: String? = switch subject {
            case .file(let file): file.path
            case .app(let app) where effect == .reveal: app.path
            default: nil
            }
            guard let path else { return nil }
            let file = LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)
            return effect == .reveal
                ? LauncherVariant(title: tr("\(key) Montrer dans le Finder", "\(key) Reveal in Finder"),
                                  effect: .action(LauncherAction(subject: .file(file), verb: .reveal, destination: nil)))
                : LauncherVariant(title: tr("\(key) Aperçu (Quick Look)", "\(key) Quick Look"),
                                  effect: .action(LauncherAction(subject: .file(file), verb: .quickLook, destination: nil)))
        case .verbs:
            return LauncherVariant(title: tr("\(key) Verbes…", "\(key) Verbs…"), effect: .verbs(subject))
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
    /// `ranking` : classement appris, qui ordonne les verbes (session 111) ; nil : ordre par défaut.
    static func verbs(for subject: LauncherSubject, query: String, destinations: [LauncherDestination],
                      newStageHome: (DisplayID, DesktopID), tiling: LauncherTilingState? = nil,
                      ranking: LauncherRanking? = nil) -> LauncherActionList {
        var list = LauncherActionList()
        list.rows.append(.header("\(subject.title) ›"))
        let folded = LauncherMatch.fold(query)
        let defaults = LauncherVerb.verbs(for: subject, tiling: tiling)
        let verbs = (ranking.map { LauncherVerb.learnedOrder(defaults, for: subject, ranking: $0) } ?? defaults)
            .filter { folded.isEmpty || $0.matches(query, app: subject.appName) }
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
        list.rows.append(.header("\(subject.title) › \(verb.destinationsTitle)"))
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
        // Documents récents : la liste entière (20 au plus), plus récent d'abord.
        let limit = verb == .recentDocuments ? LauncherRecentDocuments.limit : destinationLimit
        if folded.isEmpty {
            found = Array(accepted.prefix(limit))
        } else {
            let scored = accepted.compactMap { destination in
                ([destination.title] + destination.aliases).compactMap { LauncherMatch.score(query, in: $0) }.max().map { (destination, $0) }
            }
            found = scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        }
        guard LauncherDestination.accepts(.newStage, verb: verb, subject: subject) else { return found }
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = all.contains { destination in
            if case .stage = destination.kind { return LauncherMatch.fold(destination.title) == folded }
            return false
        }
        let named = !name.isEmpty && !taken
        found.append(LauncherDestination(kind: .newStage(name: named ? name : nil, newStageHome.0, newStageHome.1),
                                         title: named ? tr("Nouvelle stage « \(name) »", "New stage “\(name)”") : tr("Nouvelle stage", "New stage"),
                                         detail: tr("bureau", "desktop") + " \(newStageHome.1.rawValue)"))
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

    /// Construction d'une liste de lot (SPEC-091).
    mutating func appendHeader(_ title: String) { rows.append(.header(title)) }

    mutating func appendVerb(_ verb: LauncherVerb) {
        rows.append(.verb(verb))
        if best == nil { best = Row.verb(verb).id }
    }

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
