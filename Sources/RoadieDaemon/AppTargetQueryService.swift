import AppKit
import Foundation
import RoadieAX
import RoadieCore

public struct AppTargetQueryReport: Codable, Equatable, Sendable {
    public var targets: [RoadieTarget]
    public var partial: Bool
    public var error: String?
    /// Statistiques du parcours AX ; absentes quand aucun parcours n'a eu lieu.
    public var scan: AppTargetScanStats?
    /// Portée `visible_windows` (SPEC-021) : statistiques de chaque fenêtre parcourue.
    public var windowScans: [AppTargetScanStats]

    public init(
        targets: [RoadieTarget] = [], partial: Bool = false, error: String? = nil, scan: AppTargetScanStats? = nil,
        windowScans: [AppTargetScanStats] = []
    ) {
        self.targets = targets
        self.partial = partial
        self.error = error
        self.scan = scan
        self.windowScans = windowScans
    }
}

/// Mesure d'un parcours applicatif, journalisée en `targets.app_scan` pour régler
/// `max_depth` et `timeout_ms` avec des chiffres (contrat `specs/018-electron-app-hints/contracts`).
public struct AppTargetScanStats: Codable, Equatable, Sendable {
    public var bundleID: String
    public var isElectron: Bool
    /// `enabled`, `unsupported` ou `skipped`.
    public var manualAccessibility: String
    public var visited: Int
    public var candidates: Int
    public var offscreen: Int
    public var maxDepthReached: Int
    /// Éléments à `max_depth` dont les enfants n'ont pas été lus.
    public var atMaxDepth: Int
    /// Une zone web (`AXWebArea`) a été lue : Electron a publié son contenu.
    public var sawWebArea: Bool
    /// Candidats ajoutés par la règle « feuille focalisable » (SPEC-020).
    public var focusableAdded: Int
    /// Rôles lus et non retenus, les plus fréquents d'abord (`AXGroup=197,AXStaticText=106`).
    public var rejectedRoles: String
    public var elapsedMs: Int
    /// `complete`, `timeout` ou `limit`.
    public var stopReason: String
    public var retries: Int

    public init(
        bundleID: String, isElectron: Bool, manualAccessibility: String,
        visited: Int, candidates: Int, offscreen: Int, maxDepthReached: Int, atMaxDepth: Int,
        sawWebArea: Bool, focusableAdded: Int, rejectedRoles: String, elapsedMs: Int, stopReason: String, retries: Int
    ) {
        self.bundleID = bundleID
        self.isElectron = isElectron
        self.manualAccessibility = manualAccessibility
        self.visited = visited
        self.candidates = candidates
        self.offscreen = offscreen
        self.maxDepthReached = maxDepthReached
        self.atMaxDepth = atMaxDepth
        self.sawWebArea = sawWebArea
        self.focusableAdded = focusableAdded
        self.rejectedRoles = rejectedRoles
        self.elapsedMs = elapsedMs
        self.stopReason = stopReason
        self.retries = retries
    }

    public var eventDetails: [String: String] {
        [
            "bundleID": bundleID,
            "isElectron": String(isElectron),
            "manualAccessibility": manualAccessibility,
            "visited": String(visited),
            "candidates": String(candidates),
            "offscreen": String(offscreen),
            "maxDepthReached": String(maxDepthReached),
            "atMaxDepth": String(atMaxDepth),
            "sawWebArea": String(sawWebArea),
            "focusableAdded": String(focusableAdded),
            "rejectedRoles": rejectedRoles,
            "elapsedMs": String(elapsedMs),
            "stopReason": stopReason,
            "retries": String(retries),
        ]
    }
}

public struct AppElementCandidate: Equatable, Sendable {
    public var id: String
    public var role: String
    public var title: String
    public var value: String?
    public var frame: Rect?
    public var actions: [String]
    /// Retenu par la règle « feuille focalisable » d'une zone web (SPEC-020), sans action exposée.
    public var isFocusableLeaf: Bool
    /// Texte des `AXStaticText` descendants, pour la recherche seulement (SPEC-021) ; `title` reste inchangé.
    public var searchText: String
    /// Feuille focalisable : cadre de sa première image ou de son premier texte visible (SPEC-021).
    public var clickFrame: Rect?

    public init(
        id: String, role: String, title: String, value: String? = nil, frame: Rect? = nil, actions: [String],
        isFocusableLeaf: Bool = false, searchText: String = "", clickFrame: Rect? = nil
    ) {
        self.clickFrame = clickFrame
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.actions = actions
        self.isFocusableLeaf = isFocusableLeaf
        self.searchText = searchText
    }
}

public protocol AppTargetProviding {
    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport
    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult
}

public struct AppTargetQueryService {
    private let provider: any AppTargetProviding

    public init(provider: any AppTargetProviding = LiveAppTargetProvider()) {
        self.provider = provider
    }

    public func query(config: AppTargetsConfig, enabledOverride: Bool = false) -> AppTargetQueryReport {
        guard config.enabled || enabledOverride else {
            return AppTargetQueryReport(error: "app_targets_disabled")
        }
        return provider.candidates(config: config)
    }

    public func click(_ target: RoadieTarget, action: TargetActionVerb = .click) -> TargetActionResult {
        provider.click(target, action: action)
    }

    /// Electron construit son arbre AX en arrière-plan après `AXManualAccessibility` : juste après
    /// l'activation, seuls les boutons de la fenêtre existent. Un parcours complet (ni coupé par la
    /// profondeur, le temps ou la limite) sans zone web (`AXWebArea`) est relancé, deux fois au plus.
    /// Un parcours coupé ne prouve rien et ne relance pas ; une application native ne relance jamais.
    public static func shouldRetryScan(isElectron: Bool, sawWebArea: Bool, exploredFully: Bool, retries: Int) -> Bool {
        isElectron && !sawWebArea && exploredFully && retries < 2
    }

