import AppKit
import Foundation
import RoadieAX
import RoadieCore

/// Ce que la barre de recherche reçoit pour jouer le rôle de lanceur (SPEC-073).
struct LauncherSearchContext {
    var apps: [LauncherApp]
    /// État affiché à côté de chaque application, par identifiant.
    var details: [String: String]
    var ranking: LauncherRanking
    /// Rafraîchit l'index des applications et rappelle avec le nouveau, sur le fil principal.
    var refreshApps: (@escaping @MainActor @Sendable ([LauncherApp]) -> Void) -> Void
    /// Va à la fenêtre de l'application ou l'ouvre ; appelé après la fermeture de la barre.
    var launch: @MainActor (LauncherApp) -> TargetActionResult
    /// Mémorise un choix : clé de classement, requête tapée.
    var recordVisit: @MainActor (String, String) -> Void
    /// Stages, bureaux et écrans proposés comme destinations (SPEC-074).
    var destinations: [LauncherDestination] = []
    /// Bureau affiché de l'écran actif : là où « Nouvelle stage » crée la stage.
    var newStageHome = (DisplayID(rawValue: "none"), DesktopID(rawValue: 1))
    /// Exécute un verbe ; appelé après la fermeture de la barre.
    var perform: @MainActor (LauncherAction) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    /// Stage active du bureau affiché : la destination de ⌥ Retour (SPEC-075).
    var activeStage: StageScope?
    /// Stages affichées, une par écran (SPEC-084) : seules leurs fenêtres reçoivent un badge à l'écran.
    var shownStages: Set<StageScope> = []
    /// Touche des raccourcis 1 à 9 (SPEC-085).
    var pickModifier = LauncherPickModifier.command
    /// Identité de cette stage pour le classement appris (SPEC-076) : `stage:<nom>` ou `scope:<place>`.
    var rankingContext: String?
    /// Objet dont la barre montre tout de suite les verbes (Capslock + Maj + F) ; nil : la liste.
    var initialSubject: LauncherSubject?
    /// État de tuilage d'une fenêtre, pour ses verbes de flottement.
    var tiling: @MainActor (WindowID) -> LauncherTilingState? = { _ in nil }
    /// Aperçu actif (SPEC-078) : nil termine l'aperçu en remettant tout comme avant ; le fantôme est
    /// rendu quand les fenêtres ont pris leur place (nil sans fantôme ou sans aperçu).
    var preview: @MainActor (LauncherPreviewRequest?, @escaping @MainActor (LauncherGhost?) -> Void) -> Void = { _, done in done(nil) }
    /// Abréviations de l'utilisateur (SPEC-079), l'action d'une abréviation aujourd'hui, le nom réel
    /// d'une stage (nil si anonyme) et l'enregistrement d'une abréviation.
    var aliases = LauncherAliasBook()
    /// Projets gardés (SPEC-080).
    var projects: [StageProject] = []
    /// Documents et onglets ouverts, lus en fond à l'ouverture (SPEC-082), et Retour sur l'un d'eux.
    var loadOpenItems: (@escaping @MainActor @Sendable ([LauncherOpenItem]) -> Void) -> Void = { _ in }
    var activateOpenItem: @MainActor (LauncherOpenItem) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    /// Liste de la barre vide, règles à proposer (chip) et choix d'une règle (SPEC-081).
    var idleRows: [LauncherList.Row] = []
    var pendingRules = 0
    var ruleChoice: @MainActor (RuleSuggestion, RuleChoice) -> TargetActionResult = { _, _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    var aliasAction: @MainActor (LauncherAlias) -> LauncherAction? = { _ in nil }
    var stageName: @MainActor (StageScope) -> String? = { _ in nil }
    var saveAlias: @MainActor (LauncherAlias, String) -> Result<LauncherAlias?, Error> = { _, _ in
        .failure(JSONPersistence.PersistenceError(description: "launcher indisponible"))
    }
    /// Fin de l'aperçu par Retour : la disposition de l'aperçu reste (vrai) ou est restaurée (faux).
    var endPreview: @MainActor (Bool) -> Void = { _ in }
    /// Workflows (SPEC-088) : entrées tapées ; Script Filter lancé hors du fil principal (réponse ou
    /// erreur rendue sur le fil principal, processus annulable) ; schéma exécuté après la fermeture.
    var workflowEntries: [AlfredEntry] = []
    /// Déclencheurs (SPEC-089) : recherches de repli, actions universelles sur texte, actions sur fichier.
    var workflowTriggers: [AlfredEntry] = []
    var runScriptFilter: (AlfredEntry, String, @escaping @MainActor @Sendable (AlfredScriptFilterResponse?, String?) -> Void) -> AlfredProcess? = { _, _, _ in nil }
    var runWorkflow: @MainActor (AlfredEntry, [String], [String: String], Int) -> TargetActionResult = { _, _, _, _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    /// Grille d'un workflow (SPEC-092) : la barre s'ouvre en tuiles, Retour repart de la grille.
    var workflowGrid: AlfredGridView?
    /// Présentations retenues (session 099), leur enregistrement et la touche qui les fait défiler.
    var viewBook = LauncherViewBook()
    var saveViews: (LauncherViewBook) -> Void = { _ in }
    var viewCycleKey = ""
    /// Touches réglables de la barre (session 108).
    var barKeys = LauncherBarKeys.resolved([:])
    /// Mises à jour de cette grille (tuiles après le texte d'attente, session 095) : la barre s'abonne.
    var subscribeGrid: (@escaping @MainActor (AlfredGridView) -> Void) -> Void = { _ in }
    /// Texte de départ de la barre (Show Alfred d'un workflow, ou dernière saisie reprise).
    var initialQuery: String?
    /// La saisie de départ est la dernière reprise (moins de 5 minutes) : elle est sélectionnée (SPEC-090).
    var restoredQuery = false
    /// Web (SPEC-090) : recherches par mot-clé, adresse de ⌃ Retour, mots-clés de repli.
    var webSearches: [WebSearch] = WebSearch.defaults
    var webSearchTemplate = TargetModeConfig.defaultWebSearchURL
    /// Place de la barre (session 102) : retenue après un glisser, sinon `bar_position` ; écran de
    /// `bar_screen` en coordonnées AppKit (nil : écran du pointeur) ; `savePlacement` retient la place
    /// (nil l'efface), sans effet si `bar_save_position` est faux.
    var barPlacement = SearchBarPlacement.bottom
    var defaultBarPlacement = SearchBarPlacement.bottom
    var barScreenFrame: CGRect?
    var savePlacement: (SearchBarPlacement?) -> Void = { _ in }
    /// Commandes système proposées (session 105).
    var systemCommands = LauncherSystemCommand.all()
    /// Ordre des éléments d'un chemin tapé (session 105) : `name`, `modified` ou `created`.
    var pathSort = "name"
    /// Réglages trouvés par la barre (session 115) ; vide si `settings_in_search` est faux.
    var settingTargets: [LauncherSystemCommand] = []
    /// Types de fichiers ajoutés, dossiers écartés et format du calcul (session 119).
    var fileTypes: [String] = []
    var fileExcluded: [String] = []
    var calcLocale = Locale.current
    var calcGrouping = false
    /// Mots-clés de la recherche dans le contenu et par étiquette (session 113).
    var fileKeywords = LauncherFileKeywords()
    /// Les verbes les plus choisis passent en tête (session 111, `learn_verb_order`).
    var learnsVerbOrder = true
    /// Retour sur un calcul ouvre aussi Calculette (session 110, `calc_opens_calculator`).
    var calcOpensCalculator = false
    /// Terminal du préfixe `>` (session 103).
    var terminalApp = "terminal"
    /// Signets des navigateurs (session 104), lus hors du fil principal ; rien si `bookmarks_enabled` est faux.
    var loadBookmarks: (@escaping @MainActor @Sendable ([LauncherBookmark]) -> Void) -> Void = { _ in }
    /// Historique des navigateurs (session 114), lu hors du fil principal ; rien si `web_history_days` vaut 0.
    var loadHistory: (@escaping @MainActor @Sendable ([LauncherBookmark]) -> Void) -> Void = { _ in }
    var fallbackSearches: [String] = []
    /// Lot de la sélection multiple (SPEC-091) et annulation du dernier lot.
    var performBatch: @MainActor ([LauncherAction]) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }
    var undo: @MainActor () -> TargetActionResult = { TargetActionResult(changed: false, message: "launcher_disabled") }
    /// Saisie qui a mené à une action : gardée pour l'historique.
    var recordQuery: @MainActor (String) -> Void = { _ in }
    /// ⌃ Retour : le texte tapé sur le web ; appelé après la fermeture de la barre.
    var webSearch: @MainActor (String) -> TargetActionResult = { _ in
        TargetActionResult(changed: false, message: "launcher_disabled")
    }

    /// Badge à l'écran (SPEC-084) : une fenêtre Roadie seulement si sa stage est affichée ; une fenêtre
    /// d'une stage cachée ou d'un autre bureau n'est pas visible. Les autres cibles sont à l'écran. O(1).
    func isOnScreen(_ target: RoadieTarget) -> Bool {
        guard target.kind == .window, target.source == .roadie, let display = target.scope.displayId,
              let desktop = target.scope.desktopId, let stage = target.scope.stageId else { return true }
        return shownStages.contains(StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop),
                                               stageID: StageID(rawValue: stage)))
    }

    /// Sans lanceur : la barre garde le seul mode recherche (tests, configuration désactivée).
    static var disabled: LauncherSearchContext { LauncherSearchContext(
        apps: [], details: [:], ranking: LauncherRanking(), refreshApps: { _ in },
        launch: { _ in TargetActionResult(changed: false, message: "launcher_disabled") }, recordVisit: { _, _ in }) }
}

