import AppKit
import ApplicationServices
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

/// Politique du clic extérieur (SPEC-028), partagée avec les tests sans installer de tap système.
enum TargetSearchDismissal {
    static func isMouseDown(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }

    static func eventMask(search: Bool) -> CGEventMask {
        let keyboard = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard search else { return keyboard }
        // Session 131 : défilement au trackpad ou à la molette sur la liste et la grille.
        let mouseTypes: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        return mouseTypes.reduce(keyboard) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }
    }

    /// Annuler le Retour différé avant la fermeture empêche une activation après le clic.
    static func cancelIfOutside(at point: CGPoint, layout: SearchBarLayout?, model: inout TargetSearchModel) -> Bool {
        guard let layout, !layout.contains(point) else { return false }
        model.cancelPendingReturn()
        return true
    }
}

/// Session du mode recherche (SPEC-021). La logique est dans `TargetSearchModel` ; la session lit les
/// touches, met à jour l'affichage et active la cible figée au moment de la validation.
/// Une requête qui commence par `/` passe en mode commande (SPEC-023) : les touches vont alors à
/// `SlashCommandModel` et Retour exécute la commande par `SlashCommandRunner`.
@MainActor
final class TargetSearchSession: TargetOverlaySessionHandle, KeyEventTapSession {
    /// Fermeture sans frappe pendant ce délai.
    static let idleTimeout: TimeInterval = 60

    private var model: TargetSearchModel
    /// Mode commande : créé à la frappe du `/` dans une requête vide, nil en mode recherche.
    private var commandModel: SlashCommandModel?
    private var inputPanel: SearchInputPanel?
    private var style: TargetOverlayStyle
    private let commands: SlashCommandRunner
    private let runDeferred: @MainActor ([String]) -> Void
    private let openSettings: @MainActor (SettingCategory?) -> Void
    private let activate: @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult
    private let onFinish: (@MainActor (TargetActionResult) -> Void)?
    private var lastInputAt = Date()
    private(set) var finished = false
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var eventTapContext: UnsafeMutableRawPointer?
    private var timer: Timer?
    private var windows: [TargetOverlayWindow] = []
    private var searchBarLayout: SearchBarLayout?
    /// Dernière barre montrée : le clic sur le chip retrouve son rectangle (session 099).
    private var shownBar: TargetSearchBar?
    /// Résultats dont la présentation se choisit (session 099) ; nil : liste seule.
    private var viewSource: LauncherViewSource?
    /// Écran du pointeur à l'ouverture : classement des cibles, et barre si `bar_screen` vaut `mouse`.
    private let pointerScreen: CGRect?
    /// Place de la barre (session 102) et glisser en cours : point de départ, centre de la barre au départ,
    /// déplacement réel.
    private var placement: SearchBarPlacement = .bottom
    private var drag: (start: CGPoint, center: CGPoint, moved: Bool)?
    /// Des fenêtres sont encore en cours de lecture.
    private var isLoading: Bool
    /// Un scan asynchrone des éléments à l'écran est prévu pour cette session (Lot I).
    private let expectsOnScreenScan: Bool
    /// Lanceur (SPEC-073) : liste en sections au-dessus de la barre, et ligne choisie.
    private var launcher: LauncherSearchContext
    /// Recherche à l'écran (session 133) : aucune liste, seulement les étiquettes des éléments visibles.
    private let screenOnly: Bool
    private var launcherList = LauncherList.empty
    private var launcherSelection: String?
    /// Requête et cibles de la dernière liste : elle n'est recalculée que si l'une change.
    private var launcherQuery: String?
    private var launcherTargetIDs: [String] = []
    /// Étapes du lanceur (SPEC-074) : objet, puis verbe, puis destination si le verbe en demande une.
    private enum LauncherStep: Equatable {
        case objects
        case verbs(LauncherSubject)
        case destinations(LauncherSubject, LauncherVerb)
        /// ⌘S (SPEC-079) : la saisie est l'abréviation ; échec si l'action ne se garde pas.
        case saving(LauncherAction, Result<LauncherAlias, LauncherAlias.Refusal>)
        /// Lot de la sélection multiple (SPEC-091) : ses verbes, puis la destination d'« Envoyer vers… ».
        case batchVerbs
        case batchDestinations
    }
    /// Sélection multiple (SPEC-091), gardée quand la saisie change.
    private var selection = LauncherSelection()
    /// Verbe du lot qui attend sa destination : « Envoyer vers… », ou un verbe de fichier (session 131).
    private var batchVerb = LauncherVerb.sendTo
    /// « Extraire les adresses » (session 131) : la barre ne montre plus que ces adresses, chacune avec ses verbes.
    private var extractedAddresses: [LauncherText.Address]?
    private var step = LauncherStep.objects
    private var actionList = LauncherActionList()
    private var actionSelection: String?
    /// Saisie des deuxième et troisième étapes ; la requête de l'objet reste dans `model`.
    private var stepQuery = ""
    /// État de tuilage de la fenêtre dont les verbes sont montrés, lu une fois à l'entrée (SPEC-075).
    private var stepTiling: LauncherTilingState?
    /// Documents récents de la dernière application vue à la troisième étape (session 116).
    private var recent: (bundleID: String, destinations: [LauncherDestination])?
    /// Touche tenue qui change ce que fait Retour (SPEC-075).
    private var heldModifier: LauncherModifier?
    /// Maj tenue seule : sous-titre `mods.shift` d'une ligne de workflow (SPEC-088 FR-006).
    private var heldShift = false
    /// Rangs ⌘1 à ⌘9 : index des lignes montrées, dans l'ordre, calculés avec la géométrie.
    private var pickRows: [Int] = []
    /// Lettres Maj (SPEC-084) : index de la ligne de cible montrée pour chaque lettre, dans l'ordre affiché.
    private var letterRows: [String: Int] = [:]
    /// Lettres simples de `hint_characters`, dans leur ordre.
    private let letters: [String]
    /// Fichiers de Spotlight pour la saisie `filesQuery` (SPEC-077) ; `filesChanged` force la liste.
    private let fileSearch = LauncherFileSearch()
    private var files: [LauncherFile] = []
    private var filesQuery: String?
    private var filesChanged = false
    /// Ligne copiée par ⌘C : son détail le dit jusqu'à la frappe suivante.
    private var copiedRowID: String?
    /// Documents et onglets ouverts (SPEC-082), arrivés en fond après l'ouverture.
    private var openItems: [LauncherOpenItem] = []
    /// Signets des navigateurs (session 104), arrivés après l'ouverture.
    private var bookmarks: [LauncherBookmark] = []
    /// Signets et pages pliés en fond à leur lecture, pas à chaque frappe (session 123).
    private var bookmarkIndex = LauncherBookmarkIndex([])
    /// Pages de l'historique des navigateurs (session 114).
    private var historyIndex = LauncherBookmarkIndex([])
    /// Commande système en attente du second Retour (session 105).
    private var pendingSystem: String?
    /// Chemin tapé (SPEC-087) : lecture du dossier en fond, éléments de la saisie `pathFor`.
    private let pathListing = LauncherPathListing()
    private var pathFiles: [LauncherFile] = []
    private var pathFor: String?
    /// Workflows (SPEC-088) : script en cours, saisie demandée, générations par workflow et dernière réponse, par entrée.
    private var workflowRuns: [String: AlfredProcess] = [:]
    private var workflowRequested: [String: String] = [:]
    private var workflowResponses: [String: (argument: String, response: AlfredScriptFilterResponse?, error: String?)] = [:]
    private var workflowPending: [String: DispatchWorkItem] = [:]
    private var workflowReruns: [String: DispatchWorkItem] = [:]
    private var workflowGenerations: [String: UInt64] = [:]
    /// Aperçu actif (SPEC-078) : demande envoyée au contrôleur, attente de 150 ms, fantôme rendu.
    private var sentPreview: LauncherPreviewRequest?
    private var pendingPreview: LauncherPreviewRequest?
    private var previewWork: DispatchWorkItem?
    private var ghost: LauncherGhost?
    /// Étape « Garder » : la commande vient d'être copiée par ⌘C.
    private var savingCopied = false