    /// Le code retour de `AXManualAccessibility` ne prouve pas son effet (issue Electron #37465) :
    /// Electron se reconnaît à son framework embarqué.
    public static func isElectronBundle(at url: URL?) -> Bool {
        guard let url else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    /// Partie visible d'un élément dans la fenêtre, nil s'il est entièrement dehors. Le clic Roadie
    /// vise le centre du cadre retenu : rogné, il reste dans la fenêtre au lieu de tomber sur une
    /// autre. Sans cadre de fenêtre connu, le cadre est gardé tel quel.
    public static func visibleFrame(_ frame: Rect, in windowFrame: Rect?) -> Rect? {
        guard let windowFrame else { return frame }
        let visible = frame.cgRect.intersection(windowFrame.cgRect)
        return visible.isNull || visible.isEmpty ? nil : Rect(visible)
    }

    /// Le parcours est en préordre : un élément focalisable contient un autre focalisable si et
    /// seulement si le focalisable suivant dans ce préordre est son descendant (chemin `path.`).
    public static func keepsFocusableLeaf(path: String, nextFocusablePath: String?) -> Bool {
        guard let nextFocusablePath else { return true }
        return !nextFocusablePath.hasPrefix(path + ".")
    }

    /// Feuilles focalisables retenues parmi `pending`. `markers` liste en préordre les focalisables de
    /// zone web et les sous-arbres inconnus (coupés à `max_depth` ou enfants illisibles) : un élément
    /// suivi d'un marqueur descendant n'est pas une feuille, ou ne peut pas être prouvé tel. `unexplored`
    /// liste les chemins restés dans la pile d'un parcours coupé. Heuristique sur l'arbre parcouru :
    /// un alias des attributs boost peut placer un élément sous un autre parent que son parent réel.
    /// Complexité : O(m + p + u * d), m marqueurs, p en attente, u restés dans la pile, d profondeur.
    public static func focusableLeaves(pending: [String], markers: [String], unexplored: [String]) -> Set<String> {
        var containers = Set<String>()
        for index in markers.indices.dropLast()
            where !keepsFocusableLeaf(path: markers[index], nextFocusablePath: markers[index + 1]) {
            containers.insert(markers[index])
        }
        // Ancêtres des chemins restés dans la pile : leur sous-arbre n'a pas été lu en entier.
        for path in unexplored {
            var ancestor = Substring(path)
            while let dot = ancestor.lastIndex(of: ".") {
                ancestor = ancestor[..<dot]
                containers.insert(String(ancestor))
            }
        }
        return Set(pending.filter { !containers.contains($0) })
    }

    /// Une feuille qui couvre au moins 80 % de la cible web retenue qui l'enveloppe est le même élément
    /// cliquable (bouton qui enveloppe un `div` focalisable) : seule la cible garde sa lettre. Une cible
    /// beaucoup plus grande est un conteneur (mesure Bluejay : `AXGroup` avec `AXPress` sur toute la page).
    /// Décision locale : ne dépend ni du nombre de feuilles ni d'un parcours complet.
    public static func duplicatesTarget(_ leaf: Rect, of retainedAncestor: Rect?) -> Bool {
        guard let retainedAncestor else { return false }
        let ancestorArea = retainedAncestor.width * retainedAncestor.height
        let leafArea = leaf.width * leaf.height
        let overlap = leaf.cgRect.intersection(retainedAncestor.cgRect)
        guard ancestorArea > 0, leafArea > 0, !overlap.isNull else { return false }
        // Recouvrement dans les deux sens : même boîte. Une feuille qui déborde d'une petite cible
        // (cible dans un coin) n'est pas un doublon (contre-revue round 5).
        let shared = Double(overlap.width * overlap.height)
        return shared >= 0.8 * ancestorArea && shared >= 0.8 * leafArea
    }

    /// Texte de recherche d'une cible web : fragments des `AXStaticText` descendants, sans répéter
    /// le titre ou la valeur, borné à `limit` caractères (SPEC-021).
    public static func searchText(_ fragments: [String], excluding own: [String], limit: Int = 500) -> String {
        let ownTexts = Set(own.map(TargetHintService.normalized).filter { !$0.isEmpty })
        var kept: [String] = []
        for fragment in fragments {
            let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !ownTexts.contains(TargetHintService.normalized(trimmed)), kept.last != trimmed else { continue }
            kept.append(trimmed)
        }
        return String(kept.joined(separator: " ").prefix(limit))
    }

    /// Un candidat qui contient d'autres candidats garde son texte s'il occupe au plus un quart de la
    /// fenêtre : une ligne avec ses boutons, pas un conteneur de page.
    public static func keepsContainerText(_ frame: Rect?, in windowFrame: Rect?) -> Bool {
        guard let frame, let windowFrame else { return false }
        return frame.width * frame.height * 4 <= windowFrame.width * windowFrame.height
    }

    /// Point de clic d'une cible caché par une fenêtre placée devant la sienne (SPEC-021).
    /// Complexité : O(f), f fenêtres devant.
    public static func isCovered(_ target: RoadieTarget, by framesInFront: [Rect]) -> Bool {
        guard let frame = (target.clickFrame ?? target.frame)?.cgRect else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return framesInFront.contains { $0.cgRect.contains(point) }
    }

    /// Même seuil que l'affichage (`TargetOverlayPresenter`, plus de 4 points) : en dessous, aucune
    /// lettre n'est dessinée. Chromium réduit à 1 point les éléments défilés hors d'une liste.
    /// Processus d'une cible d'application : son id vaut `app:<pid>/<chemin>`.
    public static func pid(of target: RoadieTarget) -> pid_t? {
        guard target.id.hasPrefix("app:"), let slash = target.id.firstIndex(of: "/") else { return nil }
        return pid_t(target.id[target.id.index(target.id.startIndex, offsetBy: 4)..<slash])
    }

    /// L'élément occupe-t-il encore le cadre affiché par l'overlay (REL-012) ? Chaque bord doit rester
    /// à `tolerance` points près : un décalage d'arrondi passe, un défilement ou un déplacement de
    /// fenêtre non. `current` nil : élément introuvable. O(1).
    public static func isStillInPlace(_ shown: Rect, current: Rect?, tolerance: Double = 4) -> Bool {
        guard let current else { return false }
        let a = shown.cgRect
        let b = current.cgRect
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    public static func isHintable(_ visible: Rect) -> Bool {
        visible.width > 4 && visible.height > 4
    }

    /// Un élément non parcouru cache-t-il un contenu ? Oui s'il est hors fenêtre ou réduit à 1 point
    /// (élément défilé hors d'une liste). Non pour un élément réellement fin, comme une barre de
    /// progression de 4 points : sinon la carte vidéo qui la contient ne serait plus une feuille (mesure Bluejay).
    public static func hidesContent(_ visible: Rect?) -> Bool {
        guard let visible else { return true }
        return min(visible.width, visible.height) <= 1
    }

    /// Rôles lus et non retenus, les plus fréquents d'abord : `AXGroup=197,AXStaticText=106`.
    /// Complexité : O(k log k), k = rôles distincts.
    public static func rejectedRoleSummary(_ counts: [String: Int], limit: Int = 5) -> String {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    /// `windowID` : fenêtre parcourue, portée par chaque cible ; le clic exige cette identité (REL-012).
    public static func targets(
        from candidates: [AppElementCandidate], config: AppTargetsConfig, windowID: UInt32? = nil
    ) -> [RoadieTarget] {
        let allowedRoles = Set(config.includeRoles)
        return candidates
            .filter { allowedRoles.contains($0.role) || !$0.actions.isEmpty || $0.isFocusableLeaf }
            .prefix(config.maxTargets)
            .map { candidate in
                let title = candidate.title.isEmpty ? candidate.role : candidate.title
                return RoadieTarget(
                    id: "app:\(candidate.id)",
                    kind: .appElement,
                    title: title,
                    subtitle: [candidate.role, candidate.value].compactMap(\.self).joined(separator: " - "),
                    source: .app,
                    matchText: RoadieTarget.normalizedMatchText([candidate.id, candidate.role, title, candidate.value ?? "", candidate.searchText]),
                    scope: TargetScopeSnapshot(windowId: windowID),
                    frame: candidate.frame,
                    actions: [.click, .doubleClick, .rightClick, .commandClick, .inspect],
                    diagnostics: candidate.actions.map { "action=\($0)" } + ["role=\(candidate.role)"],
                    searchText: candidate.searchText.isEmpty ? nil : candidate.searchText,
                    clickFrame: candidate.clickFrame
                )
            }
    }
}

/// Ensemble d'objets Core Foundation par égalité réelle (`CFEqual`). `CFHash` seul ne suffit pas :
/// des éléments AX Chromium distincts partagent un hash (mesure Bluejay : la zone de contenu entière
/// était écartée comme « déjà vue », research.md). Complexité : O(1) en moyenne, O(c) sur c collisions.
public struct CFIdentitySet {
    private var buckets: [CFHashCode: [CFTypeRef]] = [:]

    public init() {}

    /// Vrai si `value` n'était pas déjà présent.
    public mutating func insert(_ value: CFTypeRef) -> Bool {
        let hash = CFHash(value)
        if buckets[hash, default: []].contains(where: { CFEqual($0, value) }) { return false }
        buckets[hash, default: []].append(value)
        return true
    }
}

/// Éléments AX des cibles du dernier parcours, par id de cible (R2-02). Le clic relit l'élément
/// affiché lui-même, pas l'élément qui occupe aujourd'hui le même rang : un élément remplacé, même
/// au même cadre, devient invalide et ne se relit plus. En mémoire seulement, remplacée à chaque
/// parcours ; protégée par un verrou, car la portée `visible_windows` remplit la table depuis un fil
/// par fenêtre. Un parcours plus récent rend les ajouts d'un ancien sans effet (numéro de parcours).
final class AppTargetElementRegistry: @unchecked Sendable {
    static let shared = AppTargetElementRegistry()

    struct Entry {
        var element: AXUIElement
        /// Premier contenu visible d'une feuille focalisable : l'élément sous `clickFrame`.
        var clickElement: AXUIElement?
        var window: AXUIElement
    }

    private let lock = NSLock()
    private var generation = 0
    private var entries: [String: Entry] = [:]

    /// Début d'un parcours : vide la table et rend le numéro du parcours. O(1), hors libération.
    func begin() -> Int {
        lock.withLock {
            generation += 1
            entries = [:]
            return generation
        }
    }

    /// Éléments d'une fenêtre lue ; sans effet si un autre parcours a commencé depuis. O(k).
    func add(_ new: [String: Entry], generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            entries.merge(new) { _, latest in latest }
        }
    }

    /// O(1) en moyenne.
    func entry(for id: String) -> Entry? {
        lock.withLock { entries[id] }
    }
}

/// Résultat du parcours d'une fenêtre visible (SPEC-021) ; `order` : rang de la fenêtre, de l'avant
/// vers l'arrière.
public struct VisibleWindowScan: Sendable {
    public var order: Int
    public var targets: [RoadieTarget]
    public var stats: AppTargetScanStats
    public var partial: Bool
}

/// Issue de l'attente du focus avant un clic sur la cible d'une fenêtre (REL-012).
public enum AppWindowFocusWait: Equatable, Sendable {
    case focused
    /// La fenêtre n'existe plus dans son application.
    case windowGone
    /// La fenêtre n'est pas devenue active dans le délai.
    case timedOut
}

/// Frontière AX injectable : les fixtures exécutent le même parcours sans permission macOS.
struct AppTargetScanReader {
    var string: (AXUIElement, String) -> String?
    var actions: (AXUIElement) -> [String]
    var frame: (AXUIElement) -> Rect?
    var children: (AXUIElement, Bool) -> (children: [AXUIElement], unreadable: Bool)
    var focusSettable: (AXUIElement) -> Bool
}

public struct LiveAppTargetProvider: AppTargetProviding, Sendable {
    /// Points d'injection des tests (REL-012, TEST-002) : attente du focus et émission des événements
    /// souris, sans AX ni CGEvent réels.
    private let waitForFocus: @Sendable (CGWindowID, pid_t, TimeInterval) -> AppWindowFocusWait
    private let postEvent: @Sendable (CGEvent) -> Void
    /// Cadre visible actuel de la zone cliquée d'une cible (`clickFrame`, sinon `frame`), relu après
    /// le focus (REL-012, R2-02) ; nil : élément introuvable, remplacé ou illisible.
    private let currentFrame: @Sendable (RoadieTarget) -> Rect?

    public init() {
        self.init(
            waitForFocus: { Self.waitUntilFocused(windowID: $0, pid: $1, timeout: $2) },
            postEvent: { $0.post(tap: .cghidEventTap) },
            currentFrame: { Self.currentVisibleFrame(of: $0, in: .shared, readFrame: Self.readFrame) }
        )
    }

    init(
        waitForFocus: @escaping @Sendable (CGWindowID, pid_t, TimeInterval) -> AppWindowFocusWait,
        postEvent: @escaping @Sendable (CGEvent) -> Void,
        currentFrame: @escaping @Sendable (RoadieTarget) -> Rect?
    ) {
        self.waitForFocus = waitForFocus
        self.postEvent = postEvent
        self.currentFrame = currentFrame
    }

    public func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        guard AXIsProcessTrusted() else {
            return AppTargetQueryReport(error: "accessibility_denied")
        }
        switch config.scope {
        case "frontmost_window":
            return frontmostWindowCandidates(config: config)
        case "visible_windows":
            return visibleWindowsCandidates(config: config)
        default:
            return AppTargetQueryReport(error: "unsupported_scope")
        }
    }

    private func frontmostWindowCandidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppTargetQueryReport(error: "no_frontmost_application")
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // REL-012 : identité de la fenêtre, pour que le clic vérifie son focus. O(m), m fenêtres de l'application.
        guard let window = Self.copyElementAttribute(appElement, kAXFocusedWindowAttribute),
              let windowID = axWindowElements(pid: app.processIdentifier).first(where: { CFEqual($0.value, window) })?.key
        else {
            return AppTargetQueryReport(error: "no_focused_window")
        }
        let generation = AppTargetElementRegistry.shared.begin()
        let result = scanWindow(window, app: app, rootPath: "0", config: config, startedAt: Date())
        AppTargetElementRegistry.shared.add(result.pass.elements, generation: generation)
        let partial = result.pass.stopReason != "complete"
        let targets = AppTargetQueryService.targets(from: result.pass.candidates, config: config, windowID: windowID)
        return AppTargetQueryReport(
            targets: Self.labeled(targets, config: config),
            partial: partial,
            error: partial ? "partial_timeout_or_limit" : nil,
            scan: result.stats
        )
    }