/// Décisions du lanceur sur l'état de Roadie, sans effet de bord.
enum LauncherPlacement {
    /// Fenêtre à rejoindre pour une application déjà ouverte : celle qui a le focus dans une stage
    /// affichée, puis une fenêtre d'une stage affichée, puis la fenêtre qui avait le focus dans sa
    /// stage, puis la première. O(w), w fenêtres de l'application.
    static func preferredWindow(_ entries: [WindowSwitcherEntry], state: PersistentStageState) -> WindowSwitcherEntry? {
        func stage(_ scope: StageScope) -> PersistentStage? {
            state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages.first { $0.id == scope.stageID }
        }
        func shown(_ scope: StageScope) -> Bool {
            state.currentDesktopID(for: scope.displayID) == scope.desktopID
                && state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?.activeStageID == scope.stageID
        }
        func focused(_ entry: WindowSwitcherEntry) -> Bool { entry.scope.flatMap(stage)?.focusedWindowID == entry.id }
        let managed = entries.filter { $0.scope != nil }
        return managed.first { shown($0.scope!) && focused($0) }
            ?? managed.first { shown($0.scope!) }
            ?? managed.first(where: focused)
            ?? managed.first
            ?? entries.first
    }

    /// État de chaque application : ouverte ou non, et stage et bureau de sa fenêtre la plus
    /// pertinente, avec les noms du rail. O(m), m membres des stages.
    static func details(runningBundleIDs: Set<String>, state: PersistentStageState, stageNames: [StageScope: String]) -> [String: String] {
        var locations: [String: (shown: Bool, text: String)] = [:]
        for scope in state.scopes {
            let current = state.currentDesktopID(for: scope.displayID) == scope.desktopID
            for stage in scope.stages {
                let key = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                guard let name = stageNames[key] else { continue }
                for member in stage.members where member.confirmedClosedAt == nil && runningBundleIDs.contains(member.bundleID) {
                    let shown = current && scope.activeStageID == stage.id
                    if let known = locations[member.bundleID], known.shown || !shown { continue }
                    locations[member.bundleID] = (shown, "\(name) · bureau \(scope.desktopID.rawValue)")
                }
            }
        }
        var result: [String: String] = [:]
        for bundleID in runningBundleIDs {
            result[bundleID] = LauncherList.detail(running: true, location: locations[bundleID]?.text)
        }
        return result
    }