    init(
        targets: [RoadieTarget],
        alphabet: String,
        style: TargetOverlayStyle,
        commands: SlashCommandRunner,
        runDeferred: @escaping @MainActor ([String]) -> Void,
        openSettings: @escaping @MainActor (SettingCategory?) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        launcher: LauncherSearchContext,
        screenOnly: Bool = false,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        self.screenOnly = screenOnly
        self.launcher = launcher
        let expectsScan = screenOnly || launcher.expectsOnScreenScan
        self.expectsOnScreenScan = expectsScan
        self.isLoading = expectsScan
        let mouse = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(mouse) }?.frame
        self.pointerScreen = pointerScreen
        self.placement = launcher.barPlacement
        self.model = TargetSearchModel(targets: targets, alphabet: alphabet) { Self.rank($0, windowOrder: -1, pointerScreen: pointerScreen) }
        // Fautes de frappe rattrapées (session 134), à l'écran comme dans le lanceur.
        self.model.typoMaxErrors = ConfigReloadService.shared.currentConfig().experimental.targetMode.typoMaxErrors
        self.letters = LauncherList.letters(alphabet)
        self.style = style
        self.commands = commands
        self.runDeferred = runDeferred
        self.openSettings = openSettings
        self.activate = activate
        self.onFinish = onFinish
    }

    /// Écran du pointeur d'abord : la première correspondance mise en avant est sous les yeux, pas sur
    /// un autre moniteur. Puis les fenêtres de l'avant vers l'arrière (cibles Roadie : -1).
    private static func rank(_ target: RoadieTarget, windowOrder: Int, pointerScreen: CGRect?) -> Int {
        guard let pointerScreen, let frame = (target.clickFrame ?? target.frame)?.cgRect else { return 100_000 + windowOrder }
        let ns = RoadieScreenCoordinate.axRectToNS(frame)
        return (pointerScreen.contains(CGPoint(x: ns.midX, y: ns.midY)) ? 0 : 100_000) + windowOrder
    }

    func append(_ targets: [RoadieTarget], windowOrder: Int) {
        guard !finished else { return }
        LauncherOpenClock.current?.mark("scan_first")
        model.append(targets) { Self.rank($0, windowOrder: windowOrder, pointerScreen: pointerScreen) }
        render()
    }

    func finishLoading() {
        guard !finished else { return }
        LauncherOpenClock.current?.mark("scan_done")
        guard isLoading else { return }
        isLoading = false
        render()
    }

    func start() -> TargetActionResult? {
        LauncherOpenClock.current?.mark("session_init")
        guard installEventTap() else {
            return TargetActionResult(changed: false, message: "target_search: event tap unavailable", error: "event_tap_unavailable")
        }
        LauncherOpenClock.current?.mark("event_tap")
        NSApplication.shared.setActivationPolicy(.accessory)
        // Lanceur seul : n'alloue qu'une fenêtre sur l'écran de la barre ; les autres écrans sont
        // ouverts paresseusement si un badge ou un aperçu fantôme y apparaît (Lot I).
        let initialFrames = TargetOverlayPresenter.initialOverlayFrames(
            screens: NSScreen.screens.map(\.frame),
            barScreen: launcher.barScreenFrame,
            pointerScreen: pointerScreen,
            expectsOnScreenScan: expectsOnScreenScan
        )
        windows = initialFrames.map { TargetOverlayWindow(frame: $0, badges: [], style: style) }
        windows.forEach { EffectAnimator.shared.visibility($0, visible: true, action: .launcher, ignoresMouseEvents: true) }
        let input = SearchInputPanel()
        let layout = TargetSearchHotkey.currentLayoutTable()
        input.viewCycle = SearchInputPanel.cycleKey(launcher.viewCycleKey, layout: layout)
        input.barKeys = SearchInputPanel.barKeyTable(launcher.barKeys, layout: layout)
        input.onChange = { [weak self] text in self?.replaceInput(text) }
        input.onKey = { [weak self] key in self?.handleSearch(key) }
        input.onFlags = { [weak self] flags in self?.modifiersChanged(flags) }
        if let subject = launcher.initialSubject { enterVerbs(subject) }
        input.onCancel = { [weak self] in self?.cancel() }
        launcher.subscribeGrid { [weak self] view in self?.updateGrid(view) }
        inputPanel = input
        if let text = launcher.initialQuery, !text.isEmpty { model.replaceQuery(text) }
        LauncherIconRaster.redraw = { [weak self] in self?.windows.forEach { $0.redraw() } }
        LauncherRecentFiles.shared.refresh(extraTypes: launcher.fileTypes, excluded: launcher.fileExcluded)
        LauncherOpenClock.current?.mark("windows_created")
        render()
        LauncherOpenClock.current?.mark("first_render")
        input.beginEditing()
        if launcher.restoredQuery { input.selectAllText() }
        launcher.loadOpenItems { [weak self] items in
            guard let self, !self.finished else { return }
            LauncherOpenClock.current?.mark("open_items")
            self.openItems = items
            self.filesChanged = true
            self.render()
        }
        launcher.loadBookmarks { [weak self] index in
            guard let self, !self.finished else { return }
            LauncherOpenClock.current?.mark("bookmarks")
            let bookmarks = index.entries.map(\.bookmark)
            self.bookmarkIndex = index
            self.bookmarks = bookmarks
            // Mots-clés Firefox avec %s : des recherches par mot-clé de plus (« w chat »).
            let taken = Set(self.launcher.webSearches.map { $0.keyword.lowercased() })
            self.launcher.webSearches += LauncherBookmark.keywordSearches(bookmarks, taken: taken)
            self.filesChanged = true
            self.render()
        }
        launcher.loadHistory { [weak self] pages in
            guard let self, !self.finished else { return }
            LauncherOpenClock.current?.mark("web_history")
            self.historyIndex = pages
            self.filesChanged = true
            self.render()
        }
        launcher.refreshApps { [weak self] apps in
            guard let self, !self.finished else { return }
            LauncherOpenClock.current?.mark("apps_refreshed")
            // Catalogue relu sans changement : rien à redessiner (session 123).
            guard apps != self.launcher.apps else { return }
            self.launcher.apps = apps
            self.launcherQuery = nil
            self.render()
        }
        launcher.loadWorkflows { [weak self] entries, triggers, changedWorkflowIDs in
            guard let self, !self.finished else { return }
            LauncherOpenClock.current?.mark("workflows_refreshed")
            let entriesChanged = entries != self.launcher.workflowEntries || triggers != self.launcher.workflowTriggers
            guard entriesChanged || !changedWorkflowIDs.isEmpty else { return }
            self.launcher.workflowEntries = entries
            self.launcher.workflowTriggers = triggers
            if !changedWorkflowIDs.isEmpty {
                self.invalidateWorkflowState(for: changedWorkflowIDs)
            }
            self.launcherQuery = nil
            self.filesChanged = true
            self.render()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        return nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        guard !finished, self.style != style else { return }
        self.style = style
        windows.forEach { $0.updateStyle(style) }
        render()
    }

    func cancel() {
        finish(TargetActionResult(changed: false, message: "target_search_cancelled", error: "cancelled"))
    }

    /// Défilement accumulé au-dessus de la liste ou de la grille : un pas de `LauncherScroll.step` points déplace la
    /// sélection d'une ligne (d'une rangée en grille), donc la partie visible. Faux hors de la liste. O(1).
    func handleScroll(at point: CGPoint, delta: Double) -> Bool {
        guard !finished, let layout = searchBarLayout, let panel = layout.panel else { return false }
        let nsPoint = RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        guard panel.contains(nsPoint) else { return false }
        let (steps, rest) = LauncherScroll.steps(accumulated: scrollAccumulator, delta: delta)
        scrollAccumulator = rest
        guard steps != 0 else { return true }
        let input = SearchKeyInput(kind: steps > 0 ? .previous : .next)
        for _ in 0..<abs(steps) {
            if step == .objects { navigate(input) } else { handleStep(input) }
        }
        syncHighlight()
        render()
        return true
    }
    private var scrollAccumulator = 0.0

    func handleMouseDown(at point: CGPoint, type: CGEventType, clicks: Int = 1) -> Bool {
        guard !finished else { return false }
        let nsPoint = RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        if let layout = searchBarLayout, layout.contains(nsPoint) {
            lastInputAt = Date()
            model.cancelPendingReturn()
            if let panel = layout.panel, panel.contains(nsPoint) {
                if type == .leftMouseDown, step != .objects,
                   let index = layout.suggestionIndex(at: nsPoint, count: actionList.rows.count,
                                                      selected: actionList.rows.firstIndex { $0.id == actionSelection && $0.id != nil }),
                   let id = actionList.rows[index].id {
                    actionSelection = id
                    confirmStep()
                    return true
                }
                if type == .leftMouseDown, commandModel == nil, step == .objects,
                   let index = layout.suggestionIndex(at: nsPoint, count: launcherList.rows.count, selected: selectedLauncherRow),
                   let id = launcherList.rows[index].id {
                    launcherSelection = id
                    syncHighlight()
                    activateSelection(immediate: true)
                    return true
                }
                if type == .leftMouseDown, var command = commandModel,
                   let index = layout.suggestionIndex(at: nsPoint, count: command.suggestions.count, selected: command.selected) {
                    command.selectSuggestion(at: index)
                    command.acceptSelectedSuggestion()
                    commandModel = command
                    render()
                }
                // Hors d'une ligne (marges, titres) : le fond de la liste déplace la barre (session 102).
                if type == .leftMouseDown { beginDrag(at: nsPoint, bar: layout.bar, clicks: clicks) }
                return true
            }
            // Chip de la présentation (session 099) : un clic passe à la suivante.
            if type == .leftMouseDown, step == .objects, viewSource != nil, let bar = shownBar,
               let chip = SearchBarRenderer.counterFrame(bar, bar: layout.bar, style: style), chip.contains(nsPoint) {
                cycleView()
                return true
            }
            // Bord de la barre, hors du champ : glisser la déplace, double-clic la remet à sa place par défaut.
            if type == .leftMouseDown, let bar = shownBar,
               !SearchBarRenderer.inputFrame(bar, bar: layout.bar, style: style).contains(nsPoint) {
                beginDrag(at: nsPoint, bar: layout.bar, clicks: clicks)
                return true
            }
            return false // Le champ natif reçoit clic, sélection et menu contextuel.
        }
        if TargetSearchDismissal.cancelIfOutside(at: nsPoint, layout: searchBarLayout, model: &model) { cancel() }
        return false
    }

    /// Début d'un glisser de la barre ; un double-clic oublie la place retenue (session 102).
    private func beginDrag(at point: CGPoint, bar: CGRect, clicks: Int) {
        if clicks >= 2 {
            drag = nil
            placement = launcher.defaultBarPlacement
            launcher.savePlacement(nil)
            render()
            return
        }
        drag = (point, CGPoint(x: bar.midX, y: bar.midY), false)
    }

    /// Glisser de la barre : elle suit le pointeur ; au relâchement, sa place est retenue. Vrai si
    /// l'événement appartient au glisser. O(rendu).
    func handleMouseDrag(at point: CGPoint, ended: Bool) -> Bool {
        guard !finished, var current = drag else { return false }
        let nsPoint = RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        let dx = nsPoint.x - current.start.x, dy = nsPoint.y - current.start.y
        if abs(dx) + abs(dy) > 2 { current.moved = true }
        if current.moved, let screen = windows.first(where: { $0.frame.contains(current.center) })?.frame
            ?? launcher.barScreenFrame ?? pointerScreen {
            placement = .custom(center: CGPoint(x: current.center.x + dx, y: current.center.y + dy), in: screen)
            render()
        }
        drag = ended ? nil : current
        if ended, current.moved { launcher.savePlacement(placement) }
        return true
    }

    private func replaceInput(_ text: String) {
        guard !finished else { return }
        lastInputAt = Date()
        model.cancelPendingReturn()
        if step != .objects {
            stepQuery = text
            refreshActions()
            render()
            return
        }
        if text.hasPrefix("/"), !Self.isPath(text) {
            if commandModel == nil {
                model.replaceQuery("/")
                enterCommandMode()
            }
            commandModel?.replaceInput(String(text.dropFirst()))
        } else {
            commandModel = nil
            model.replaceQuery(text)
        }
        render()
    }

    private static func isConfirm(_ input: SearchKeyInput) -> Bool {
        if case .confirm = input.kind { return true }
        return false
    }

    /// Exigé par `KeyEventTapSession` ; la recherche reçoit `SearchKeyInput` via `handleSearch`.
    func handle(_ input: KeyInput) {}

    func handleSearch(_ input: SearchKeyInput) {
        guard !finished else { return }
        lastInputAt = Date()
        // Toute autre touche que Retour annule une confirmation en attente (session 105).
        if pendingSystem != nil, !Self.isConfirm(input) { pendingSystem = nil }
        if step != .objects {
            handleStep(input)
            return
        }
        // Mode commande (SPEC-023 R3) : aiguillage avant le modèle de recherche. Un chemin `/Users…`
        // reste une recherche (SPEC-087).
        if commandModel != nil {
            handleCommand(input)
            return
        }
        if case .escape = input.kind {
            model.cancelPendingReturn()
            // Échap vide d'abord la sélection, puis ferme (SPEC-091 FR-003).
            if !selection.isEmpty {
                selection.clear()
                render()
                return
            }
            // Message distinct : le contrôleur rend le focus clavier à l'application (session 097).
            finish(TargetActionResult(changed: false, message: "target_search_escaped", error: "cancelled"))
            return
        }
        if case .confirm(let shift, let command, let option, let control, let isRepeat) = input.kind {
            guard !isRepeat else { return }
            // Retour avec une sélection : ses verbes, sans agir tout de suite (FR-003).
            if !selection.isEmpty {
                enterBatch()
                render()
                return
            }
            if let modifier = Self.modifier(command: command && !shift, option: option, control: control),
               let variant = currentVariant(modifier) {
                finishVariant(variant)
                return
            }
            if case .calc(let calc)? = launcherList.row(for: launcherSelection) {
                finishCalc(calc)
                return
            }
            if confirmWorkflow(modifiers: Self.alfredModifiers(command: command, option: option, control: control, shift: shift)) { return }
            if confirmWeb() { return }
            if case .app(let app, _)? = launcherList.row(for: launcherSelection) {
                finishLaunching(app)
                return
            }
            if case .file(let file)? = launcherList.row(for: launcherSelection) {
                finishAction(LauncherAction(subject: .file(file), verb: fileVerb, destination: nil))
                return
            }
            switch launcherList.row(for: launcherSelection) {
            case .phrase(let action, _)?, .alias(_, let action, _)?:
                finishAction(action)
                return
            case .project(let project)?:
                finishAction(LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil))
                return
            case .action(let key, let action, _, _)?:
                if key == "undo-batch" { finishUndo() } else { finishAction(action) }
                return
            case .rule(let suggestion, let choice)?:
                finishRule(suggestion, choice)
                return
            case .openItem(let item)?:
                finishOpenItem(item)
                return
            default: break
            }
            guard let target = model.highlighted else { return }
            if let verb = model.pressReturn(shift: shift, command: command, at: Date()) {
                finishActivating(target, verb)
            }
            return
        }
        // Retour seul en attente : les autres touches sont ignorées jusqu'à l'échéance.
        guard !model.isAwaitingSecondReturn else { return }
        switch input.kind {
        case .text(let value):
            model.type(value)
            if model.isCommandMode, !Self.isPath(model.query) { enterCommandMode() }
        case .labelCharacter(let value):
            // Recherche à l'écran : Maj + étiquette complète clique la cible, comme Retour (essai du 30 octobre
            // 2026 : choisir sans cliquer ne se devinait pas). Une étiquette de deux lettres attend la seconde.
            if screenOnly {
                if let verb = model.chooseLabel(value), let target = model.highlighted {
                    finishActivating(target, verb)
                    return
                }
                break
            }
            // Maj + lettre d'une pastille : sa ligne s'ouvre, comme ⌘ + chiffre (SPEC-084).
            guard let index = letterRows[value], index < launcherList.rows.count else { return }
            launcherSelection = launcherList.rows[index].id
            syncHighlight()
            activateSelection(immediate: true)
            return
        case .delete:
            model.deleteBackward()
        case .next, .previous:
            navigate(input)
        case .actions:
            // Chemin tapé : → ouvre les verbes, Tab complète (SPEC-087).
            if Self.isPath(model.query), case .file(let file)? = launcherList.row(for: launcherSelection) {
                enterVerbs(.file(file))
            } else if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection), item.isFile,
                      let path = item.arg.first, path.hasPrefix("/") {
                // Fichier rendu par un workflow (filtre de fichiers) : ses verbes de Roadie (SPEC-089 FR-006).
                enterVerbs(.file(LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)))
            } else {
                navigate(SearchKeyInput(kind: .next, navigationSource: .tab))
            }
        case .pick(let rank):
            pick(rank)
            return
        case .copy:
            copySelection()
        case .save:
            if let action = objectAction() { enterSaving(action) }
        case .showRules:
            model.replaceQuery("")
        case .selectToggle:
            if let subject = Self.subject(of: launcherList.row(for: launcherSelection)) { selection.toggle(subject) }
        case .selectAddNext:
            if let subject = Self.subject(of: launcherList.row(for: launcherSelection)), LauncherSelection.key(subject) != nil {
                selection.add(subject)
                launcherSelection = launcherList.neighbour(of: launcherSelection, step: 1)
                syncHighlight()
            }
        case .selectRemoveLast:
            selection.removeLast()
        case .selectionVerbs:
            if !selection.isEmpty { enterBatch() }
        case .selectClear:
            selection.clear()
        case .move(let step):
            moveInGrid(step)
        case .cycleView:
            cycleView()
        case .parentFolder:
            if let parent = LauncherPathRules.parent(model.query) { model.replaceQuery(parent) }
        case .largeType:
            // ⌘L : la ligne en grand texte, la barre se ferme comme chez Alfred (session 105).
            guard let text = selectionText else { return }
            finish(TargetActionResult(changed: true, message: "launcher large type"))
            LargeTypePanel.show(text)
            return
        case .closeAll:
            finish(TargetActionResult(changed: false, message: "target_search_escaped", error: "cancelled"))
            return
        case .openSettings:
            // ⌘, : les Paramètres de Roadie, comme les préférences d'Alfred (session 115).
            finish(TargetActionResult(changed: true, message: "launcher settings"))
            SettingsWindowController.shared.show(category: nil)
            return
        case .preview:
            if case .file(let file)? = launcherList.row(for: launcherSelection) {
                finishAction(LauncherAction(subject: .file(file), verb: .quickLook, destination: nil))
                return
            }
            if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection), let raw = item.quickLookURL {
                let path = URL(string: raw).flatMap { $0.isFileURL ? $0.path : nil } ?? NSString(string: raw).expandingTildeInPath
                if path.hasPrefix("/") {
                    let file = LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)
                    finishAction(LauncherAction(subject: .file(file), verb: .quickLook, destination: nil))
                    return
                }
            }
        case .escape, .confirm, .ignored:
            break
        }
        render()
    }

    /// Flèches et Ctrl-N/P parcourent la liste du lanceur ; Tab complète la ligne choisie.
    private func navigate(_ input: SearchKeyInput) {
        guard !launcherList.rows.isEmpty else { model.handleNavigation(input); return }
        // Grille (SPEC-092 FR-004) : ↑ ↓ changent de rangée ; Tab garde son rôle.
        if let columns = gridColumns, input.navigationSource != .tab {
            if case .next = input.kind { moveInGrid(columns) } else { moveInGrid(-columns) }
            return
        }
        if input.navigationSource == .tab, case .next = input.kind {
            switch launcherList.row(for: launcherSelection) {
            case .app(let app, _): enterVerbs(.app(app))
            case .target(let target): enterVerbs(.target(target))
            case .file(let file):
                if Self.isPath(model.query) { completePath(file) } else { enterVerbs(.file(file)) }
            case .phrase(let action, _), .alias(_, let action, _): enterVerbs(action.subject)
            case .project(let project): enterVerbs(.project(project.name))
            case .action(_, let action, _, _): enterVerbs(action.subject)
            // Session 131 : onglet ou document ouvert, résultat d'un calcul, texte de la recherche web.
            case .openItem(let item): enterVerbs(.openItem(item))
            case .calc(let calc): enterVerbs(.text(calc.text))
            case .rule, .terminal, .system: break
            case .workflowKeyword(let entry): completeWorkflow(entry, nil)
            case .web(let row):
                if case .search = row.kind, !LauncherWeb.searchText(model.query).isEmpty {
                    enterVerbs(.text(LauncherWeb.searchText(model.query)))
                } else if let url = row.url { enterVerbs(.url(url)) } else if case .hint(let search) = row.kind { model.replaceQuery(search.keyword + " ") }
            case .history(let query): model.replaceQuery(query)
            case .workflowItem(let entry, let item, _):
                // Fichier rendu par un workflow (filtre de fichiers, grille de fichiers) : ses verbes de Roadie.
                if item.isFile, let path = item.arg.first, path.hasPrefix("/") {
                    enterVerbs(.file(LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)))
                } else if let text = item.autocomplete { completeWorkflow(entry, text) }
            case .header, nil: model.handleNavigation(input)
            }
            return
        }
        guard case .next = input.kind else {
            launcherSelection = launcherList.neighbour(of: launcherSelection, step: -1)
            syncHighlight()
            return
        }
        launcherSelection = launcherList.neighbour(of: launcherSelection, step: 1)
        syncHighlight()
    }

    /// La ligne choisie et le cadre épais à l'écran désignent la même cible. O(n).
    private func syncHighlight() {
        switch launcherList.row(for: launcherSelection) {
        case .target(let target): model.highlight(targetID: target.id)
        case .app, .file, .phrase, .alias, .project, .action, .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .web, .history,
             .terminal, .system:
            model.highlight(targetID: nil)
        case .header, nil: break
        }
    }

    /// Recalcule la liste si la requête ou les cibles ont changé. Nouvelle requête : la meilleure
    /// ligne est choisie ; nouvelles cibles seulement : la ligne choisie est gardée si elle reste. O(a + n).
    /// Lignes de la barre, puis la présentation choisie pour leur source (session 099).
    private func refreshLauncher() {
        // Recherche à l'écran : la liste reste vide ; ↑/↓ et Retour passent aux cibles (session 133).
        guard !screenOnly else { return }
        LauncherOpenClock.measure("rows") { refreshLauncherRows() }
        viewSource = currentViewSource()
        applyViewMode()
    }

    /// Présentation des résultats : celle retenue pour la source ; la grille d'un workflow (092) garde la
    /// sienne. O(1).
    private var viewMode: LauncherViewMode { launcher.workflowGrid == nil ? launcher.viewBook.mode(for: viewSource) : .list }

    /// Colonnes de la grille montrée ; nil pour une liste.
    private var gridColumns: Int? {
        if let grid = launcher.workflowGrid { return grid.loadingText == nil ? grid.columns : nil }
        return viewMode.columns
    }

    /// Source des résultats (FR-001) : une seule entrée de workflow à résultats, un chemin tapé, ou des
    /// fichiers dans la recherche ordinaire. O(e + n).
    private func currentViewSource() -> LauncherViewSource? {
        guard launcher.workflowGrid == nil, step == .objects, commandModel == nil, !model.query.isEmpty else { return nil }
        let runs = launcher.workflowEntries.filter { if case .run = $0.match(model.query) { return true } else { return false } }
        if !runs.isEmpty {
            guard runs.count == 1, let entry = runs.first, [.scriptFilter, .listFilter, .fileFilter].contains(entry.kind) else { return nil }
            let files = entry.kind == .fileFilter || launcherList.rows.contains { if case .workflowItem(_, let item, _) = $0 { return item.isFile } else { return false } }
            return .workflow(entry.id, itemsAreFiles: files)
        }
        if Self.isPath(model.query) { return .folder(LauncherPathRules.parts(model.query).directory) }
        if LauncherAppsGrid.query(model.query) != nil { return .apps }
        return launcherList.rows.contains { if case .file = $0 { return true } else { return false } } ? .files : nil
    }

    /// En grille : lignes sans titres de section, fichiers seuls pour la recherche ordinaire ; la ligne
    /// choisie reste si elle est montrée. Sans effet en liste. O(n).
    private func applyViewMode() {
        guard let source = viewSource, viewMode != .list else { return }
        let rows = source.gridRows(launcherList.rows)
        guard rows != launcherList.rows else { return }
        launcherList = .idle(rows)
        if launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Présentation suivante pour cette source (touche ou chip), retenue ; les lignes sont refaites. O(s).
    private func cycleView() {
        guard let source = viewSource else { return }
        launcher.viewBook.set(viewMode.next, for: source)
        launcher.saveViews(launcher.viewBook)
        launcherQuery = nil
        filesChanged = true
        render()
    }

    private func refreshLauncherRows() {
        if let grid = launcher.workflowGrid {
            refreshGrid(grid)
            return
        }
        if let addresses = extractedAddresses {
            let folded = LauncherMatch.fold(model.query)
            let rows = addresses.filter { folded.isEmpty || LauncherMatch.fold($0.text).contains(folded) }
                .map { LauncherList.Row.web(LauncherWebRow(kind: .address($0.url), title: $0.text)) }
            launcherQuery = model.query
            launcherList = .idle([.header(tr("Adresses", "Addresses"))] + rows)
            if launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
            syncHighlight()
            return
        }
        // `>` : la commande pour le terminal, seule (session 103), comme le préfixe d'Alfred.
        if let command = LauncherTerminal.command(model.query) {
            pruneWorkflows(keeping: [])
            launcherQuery = model.query
            launcherList = .idle([.header("Terminal"), .terminal(command)])
            launcherSelection = launcherList.best
            syncHighlight()
            return
        }
        // `apps …` (session 131, Launchpad d'Alfred 6) : toutes les applications par catégorie, épinglées en tête.
        if let appsQuery = LauncherAppsGrid.query(model.query) {
            pruneWorkflows(keeping: [])
            launcherQuery = model.query
            let sections = LauncherAppsGrid.sections(apps: launcher.apps, query: appsQuery, pins: LauncherAppsPins().load())
            launcherList = .idle(sections.flatMap { [LauncherList.Row.header($0.title)] + $0.apps.map { .app($0, detail: "") } })
            if launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
            syncHighlight()
            return
        }
        // `symbols …` (session 131) : navigateur SF Symbols, ouvert par Retour avec cette recherche.
        if let symbolsQuery = LauncherSymbols.query(model.query) {
            pruneWorkflows(keeping: [])
            launcherQuery = model.query
            let row = LauncherSystemCommand(id: "sf-symbols:" + symbolsQuery, title: tr("Navigateur SF Symbols", "SF Symbols browser"), keywords: [],
                                            symbol: "square.grid.3x3", confirms: false,
                                            detail: symbolsQuery.isEmpty ? tr("Tous les symboles", "All symbols") : "« \(symbolsQuery) »")
            launcherList = .idle([.header("SF Symbols"), .system(row)])
            launcherSelection = launcherList.best
            syncHighlight()
            return
        }
        // `menu …` (session 131) : éléments des menus de l'application au premier plan.
        if let menuQuery = LauncherMenuSearch.query(model.query), let front = launcher.frontApplication {
            let menus = LauncherMenuSearch.shared
            menus.load(pid: front.pid, appName: front.name, events: EventLog()) { [weak self] in
                guard let self, !self.finished else { return }
                self.launcherQuery = nil
                self.render()
            }
            pruneWorkflows(keeping: [])
            launcherQuery = model.query
            let found = menus.rows(menuQuery)
            var rows: [LauncherList.Row] = [.header(tr("Menus de \(front.name)", "\(front.name) menus"))]
            if found.isEmpty {
                rows.append(.system(LauncherSystemCommand(id: "menu:none", title: menus.isLoading ? tr("Lecture des menus…", "Reading menus…")
                                                                                  : tr("Aucun élément", "No item"),
                                                          keywords: [], symbol: "filemenu.and.selection", confirms: false, detail: front.name)))
            }
            launcherList = .idle(rows + found.map(LauncherList.Row.system))
            if launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
            syncHighlight()
            return
        }
        let runs = launcher.workflowEntries.compactMap { entry -> (entry: AlfredEntry, argument: String)? in
            if case .run(let argument) = entry.match(model.query) { return (entry, argument) }
            return nil
        }
        pruneWorkflows(keeping: Set(runs.map(\.entry.id)))
        if !runs.isEmpty {
            refreshWorkflows(runs)
            return
        }
        if Self.isPath(model.query) {
            refreshPath()
            return
        }
        LauncherOpenClock.measure("files") { refreshFiles() }
        let ids = model.matches.map(\.id)
        guard model.query != launcherQuery || ids != launcherTargetIDs || filesChanged else { return }
        let queryChanged = model.query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = model.query
        launcherTargetIDs = ids
        filesChanged = false
        // Barre vide (SPEC-081) : les propositions du moment, la première choisie.
        if model.query.isEmpty {
            launcherList = .idle(launcher.idleRows)
            if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
            syncHighlight()
            return
        }
        // Phrase (SPEC-079) : les premiers mots cherchent l'objet, la ligne de l'action passe en tête.
        let phrase = LauncherPhrase.parse(model.query, destinations: launcher.destinations, newStageHome: launcher.newStageHome)
        launcherList = LauncherList(query: phrase?.objectQuery ?? model.query, apps: launcher.apps, details: launcher.details,
                                    targets: model.matches, ranking: launcher.ranking, now: Date(), context: launcher.rankingContext,
                                    files: phrase == nil ? files : [], projects: launcher.projects, openItems: openItems,
                                    fileKeywords: launcher.fileKeywords, typoMaxErrors: model.typoMaxErrors,
                                    targetsCorrected: model.corrected)
        if let phrase, let subject = Self.subject(of: launcherList.row(for: launcherList.best)),
           let action = phrase.action(for: subject, activeStage: launcher.activeStage) {
            launcherList.prepend(.phrase(action, LauncherPhrase.title(action)), header: "Phrase")
        }
        if let (name, alias) = launcher.aliases.alias(for: model.query), let action = launcher.aliasAction(alias) {
            launcherList.prepend(.alias(name, action, LauncherPhrase.title(action)), header: tr("Abréviation", "Abbreviation"))
        }
        // Commandes système (session 105), après la première section.
        launcherList.insertSection(tr("Système", "System"), LauncherSystemCommand.matches(model.query, in: launcher.systemCommands).map(LauncherList.Row.system))
        // Réglages de Roadie et des Réglages Système (session 115), après les sections principales.
        launcherList.appendSection(tr("Réglages", "Settings"), LauncherSystemCommand.matches(model.query, in: launcher.settingTargets, limit: 4)
            .map(LauncherList.Row.system))
        // Mots-clés de workflows en cours de frappe (SPEC-088), après la première section.
        let keywords = launcher.workflowEntries.filter { $0.match(model.query) == .suggest }
        launcherList.insertSection("Workflows", keywords.prefix(4).map(LauncherList.Row.workflowKeyword))
        // Signets des navigateurs (session 104), avant les replis ; un mot-clé Firefox tapé seul passe en tête.
        if phrase == nil {
            let marks = LauncherBookmark.matches(model.query, in: bookmarkIndex)
            launcherList.appendSection(tr("Signets", "Bookmarks"), marks.map { .web(LauncherWebRow(kind: .bookmark($0), title: $0.title)) })
            // Historique (session 114) : pages déjà vues, hors signets proposés.
            let shown = Set(marks.map { LauncherWebHistory.normalized($0.url) })
            launcherList.appendSection(tr("Historique", "History"), LauncherWebHistory.matches(model.query, in: historyIndex, excluding: shown).map {
                .web(LauncherWebRow(kind: .bookmark($0), title: $0.title))
            })
            let typed = model.query.trimmingCharacters(in: .whitespaces).lowercased()
            if let keyword = bookmarks.first(where: { $0.keyword?.lowercased() == typed && !$0.url.contains("%s") }) {
                launcherList.prepend(.web(LauncherWebRow(kind: .bookmark(keyword), title: keyword.title)), header: tr("Signet", "Bookmark"))
            }
        }
        // Recherches de repli et actions universelles sur texte des workflows, en bas (SPEC-089 FR-003, FR-004).
        launcherList.appendSection(tr("Repli", "Fallback"), fallbackRows(model.query))
        // Web (SPEC-090) : repli en bas ; recherche par mot-clé et adresse tapée en tête, choisies.
        let webRows = LauncherWeb.fallbackRows(model.query, template: launcher.webSearchTemplate,
                                               searches: launcher.webSearches, fallbacks: launcher.fallbackSearches).map(LauncherList.Row.web)
        if model.query.hasPrefix("^") {
            // `^texte` (lu sur « ⌃ ↩ ») : les recherches web en tête, la première choisie (session 094).
            launcherList.prependSection("Web", webRows)
        } else {
            launcherList.appendSection("Web", webRows)
            if let (search, text) = LauncherWeb.keywordSearch(model.query, in: launcher.webSearches) {
                if text.isEmpty {
                    launcherList.prepend(.web(LauncherWebRow(kind: .hint(search), title: tr("\(search.title) : tapez la recherche", "\(search.title): type your search"))), header: "Web")
                } else if let url = LauncherWeb.searchURL(search.url, query: text) {
                    launcherList.prepend(.web(LauncherWebRow(kind: .search(url), title: tr("Rechercher « \(text) » sur \(search.title)", "Search \(search.title) for “\(text)”"))), header: "Web")
                }
            } else if let search = launcher.webSearches.first(where: { $0.keyword.lowercased() == model.query.lowercased() }) {
                // Mot-clé seul : l'invite, sans prendre la sélection (`g` ne cache pas Ghostty).
                launcherList.insertSection("Web", [.web(LauncherWebRow(kind: .hint(search), title: tr("\(search.title) : tapez la recherche", "\(search.title): type your search")))])
            }
        }
        if let url = LauncherWeb.address(model.query) {
            launcherList.prepend(.web(LauncherWebRow(kind: .address(url), title: tr("Ouvrir", "Open") + " \(url.absoluteString)")), header: tr("Adresse", "Address"))
        }
        // Calcul (SPEC-087) ou conversion hors ligne (Spec 161) : passe en tête et devient la ligne choisie.
        if let calc = LauncherCalculator.evaluate(model.query, locale: launcher.calcLocale, grouping: launcher.calcGrouping) {
            launcherList.prepend(.calc(calc), header: tr("Calcul", "Calculation"))
        } else if launcher.calcConversions,
                  let conversion = LauncherConverter.evaluate(model.query, locale: launcher.calcLocale, grouping: launcher.calcGrouping) {
            launcherList.prepend(.calc(conversion), header: tr("Conversion", "Conversion"))
        }
        // Émojis & symboles typographiques hors ligne (Spec 161 : `:…` ou `emoji …`).
        if launcher.emojiPicker, let emojis = LauncherEmojiCatalog.matches(model.query) {
            let emojiRows: [LauncherList.Row] = emojis.map { item in
                .system(LauncherSystemCommand(
                    id: "emoji-copy:\(item.glyph)",
                    title: "\(item.glyph)  \(item.name)",
                    keywords: item.keywords,
                    symbol: "face.smiling",
                    confirms: false,
                    detail: "\(item.category) · " + tr("Retour copie", "Return copies")
                ))
            }
            launcherList.prependSection(tr("Émojis et symboles", "Emojis & symbols"), emojiRows)
        }
        // Minuteur & Pomodoro locaux (Spec 161 : `timer …`, `pomodoro`).
        if launcher.timerEnabled, let timerQuery = LauncherTimerService.parseQuery(model.query) {
            let timerRows = Self.timerRows(for: timerQuery)
            launcherList.prependSection(tr("Minuteur", "Timer"), timerRows)
        }
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    // MARK: - Workflows (SPEC-088)

    /// Bits des modificateurs d'Alfred pour les touches tenues avec Retour.
    private static func alfredModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> Int {
        (command ? 1_048_576 : 0) + (option ? 524_288 : 0) + (control ? 262_144 : 0) + (shift ? 131_072 : 0)
    }

    /// Entrées qui ne correspondent plus à la saisie : leur script s'arrête, leur réponse est oubliée.
    private func pruneWorkflows(keeping active: Set<String>) {
        let keys = Set(workflowRuns.keys)
            .union(workflowResponses.keys)
            .union(workflowPending.keys)
            .union(workflowReruns.keys)
        for key in keys where !active.contains(key) {
            workflowRuns.removeValue(forKey: key)?.cancel()
            workflowPending.removeValue(forKey: key)?.cancel()
            workflowReruns.removeValue(forKey: key)?.cancel()
            workflowResponses[key] = nil
            workflowRequested[key] = nil
        }
    }

    /// Invalide les processus, délais, relances `rerun` et réponses Script Filter des workflows
    /// modifiés ou retirés lors d'un rafraîchissement asynchrone, et incrémente la génération par
    /// `workflowID` (les workflows inchangés poursuivent normalement leur exécution) (Lot D).
    private func invalidateWorkflowState(for workflowIDs: Set<String>) {
        for id in workflowIDs {
            workflowGenerations[id, default: 0] &+= 1
        }
        let prefixes = workflowIDs.map { "wf:\($0):" }
        let keys = Set(workflowRuns.keys)
            .union(workflowResponses.keys)
            .union(workflowPending.keys)
            .union(workflowReruns.keys)
            .union(workflowRequested.keys)
        for key in keys where prefixes.contains(where: { key.hasPrefix($0) }) {
            workflowRuns.removeValue(forKey: key)?.cancel()
            workflowPending.removeValue(forKey: key)?.cancel()
            workflowReruns.removeValue(forKey: key)?.cancel()
            workflowResponses[key] = nil
            workflowRequested[key] = nil
        }
    }

    /// Mot-clé tapé : seules les lignes de ce ou ces workflows, sous leur nom ; la réponse précédente
    /// reste affichée pendant que le script tourne (FR-002, FR-005, FR-006). O(i log i).
    private func refreshWorkflows(_ runs: [(entry: AlfredEntry, argument: String)]) {
        let query = model.query
        for run in runs where run.entry.kind == .scriptFilter || run.entry.kind == .fileFilter { requestScriptFilter(run.entry, run.argument) }
        guard query != launcherQuery || filesChanged else { return }
        let queryChanged = query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = query
        filesChanged = false
        var rows: [LauncherList.Row] = []
        for (entry, argument) in runs {
            rows.append(.header(entry.workflowName))
            if entry.kind == .listFilter {
                // Filtre de liste (SPEC-089 FR-005) : éléments fixes, filtrés par la barre.
                let items = AlfredScriptFilterResponse.filter(entry.listItems, query: argument, mode: entry.filterMode)
                rows += items.enumerated().map { .workflowItem(entry, $0.element, index: $0.offset) }
                continue
            }
            // Session 131 : dictionnaire de macOS et applications ouvertes, sans script.
            if entry.kind == .dictionary || entry.kind == .runningApps {
                let items = entry.kind == .dictionary
                    ? AlfredSystemObjects.dictionaryItems(argument, showAllWords: entry.showAllWords)
                    : AlfredSystemObjects.runningAppItems(argument, apps: AlfredSystemObjects.runningApps(), outputType: entry.outputType,
                                                          prefix: entry.outputPrefix)
                rows += items.enumerated().map { .workflowItem(entry, $0.element, index: $0.offset) }
                continue
            }
            guard entry.kind == .scriptFilter || entry.kind == .fileFilter else { rows.append(.workflowKeyword(entry)); continue }
            guard let answer = workflowResponses[entry.id], let response = answer.response else {
                let waiting = workflowResponses[entry.id]?.error ?? (entry.runningSubtitle.isEmpty ? tr("Recherche…", "Searching…") : entry.runningSubtitle)
                rows.append(.workflowItem(entry, AlfredItem(title: entry.title, subtitle: waiting, valid: false), index: 0))
                continue
            }
            var items = entry.filtersResults ? AlfredScriptFilterResponse.filter(response.items, query: argument, mode: entry.filterMode) : response.items
            if !response.skipKnowledge {
                // Classement appris par `uid`, l'ordre du script sinon (tri stable).
                let ranking = launcher.ranking
                items = items.enumerated().sorted { a, b in
                    let ua = a.element.uid.map { ranking.exactUses("\(entry.id):\($0)", query: query) } ?? 0
                    let ub = b.element.uid.map { ranking.exactUses("\(entry.id):\($0)", query: query) } ?? 0
                    return ua != ub ? ua > ub : a.offset < b.offset
                }.map(\.element)
            }
            if items.isEmpty { rows.append(.workflowItem(entry, AlfredItem(title: tr("Aucun résultat", "No results"), subtitle: entry.title, valid: false), index: 0)) }
            rows += items.enumerated().map { .workflowItem(entry, $0.element, index: $0.offset) }
        }
        launcherList = .idle(rows)
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Grille d'un workflow (SPEC-092) : ses tuiles, filtrées par la saisie si la grille l'est ; à
    /// l'ouverture, la tuile `preselect`, sinon la première choisissable. O(n × m).
    private func refreshGrid(_ grid: AlfredGridView) {
        let first = launcherQuery == nil
        guard first || model.query != launcherQuery else { return }
        launcherQuery = model.query
        if let text = grid.loadingText {
            // Attente ou échec du script : une seule ligne, sans tuiles.
            launcherList = .idle([.workflowItem(grid.entry, AlfredItem(title: text, subtitle: grid.entry.workflowName, valid: false), index: 0)])
            launcherSelection = launcherList.best
            return
        }
        var items = grid.filterable ? AlfredScriptFilterResponse.filter(grid.items, query: model.query, mode: grid.entry.filterMode) : grid.items
        if grid.learnsOrder { items = AlfredGridView.learned(items, entryID: grid.entry.id, ranking: launcher.ranking, query: model.query) }
        launcherList = .idle(items.enumerated().map { .workflowItem(grid.entry, $0.element, index: $0.offset) })
        let preselected = first ? grid.preselect.flatMap { uid in items.firstIndex { $0.uid == uid } } : nil
        let index = preselected ?? items.firstIndex(where: AlfredGridView.isSelectable)
        launcherSelection = index.map { launcherList.rows[$0].id } ?? nil
    }

    /// Tuiles arrivées après le texte d'attente (session 095) : la grille ouverte est remplacée, la saisie
    /// gardée, la présélection appliquée. Une autre grille ou une barre fermée l'ignorent.
    private func updateGrid(_ view: AlfredGridView) {
        guard !finished, launcher.workflowGrid?.entry.id == view.entry.id else { return }
        launcher.workflowGrid = view
        launcherQuery = nil
        launcherSelection = nil
        render()
    }

    /// Tuile voisine dans la grille (← → : ± 1, ↑ ↓ : ± colonnes), espaceurs sautés. O(n / |step|).
    private func moveInGrid(_ step: Int) {
        guard let index = selectedLauncherRow else { return }
        let rows = launcherList.rows
        let selectable: (Int) -> Bool = { index in
            if case .workflowItem(_, let item, _) = rows[index] { return AlfredGridView.isSelectable(item) }
            return rows[index].id != nil
        }
        if let next = AlfredGridView.neighbour(of: index, step: step, count: rows.count, selectable: selectable) {
            launcherSelection = rows[next].id
        }
    }

    /// Lignes de repli : texte du workflow avec la saisie, ou nom de l'action universelle. O(t).
    private func fallbackRows(_ query: String) -> [LauncherList.Row] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return launcher.workflowTriggers.enumerated().compactMap { index, entry in
            let title: String
            switch entry.kind {
            case .fallback: title = entry.title.replacingOccurrences(of: "{query}", with: text)
            case .universalAction where entry.acceptsText: title = tr("\(entry.title) : « \(text) »", "\(entry.title): “\(text)”")
            default: return nil
            }
            return .workflowItem(entry, AlfredItem(title: title, subtitle: entry.workflowName, arg: [text]), index: index)
        }
    }

    /// Lance le Script Filter pour cet argument : tout de suite à la première frappe, 100 ms après la
    /// dernière ensuite ; la frappe suivante arrête le script en cours (FR-004). « Alfred filtre les
    /// résultats » : une seule fois par mot-clé. `rerun` : relancé à l'identique.
    private func requestScriptFilter(_ entry: AlfredEntry, _ argument: String, force: Bool = false) {
        let key = entry.id
        if !force {
            if let answer = workflowResponses[key], entry.filtersResults || answer.argument == argument { return }
            if workflowRequested[key] == argument { return }
        }
        workflowRequested[key] = argument
        workflowRuns.removeValue(forKey: key)?.cancel()
        workflowPending.removeValue(forKey: key)?.cancel()
        workflowReruns.removeValue(forKey: key)?.cancel()
        let query = model.query
        let workflowID = entry.workflowID
        let generation = workflowGenerations[workflowID, default: 0]
        let start: @MainActor () -> Void = { [weak self] in
            guard let self, !self.finished,
                  WorkflowCallbackGuard.acceptsResponse(
                      currentGeneration: self.workflowGenerations[workflowID, default: 0],
                      callbackGeneration: generation,
                      currentArgument: self.workflowRequested[key],
                      callbackArgument: argument
                  ) else { return }
            self.workflowRuns[key] = self.launcher.runScriptFilter(entry, argument) { [weak self] response, error in
                guard let self, !self.finished,
                      WorkflowCallbackGuard.acceptsResponse(
                          currentGeneration: self.workflowGenerations[workflowID, default: 0],
                          callbackGeneration: generation,
                          currentArgument: self.workflowRequested[key],
                          callbackArgument: argument
                      ) else { return }
                self.workflowRuns[key] = nil
                self.workflowResponses[key] = (argument, response, error ?? (response == nil ? tr("Réponse illisible", "Unreadable response") : nil))
                self.filesChanged = true
                self.render()
                if let rerun = response?.rerun {
                    self.workflowReruns.removeValue(forKey: key)?.cancel()
                    let rerunWork = DispatchWorkItem { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, !self.finished,
                                  WorkflowCallbackGuard.acceptsRerun(
                                      currentGeneration: self.workflowGenerations[workflowID, default: 0],
                                      rerunGeneration: generation,
                                      currentQuery: self.model.query,
                                      rerunQuery: query,
                                      activeEntries: self.launcher.workflowEntries,
                                      entryID: key
                                  ),
                                  let currentEntry = self.launcher.workflowEntries.first(where: { $0.id == key }) else { return }
                            self.workflowReruns[key] = nil
                            self.requestScriptFilter(currentEntry, argument, force: true)
                        }
                    }
                    self.workflowReruns[key] = rerunWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + rerun, execute: rerunWork)
                }
            }
        }
        guard workflowResponses[key] != nil, !force else { start(); return }
        let work = DispatchWorkItem { MainActor.assumeIsolated { start() } }
        workflowPending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Retour sur une ligne de workflow ; vrai si c'en était une (FR-007). Modificateur sans connexion
    /// propre : géré par le moteur (research R6).
    private func confirmWorkflow(modifiers: Int) -> Bool {
        switch launcherList.row(for: launcherSelection) {
        case .workflowKeyword(let entry):
            if case .run(let argument) = entry.match(model.query), entry.kind == .keyword {
                finishWorkflow(entry, arg: [argument], variables: [:], modifiers: modifiers, rankingKey: entry.id)
            } else if case .suggest = entry.match(model.query) {
                // Entrée Keyword sans argument obligatoire : Retour la lance, comme Alfred (FR-003).
                if entry.kind == .keyword, entry.argument != .required {
                    finishWorkflow(entry, arg: [""], variables: [:], modifiers: modifiers, rankingKey: entry.id)
                } else {
                    completeWorkflow(entry, nil)
                    render()
                }
            }
            return true
        case .workflowItem(let entry, let item, let index):
            let mod = item.mods[modifiers]
            guard mod?.valid ?? item.valid else {
                if let text = item.autocomplete { completeWorkflow(entry, text); render() }
                return true
            }
            // Grille : variables du schéma au moment de la grille et de sa réponse (SPEC-092 FR-006).
            var variables = entry.kind == .grid ? launcher.workflowGrid?.variables ?? [:] : workflowResponses[entry.id]?.response?.variables ?? [:]
            variables.merge(item.variables) { $1 }
            variables.merge(mod?.variables ?? [:]) { $1 }
            finishWorkflow(entry, arg: mod?.arg ?? item.arg, variables: variables, modifiers: modifiers,
                           rankingKey: LauncherList.Row.workflowItem(entry, item, index: index).rankingKey)
            return true
        default:
            return false
        }
    }

    /// Lignes du lanceur pour une requête minuteur / Pomodoro (Spec 161).
    private static func timerRows(for query: LauncherTimerService.ParsedQuery) -> [LauncherList.Row] {
        switch query {
        case .start(let seconds, let label):
            let formatted = LauncherTimerService.formatDuration(seconds)
            return [.system(LauncherSystemCommand(
                id: "roadie-timer-start:\(seconds):\(label)",
                title: tr("Démarrer « \(label) » (\(formatted))", "Start “\(label)” (\(formatted))"),
                keywords: ["timer", "pomodoro", label],
                symbol: "timer",
                confirms: false,
                detail: tr("Notification locale macOS à la fin", "Local macOS notification when finished")
            ))]
        case .cancelAll:
            let count = LauncherTimerService.shared.activeTimers().count
            return [.system(LauncherSystemCommand(
                id: "roadie-timer-cancel-all",
                title: tr("Arrêter tous les minuteurs (\(count) actif(s))", "Stop all timers (\(count) active)"),
                keywords: ["timer", "stop", "cancel"],
                symbol: "stop.circle",
                confirms: false,
                detail: tr("Retour arrête tous les décomptes", "Return stops all active timers")
            ))]
        case .status:
            let now = Date()
            let active = LauncherTimerService.shared.activeTimers()
            var rows: [LauncherList.Row] = active.map { timer in
                let remaining = LauncherTimerService.formatDuration(timer.remainingSeconds(at: now))
                return .system(LauncherSystemCommand(
                    id: "roadie-timer-cancel:\(timer.id)",
                    title: "\(timer.label) · \(remaining)",
                    keywords: ["timer", timer.label],
                    symbol: "timer",
                    confirms: false,
                    detail: tr("En cours · Retour pour annuler", "Running · Return to cancel")
                ))
            }
            if active.isEmpty {
                rows.append(.system(LauncherSystemCommand(
                    id: "roadie-timer-start:1500:Pomodoro",
                    title: tr("Pomodoro (25:00)", "Pomodoro (25:00)"),
                    keywords: ["pomodoro", "timer"],
                    symbol: "timer",
                    confirms: false,
                    detail: tr("Démarrer un cycle de 25 min", "Start a 25 min session")
                )))
                rows.append(.system(LauncherSystemCommand(
                    id: "roadie-timer-start:300:" + tr("Pause", "Break"),
                    title: tr("Pause rapide (05:00)", "Quick break (05:00)"),
                    keywords: ["pause", "break", "timer"],
                    symbol: "cup.and.saucer",
                    confirms: false,
                    detail: tr("Démarrer un minuteur de 5 min", "Start a 5 min timer")
                )))
            }
            return rows
        }
    }

    /// Retour sur une ligne web ou une recherche récente ; vrai si c'en était une (SPEC-090).
    private func confirmWeb() -> Bool {
        switch launcherList.row(for: launcherSelection) {
        case .web(let row):
            if case .bookmark(let bookmark) = row.kind, let url = row.url, let app = LauncherBookmarkBrowsers.otherThanDefault(bookmark.browser, for: url) {
                // Signet d'un navigateur qui n'est pas celui par défaut : il s'ouvre dans son navigateur.
                launcher.recordQuery(model.query)
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                finish(TargetActionResult(changed: true, message: "launcher bookmark: \(bookmark.browser)"))
            } else if let url = row.url {
                finishAction(LauncherAction(subject: .url(url), verb: .open, destination: nil))
            } else if case .hint(let search) = row.kind {
                model.replaceQuery(search.keyword + " ")
                render()
            }
            return true
        case .history(let query):
            model.replaceQuery(query)
            render()
            return true
        case .terminal(let command):
            runTerminal(command)
            return true
        case .system(let command):
            // Commande lourde : un premier Retour l'annonce, le second la lance (session 105).
            if command.confirms, pendingSystem != command.id {
                pendingSystem = command.id
                render()
                return true
            }
            launcher.recordQuery(model.query)
            finish(TargetActionResult(changed: true, message: "launcher system: \(command.id)"))
            command.run()
            return true
        default:
            return false
        }
    }

    /// Retour sur la ligne du terminal : la commande part dans une nouvelle fenêtre, la barre se ferme ;
    /// invite vide ou terminal absent : un message, la barre reste (session 103).
    private func runTerminal(_ command: String) {
        let name = LauncherTerminal.appName(launcher.terminalApp)
        guard !command.isEmpty else { return }
        guard LauncherTerminal.isInstalled(launcher.terminalApp), LauncherTerminal.run(launcher.terminalApp, command: command) else {
            finish(TargetActionResult(changed: false, message: "launcher terminal: \(name) introuvable", error: "terminal_unavailable"))
            return
        }
        launcher.recordQuery(model.query)
        finish(TargetActionResult(changed: true, message: "launcher terminal: \(name)"))
    }

    /// Tab : `autocomplete` d'une ligne après le mot-clé (research R7), ou le mot-clé seul.
    private func completeWorkflow(_ entry: AlfredEntry, _ text: String?) {
        let prefix = entry.keyword + (entry.withSpace ? " " : "")
        let completed = text.map { $0.lowercased().hasPrefix(entry.keyword.lowercased()) ? $0 : prefix + $0 } ?? prefix
        model.replaceQuery(completed)
    }

    private func finishWorkflow(_ entry: AlfredEntry, arg: [String], variables: [String: String], modifiers: Int, rankingKey: String?) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        if let rankingKey { launcher.recordVisit(rankingKey, query) }
        onFinish?(launcher.runWorkflow(entry, arg, variables, modifiers))
    }

    /// Icône d'une ligne de workflow : image du workflow (chemin relatif à son dossier), icône d'un
    /// fichier, ou icône du workflow.
    private static func workflowIcon(_ icon: AlfredIcon?, entry: AlfredEntry) -> SlashSuggestion.Icon {
        let fallback: SlashSuggestion.Icon = entry.icon.map(SlashSuggestion.Icon.image) ?? .symbol("puzzlepiece.extension")
        switch icon {
        case .image(let path)?:
            let absolute = path.hasPrefix("/") ? path : (entry.folder as NSString).appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: absolute) ? .image(absolute) : fallback
        case .fileIcon(let path)?: return .file(NSString(string: path).expandingTildeInPath)
        case .fileType?: return .symbol("doc")
        case nil: return fallback
        }
    }

    /// Saisie qui désigne un chemin plutôt qu'une commande (SPEC-087 FR-004). O(c + r).
    private static func isPath(_ text: String) -> Bool {
        LauncherPathRules.isPath(text, commands: LauncherPathRules.commandNames, rootEntries: LauncherPathRules.rootEntries)
    }

    /// Chemin tapé : le dossier est lu en fond, la liste montre ses éléments dès la réponse ; rien
    /// d'autre n'est cherché (SPEC-087 FR-005, FR-008). O(f).
    private func refreshPath() {
        let query = model.query
        if query != pathFor {
            pathFor = query
            fileSearch.cancel()
            pathListing.list(LauncherPathRules.parts(query), sort: launcher.pathSort) { [weak self] files in
                guard let self, !self.finished, self.model.query == query, self.step == .objects else { return }
                self.pathFiles = files
                self.filesChanged = true
                self.render()
            }
        }
        guard query != launcherQuery || filesChanged else { return }
        let queryChanged = query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = query
        filesChanged = false
        launcherList = .path(pathFiles)
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Tab sur un élément d'un chemin : la saisie devient son chemin, `/` final pour un dossier (FR-006).
    private func completePath(_ file: LauncherFile) {
        model.replaceQuery(LauncherPathRules.completion(file, in: LauncherPathRules.parts(model.query)))
    }

    /// Retour sur un calcul : le résultat est copié, la barre se ferme (SPEC-087 FR-003). Avec
    /// `calc_opens_calculator`, Calculette s'ouvre aussi, ou sa fenêtre revient, comme Retour sur l'application.
    private func finishCalc(_ calc: LauncherCalculation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(calc.text, forType: .string)
        if !calc.isConversion, launcher.calcOpensCalculator, let calculator = LauncherCalculator.calculator(in: launcher.apps) {
            guard !finished else { return }
            finished = true
            launcher.recordQuery(model.query)
            cleanup()
            onFinish?(launcher.launch(calculator))
            return
        }
        launcher.recordQuery(model.query)
        finish(TargetActionResult(changed: true, message: "launcher calc copied"))
    }

    /// Nouvelle saisie : les fichiers qui la contiennent encore restent affichés pendant que Spotlight
    /// cherche ; sa réponse ne sert que si la saisie n'a pas changé entre-temps. O(f).
    private func refreshFiles() {
        guard model.query != filesQuery else { return }
        let query = model.query
        filesQuery = query
        let parsed = LauncherFileQuery.parse(query, keywords: launcher.fileKeywords)
        let needle = LauncherMatch.fold(parsed.needle)
        // Contenu ou étiquette : le nom ne dit rien des fichiers qui restent, la liste attend Spotlight.
        let shown = needle.isEmpty || parsed.mode != .name ? [] : files.filter { LauncherMatch.fold($0.name).contains(needle) }
        files = shown
        fileSearch.keywords = launcher.fileKeywords
        fileSearch.extraTypes = launcher.fileTypes
        fileSearch.excluded = launcher.fileExcluded
        fileSearch.search(query, retaining: shown) { [weak self] found in
            guard let self, !self.finished, self.model.query == query, self.step == .objects else { return }
            self.files = found
            self.filesChanged = true
            self.render()
        }
    }

    /// Objet d'une ligne de la liste. O(1).
    private static func subject(of row: LauncherList.Row?) -> LauncherSubject? {
        switch row {
        case .app(let app, _): .app(app)
        case .target(let target): .target(target)
        case .file(let file): .file(file)
        case .phrase(let action, _), .alias(_, let action, _): action.subject
        case .project(let project): .project(project.name)
        case .action(_, let action, _, _): action.subject
        case .web(let row): row.url.map(LauncherSubject.url)
        case .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .history, .terminal, .system, .header, nil: nil
        }
    }

    /// ⌘C : chemin d'un fichier ou d'une application, titre d'une fenêtre ou d'une cible (SPEC-077).
    /// Texte de la ligne choisie : copié par ⌘C, montré en grand par ⌘L (session 105).
    private var selectionText: String? {
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): app.path
        case .file(let file): file.path
        case .target(let target): target.subtitle.isEmpty ? target.title : "\(target.title) - \(target.subtitle)"
        case .phrase(_, let title), .alias(_, _, let title): title
        case .project(let project): project.name
        case .action(_, _, let title, _): title
        case .openItem(let item): item.url ?? item.title
        case .calc(let calc): calc.text
        case .workflowKeyword(let entry): entry.keyword
        case .workflowItem(_, let item, _): item.copyText ?? (item.arg.isEmpty ? item.title : item.arg.joined(separator: "\n"))
        case .web(let row): row.url?.absoluteString
        case .history(let query): query
        case .terminal(let command): command
        case .system(let command):
            command.id.hasPrefix("emoji-copy:") ? String(command.id.dropFirst("emoji-copy:".count)) : command.title
        case .rule, .header, nil: nil
        }
    }

    private func copySelection() {
        let text = selectionText
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedRowID = launcherSelection
    }

    /// Retour sur un fichier : l'ouvrir, ou le montrer dans le Finder après le mot-clé `find` (session 119).
    private var fileVerb: LauncherVerb {
        LauncherFileQuery.parse(model.query, keywords: launcher.fileKeywords).reveals ? .reveal : .open
    }

    private var selectedLauncherRow: Int? { launcherList.rows.firstIndex { $0.id == launcherSelection && $0.id != nil } }

    /// Clic sur une ligne : action immédiate, sans attendre un éventuel double Retour.
    private func activateSelection(immediate: Bool) {
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): finishLaunching(app)
        case .target(let target): finishActivating(target, target.source == .app ? .click : (target.actions.first ?? .focus))
        case .file(let file): finishAction(LauncherAction(subject: .file(file), verb: fileVerb, destination: nil))
        case .phrase(let action, _), .alias(_, let action, _): finishAction(action)
        case .project(let project): finishAction(LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil))
        case .action(let key, let action, _, _): if key == "undo-batch" { finishUndo() } else { finishAction(action) }
        case .rule(let suggestion, let choice): finishRule(suggestion, choice)
        case .openItem(let item): finishOpenItem(item)
        case .calc(let calc): finishCalc(calc)
        case .workflowKeyword, .workflowItem: _ = confirmWorkflow(modifiers: 0)
        case .web, .history, .terminal, .system: _ = confirmWeb()
        case .header, nil: break
        }
    }

    // MARK: - Verbes et destinations (SPEC-074)

    private func enterVerbs(_ subject: LauncherSubject) {
        step = .verbs(subject)
        stepQuery = ""
        stepTiling = if case .target(let target) = subject, target.kind == .window, let id = target.scope.windowId {
            launcher.tiling(WindowID(rawValue: id))
        } else { nil }
        model.highlight(targetID: { if case .target(let target) = subject { return target.id } else { return nil } }())
        refreshActions()
    }

    /// Objet des étapes verbe et destination.
    private var stepSubject: LauncherSubject? {
        switch step {
        case .objects, .batchVerbs, .batchDestinations: nil
        case .verbs(let subject), .destinations(let subject, _): subject
        case .saving(let action, _): action.subject
        }
    }

    // MARK: - Garder une action (SPEC-079)

    /// Action de la ligne choisie à l'étape des objets : son action par défaut, ou celle de la phrase. O(1).
    private func objectAction() -> LauncherAction? {
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): LauncherAction(subject: .app(app), verb: .open, destination: nil)
        case .file(let file): LauncherAction(subject: .file(file), verb: .open, destination: nil)
        case .target(let target): LauncherAction(subject: .target(target), verb: .focus, destination: nil)
        case .phrase(let action, _), .alias(_, let action, _): action
        case .project(let project): LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil)
        case .action(_, let action, _, _): action
        case .web(let row): row.url.map { LauncherAction(subject: .url($0), verb: .open, destination: nil) }
        case .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .history, .terminal, .system, .header, nil: nil
        }
    }

    /// Document ou onglet : la barre se ferme, sa fenêtre passe devant (SPEC-082).
    private func finishOpenItem(_ item: LauncherOpenItem) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit("open:\(item.kind.rawValue):\(item.bundleID):\(item.title)", query)
        onFinish?(launcher.activateOpenItem(item))
    }

    /// Choix d'une règle proposée : la barre se ferme sur le résultat (SPEC-081).
    private func finishRule(_ suggestion: RuleSuggestion, _ choice: RuleChoice) {
        guard !finished else { return }
        finished = true
        cleanup()
        onFinish?(launcher.ruleChoice(suggestion, choice))
    }

    /// Action composée aux étapes des verbes et des destinations. O(1).
    private func stepAction() -> LauncherAction? {
        guard let subject = stepSubject else { return nil }
        switch actionList.row(for: actionSelection) {
        case .verb(let verb): return verb.needsDestination ? nil : LauncherAction(subject: subject, verb: verb, destination: nil)
        case .destination(let verb, let destination): return LauncherAction(subject: subject, verb: verb, destination: destination)
        case .workflow, .header, nil: return nil
        }
    }

    private func enterSaving(_ action: LauncherAction) {
        step = .saving(action, LauncherAlias.from(action, stageName: launcher.stageName))
        stepQuery = ""
        savingCopied = false
        actionList = LauncherActionList()
        actionSelection = nil
    }

    /// Lignes de l'étape « Garder » : l'abréviation tapée, la commande, ou la raison du refus.
    private func savingRows(_ action: LauncherAction, _ alias: Result<LauncherAlias, LauncherAlias.Refusal>) -> [SlashSuggestion] {
        var rows = [SlashSuggestion(text: tr("Garder : ", "Save: ") + LauncherPhrase.title(action), kind: .header)]
        switch alias {
        case .failure(let refusal):
            rows.append(SlashSuggestion(text: tr("Cette action ne se garde pas", "This action cannot be saved"), detail: refusal.message, kind: .result, icon: .symbol("xmark.circle")))
        case .success(let alias):
            let name = stepQuery.trimmingCharacters(in: .whitespaces)
            let replaced = launcher.aliases.alias(for: name).map { tr(" · remplace « \($0.1.name) »", " · replaces “\($0.1.name)”") } ?? ""
            rows.append(SlashSuggestion(text: name.isEmpty ? tr("Abréviation…", "Abbreviation…") : tr("Abréviation « \(name) »", "Abbreviation “\(name)”"),
                                        detail: LauncherAlias.isValidName(name) ? tr("Retour enregistre", "Return saves") + replaced
                                            : tr("1 à 12 caractères, sans espace", "1 to 12 characters, no spaces"),
                                        kind: .result, icon: .symbol("character.cursor.ibeam")))
            rows.append(SlashSuggestion(text: alias.command, detail: savingCopied ? tr("Copiée dans le presse-papiers", "Copied to the clipboard") : tr("⌘C copie la commande", "⌘C copies the command"),
                                        kind: .result, icon: .symbol("terminal")))
        }
        return rows
    }

    private func confirmSaving(_ alias: LauncherAlias) {
        let name = stepQuery.trimmingCharacters(in: .whitespaces)
        guard LauncherAlias.isValidName(name) else { return }
        switch launcher.saveAlias(alias, name) {
        case .success:
            finish(TargetActionResult(changed: true, message: "launcher alias saved: \(LauncherMatch.fold(name))"))
        case .failure:
            finish(TargetActionResult(changed: false, message: tr("Abréviation non enregistrée", "Abbreviation not saved"), error: "alias_not_saved"))
        }
    }

    private func enterDestinations(_ subject: LauncherSubject, _ verb: LauncherVerb) {
        step = .destinations(subject, verb)
        stepQuery = ""
        refreshActions()
    }

    /// Échap ou effacement dans un champ vide : une étape en arrière.
    private func stepBack() {
        switch step {
        case .objects: break
        case .verbs:
            step = .objects
            stepQuery = ""
            launcherQuery = nil
        case .destinations(let subject, _):
            enterVerbs(subject)
        case .saving, .batchVerbs:
            step = .objects
            stepQuery = ""
            launcherQuery = nil
        case .batchDestinations:
            enterBatch()
        }
    }

    // MARK: - Sélection multiple (SPEC-091)

    private func enterBatch() {
        batchVerb = .sendTo
        step = .batchVerbs
        stepQuery = ""
        refreshActions()
    }

    /// Le lot part au contrôleur après la fermeture : une action par objet (FR-005).
    private func finishBatch(_ verb: LauncherVerb, _ destination: LauncherDestination?) {
        guard !finished else { return }
        finished = true
        launcher.recordQuery(model.query)
        let actions = selection.actions(verb, destination: destination)
        cleanup()
        onFinish?(launcher.performBatch(actions))
    }

    /// « Annuler » de la barre vide pour un lot (FR-006).
    private func finishUndo() {
        guard !finished else { return }
        finished = true
        cleanup()
        onFinish?(launcher.undo())
    }

    private func refreshActions() {
        switch step {
        case .objects: return
        case .verbs(let subject):
            actionList = .verbs(for: subject, query: stepQuery, destinations: launcher.destinations, newStageHome: launcher.newStageHome,
                                tiling: stepTiling, ranking: launcher.learnsVerbOrder ? launcher.ranking : nil)
            switch subject {
            case .file(let file):
                actionList.appendWorkflows(launcher.workflowTriggers.filter { AlfredWorkflowIndex.accepts($0, path: file.path) }, query: stepQuery)
            // Session 131 : actions universelles des workflows sur un texte ou une adresse.
            case .text:
                actionList.appendWorkflows(launcher.workflowTriggers.filter(AlfredWorkflowIndex.acceptsText), query: stepQuery)
            case .url:
                actionList.appendWorkflows(launcher.workflowTriggers.filter(AlfredWorkflowIndex.acceptsURL), query: stepQuery)
            default: break
            }
        case .destinations(let subject, let verb):
            actionList = .destinations(for: subject, verb: verb, query: stepQuery, destinations: destinations(for: subject, verb: verb),
                                       newStageHome: launcher.newStageHome)
        case .saving:
            return
        case .batchVerbs:
            actionList = .batch(selection, query: stepQuery)
            let paths = selection.filePaths
            if !paths.isEmpty, paths.count == selection.count {
                actionList.appendWorkflows(launcher.workflowTriggers.filter { entry in paths.allSatisfy { AlfredWorkflowIndex.accepts(entry, path: $0) } },
                                           query: stepQuery)
            }
        case .batchDestinations:
            let title = tr("\(selection.count) choisi\(selection.count > 1 ? "s" : "")", "\(selection.count) selected")
            let verb = LauncherActionList.batchDestinationVerb(selection, chosen: batchVerb)
            actionList = .destinations(for: .project(title), verb: verb, query: stepQuery,
                                       destinations: fileDestinations(verb: verb, paths: selection.filePaths) ?? launcher.destinations,
                                       newStageHome: launcher.newStageHome)
        }
        actionSelection = actionList.best
    }

    /// Destinations d'un verbe ; documents récents (session 116) lus une fois par application ouverte dans l'étape.
    private func destinations(for subject: LauncherSubject, verb: LauncherVerb) -> [LauncherDestination] {
        if let files = fileDestinations(verb: verb, paths: { if case .file(let file) = subject { [file.path] } else { [] } }()) { return files }
        guard verb == .recentDocuments, case .app(let app) = subject else { return launcher.destinations }
        if let recent, recent.bundleID == app.bundleID { return recent.destinations }
        let found = LauncherRecentDocuments.destinations(LauncherRecentDocuments.documents(bundleID: app.bundleID))
        recent = (app.bundleID, found)
        return found
    }

    /// Destinations des verbes de fichier (session 131) : dossiers (chemin tapé, habituels, récents), applications,
    /// étiquettes ; nil pour un autre verbe. O(r).
    private func fileDestinations(verb: LauncherVerb, paths: [String]) -> [LauncherDestination]? {
        switch verb {
        case .copyTo, .moveFileTo, .copyReplace, .moveReplace:
            return LauncherFileOperations.folderDestinations(typed: stepQuery, recent: LauncherRecentFiles.shared.recentFolders(),
                                                             excluding: [.moveFileTo, .moveReplace].contains(verb) ? paths : [])
        case .openWith: return LauncherFileOperations.applicationDestinations(for: paths)
        case .addTag:
            var tags = LauncherFileOperations.tagDestinations(for: paths)
            let typed = stepQuery.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty, !tags.contains(where: { $0.title.caseInsensitiveCompare(typed) == .orderedSame }) {
                tags.insert(LauncherDestination(kind: .tag(typed), title: typed, detail: tr("nouvelle étiquette", "new tag")), at: 0)
            }
            return tags
        default: return nil
        }
    }

    private func handleStep(_ input: SearchKeyInput) {
        if case .saving(_, let alias) = step {
            switch input.kind {
            case .escape: stepBack()
            case .delete: if stepQuery.isEmpty { stepBack() }
            case .confirm(_, _, _, _, let isRepeat):
                guard !isRepeat, case .success(let alias) = alias else { return }
                confirmSaving(alias)
                return
            case .copy:
                guard case .success(let alias) = alias else { break }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(alias.command, forType: .string)
                savingCopied = true
            default: break
            }
            render()
            return
        }
        switch input.kind {
        case .save:
            if let action = stepAction() { enterSaving(action) }
        case .escape:
            stepBack()
        case .delete:
            if stepQuery.isEmpty { stepBack() }
        case .pick(let rank):
            pick(rank)
            return
        case .next where input.navigationSource == .tab, .actions:
            // Tab ou → sur un verbe qui demande une destination : la troisième étape.
            if case .verb(let verb)? = actionList.row(for: actionSelection), verb.needsDestination, case .verbs(let subject) = step {
                enterDestinations(subject, verb)
            } else if case .verb(let verb)? = actionList.row(for: actionSelection), verb.needsDestination, step == .batchVerbs {
                batchVerb = verb
                step = .batchDestinations
                stepQuery = ""
                refreshActions()
            }
        case .next:
            actionSelection = actionList.neighbour(of: actionSelection, step: 1)
        case .previous:
            actionSelection = actionList.neighbour(of: actionSelection, step: -1)
        case .confirm(_, _, _, _, let isRepeat):
            guard !isRepeat else { return }
            confirmStep()
            return
        case .closeAll:
            finish(TargetActionResult(changed: false, message: "target_search_escaped", error: "cancelled"))
            return
        case .text, .labelCharacter, .ignored, .copy, .preview, .showRules, .selectToggle, .selectAddNext, .selectRemoveLast,
             .selectionVerbs, .selectClear, .move, .cycleView, .parentFolder, .largeType, .openSettings:
            break
        }
        render()
    }

    // MARK: - Aperçu actif (SPEC-078)

    /// Destination de la ligne choisie, si elle se prête à l'aperçu. O(1).
    private var desiredPreview: LauncherPreviewRequest? {
        guard let subject = stepSubject, case .destination(let verb, let destination)? = actionList.row(for: actionSelection) else { return nil }
        return LauncherPreviewRequest.of(LauncherAction(subject: subject, verb: verb, destination: destination))
    }

    /// La ligne se pose 150 ms sur une destination : l'aperçu s'y pose. Elle la quitte : l'aperçu
    /// précédent est défait tout de suite. Rappelée à chaque rendu ; sans effet si rien ne change.
    private func schedulePreview() {
        let desired = desiredPreview
        guard desired != pendingPreview else { return }
        pendingPreview = desired
        previewWork?.cancel()
        previewWork = nil
        guard let desired else {
            ghost = nil
            if sentPreview != nil {
                sentPreview = nil
                launcher.preview(nil) { _ in }
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.pendingPreview == desired else { return }
                self.ghost = nil
                self.sentPreview = desired
                self.launcher.preview(desired) { [weak self] ghost in
                    guard let self, !self.finished, self.sentPreview == desired else { return }
                    self.ghost = ghost
                    self.render()
                }
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Touches du lanceur (SPEC-075)

    /// Une seule touche tenue choisit la variante ; deux à la fois, aucune. O(1).
    private static func modifier(command: Bool, option: Bool, control: Bool) -> LauncherModifier? {
        switch (command, option, control) {
        case (true, false, false): .command
        case (false, true, false): .option
        case (false, false, true): .control
        default: nil
        }
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let held = flags.contains(.shift) ? nil : Self.modifier(command: flags.contains(.command), option: flags.contains(.option),
                                                              control: flags.contains(.control))
        let shift = flags.intersection([.command, .option, .control, .shift]) == .shift
        guard held != heldModifier || shift != heldShift else { return }
        heldModifier = held
        heldShift = shift
        render()
    }

    /// Variante de la ligne choisie à l'étape des objets, hors mode commande. O(1).
    private func currentVariant(_ modifier: LauncherModifier) -> LauncherVariant? {
        guard step == .objects, commandModel == nil else { return nil }
        let subject: LauncherSubject
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): subject = .app(app)
        case .target(let target): subject = .target(target)
        case .file(let file): subject = .file(file)
        case .web(let row):
            guard let url = row.url else { return nil }
            subject = .url(url)
        case .openItem(let item): subject = .openItem(item)
        case .calc(let calc): subject = .text(calc.text)
        case .phrase, .alias, .project, .action, .rule, .workflowKeyword, .workflowItem, .history, .terminal, .system, .header, nil: return nil
        }
        return LauncherVariant.of(subject, modifier: modifier, query: model.query,
                                  newStageHome: launcher.newStageHome, activeStage: launcher.activeStage,
                                  effect: launcher.returnEffects[modifier])
    }

    private func finishVariant(_ variant: LauncherVariant) {
        switch variant.effect {
        case .action(let action):
            finishAction(action)
        case .webSearch(let text):
            guard !finished else { return }
            finished = true
            launcher.recordQuery(model.query)
            cleanup()
            onFinish?(launcher.webSearch(text))
        case .copy(let text):
            // Session 131 : la barre reste ouverte, la ligne montre « copié » comme ⌘C.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedRowID = launcherSelection
            render()
        case .verbs(let subject):
            enterVerbs(subject)
            render()
        }
    }

    /// ⌘ + chiffre : action par défaut de la ligne de ce rang parmi celles montrées. O(1).
    private func pick(_ rank: Int) {
        guard rank >= 1, rank <= pickRows.count else { return }
        let index = pickRows[rank - 1]
        if step == .objects {
            guard commandModel == nil, index < launcherList.rows.count else { return }
            launcherSelection = launcherList.rows[index].id
            syncHighlight()
            activateSelection(immediate: true)
        } else {
            guard index < actionList.rows.count else { return }
            actionSelection = actionList.rows[index].id
            confirmStep()
        }
    }

    private func confirmStep() {
        if step == .batchVerbs || step == .batchDestinations {
            switch actionList.row(for: actionSelection) {
            case .verb(let verb) where verb.needsDestination && step == .batchVerbs:
                batchVerb = verb
                step = .batchDestinations
                stepQuery = ""
                refreshActions()
                render()
            case .verb(let verb): finishBatch(verb, nil)
            case .destination(_, let destination): finishBatch(batchVerb, destination)
            // Action universelle d'un workflow sur plusieurs fichiers (session 131) : tous les chemins en argument.
            case .workflow(let entry): finishWorkflow(entry, arg: selection.filePaths, variables: [:], modifiers: 0, rankingKey: nil)
            case .header, nil: break
            }
            return
        }
        let subject: LauncherSubject
        switch step {
        case .objects, .saving, .batchVerbs, .batchDestinations: return
        case .verbs(let current): subject = current
        case .destinations(let current, _): subject = current
        }
        switch actionList.row(for: actionSelection) {
        case .verb(let verb):
            if verb.needsDestination {
                enterDestinations(subject, verb)
                render()
            } else {
                finishAction(LauncherAction(subject: subject, verb: verb, destination: nil))
            }
        case .destination(let verb, let destination):
            finishAction(LauncherAction(subject: subject, verb: verb, destination: destination))
        case .workflow(let entry):
            // Action sur fichier d'un workflow (SPEC-089 FR-003) : le chemin en argument ; texte ou adresse (session 131).
            switch subject {
            case .file(let file): finishWorkflow(entry, arg: [file.path], variables: [:], modifiers: 0, rankingKey: nil)
            case .text(let text): finishWorkflow(entry, arg: [text], variables: [:], modifiers: 0, rankingKey: nil)
            case .url(let url): finishWorkflow(entry, arg: [url.absoluteString], variables: [:], modifiers: 0, rankingKey: nil)
            default: break
            }
        case .header, nil:
            break
        }
    }

    /// Verbes d'une cible déjà connus du mode recherche : exécutés comme avant (clics, aller à).
    /// Les autres passent au lanceur, après la fermeture de la barre.
    private func finishAction(_ action: LauncherAction) {
        // Verbe choisi à la deuxième étape : il remonte pour ce type d'objet (session 111).
        switch step {
        case .verbs where !finished, .destinations where !finished: launcher.recordVisit(action.verb.rankingKey(for: action.subject), "")
        default: break
        }
        if action.position == nil, case .target(let target) = action.subject, let verb = Self.searchVerb(action.verb, for: target) {
            finishActivating(target, verb)
            return
        }
        // Session 131 : les adresses d'un texte s'affichent dans la barre, qui reste ouverte.
        if action.verb == .extractURLs, case .text(let text) = action.subject {
            extractedAddresses = LauncherText.addresses(in: text)
            step = .objects
            stepQuery = ""
            launcherQuery = nil
            model.replaceQuery("")
            render()
            return
        }
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        // Retour sur la destination de l'aperçu : la disposition reste ; sur une autre, elle est restaurée.
        if sentPreview != nil {
            launcher.endPreview(sentPreview == LauncherPreviewRequest.of(action))
            sentPreview = nil
        }
        cleanup()
        launcher.recordVisit(action.subject.rankingKey, query)
        onFinish?(launcher.perform(action))
    }

    private static func searchVerb(_ verb: LauncherVerb, for target: RoadieTarget) -> TargetActionVerb? {
        switch verb {
        case .click: .click
        case .doubleClick: .doubleClick
        case .rightClick: .rightClick
        case .commandClick: .commandClick
        case .focus, .show: target.actions.first ?? .focus
        default: nil
        }
    }

    private func finishLaunching(_ app: LauncherApp) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit(app.rankingKey, query)
        onFinish?(launcher.launch(app))
    }

    /// Premier `/` d'une requête vide : la boîte de commandes prend la main. Le contexte (stages,
    /// bookmarks) est lu une fois, à la bascule.
    private func enterCommandMode() {
        model.cancelPendingReturn()
        let context = commands.context()
        commandModel = SlashCommandModel(history: commands.loadHistory()) {
            SlashCommandCatalog.suggestions(for: $0, context: context)
        }
    }

    private func handleCommand(_ input: SearchKeyInput) {
        guard var command = commandModel else { return }
        let effect = command.handle(input)
        commandModel = command
        switch effect {
        case .update:
            render()
        case .close:
            cancel()
        case .leave:
            // Le `/` est effacé : la requête de recherche revient à vide.
            commandModel = nil
            model.deleteBackward()
            render()
        case .submit(let line):
            execute(line)
        }
    }

    /// Retour en mode commande. Succès, action différée et réglages ferment la boîte ; un résultat
    /// d'information ou une erreur s'affichent dans la boîte, qui reste ouverte.
    private func execute(_ line: String) {
        switch commands.execute(line) {
        case .done:
            finish(TargetActionResult(changed: true, message: "command_box_done"))
        case .deferred(let argv):
            let runDeferred = runDeferred
            finish(TargetActionResult(changed: false, message: "command_box_deferred")) { runDeferred(argv) }
        case .openSettings(let category):
            let openSettings = openSettings
            finish(TargetActionResult(changed: false, message: "command_box_settings")) { openSettings(category) }
        case .info(let lines):
            commandModel?.setMessage(.info(lines))
            render()
        case .failed(let error):
            let hint = error.suggestion.map { tr(" Vouliez-vous dire « \($0) » ?", " Did you mean “\($0)”?") } ?? ""
            commandModel?.setMessage(.error(error.message + hint, usage: error.usage))
            render()
        }
    }

    private func tick() {
        guard !finished else { return }
        LauncherOpenClock.current?.tick(interval: 0.05)
        if let target = model.highlighted, let verb = model.pendingReturn(at: Date()) {
            finishActivating(target, verb)
            return
        }
        if Date().timeIntervalSince(lastInputAt) >= Self.idleTimeout {
            finish(TargetActionResult(changed: false, message: "target_search_timeout", error: "timeout"))
        }
    }

    /// Dessin de la barre, chronométré pendant l'ouverture (session 123).
    private func render() {
        if let clock = LauncherOpenClock.current { clock.measureRender(renderNow) } else { renderNow() }
    }

    private func renderNow() {
        schedulePreview()
        if case .saving(let action, let alias) = step {
            let rows = savingRows(action, alias)
            show(badges: [], bar: TargetSearchBar(query: stepQuery, matchCount: 0, properties: nil, isLoading: false,
                                                  suggestions: rows, selectedSuggestion: rows.count > 1 ? 1 : nil, richRows: true))
            return
        }
        if step != .objects {
            let subjectID = model.highlighted?.id
            let badges: [TargetOverlayBadge] = model.matches.compactMap { target in
                guard target.id == subjectID, let frame = target.frame?.cgRect else { return nil }
                return TargetOverlayBadge(label: target.label, title: target.title, kind: target.kind, isActive: target.isActive,
                                          frame: RoadieScreenCoordinate.axRectToNS(frame), isHighlighted: true, isFramed: true, isSearchResult: true)
            }
            let batch = step == .batchVerbs
            show(badges: badges, bar: TargetSearchBar(
                query: stepQuery, matchCount: actionList.rows.filter { $0.id != nil }.count, properties: nil, isLoading: false,
                suggestions: actionList.rows.map { row in
                    // Lot : chaque verbe avec le nombre d'objets qu'il concerne (SPEC-091 FR-004).
                    guard batch, case .verb(let verb) = row else { return Self.suggestion(row, app: stepSubject?.appName ?? "") }
                    var line = Self.suggestion(row, app: "")
                    line.text = LauncherSelection.title(verb, count: selection.applicable(verb).count)
                    return line
                },
                selectedSuggestion: actionList.rows.firstIndex { $0.id == actionSelection && $0.id != nil },
                richRows: true))
            return
        }
        if let command = commandModel {
            // Mode commande : la saisie, la liste et le message, sans aucune cible.
            show(badges: [], bar: TargetSearchBar(
                query: model.query,
                matchCount: 0,
                properties: nil,
                isLoading: false,
                commandInput: command.input,
                suggestions: command.suggestions,
                selectedSuggestion: command.selected,
                message: command.message
            ))
            return
        }
        if screenOnly {
            renderScreenSearch()
            return
        }
        refreshLauncher()
        // Icône d'une fenêtre : celle de son application, retrouvée par son nom. O(a).
        let appPaths = Dictionary(launcher.apps.map { ($0.name, $0.path) }, uniquingKeysWith: { first, _ in first })
        let calcOpens = launcher.calcOpensCalculator && LauncherCalculator.calculator(in: launcher.apps) != nil
        var suggestions = launcherList.rows.map {
            Self.suggestion($0, appPaths: appPaths, terminal: launcher.terminalApp, pendingSystem: pendingSystem, calcOpens: calcOpens)
        }
        // Touche tenue : la ligne choisie annonce ce que Retour fera (SPEC-075).
        if let modifier = heldModifier, let index = selectedLauncherRow, let variant = currentVariant(modifier) {
            suggestions[index].detail = variant.title
        }
        // Workflow : le sous-titre du modificateur tenu (SPEC-088 FR-006).
        if heldModifier != nil || heldShift, let index = selectedLauncherRow,
           case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection) {
            let bits = Self.alfredModifiers(command: heldModifier == .command, option: heldModifier == .option,
                                            control: heldModifier == .control, shift: heldShift)
            if let subtitle = item.mods[bits]?.subtitle { suggestions[index].detail = subtitle }
        }
        if let copied = copiedRowID, let index = launcherList.rows.firstIndex(where: { $0.id == copied }) {
            suggestions[index].detail = tr("Copié dans le presse-papiers", "Copied to the clipboard")
        }
        // Sélection multiple : « ✓ » devant les lignes choisies (SPEC-091 FR-002).
        if !selection.isEmpty {
            for (index, row) in launcherList.rows.enumerated() {
                if let subject = Self.subject(of: row), selection.contains(subject) { suggestions[index].text = "✓ " + suggestions[index].text }
            }
        }
        // Présentation en grille (session 099) : images montrées par leur contenu, noms sous la tuile ou en pied.
        var viewGrid: SearchGrid?
        if launcher.workflowGrid == nil, let columns = viewMode.columns, let source = viewSource {
            for index in suggestions.indices {
                if case .file(let path)? = suggestions[index].icon, AlfredGridView.isImage(path) { suggestions[index].icon = .image(path) }
            }
            let footer = selectedLauncherRow.map { suggestions[$0].text } ?? ""
            viewGrid = SearchGrid(columns: columns, showTitles: !source.namesInFooter, showSubtitles: false,
                                  footer: source.namesInFooter ? footer : nil)
        }
        var bar = TargetSearchBar(
            query: model.query, matchCount: model.matches.count, properties: model.properties, isLoading: isLoading,
            suggestions: suggestions, selectedSuggestion: selectedLauncherRow,
            richRows: true)
        bar.grid = viewGrid
        // Chip de la présentation (session 099) : là où elle se choisit.
        if viewSource != nil { bar.viewChip = "\(viewMode.symbol) \(viewMode.title)" }
        // Chip (SPEC-081) : une règle attend pendant une recherche ; ⌘R la montre.
        if launcher.pendingRules > 0, !model.query.isEmpty { bar.chip = "💡 \(launcher.pendingRules)" }
        if let grid = launcher.workflowGrid, grid.loadingText == nil {
            // Grille (SPEC-092 FR-003) : titre et sous-titre sur la tuile, ou en pied pour la tuile choisie.
            var footer: [String] = []
            if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection) {
                if grid.titlesInFooter, grid.showTitles, !item.title.isEmpty { footer.append(item.title) }
                if grid.subtitlesInFooter, grid.showSubtitles, !item.subtitle.isEmpty { footer.append(item.subtitle) }
            }
            bar.grid = SearchGrid(columns: grid.columns, showTitles: grid.showTitles && !grid.titlesInFooter,
                                  showSubtitles: grid.showSubtitles && !grid.subtitlesInFooter,
                                  footer: grid.titlesInFooter || grid.subtitlesInFooter ? footer.joined(separator: " · ") : nil,
                                  aspect: grid.imageAspect)
        }
        if !selection.isEmpty {
            let chosen = tr("\(selection.count) choisi\(selection.count > 1 ? "s" : "")", "\(selection.count) selected")
            bar.chip = bar.chip.map { "\($0) · \(chosen)" } ?? chosen
        }
        // Barre vide : aucune lettre ; sinon les cibles montrées en reçoivent une (SPEC-084).
        show(badges: [], bar: bar, letterTargets: !model.query.isEmpty)
    }

    /// Recherche à l'écran (session 133), rendu d'avant le lanceur : barre vide, aucune étiquette ; sinon chaque
    /// correspondance porte son étiquette, la cible choisie est encadrée, toutes le sont à une lettre. O(m).
    private func renderScreenSearch() {
        let highlightedID = model.highlighted?.id
        let framesAll = model.hasShortLabels
        let badges: [TargetOverlayBadge] = (model.query.isEmpty ? [] : model.matches).compactMap { target in
            guard let frame = target.frame?.cgRect else { return nil }
            return TargetOverlayBadge(label: target.label, title: target.title, kind: target.kind, isActive: target.isActive,
                                      frame: RoadieScreenCoordinate.axRectToNS(frame), isHighlighted: target.id == highlightedID,
                                      isFramed: framesAll || target.id == highlightedID, isSearchResult: true)
        }
        var bar = TargetSearchBar(query: model.query, matchCount: model.matches.count, properties: model.properties,
                                  isLoading: isLoading, suggestions: [])
        // Aucune correspondance exacte : la barre dit que les étiquettes viennent d'une faute rattrapée (session 134).
        if model.corrected { bar.chip = tr("≈ approché", "≈ approximate") }
        show(badges: badges, bar: bar)
        // Maj + lettre d'une étiquette affichée : le champ la transmet comme étiquette, pas comme texte (essai du
        // 30 octobre 2026 : sans cette liste, la majuscule s'ajoutait à la saisie).
        inputPanel?.labelLetters = Self.labelLetters(of: badges.map(\.label))
    }

    /// Lettres des étiquettes montrées, en minuscules, pour reconnaître Maj + lettre. O(e).
    static func labelLetters(of labels: [String]) -> Set<String> {
        Set(labels.flatMap { $0.lowercased().map(String.init) })
    }

    /// Ligne des étapes verbe et destination.
    private static func suggestion(_ row: LauncherActionList.Row, app: String) -> SlashSuggestion {
        switch row {
        case .header(let title):
            return SlashSuggestion(text: title, kind: .header)
        case .workflow(let entry):
            return SlashSuggestion(text: tr("Workflow : ", "Workflow: ") + entry.title, detail: entry.workflowName, kind: .result, icon: workflowIcon(nil, entry: entry))
        case .verb(let verb):
            return SlashSuggestion(text: verb.title(app: app), detail: verb.needsDestination ? tr("Tab ou Retour : choisir", "Tab or Return: choose") : "",
                                   kind: .result, icon: .symbol(verb.needsDestination ? "arrow.right.circle" : "play.circle"))
        case .destination(let verb, let destination):
            let symbol = switch destination.kind {
            case .stage: "square.stack.3d.up"
            case .desktop: "rectangle.on.rectangle"
            case .display: "display"
            case .newStage: "plus.square.on.square"
            case .document: "doc"
            case .folder: "folder"
            case .application: "app"
            case .tag: "tag"
            }
            switch destination.kind {
            case .document(let path), .folder(let path), .application(let path):
                return SlashSuggestion(text: destination.kind.isDocument ? destination.title : "\(verb.destinationPrefix) \(destination.title)",
                                       detail: destination.detail, kind: .result, icon: .file(path))
            default: break
            }
            return SlashSuggestion(text: "\(verb.destinationPrefix) \(destination.title)", detail: destination.detail,
                                   kind: .result, icon: .symbol(symbol))
        }
    }

    /// Ligne du lanceur dessinée par la barre : en-tête, application avec son icône, ou cible.
    private static func suggestion(_ row: LauncherList.Row, appPaths: [String: String], terminal: String = "terminal",
                                   pendingSystem: String? = nil, calcOpens: Bool = false) -> SlashSuggestion {
        switch row {
        case .header(let title):
            return SlashSuggestion(text: title, kind: .header)
        case .app(let app, let detail):
            return SlashSuggestion(text: app.name, detail: detail, kind: .result, icon: .file(app.path))
        case .target(let target):
            let symbol = switch target.kind {
            case .window: "macwindow"
            case .stage: "square.stack.3d.up"
            case .desktop: "rectangle.on.rectangle"
            case .display: "display"
            case .bookmark: "bookmark"
            case .appElement, .gridCell: "cursorarrow.rays"
            }
            // Fenêtre : sa vignette réelle si Roadie l'a capturée, sinon l'icône de son application (SPEC-076).
            let icon: SlashSuggestion.Icon = if target.kind == .window, let id = target.scope.windowId {
                .window(id, app: appPaths[target.title])
            } else { .symbol(symbol) }
            return SlashSuggestion(text: target.title, detail: target.subtitle, kind: .result, icon: icon)
        case .file(let file):
            return SlashSuggestion(text: file.name, detail: file.location, kind: .result, icon: .file(file.path))
        case .phrase(let action, let title):
            return SlashSuggestion(text: title, detail: tr("Retour fait l'action · ⌘S la garde", "Return runs it · ⌘S saves it"), kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .alias(let name, let action, let title):
            return SlashSuggestion(text: title, detail: tr("Abréviation « \(name) »", "Abbreviation “\(name)”"), kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .project(let project):
            return SlashSuggestion(text: project.name, detail: tr("Projet", "Project") + " · \(project.windows.count) " + tr("fenêtre", "window") + (project.windows.count > 1 ? "s" : ""),
                                   kind: .result, icon: .symbol("square.stack.3d.down.right"))
        case .action(_, let action, let title, let detail):
            return SlashSuggestion(text: title, detail: detail, kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .openItem(let item):
            let icon: SlashSuggestion.Icon = item.windowID.map { .window($0.rawValue, app: appPaths[item.appName]) }
                ?? appPaths[item.appName].map(SlashSuggestion.Icon.file) ?? .symbol(item.kind == .tab ? "globe" : "doc")
            return SlashSuggestion(text: item.title, detail: item.detail, kind: .result, icon: icon)
        case .web(let row):
            if case .bookmark(let bookmark) = row.kind {
                let icon: SlashSuggestion.Icon = bookmark.icon.map(SlashSuggestion.Icon.image)
                    ?? LauncherBookmarkBrowsers.appPath(bookmark.browser).map(SlashSuggestion.Icon.file) ?? .symbol("bookmark")
                return SlashSuggestion(text: row.title, detail: bookmark.detail, kind: .result, icon: icon)
            }
            let (detail, symbol): (String, String) = switch row.kind {
            case .address: (tr("Retour ouvre · Tab : ouvrir dans une stage", "Return opens · Tab: open in a stage"), "globe")
            case .search(let url): (url.host ?? "", "magnifyingglass")
            case .hint(let search): (tr("Tab ou Retour : « \(search.keyword) »", "Tab or Return: “\(search.keyword)”"), "keyboard")
            case .bookmark: ("", "bookmark")
            }
            return SlashSuggestion(text: row.title, detail: detail, kind: .result, icon: .symbol(symbol))
        case .history(let query):
            return SlashSuggestion(text: query, detail: tr("Recherche récente", "Recent search"), kind: .result, icon: .symbol("clock.arrow.circlepath"))
        case .system(let command):
            let detail = command.id == pendingSystem ? tr("Retour encore pour confirmer · Échap annule", "Return again to confirm · Esc cancels")
                : command.confirms ? tr("Système · Retour deux fois", "System · Return twice") : command.detail ?? tr("Système", "System")
            return SlashSuggestion(text: command.title, detail: detail, kind: .result, icon: .symbol(command.symbol))
        case .terminal(let command):
            let name = LauncherTerminal.appName(terminal)
            if command.isEmpty { return SlashSuggestion(text: tr("\(name) : tapez une commande après >", "\(name): type a command after >"), detail: "", kind: .result, icon: .symbol("terminal")) }
            let detail = terminal == "warp" ? tr("Retour ouvre Warp et copie la commande", "Return opens Warp and copies the command")
                : tr("Retour lance dans \(name)", "Return runs it in \(name)")
            return SlashSuggestion(text: command, detail: detail, kind: .result, icon: .symbol("terminal"))
        case .workflowKeyword(let entry):
            return SlashSuggestion(text: entry.title, detail: entry.subtitle.isEmpty ? "\(entry.keyword) · \(entry.workflowName)" : entry.subtitle,
                                   kind: .result, icon: workflowIcon(nil, entry: entry))
        case .workflowItem(let entry, let item, _):
            return SlashSuggestion(text: item.title, detail: item.subtitle, kind: .result, icon: workflowIcon(item.icon, entry: entry))
        case .calc(let calc):
            let detail = calc.detail ?? "\(calc.expression) · \(LauncherCalculator.returnHint(opensCalculator: calcOpens))"
            return SlashSuggestion(text: calc.text, detail: detail, kind: .result,
                                   icon: .symbol(calc.isConversion ? "arrow.left.arrow.right.square" : "equal.square"))
        case .rule(let suggestion, let choice):
            let text = switch choice {
            case .create: tr("Créer la règle : \(suggestion.appName) toujours dans \(suggestion.stageTitle)",
                             "Create the rule: \(suggestion.appName) always in \(suggestion.stageTitle)")
            case .later: tr("Plus tard", "Later")
            case .never: tr("Jamais pour \(suggestion.appName) dans \(suggestion.stageTitle)", "Never for \(suggestion.appName) in \(suggestion.stageTitle)")
            }
            let detail = choice == .create ? tr("\(suggestion.count) déplacements cette semaine", "\(suggestion.count) moves this week")
                : choice == .later ? tr("Reproposer demain", "Ask again tomorrow") : tr("Ne plus proposer", "Don't ask again")
            return SlashSuggestion(text: text, detail: detail, kind: .result,
                                   icon: .symbol(choice == .create ? "lightbulb" : choice == .later ? "clock" : "nosign"))
        }
    }

    /// Icône de l'objet d'une phrase ou d'une abréviation : application, fichier, ou symbole. O(1).
    private static func icon(of action: LauncherAction, appPaths: [String: String]) -> SlashSuggestion.Icon {
        switch action.subject {
        case .app(let app): .file(app.path)
        case .file(let file): .file(file.path)
        case .target(let target): appPaths[target.title].map(SlashSuggestion.Icon.file) ?? .symbol("macwindow")
        case .project: .symbol("square.stack.3d.down.right")
        case .url: .symbol("globe")
        case .text: .symbol("text.quote")
        case .openItem(let item): item.kind == .tab ? .symbol("globe") : .symbol("doc")
        }
    }

    /// `letterTargets` : étape des objets avec une saisie ; les lignes de cible montrées reçoivent une
    /// lettre et leur fenêtre le même badge à l'écran. O(v), v lignes montrées.
    private func show(badges: [TargetOverlayBadge], bar: TargetSearchBar, letterTargets: Bool = false) {
        var bar = bar
        var badges = badges
        bar.usesNativeInput = true
        bar.placement = placement
        let barWindow = (launcher.barScreenFrame ?? pointerScreen).flatMap { screen in windows.first { $0.frame == screen } } ?? windows.first
        searchBarLayout = barWindow.map { bar.layout(in: $0.frame, style: style) }
        // ⌘1 à ⌘9 sur les lignes montrées ; le rang sert au dessin et à la touche (SPEC-075).
        pickRows = []
        if bar.richRows, let layout = searchBarLayout {
            for index in layout.visibleRange(count: bar.suggestions.count, selected: bar.selectedSuggestion)
            where bar.suggestions[index].kind != .header && pickRows.count < 9 {
                pickRows.append(index)
                bar.suggestions[index].shortcut = "\(launcher.pickModifier.symbol)\(pickRows.count)"
            }
        }
        letterRows = [:]
        if letterTargets, let layout = searchBarLayout {
            let highlightedID = model.highlighted?.id
            let visible = layout.visibleRange(count: bar.suggestions.count, selected: bar.selectedSuggestion)
            for (letter, index, target) in launcherList.letterRows(visible: visible, letters: letters) {
                letterRows[letter] = index
                bar.suggestions[index].letter = "⇧" + letter.uppercased()
                guard let frame = target.frame?.cgRect, launcher.isOnScreen(target) else { continue }
                badges.append(TargetOverlayBadge(label: letter.uppercased(), title: target.title, kind: target.kind,
                                                 isActive: target.isActive, frame: RoadieScreenCoordinate.axRectToNS(frame),
                                                 isHighlighted: target.id == highlightedID, isFramed: true, isSearchResult: true))
            }
        }
        inputPanel?.labelLetters = Set(letterRows.keys)
        inputPanel?.pickModifier = launcher.pickModifier.flags
        inputPanel?.gridColumns = step == .objects ? gridColumns : nil
        inputPanel?.pathNavigation = step == .objects && commandModel == nil && Self.isPath(model.query)
        shownBar = bar
        let selectable = Self.subject(of: launcherList.row(for: launcherSelection)).flatMap(LauncherSelection.key) != nil
        inputPanel?.selectionKeys = step == .objects ? SelectionKeys(hasSelection: !selection.isEmpty, rowSelectable: selectable) : SelectionKeys()
        inputPanel?.field.placeholderString = switch step {
        case .objects where screenOnly: tr("Chercher à l'écran", "Find on screen")
        case .objects: launcher.workflowGrid.map { tr("Filtrer : ", "Filter: ") + $0.entry.workflowName } ?? tr("Rechercher ou saisir /commande", "Search or type /command")
        case .verbs: tr("Verbe ou destination…", "Verb or destination…")
        case .destinations, .batchDestinations: tr("Stage, bureau ou écran…", "Stage, desktop or display…")
        case .saving: tr("Abréviation (12 caractères au plus)…", "Abbreviation (12 characters at most)…")
        case .batchVerbs: tr("Verbe pour la sélection…", "Verb for the selection…")
        }
        if let layout = searchBarLayout {
            let text = step != .objects ? stepQuery : commandModel.map { "/" + $0.input } ?? model.query
            inputPanel?.update(text: text,
                frame: SearchBarRenderer.inputFrame(bar, bar: layout.bar, style: style),
                font: SearchBarRenderer.font(family: style.searchFontFamily, size: style.searchTextFontSize),
                color: LauncherTheme.color(style.theme.searchText.color))
        }
        let missingFrames = TargetOverlayPresenter.missingOverlayFrames(
            existing: windows.map(\.frame),
            screens: NSScreen.screens.map(\.frame),
            badgeFrames: badges.map(\.frame),
            hasGhost: ghost != nil
        )
        if !missingFrames.isEmpty {
            let added = missingFrames.map { TargetOverlayWindow(frame: $0, badges: [], style: style) }
            added.forEach { EffectAnimator.shared.visibility($0, visible: true, action: .launcher, ignoresMouseEvents: true) }
            windows.append(contentsOf: added)
        }
        for window in windows {
            window.update(badges: badges, searchBar: window === barWindow ? bar : nil, ghost: ghost)
        }
    }

    /// `then` : action de la boîte de commandes, lancée après la fin de la session (research R2).
    private func finish(_ result: TargetActionResult, then action: (@MainActor @Sendable () -> Void)? = nil) {
        guard !finished else { return }
        finished = true
        CommandBoxFollowUp.finish(cleanup: cleanup, notify: { onFinish?(result) }, then: action)
    }

    private func finishActivating(_ target: RoadieTarget, _ verb: TargetActionVerb) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit(LauncherList.rankingKey(target), query)
        onFinish?(activate(target, verb))
    }

    private func cleanup() {
        fileSearch.cancel()
        pathListing.cancel()
        workflowRuns.values.forEach { $0.cancel() }
        workflowRuns = [:]
        workflowPending.values.forEach { $0.cancel() }
        workflowPending = [:]
        previewWork?.cancel()
        previewWork = nil
        pendingPreview = nil
        if sentPreview != nil {
            sentPreview = nil
            launcher.preview(nil) { _ in }
        }
        model.cancelPendingReturn()
        searchBarLayout = nil
        LauncherIconRaster.purgeTransientThumbnails()
        timer?.invalidate()
        timer = nil
        inputPanel?.endEditing()
        inputPanel = nil
        removeEventTap()
        for window in windows {
            EffectAnimator.shared.visibility(window, visible: false, action: .launcher) {
                window.orderOut(nil)
                window.close()
            }
        }
        windows = []
        NSApplication.shared.updateWindows()
    }
}