    /// Portée `visible_windows` du mode lettres : toutes les fenêtres lues, puis étiquetées ensemble.
    private func visibleWindowsCandidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        let scan = scanVisibleWindows(config: config)
        guard !scan.results.isEmpty else {
            return AppTargetQueryReport(error: "no_visible_window", windowScans: scan.skipped)
        }
        let partial = scan.results.contains(where: \.partial)
        return AppTargetQueryReport(
            targets: Self.labeled(scan.results.flatMap(\.targets), config: config),
            partial: partial,
            error: partial ? "partial_timeout_or_limit" : nil,
            windowScans: scan.skipped + scan.results.map(\.stats)
        )
    }

    /// Toutes les fenêtres à l'écran (SPEC-021) : un parcours par fenêtre, en parallèle, avec la même
    /// échéance ; la durée est celle de la fenêtre la plus lente, pas la somme. `onWindow` reçoit chaque
    /// fenêtre dès qu'elle est lue, depuis le fil de son parcours (mode recherche : la barre est déjà
    /// ouverte). Cibles sans étiquette ; un élément caché par une fenêtre de devant est retiré.
    /// `max_targets` s'applique à chaque fenêtre. `results` suit l'ordre des fenêtres, de l'avant vers
    /// l'arrière ; `skipped` liste les fenêtres écartées avant parcours (raison dans `stopReason`).
    /// Complexité : O(w * n) appels AX répartis sur w fils, n éléments lus par fenêtre ; occlusion
    /// O(c * w), c cibles, w fenêtres à l'écran (quelques dizaines au plus).
    public func scanVisibleWindows(
        config: AppTargetsConfig,
        onWindow: @Sendable (VisibleWindowScan) -> Void = { _ in }
    ) -> (results: [VisibleWindowScan], skipped: [AppTargetScanStats]) {
        guard AXIsProcessTrusted() else { return ([], []) }
        let generation = AppTargetElementRegistry.shared.begin()
        let windows = Self.visibleWindows()
        var elementsByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var jobs: [(order: Int, id: CGWindowID, element: AXUIElement, app: NSRunningApplication)] = []
        var skipped: [AppTargetScanStats] = []
        for (order, window) in windows.enumerated() {
            if elementsByPID[window.pid] == nil {
                elementsByPID[window.pid] = axWindowElements(pid: window.pid)
            }
            let app = NSRunningApplication(processIdentifier: window.pid)
            guard let element = elementsByPID[window.pid]?[window.id], let app else {
                skipped.append(AppTargetScanStats(
                    bundleID: app?.bundleIdentifier ?? "pid:\(window.pid)", isElectron: false, manualAccessibility: "skipped",
                    visited: 0, candidates: 0, offscreen: 0, maxDepthReached: 0, atMaxDepth: 0, sawWebArea: false,
                    focusableAdded: 0, rejectedRoles: "window=\(window.id),axWindows=\(elementsByPID[window.pid]?.count ?? 0)",
                    elapsedMs: 0, stopReason: app == nil ? "no_app" : "no_ax_window", retries: 0
                ))
                continue
            }
            jobs.append((order, window.id, element, app))
        }

        let startedAt = Date()
        let frames = windows.map(\.frame)
        let batch = WindowScanBatch(jobs: jobs)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = batch.jobs[index]
            let scan = scanWindow(job.element, app: job.app, rootPath: "w\(job.id)", config: config, startedAt: startedAt)
            let inFront = Array(frames.prefix(job.order))
            let targets = AppTargetQueryService.targets(from: scan.pass.candidates, config: config, windowID: job.id)
                .filter { !AppTargetQueryService.isCovered($0, by: inFront) }
            let result = VisibleWindowScan(order: job.order, targets: targets, stats: scan.stats,
                                           partial: scan.pass.stopReason != "complete")
            batch.results[index] = result
            // Avant `onWindow` : une cible affichée peut être cliquée aussitôt (mode recherche).
            AppTargetElementRegistry.shared.add(scan.pass.elements, generation: generation)
            onWindow(result)
        }
        return (Array(batch.results).compactMap(\.self), skipped)
    }

    private struct WindowScan {
        var pass: ScanPass
        var stats: AppTargetScanStats
    }

    /// `@unchecked Sendable` : pendant `concurrentPerform`, chaque fil lit `jobs` sans le modifier
    /// et écrit seulement sa case de `results`. Les éléments AX se lisent depuis n'importe quel fil.
    private final class WindowScanBatch: @unchecked Sendable {
        let jobs: [(order: Int, id: CGWindowID, element: AXUIElement, app: NSRunningApplication)]
        let results: UnsafeMutableBufferPointer<VisibleWindowScan?>

        init(jobs: [(order: Int, id: CGWindowID, element: AXUIElement, app: NSRunningApplication)]) {
            self.jobs = jobs
            results = .allocate(capacity: jobs.count)
            results.initialize(repeating: nil)
        }

        deinit {
            results.deinitialize()
            results.deallocate()
        }
    }

    /// Fenêtres normales à l'écran (couche 0), de l'avant vers l'arrière, hors fenêtres de Roadie.
    private static func visibleWindows() -> [(id: CGWindowID, pid: pid_t, frame: Rect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32, id > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  // Sans application (cadres de l'outil `borders`) : ni parcourue, ni masquante.
                  NSRunningApplication(processIdentifier: pid) != nil,
                  info[kCGWindowLayer as String] as? Int ?? 0 == 0,
                  info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  !["roadied", "roadie"].contains(info[kCGWindowOwnerName as String] as? String ?? ""),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 40, rect.height > 40
            else { return nil }
            return (id, pid, Rect(rect))
        }
    }

    private static func labeled(_ targets: [RoadieTarget], config: AppTargetsConfig) -> [RoadieTarget] {
        var targets = targets
        let labels = TargetHintService.labels(count: targets.count, alphabet: config.hintCharacters)
        for index in targets.indices {
            targets[index].label = labels[index]
        }
        return targets
    }

    /// Parcours d'une fenêtre, avec ses relances Electron.
    /// Complexité : O(r * n), n = éléments lus par passe (borné par max_targets, max_depth et
    /// timeout_ms), r ≤ 3 passes. Seule une application Electron dont l'arbre est vide relance.
    /// Les relances et leurs attentes partagent une échéance : timeout_ms + 300 ms au total, à un
    /// appel AX près (un appel synchrone lent n'est pas interrompu).
    private func scanWindow(
        _ window: AXUIElement, app: NSRunningApplication, rootPath: String, config: AppTargetsConfig, startedAt: Date
    ) -> WindowScan {
        let effectiveBoost = config.axBoostEnabled || config.additionalBoostBundleIDs.contains(app.bundleIdentifier ?? "")
        let timeout = TimeInterval(config.timeoutMs) / 1000
        let retryDeadline = startedAt.addingTimeInterval(timeout + 0.3)
        let isElectron = AppTargetQueryService.isElectronBundle(at: app.bundleURL)
        let manualAccessibility = effectiveBoost && isElectron ? requestPublication(app.processIdentifier) : "skipped"
        var pass = scan(window: window, rootPath: rootPath, pid: app.processIdentifier, config: config, boost: effectiveBoost,
                        deadline: startedAt.addingTimeInterval(timeout))
        var retries = 0
        while AppTargetQueryService.shouldRetryScan(
            isElectron: isElectron && effectiveBoost,
            sawWebArea: pass.sawWebArea,
            exploredFully: pass.stopReason == "complete" && pass.atMaxDepth == 0,
            retries: retries
        ), Date().addingTimeInterval(0.15) < retryDeadline {
            Thread.sleep(forTimeInterval: 0.15)
            retries += 1
            pass = scan(window: window, rootPath: rootPath, pid: app.processIdentifier, config: config, boost: effectiveBoost,
                        deadline: retryDeadline)
        }
        return WindowScan(pass: pass, stats: AppTargetScanStats(
            bundleID: app.bundleIdentifier ?? "",
            isElectron: isElectron,
            manualAccessibility: manualAccessibility,
            visited: pass.visited,
            candidates: pass.candidates.count,
            offscreen: pass.offscreen,
            maxDepthReached: pass.maxDepthReached,
            atMaxDepth: pass.atMaxDepth,
            sawWebArea: pass.sawWebArea,
            focusableAdded: pass.focusableAdded,
            rejectedRoles: AppTargetQueryService.rejectedRoleSummary(pass.rejectedRoles),
            elapsedMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            stopReason: pass.stopReason,
            retries: retries
        ))
    }

    /// Electron ne publie son arbre AX qu'à la demande d'un outil d'assistance
    /// (https://www.electronjs.org/docs/latest/tutorial/accessibility). Redemandée à chaque parcours :
    /// une demande faite au lancement de l'application peut être ignorée (mesure du 2026-10-12 sur
    /// draw.io, voir research.md). Délai AX court : une application figée ne bloque pas le parcours.
    private func requestPublication(_ pid: pid_t) -> String {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
            ? "enabled" : "unsupported"
    }

    struct ScanPass {
        var candidates: [AppElementCandidate] = []
        var visited = 0
        var offscreen = 0
        var maxDepthReached = 0
        var atMaxDepth = 0
        var sawWebArea = false
        var focusableAdded = 0
        var rejectedRoles: [String: Int] = [:]
        var stopReason = "complete"
        /// Élément AX de chaque candidat, par id de cible (`app:<pid>/<chemin>`, R2-02).
        var elements: [String: AppTargetElementRegistry.Entry] = [:]
    }

    /// Complexité : O(n + m + p + u * d), n = éléments lus ; voir `focusableLeaves` pour m, p, u, d.
    func scan(window: AXUIElement, rootPath: String, pid: pid_t, config: AppTargetsConfig, boost: Bool, deadline: Date,
              reader: AppTargetScanReader? = nil) -> ScanPass {
        let readString = reader?.string ?? copyStringAttribute
        let readActions = reader?.actions ?? copyActionNames
        let readFrame = reader?.frame ?? Self.copyFrame
        let readChildren = reader?.children ?? Self.copyChildren
        let readFocusSettable = reader?.focusSettable ?? isFocusSettable
        let windowFrame = readFrame(window)
        // `inWeb` : sous une `AXWebArea` ; `retainedFrame` : cadre visible de la plus proche cible web ajoutée.
        // Le texte natif reste dans le cadre de son contrôle ; les zones web gardent leur règle SPEC-021.
        var stack: [(element: AXUIElement, path: String, depth: Int, inWeb: Bool, retainedFrame: Rect?, textOwner: String?, textOwnerFrame: Rect?)] =
            [(window, rootPath, 0, false, nil, nil, nil)]
        var pass = ScanPass()
        var seen = CFIdentitySet()
        let ignoredActions: Set<String> = ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"]
        let includedRoles = Set(config.includeRoles)
        let nativeTextRoles: Set<String> = ["AXRow", "AXCell", "AXButton", "AXLink", "AXCheckBox", "AXRadioButton",
                                            "AXPopUpButton", "AXMenuItem", "AXTextField", "AXComboBox", "AXTab"]
        // SPEC-020 : feuilles focalisables en attente et marqueurs de zone web, en préordre.
        var pending: [(candidate: AppElementCandidate, path: String, element: AXUIElement)] = []
        var markers: [String] = []
        var texts: [String: [String]] = [:]
        var historicPaths: [String] = []
        // Premier contenu visible (préordre) de chaque candidat web : point de clic des feuilles.
        var contents: [String: (frame: Rect, element: AXUIElement)] = [:]

        while let entry = stack.popLast() {
            let (element, path, depth, parentInWeb, retainedFrame, textOwner, textOwnerFrame) = entry
            guard seen.insert(element) else { continue }
            if pass.candidates.count >= config.maxTargets {
                pass.stopReason = "limit"
                stack.append(entry)
                break
            }
            if Date() > deadline {
                pass.stopReason = "timeout"
                stack.append(entry)
                break
            }
            pass.visited += 1
            pass.maxDepthReached = max(pass.maxDepthReached, depth)
            let role = readString(element, kAXRoleAttribute) ?? "AXUnknown"
            let isWebArea = role == "AXWebArea"
            let inWeb = parentInWeb || isWebArea
            pass.sawWebArea = pass.sawWebArea || isWebArea
            // Une liste native peut publier des centaines de lignes hors fenêtre. Leur cadre suffit
            // à les rejeter : ne pas dépenser le budget en libellés/actions, mais lire encore les enfants.
            let readsNativeFrame = !inWeb && (role == "AXRow" || role == "AXCell" || role == "AXStaticText")
            let nativeFrame = readsNativeFrame ? readFrame(element) : nil
            let skipsMetadata = nativeFrame != nil && nativeFrame.flatMap { AppTargetQueryService.visibleFrame($0, in: windowFrame) } == nil
            let rawTitle = skipsMetadata ? nil : readString(element, kAXTitleAttribute)
            let preferredTitle = inWeb ? rawTitle : Self.nonempty(rawTitle)
            let title = skipsMetadata ? "" : preferredTitle ?? readString(element, kAXDescriptionAttribute) ?? ""
            let value = skipsMetadata ? nil : readString(element, kAXValueAttribute)
            let actions = skipsMetadata ? [] : readActions(element).filter { !ignoredActions.contains($0) }
            let isCandidate = !actions.isEmpty || includedRoles.contains(role)
            // SolidJS, React... délèguent les clics au document : Chromium ne donne pas d'action aux
            // éléments cliquables, mais les expose focalisables (mesure Bluejay, research.md).
            let isPending = !isCandidate && inWeb && !isWebArea && depth < config.maxDepth && readFocusSettable(element)
            if inWeb && (isCandidate || isPending) {
                markers.append(path)
            }
            if inWeb, role == "AXStaticText", let owner = textOwner, let text = value ?? (title.isEmpty ? nil : title) {
                texts[owner, default: []].append(text)
            }
            var retained = false
            var retainedVisible: Rect?
            // Zone web : le cadre est lu pour tous, afin de ne pas descendre dans un élément invisible.
            let needsFrame = isCandidate || isPending || (inWeb && !isWebArea) || (textOwner != nil && role == "AXStaticText")
            let frame = readsNativeFrame ? nativeFrame : (needsFrame ? readFrame(element) : nil)
            let visibleFrame = frame.flatMap { AppTargetQueryService.visibleFrame($0, in: windowFrame) }
            if !inWeb, role == "AXStaticText", let owner = textOwner, let ownerFrame = textOwnerFrame,
               let visible = visibleFrame, !visible.cgRect.intersection(ownerFrame.cgRect).isEmpty,
               let text = Self.nonempty(value) ?? Self.nonempty(title) {
                texts[owner, default: []].append(text)
            }
            if inWeb, role == "AXImage" || role == "AXStaticText", let owner = textOwner, contents[owner] == nil,
               let visible = visibleFrame, AppTargetQueryService.isHintable(visible) {
                contents[owner] = (visible, element)
            }
            if isCandidate || isPending, frame != nil {
                if let visible = visibleFrame,
                   !isPending || (AppTargetQueryService.isHintable(visible)
                                  && !AppTargetQueryService.duplicatesTarget(visible, of: retainedFrame)) {
                    let candidate = AppElementCandidate(
                        id: "\(pid)/\(path)",
                        role: role,
                        title: title,
                        value: value,
                        frame: visible,
                        actions: actions,
                        isFocusableLeaf: isPending
                    )
                    if isPending {
                        pending.append((candidate, path, element))
                    } else {
                        pass.candidates.append(candidate)
                        pass.elements["app:\(candidate.id)"] = .init(element: element, window: window)
                        historicPaths.append(path)
                        retained = true
                        retainedVisible = visible
                    }
                } else if isCandidate {
                    pass.offscreen += 1
                }
            }
            if !retained {
                pass.rejectedRoles[role, default: 0] += 1
            }
            guard depth < config.maxDepth else {
                pass.atMaxDepth += 1
                if inWeb { markers.append(path + ".?") }
                continue
            }
            // Zone web : un élément invisible ou réduit à un trait (liste défilée) n'est pas parcouru ; il
            // reste « inconnu » pour la règle des feuilles. Mesure Bluejay : ~1 000 abonnements de la barre
            // latérale à 1 point épuisaient le budget avant la grille de vidéos (research.md).
            // Limite connue (contre-revue round 5) : un enfant qui déborderait d'un parent de 4 points ou
            // moins n'est pas lu ; descendre dans ces éléments fins a fait perdre les cartes de Bluejay (mesure).
            if inWeb, !isWebArea, frame != nil, !(visibleFrame.map(AppTargetQueryService.isHintable) ?? false) {
                if AppTargetQueryService.hidesContent(visibleFrame) { markers.append(path + ".?") }
                continue
            }
            let (children, unreadable) = readChildren(element, boost && !inWeb)
            if inWeb && unreadable { markers.append(path + ".?") }
            let ownsNativeText = !inWeb && retained && nativeTextRoles.contains(role)
            for (index, child) in children.enumerated().reversed() {
                stack.append((child, "\(path).\(index)", depth + 1, inWeb, inWeb && retained ? retainedVisible : retainedFrame,
                              (inWeb && (isCandidate || isPending)) || ownsNativeText ? path : textOwner,
                              ownsNativeText ? retainedVisible : textOwnerFrame))
            }
        }

        // Les cibles historiques gardent leur priorité ; les feuilles s'ajoutent ensuite.
        let leaves = AppTargetQueryService.focusableLeaves(
            pending: pending.map(\.path),
            markers: markers,
            unexplored: stack.map(\.path)
        )
        // Texte des enfants : chaque texte va à son plus proche candidat. Un grand conteneur ne le garde
        // pas (le conteneur de page de Bluejay recevrait sinon tout le texte de la page) ; une ligne qui
        // contient ses propres boutons le garde (fil de T3 Code avec épingle et menu, mesure du 2026-10-13).
        var containers = Set<String>()
        for index in markers.indices.dropLast()
            where !AppTargetQueryService.keepsFocusableLeaf(path: markers[index], nextFocusablePath: markers[index + 1]) {
            containers.insert(markers[index])
        }
        func withText(_ candidate: AppElementCandidate, at path: String) -> AppElementCandidate {
            guard let fragments = texts[path],
                  !containers.contains(path) || AppTargetQueryService.keepsContainerText(candidate.frame, in: windowFrame)
            else { return candidate }
            var updated = candidate
            updated.searchText = AppTargetQueryService.searchText(fragments, excluding: [candidate.title, candidate.value ?? ""])
            return updated
        }
        for (index, path) in historicPaths.enumerated() where texts[path] != nil {
            pass.candidates[index] = withText(pass.candidates[index], at: path)
        }
        for item in pending where leaves.contains(item.path) && pass.candidates.count < config.maxTargets {
            var leaf = withText(item.candidate, at: item.path)
            let content = contents[item.path]
            leaf.clickFrame = content?.frame
            pass.candidates.append(leaf)
            pass.elements["app:\(leaf.id)"] = .init(element: item.element, clickElement: content?.element, window: window)
            pass.focusableAdded += 1
            pass.rejectedRoles[item.candidate.role, default: 0] -= 1
        }
        pass.rejectedRoles = pass.rejectedRoles.filter { $0.value > 0 }
        return pass
    }

    private static func nonempty(_ text: String?) -> String? {
        text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    private func isFocusSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    public func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        // Feuille web sans action : son centre peut tomber hors des zones qui réagissent (ligne de
        // l'Historique Bluejay, où seuls vignette, titre et auteur ont un gestionnaire de clic).
        guard let shown = target.clickFrame ?? target.frame else {
            return TargetActionResult(changed: false, message: "app click: no frame", target: target, error: "no_frame")
        }
        let frame = shown.cgRect
        // REL-012 : sans fenêtre active, le clic tomberait sur une autre fenêtre ou application. Toute
        // cible porte sa fenêtre ; sans elle, le focus ne se vérifie pas et rien n'est cliqué. Fenêtre
        // déjà active (cas courant) : l'attente répond dès la première lecture, sans délai.
        guard let windowID = target.scope.windowId, let pid = AppTargetQueryService.pid(of: target) else {
            return TargetActionResult(changed: false, message: "stale_target: no_window \(target.id)", target: target, error: "stale_target")
        }
        switch waitForFocus(windowID, pid, 0.5) {
        case .focused:
            break
        case .windowGone:
            return TargetActionResult(changed: false, message: "stale_target: window_gone \(target.id)", target: target, error: "stale_target")
        case .timedOut:
            // Diagnostic (essai du 30 octobre 2026) : ce que l'accessibilité voit au premier plan à l'échéance.
            return TargetActionResult(changed: false, message: "focus_failed: \(Self.focusDescription(pid: pid)) \(target.id)",
                                      target: target, error: "focus_failed")
        }
        // REL-012 : l'overlay a pu rester ouvert, la fenêtre bouger ou la page défiler pendant l'attente.
        // Le point de clic n'est sûr que si la zone cliquée occupe encore le cadre affiché (R2-02).
        let current = currentFrame(target)
        guard AppTargetQueryService.isStillInPlace(shown, current: current) else {
            // Session 134 : élément illisible (remplacé) ou déplacé, avec ses deux cadres, pour le diagnostic.
            let describe = { (frame: Rect) in "\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))" }
            let reason = current.map { "moved \(describe(shown)) -> \(describe($0))" } ?? "unreadable"
            return TargetActionResult(changed: false, message: "stale_target: \(reason) \(target.id)", target: target, error: "stale_target")
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        switch action {
        case .click:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
        case .doubleClick:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 2)
        case .rightClick:
            postClick(at: point, button: .right, down: .rightMouseDown, up: .rightMouseUp, clickCount: 1)
        case .commandClick:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1, flags: .maskCommand)
        default:
            return TargetActionResult(changed: false, message: "app click: unsupported \(action.rawValue)", target: target, error: "unsupported_action")
        }
        return TargetActionResult(changed: true, message: "app \(action.rawValue) \(target.id)", target: target)
    }

    /// Cible d'une autre fenêtre (SPEC-021) : `TargetHintService` vient de la focaliser. Le clic attend
    /// que son application soit active et que la fenêtre soit la sienne, sinon une application peut
    /// ne prendre le premier clic que pour s'activer. Fenêtre disparue ou délai dépassé : pas de clic
    /// (REL-012).
    /// Application au premier plan pour l'accessibilité, et fenêtre active de l'application visée. Diagnostic.
    static func focusDescription(pid: pid_t) -> String {
        var focusedPID: pid_t = 0
        let front = copyElementAttribute(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)
            .flatMap { AXUIElementGetPid($0, &focusedPID) == .success ? focusedPID : nil }
        var title: CFTypeRef?
        let window = copyElementAttribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
        if let window { AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return "axFront=\(front.map(String.init) ?? "none") frontmost=\(frontmost.map(String.init) ?? "none") target=\(pid)"
            + " targetFocusedWindow=\(window == nil ? "none" : "\"\((title as? String) ?? "?")\"")"
    }

    private static func waitUntilFocused(windowID: CGWindowID, pid: pid_t, timeout: TimeInterval) -> AppWindowFocusWait {
        guard let expected = axWindowElements(pid: pid)[windowID] else { return .windowGone }
        let system = AXUIElementCreateSystemWide()
        let appElement = AXUIElementCreateApplication(pid)
        let deadline = Date().addingTimeInterval(timeout)
        let ownPID = getpid()
        repeat {
            var focusedPID: pid_t = 0
            let axFront = copyElementAttribute(system, kAXFocusedApplicationAttribute)
                .flatMap { AXUIElementGetPid($0, &focusedPID) == .success ? focusedPID : nil }
            let targetFocused = copyElementAttribute(appElement, kAXFocusedWindowAttribute).map { CFEqual($0, expected) } ?? false
            // La pile des fenêtres n'est lue que si la barre de Roadie paraît encore avoir le clavier.
            let top = axFront == ownPID ? frontWindowID(excluding: ownPID) : nil
            if isFocusReached(axFront: axFront, ownPID: ownPID, targetPID: pid, targetWindowFocused: targetFocused,
                              topWindow: top, windowID: windowID) {
                return .focused
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline
        return .timedOut
    }

    /// Fenêtre visée prête à recevoir le clic : son application au premier plan pour l'accessibilité avec cette
    /// fenêtre active ; ou bien, la barre de Roadie venant de se fermer (l'accessibilité la voit encore au premier
    /// plan, essai du 30 octobre 2026), cette fenêtre active dans son application et tout en haut de la pile des
    /// fenêtres, hors Roadie : le clic tombe sur elle. O(1).
    static func isFocusReached(axFront: pid_t?, ownPID: pid_t, targetPID: pid_t, targetWindowFocused: Bool,
                               topWindow: CGWindowID?, windowID: CGWindowID) -> Bool {
        guard targetWindowFocused else { return false }
        if axFront == targetPID { return true }
        return axFront == ownPID && topWindow == windowID
    }

    /// Fenêtre ordinaire (calque 0) la plus haute à l'écran, hors du processus donné et des liserés de
    /// JankyBorders (même critère que `isKnownBorderDecoration` : processus « borders », sans titre). O(w).
    private static func frontWindowID(excluding pid: pid_t) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.first { info in
            let decoration = (info[kCGWindowOwnerName as String] as? String) == "borders"
                && ((info[kCGWindowName as String] as? String) ?? "").isEmpty
            return (info[kCGWindowLayer as String] as? Int) == 0 && (info[kCGWindowOwnerPID as String] as? Int32) != pid && !decoration
        }.flatMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    /// Relecture de la zone cliquée d'une cible (REL-012, R2-02, R2-03) : l'élément conservé par le
    /// dernier parcours, jamais re-résolu par son chemin, puis le cadre de sa fenêtre pour le rogner
    /// comme dans `scan`. Échéance commune `budget` ; un échec de lecture de l'élément abandonne aussitôt.
    /// Complexité : 2 appels AX au plus (avant : énumération des fenêtres, un appel par niveau, jusqu'à
    /// 8 sur un niveau illisible, puis 4 pour les deux cadres).
    static func currentVisibleFrame(
        of target: RoadieTarget,
        in registry: AppTargetElementRegistry,
        readFrame: (AXUIElement, TimeInterval) -> Rect?,
        budget: TimeInterval = 0.3
    ) -> Rect? {
        guard let entry = registry.entry(for: target.id) else { return nil }
        let deadline = Date().addingTimeInterval(budget)
        guard let frame = readFrame(entry.clickElement ?? entry.element, budget) else { return nil }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return AppTargetQueryService.visibleFrame(frame, in: readFrame(entry.window, remaining))
    }

    /// Cadre d'un élément en un seul aller-retour AX (position et taille), en `timeout` secondes au plus.
    /// nil si l'élément est invalide (remplacé, fermé), ne répond pas ou n'a pas de cadre.
    private static func readFrame(_ element: AXUIElement, timeout: TimeInterval) -> Rect? {
        AXUIElementSetMessagingTimeout(element, Float(timeout))
        var raw: CFArray?
        let attributes = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == 2,
              values.allSatisfy({ CFGetTypeID($0) == AXValueGetTypeID() })
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // Une erreur par attribut arrive comme un AXValue de type `.axError` : la conversion échoue.
        guard AXValueGetValue(values[0] as! AXValue, .cgPoint, &point),
              AXValueGetValue(values[1] as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return Rect(CGRect(origin: point, size: size))
    }

    private func postClick(
        at point: CGPoint,
        button: CGMouseButton,
        down: CGEventType,
        up: CGEventType,
        clickCount: Int64,
        flags: CGEventFlags = []
    ) {
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)
        downEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        upEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        // Toujours fixées, vides pour un clic simple : sans cela, le clic reprenait les touches tenues à cet instant
        // (Maj de Maj + étiquette), et un clic devenait un Maj + clic (essai du 30 octobre 2026).
        downEvent?.flags = flags
        upEvent?.flags = flags
        if let downEvent { postEvent(downEvent) }
        if let upEvent { postEvent(upEvent) }
    }

    private static func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    /// `unreadable` : `AXChildren` a échoué pour une autre raison qu'une absence d'enfants.
    private static func copyChildren(_ element: AXUIElement, boost: Bool) -> (children: [AXUIElement], unreadable: Bool) {
        let attributes = boost ? [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXRows",
            "AXColumns",
            "AXContents",
            "AXTabs",
        ] : [kAXChildrenAttribute]
        var result: [AXUIElement] = []
        var seen = CFIdentitySet()
        var unreadable = false
        for attribute in attributes {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if attribute == kAXChildrenAttribute, ![.success, .noValue, .attributeUnsupported].contains(error) {
                unreadable = true
            }
            guard error == .success, let value else { continue }
            if let children = value as? [AXUIElement] {
                for child in children where seen.insert(child) {
                    result.append(child)
                }
            } else if CFGetTypeID(value) == AXUIElementGetTypeID() {
                let child = value as! AXUIElement
                if seen.insert(child) {
                    result.append(child)
                }
            }
        }
        return (result, unreadable)
    }

    private func copyActionNames(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let names = value as? [String]
        else { return [] }
        return names
    }

    private static func copyFrame(_ element: AXUIElement) -> Rect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0
        else { return nil }
        return Rect(CGRect(origin: point, size: size))
    }
}