    /// Destinations proposées : stages visibles au rail (nommées ou occupées), bureaux occupés, nommés
    /// ou affichés, puis écrans ; écrans dans leur ordre, bureaux par numéro. O(S + d).
    static func destinations(state: PersistentStageState, displays: [DisplaySnapshot],
                             stageNames: [StageScope: String]) -> [LauncherDestination] {
        var stages: [LauncherDestination] = [], desktops: [LauncherDestination] = [], screens: [LauncherDestination] = []
        for display in displays.sorted(by: { $0.index < $1.index }) {
            let current = state.currentDesktopID(for: display.id)
            let scopes = state.scopes.filter { $0.displayID == display.id }.sorted { $0.desktopID < $1.desktopID }
            for scope in scopes {
                let label = state.label(displayID: display.id, desktopID: scope.desktopID)
                let occupied = scope.stages.contains { !$0.members.isEmpty }
                if occupied || label != nil || scope.desktopID == current {
                    desktops.append(LauncherDestination(kind: .desktop(display.id, scope.desktopID),
                                                        title: "Bureau \(scope.desktopID.rawValue)" + (label.map { " · \($0)" } ?? ""),
                                                        detail: display.name))
                }
                for stage in scope.stages {
                    let key = StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stage.id)
                    guard let name = stageNames[key] else { continue }
                    stages.append(LauncherDestination(kind: .stage(key), title: name,
                                                      detail: "bureau \(scope.desktopID.rawValue) · \(display.name)"))
                }
            }
            screens.append(LauncherDestination(kind: .display(display.id), title: display.name, detail: "écran"))
        }
        return stages + desktops + screens
    }
}

