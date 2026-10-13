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

    public static func targets(from candidates: [AppElementCandidate], config: AppTargetsConfig) -> [RoadieTarget] {
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

/// Résultat du parcours d'une fenêtre visible (SPEC-021) ; `order` : rang de la fenêtre, de l'avant
/// vers l'arrière.
public struct VisibleWindowScan: Sendable {
    public var order: Int
    public var targets: [RoadieTarget]
    public var stats: AppTargetScanStats
    public var partial: Bool
}

public struct LiveAppTargetProvider: AppTargetProviding, Sendable {
    public init() {}

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
        guard let window = copyElementAttribute(appElement, kAXFocusedWindowAttribute) else {
            return AppTargetQueryReport(error: "no_focused_window")
        }
        let result = scanWindow(window, app: app, rootPath: "0", config: config, startedAt: Date())
        let partial = result.pass.stopReason != "complete"
        return AppTargetQueryReport(
            targets: Self.labeled(AppTargetQueryService.targets(from: result.pass.candidates, config: config), config: config),
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
            var targets: [RoadieTarget] = []
            for var target in AppTargetQueryService.targets(from: scan.pass.candidates, config: config)
            where !AppTargetQueryService.isCovered(target, by: inFront) {
                target.scope.windowId = job.id
                targets.append(target)
            }
            let result = VisibleWindowScan(order: job.order, targets: targets, stats: scan.stats,
                                           partial: scan.pass.stopReason != "complete")
            batch.results[index] = result
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

    private struct ScanPass {
        var candidates: [AppElementCandidate] = []
        var visited = 0
        var offscreen = 0
        var maxDepthReached = 0
        var atMaxDepth = 0
        var sawWebArea = false
        var focusableAdded = 0
        var rejectedRoles: [String: Int] = [:]
        var stopReason = "complete"
    }

    /// Complexité : O(n + m + p + u * d), n = éléments lus ; voir `focusableLeaves` pour m, p, u, d.
    private func scan(window: AXUIElement, rootPath: String, pid: pid_t, config: AppTargetsConfig, boost: Bool, deadline: Date) -> ScanPass {
        let windowFrame = copyFrame(window)
        // `inWeb` : sous une `AXWebArea` ; `retainedFrame` : cadre visible de la plus proche cible web ajoutée.
        // `textOwner` : chemin du plus proche candidat web, qui reçoit le texte des `AXStaticText` (SPEC-021).
        var stack: [(element: AXUIElement, path: String, depth: Int, inWeb: Bool, retainedFrame: Rect?, textOwner: String?)] =
            [(window, rootPath, 0, false, nil, nil)]
        var pass = ScanPass()
        var seen = CFIdentitySet()
        let ignoredActions: Set<String> = ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"]
        let includedRoles = Set(config.includeRoles)
        // SPEC-020 : feuilles focalisables en attente et marqueurs de zone web, en préordre.
        var pending: [(candidate: AppElementCandidate, path: String)] = []
        var markers: [String] = []
        var texts: [String: [String]] = [:]
        var historicPaths: [String] = []
        // Premier contenu visible (préordre) de chaque candidat web : point de clic des feuilles.
        var contentFrames: [String: Rect] = [:]

        while let entry = stack.popLast() {
            let (element, path, depth, parentInWeb, retainedFrame, textOwner) = entry
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
            let role = copyStringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
            let isWebArea = role == "AXWebArea"
            let inWeb = parentInWeb || isWebArea
            pass.sawWebArea = pass.sawWebArea || isWebArea
            let title = copyStringAttribute(element, kAXTitleAttribute)
                ?? copyStringAttribute(element, kAXDescriptionAttribute)
                ?? ""
            let value = copyStringAttribute(element, kAXValueAttribute)
            let actions = copyActionNames(element).filter { !ignoredActions.contains($0) }
            let isCandidate = !actions.isEmpty || includedRoles.contains(role)
            // SolidJS, React... délèguent les clics au document : Chromium ne donne pas d'action aux
            // éléments cliquables, mais les expose focalisables (mesure Bluejay, research.md).
            let isPending = !isCandidate && inWeb && !isWebArea && depth < config.maxDepth && isFocusSettable(element)
            if inWeb && (isCandidate || isPending) {
                markers.append(path)
            }
            if inWeb, role == "AXStaticText", let owner = textOwner, let text = value ?? (title.isEmpty ? nil : title) {
                texts[owner, default: []].append(text)
            }
            var retained = false
            var retainedVisible: Rect?
            // Zone web : le cadre est lu pour tous, afin de ne pas descendre dans un élément invisible.
            let frame = isCandidate || isPending || (inWeb && !isWebArea) ? copyFrame(element) : nil
            let visibleFrame = frame.flatMap { AppTargetQueryService.visibleFrame($0, in: windowFrame) }
            if inWeb, role == "AXImage" || role == "AXStaticText", let owner = textOwner, contentFrames[owner] == nil,
               let visible = visibleFrame, AppTargetQueryService.isHintable(visible) {
                contentFrames[owner] = visible
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
                        pending.append((candidate, path))
                    } else {
                        pass.candidates.append(candidate)
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
            let (children, unreadable) = copyChildren(element, boost: boost && !inWeb)
            if inWeb && unreadable { markers.append(path + ".?") }
            for (index, child) in children.enumerated().reversed() {
                stack.append((child, "\(path).\(index)", depth + 1, inWeb, inWeb && retained ? retainedVisible : retainedFrame,
                              inWeb && (isCandidate || isPending) ? path : textOwner))
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
            leaf.clickFrame = contentFrames[item.path]
            pass.candidates.append(leaf)
            pass.focusableAdded += 1
            pass.rejectedRoles[item.candidate.role, default: 0] -= 1
        }
        pass.rejectedRoles = pass.rejectedRoles.filter { $0.value > 0 }
        return pass
    }

    private func isFocusSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    public func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        // Feuille web sans action : son centre peut tomber hors des zones qui réagissent (ligne de
        // l'Historique Bluejay, où seuls vignette, titre et auteur ont un gestionnaire de clic).
        guard let frame = (target.clickFrame ?? target.frame)?.cgRect else {
            return TargetActionResult(changed: false, message: "app click: no frame", target: target, error: "no_frame")
        }
        if let windowID = target.scope.windowId, let pid = AppTargetQueryService.pid(of: target) {
            waitUntilFocused(windowID: windowID, pid: pid, timeout: 0.5)
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
    /// ne prendre le premier clic que pour s'activer. Au-delà du délai, le clic part quand même.
    private func waitUntilFocused(windowID: CGWindowID, pid: pid_t, timeout: TimeInterval) {
        guard let expected = axWindowElements(pid: pid)[windowID] else { return }
        let system = AXUIElementCreateSystemWide()
        let appElement = AXUIElementCreateApplication(pid)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var focusedPID: pid_t = 0
            if let app = copyElementAttribute(system, kAXFocusedApplicationAttribute),
               AXUIElementGetPid(app, &focusedPID) == .success, focusedPID == pid,
               let window = copyElementAttribute(appElement, kAXFocusedWindowAttribute), CFEqual(window, expected) {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline
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
        if !flags.isEmpty {
            downEvent?.flags = flags
            upEvent?.flags = flags
        }
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
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
    private func copyChildren(_ element: AXUIElement, boost: Bool) -> (children: [AXUIElement], unreadable: Bool) {
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

    private func copyFrame(_ element: AXUIElement) -> Rect? {
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