/// Aperçu demandé par la barre (SPEC-078) : la stage visée et la fenêtre qui y arrive, réelle ou à
/// venir (nil : fantôme, avec l'application dont il montre l'icône).
struct LauncherPreviewRequest: Equatable, Sendable {
    let stage: StageScope
    let incoming: WindowID?
    let appPath: String?

    /// Aperçu d'une action de la barre : destination stage d'Ouvrir dans, Envoyer vers ou Amener ici.
    static func of(_ action: LauncherAction) -> LauncherPreviewRequest? {
        guard [.openIn, .sendTo, .bringHere].contains(action.verb), case .stage(let stage)? = action.destination?.kind else { return nil }
        switch action.subject {
        case .app(let app):
            return LauncherPreviewRequest(stage: stage, incoming: nil, appPath: app.path)
        case .file(let file):
            return LauncherPreviewRequest(stage: stage, incoming: nil,
                                          appPath: NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: file.path))?.path)
        case .target(let target):
            guard target.kind == .window, let id = target.scope.windowId,
                  LauncherActionList.ownStage(of: action.subject) != stage else { return nil }
            return LauncherPreviewRequest(stage: stage, incoming: WindowID(rawValue: id), appPath: nil)
        case .url(let url):
            return LauncherPreviewRequest(stage: stage, incoming: nil, appPath: NSWorkspace.shared.urlForApplication(toOpen: url)?.path)
        case .project:
            return nil
        }
    }
}

/// Place de la fenêtre à venir, en coordonnées d'écran AppKit, et l'icône de son application.
struct LauncherGhost {
    let frame: CGRect
    let icon: NSImage?
}

/// Recherche web de ⌃ Retour (SPEC-075), reprise par le repli de la session 077.
extension LauncherSearchContext {
    /// Stage nommée (règle SPEC-067, hors « Stage N ») : son nom, unique dans tout Roadie et stable quand
    /// elle change de bureau. Stage anonyme : sa place. O(1).
    static func rankingContext(_ scope: StageScope, stage: PersistentStage?) -> String {
        rankingContext(scope, name: stage.flatMap { StagePresentationOrder.isNamed($0) ? $0.name : nil })
    }

    static func rankingContext(_ scope: StageScope, name: String?) -> String {
        let folded = name.map(LauncherMatch.fold) ?? ""
        return folded.isEmpty ? "scope:\(scope.description)" : "stage:\(folded)"
    }

    /// Stage qui porte cette identité de classement aujourd'hui (inverse de `rankingContext`). O(S).
    static func stage(for context: String, in state: PersistentStageState) -> StageScope? {
        for scope in state.scopes {
            for stage in scope.stages {
                let key = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                if rankingContext(key, stage: stage) == context { return key }
            }
        }
        return nil
    }
}

enum LauncherWeb {
    /// `{query}` remplacé par le texte encodé ; nil si l'adresse obtenue est invalide. O(q).
    static func searchURL(_ template: String, query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard template.contains("{query}"),
              let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }

    /// Texte envoyé au moteur : un `^` en tête (lu sur le rappel « ⌃ ↩ ») est retiré, comme les espaces.
    /// `^claude` cherche donc « claude » (session 094). O(q).
    static func searchText(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("^") { text = text.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) }
        return text
    }

    /// Suffixes reconnus seuls (research R1 de la 090).
    static let suffixes: Set<String> = ["com", "net", "org", "io", "dev", "fr", "de", "uk", "eu", "be", "ch", "ca", "us", "info", "ai",
                                        "co", "me", "tv", "gg", "ly", "es", "it", "nl", "se", "no", "dk", "fi", "pl", "pt", "at", "jp",
                                        "cn", "ru", "br", "in", "au", "nz", "xyz", "site", "online", "tech", "cloud", "page", "so", "app"]
    /// Aussi des extensions de fichiers : une adresse seulement avec `www.`, un chemin ou un port.
    static let fileLike: Set<String> = ["md", "sh", "py", "rs", "js", "ts", "pl", "app", "zip", "so", "in", "me", "co", "it", "rb", "go"]

    /// Adresse tapée, sans espace : schéma, `localhost` ou IPv4, `www.`, ou nom de domaine à suffixe
    /// connu ; un chemin, un port ou `www.` rendent l'intention claire. nil sinon. O(q).
    static func address(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: text).flatMap { ($0.host ?? "").isEmpty ? nil : $0 }
        }
        let hostEnd = text.firstIndex { "/:?#".contains($0) } ?? text.endIndex
        let host = String(text[..<hostEnd]).lowercased()
        let explicit = hostEnd != text.endIndex
        if host == "localhost" || isIPv4(host) { return explicit || host != "localhost" ? URL(string: "http://" + text) : nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              let suffix = labels.last.map(String.init), suffix.count >= 2, suffix.allSatisfy(\.isLetter) else { return nil }
        let strong = explicit || host.hasPrefix("www.")
        guard strong || (suffixes.contains(suffix) && !fileLike.contains(suffix)) else { return nil }
        return URL(string: "https://" + text)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// Recherche par mot-clé : `yt chat` → YouTube, « chat ». Le mot-clé seul suivi d'une espace donne
    /// un texte vide (ligne d'invite). O(k).
    static func keywordSearch(_ query: String, in searches: [WebSearch]) -> (search: WebSearch, text: String)? {
        guard let space = query.firstIndex(of: " ") else { return nil }
        let keyword = query[..<space].lowercased()
        guard let search = searches.first(where: { $0.keyword.lowercased() == keyword }) else { return nil }
        return (search, query[query.index(after: space)...].trimmingCharacters(in: .whitespaces))
    }

    /// Nom du moteur d'une adresse de recherche : celui d'une recherche connue, sinon l'hôte. O(k).
    static func engineName(_ template: String, searches: [WebSearch]) -> String {
        if let known = (searches + WebSearch.defaults).first(where: { $0.url == template }) { return known.title }
        let host = URL(string: template.replacingOccurrences(of: "{query}", with: "x"))?.host ?? "le web"
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return name.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? name
    }

    /// Lignes de repli : la recherche de `web_search_url`, puis celles de `fallback_searches`. O(k).
    static func fallbackRows(_ text: String, template: String, searches: [WebSearch], fallbacks: [String]) -> [LauncherWebRow] {
        let query = searchText(text)
        guard !query.isEmpty else { return [] }
        var rows: [LauncherWebRow] = []
        if let url = searchURL(template, query: query) {
            rows.append(LauncherWebRow(kind: .search(url), title: "Rechercher « \(query) » sur \(engineName(template, searches: searches))"))
        }
        for keyword in fallbacks {
            guard let search = searches.first(where: { $0.keyword.lowercased() == keyword.lowercased() }),
                  let url = searchURL(search.url, query: query), !rows.contains(where: { $0.kind == .search(url) }) else { continue }
            rows.append(LauncherWebRow(kind: .search(url), title: "Rechercher « \(query) » sur \(search.title)"))
        }
        return rows
    }
}

/// Ligne web de la barre (SPEC-090) : adresse tapée, recherche, ou invite d'une recherche par mot-clé.
struct LauncherWebRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case address(URL)
        case search(URL)
        case hint(WebSearch)
        /// Signet d'un navigateur (session 104).
        case bookmark(LauncherBookmark)
    }

    let kind: Kind
    let title: String

    var id: String {
        switch kind {
        case .address(let url): "web:open:\(url.absoluteString)"
        case .search(let url): "web:search:\(url.absoluteString)"
        case .hint(let search): "web:hint:\(search.keyword)"
        case .bookmark(let bookmark): bookmark.id
        }
    }

    var url: URL? {
        switch kind {
        case .address(let url), .search(let url): url
        case .bookmark(let bookmark): URL(string: bookmark.url)
        case .hint: nil
        }
    }
}
