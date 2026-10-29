import AppKit
import RoadieCore

/// Session de consultation : un inventaire à l'ouverture, aucune acquisition au déplacement de souris.
@MainActor
public final class OverviewController {
    nonisolated public static let notificationName = Notification.Name("com.roadie.overview.command")
    private let service: WindowSwitcherService
    private let snapshots: SnapshotService
    private let thumbnails: RailThumbnailStore
    private let componentLock = ComponentLockFile(component: "overview")
    private let events: EventLog
    private var observer: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var hotkey: TargetSearchHotkey?
    private var panel: OverviewPanel?
    private var loadTask: Task<Void, Never>?
    private var timer: Timer?
    /// Largeur (points de capture) déjà demandée par fenêtre pendant la session : pas de redemande en boucle.
    private var requestedWidths: [WindowID: CGFloat] = [:]
    /// Date de la capture nette affichée par fenêtre : seule une capture nette plus récente la remplace.
    private var shownAt: [WindowID: Date] = [:]
    /// Mesure du temps jusqu’à ce que toutes les cartes aient leur capture à la bonne définition.
    private var openedAt = Date()
    private var sharpReported = false
    private var monitor: Any?
    private var sessionID = UUID()
    private var members: [PersistentStageMember] = []
    private var liveFrames: [WindowID: Rect] = [:]
    private var imageVersion = -1

    public init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.service = WindowSwitcherService(service: service)
        self.snapshots = service
        self.thumbnails = .shared
        self.events = events
    }

    public func start() {
        guard observer == nil else { return }
        do { try componentLock.acquire() }
        catch {
            events.append(RoadieEvent(type: "overview.state", details: ["state": "unavailable", "error": String(describing: error)]))
            return
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.notificationName, object: "roadie", queue: .main) { [weak self] notification in
            let command = TargetModeRuntimeCommand(userInfo: notification.userInfo)
            Task { @MainActor in
                switch command?.name {
                case "overview.show": self?.show()
                case "overview.toggle": self?.toggle()
                case "overview.hide": self?.hide()
                default: break
                }
            }
        }
        hotkey = TargetSearchHotkey(configLoader: {
            let c = ConfigReloadService.shared.currentConfig().overview
            return TargetModeConfig(enabled: c.enabled, overlayEnabled: true, searchHotkey: c.hotkey)
        }, signature: 0x5244_4F56, eventType: "overview.hotkey", settingsIDs: ["overview.hotkey", "overview.enabled", "*"]) { [weak self] in self?.toggle() }
        hotkey?.start()
        settingsObserver = NotificationCenter.default.addObserver(forName: .roadieSettingsDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let id = notification.userInfo?["settingID"] as? String, id.hasPrefix("overview.") || id == "*" else { return }
            Task { @MainActor in
                guard let self else { return }
                let config = ConfigReloadService.shared.currentConfig().overview
                if !config.enabled { self.hide(); return }
                self.panel?.config = config
                self.panel?.syncControls()
                self.panel?.canvas.rebuild()
            }
        }
    }

    public func stop() {
        hide()
        hotkey?.stop(); hotkey = nil
        componentLock.release()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }; observer = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }; settingsObserver = nil
    }

    public func toggle() { panel == nil ? show() : hide() }

    public func show() {
        let config = ConfigReloadService.shared.currentConfig().overview
        guard config.enabled else { events.append(RoadieEvent(type: "overview.state", details: ["state": "disabled"])); return }
        if let panel { panel.orderFrontRegardless(); panel.makeKey(); return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let p = OverviewPanel(events: events)
        panel = p
        let id = UUID(); sessionID = id
        p.onClose = { [weak self] in self?.hide() }
        p.onKey = { [weak self] code, shift in self?.key(code, backwards: shift) }
        p.canvas.onOpen = { [weak self] entry in self?.activate(entry) }
        p.canvas.onDrop = { [weak self] intent in self?.drop(intent) }
        p.present(on: screen, config: config)
        p.showMessage(tr("Chargement des bureaux et stages…", "Loading desktops and stages…"))
        loadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.service.load()
            guard !Task.isCancelled, self.sessionID == id, self.panel === p else { return }
            guard let snapshot = loaded.snapshot else { p.showMessage(tr("Inventaire indisponible. Fermez puis réessayez.", "Inventory unavailable. Close and try again.")); return }
            p.canvas.model = OverviewModel(entries: loaded.entries, displays: snapshot.displays, state: loaded.persisted)
            let bureaux = p.canvas.model.displays.flatMap(\.desktops)
            p.canvas.focusedDesktop = bureaux.first(where: { $0.entries.contains { $0.id == loaded.context.focusedWindowID } })?.id
                ?? bureaux.first(where: { $0.id.displayID == loaded.context.displayID && $0.isActive })?.id
                ?? bureaux.first(where: { $0.isActive })?.id
            p.canvas.selectedID = loaded.context.focusedWindowID ?? p.canvas.model.entries.first?.id
            self.members = p.canvas.model.entries.map { PersistentStageMember(windowID: $0.id, bundleID: $0.window.bundleID, title: $0.window.title, frame: $0.window.frame, pid: $0.window.pid) }
            self.liveFrames = Dictionary(p.canvas.model.entries.filter { $0.window.isOnScreen }.map { ($0.id, $0.window.frame) }, uniquingKeysWith: { first, _ in first })
            self.thumbnails.prune(keeping: Set(self.members.map(\.windowID)), owner: "overview")
            // Captures déjà en cache d’un côté, icônes de secours de l’autre : une capture s’agrandit, une icône non.
            // La dernière capture nette s’affiche tout de suite ; sinon la vignette du rail, sinon l’icône.
            let cached = self.thumbnails.images(for: self.members)
            self.shownAt = [:]
            var images: [WindowID: NSImage] = [:]
            for member in self.members {
                if let sharp = self.thumbnails.detailedImage(for: member.windowID) {
                    images[member.windowID] = sharp.image; self.shownAt[member.windowID] = sharp.at
                } else if self.thumbnails.hasCapturedImage(for: member.windowID) {
                    images[member.windowID] = cached[member.windowID]
                }
            }
            p.canvas.images = images
            p.canvas.icons = cached.filter { images[$0.key] == nil }
            self.requestedWidths = [:]
            self.openedAt = Date(); self.sharpReported = false
            // Même cache par application que le sélecteur ; aucune résolution au dessin/survol.
            for pid in Set(p.canvas.model.entries.map { $0.window.pid }) {
                p.canvas.appIcons[pid] = NSRunningApplication(processIdentifier: pid)?.icon
            }
            p.canvas.rebuild()
            p.canvas.notice = nil
            self.tick()
            // 0,1 s : une capture arrivée s’affiche sans attendre ; la vérification ne lit que le cache.
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            self.events.append(RoadieEvent(type: "overview.state", details: ["state": "open", "windows": String(self.members.count),
                "sharpAtOpen": String(self.shownAt.count), "selected": p.canvas.selectedID.map { String($0.rawValue) } ?? "-"]))
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.hide()
            }
        }
    }

    public func hide() {
        sessionID = UUID()
        loadTask?.cancel(); loadTask = nil
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        let closing = panel; panel = nil
        closing?.canvas.cancelHover()
        closing?.dismiss()
        members = []; liveFrames = [:]; imageVersion = -1
        thumbnails.prune(keeping: [], owner: "overview")
        events.append(RoadieEvent(type: "overview.state", details: ["state": "closed"]))
    }

    /// Les aperçus restent figés pendant la consultation : une image n’est remplacée que par une
    /// version plus définie (fenêtre consultée par la loupe), jamais par une capture plus récente.
    private func tick() {
        guard let panel else { return }
        if thumbnails.version != imageVersion {
            imageVersion = thumbnails.version
            var changed = false
            for member in members {
                let current = panel.canvas.images[member.windowID]
                if let sharp = thumbnails.detailedImage(for: member.windowID),
                   sharp.at > (shownAt[member.windowID] ?? .distantPast),
                   sharp.image.size.width >= (current?.size.width ?? 0) * 0.9 {
                    // Capture fraîche au moins aussi nette : contenu identique, rien ne bouge ; sinon mise à jour.
                    panel.canvas.images[member.windowID] = sharp.image
                    shownAt[member.windowID] = sharp.at
                    changed = true
                } else if current == nil, thumbnails.hasCapturedImage(for: member.windowID),
                          let image = thumbnails.cachedImage(for: member.windowID) {
                    panel.canvas.images[member.windowID] = image; changed = true
                }
            }
            if changed { panel.canvas.needsDisplay = true }
        }
        // Définition réelle de chaque carte : largeur affichée en pixels, exprimée en points de capture (pixels / 2).
        // Une fenêtre n’est redemandée que si sa carte a grandi (loupe) d’au moins 30 %. Le survol seul ne capture pas.
        let pixels = (panel.screen ?? NSScreen.main)?.backingScaleFactor ?? 2
        let needed = Dictionary(panel.canvas.plan.cards.map { ($0.entry.id, ceil($0.frame.width * pixels / 2)) }, uniquingKeysWith: { first, _ in first })
        // Une capture fraîche par fenêtre et par ouverture (sauf capture de moins de 5 s), puis une
        // nouvelle seulement si la carte grandit (loupe) d’au moins 30 %.
        let wanted = members.filter { member in
            guard let need = needed[member.windowID] else { return false }
            if let requested = requestedWidths[member.windowID], need <= requested * 1.3 { return false }
            return true
        }
        // Fenêtres sans capture possible (contenu protégé, icône seule) exclues de la mesure.
        let pictured = members.filter { panel.canvas.images[$0.windowID] != nil }
        if !sharpReported, !pictured.isEmpty, pictured.allSatisfy({ member in
            needed[member.windowID].map { (panel.canvas.images[member.windowID]?.size.width ?? 0) >= $0 * 0.9 } ?? true
        }) {
            sharpReported = true
            events.append(RoadieEvent(type: "overview.captures_sharp", details: [
                "windows": String(pictured.count), "durationMs": String(format: "%.0f", Date().timeIntervalSince(openedAt) * 1000)]))
        }
        guard let widest = wanted.compactMap({ needed[$0.windowID] }).max() else { return }
        // Toutes les fenêtres de la vue en un lot ; réessayer au tick suivant si le rail tient le lot partagé.
        for id in thumbnails.requestCaptures(for: wanted, protectedWindowIDs: [], liveFrames: liveFrames, displayWidth: widest, budget: wanted.count, ifNarrowerThan: widest * 0.9) {
            requestedWidths[id] = widest
        }
    }

    private func activate(_ entry: WindowSwitcherEntry) {
        guard let panel else { return }
        let id = sessionID
        let screen = panel.screen ?? NSScreen.main
        // Retirer la vue globale avant de rejoindre le contexte Roadie cible.
        panel.dismiss { [weak self, weak panel] in
            guard let self, let panel, self.sessionID == id, self.panel === panel else { return }
            let result = self.service.activate(entry)
            if result.outcome == .failed {
                if let screen { panel.present(on: screen, config: panel.config) }
                panel.showMessage(tr("Impossible d’ouvrir cette fenêtre. Elle a peut-être été fermée. Échap pour quitter.",
                                     "Could not open this window. It may have been closed. Press Esc to leave."))
                self.events.append(RoadieEvent(type: "overview.activation_failed", details: ["windowID": String(entry.id.rawValue), "message": result.message]))
            } else { self.hide() }
        }
    }

    /// Renumérote puis recharge la vue ouverte : les cartes gardent leurs captures, seuls les bureaux changent.
    /// Exécute le dépôt montré par l’aperçu (SPEC-066, 067, 070, 071).
    private func drop(_ intent: OverviewDropIntent) {
        guard let panel else { return }
        let entries = Dictionary(panel.canvas.model.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        switch intent {
        case .desktop(let source, let display, let target):
            moveDesktop(source, to: display, target)
        case .stage(let source, let display, let desktop, let before):
            moveStage(source, to: display, desktop, before: before)
        case .stageToNewDesktop(let source, let display):
            moveStage(source, to: display, newDesktopID(on: display), before: nil)
        case .window(let id, let target):
            guard let entry = entries[id] else { return panel.canvas.cancelPreview() }
            moveWindow(entry, to: target)
        case .windowToNewStage(let id, let display, let desktop):
            guard let entry = entries[id] else { return panel.canvas.cancelPreview() }
            moveWindow(entry, to: StageScope(displayID: display, desktopID: desktop, stageID: newStageID(on: display, desktop)))
        case .windowToNewDesktop(let id, let display):
            guard let entry = entries[id] else { return panel.canvas.cancelPreview() }
            let desktop = newDesktopID(on: display)
            moveWindow(entry, to: StageScope(displayID: display, desktopID: desktop, stageID: newStageID(on: display, desktop)))
        }
    }

    /// Nouveau bureau d’un écran : le premier numéro après le dernier bureau montré qui ne contient
    /// aucune fenêtre ni aucun nom (un bureau vide déjà créé est réutilisé). O(s).
    private func newDesktopID(on display: DisplayID) -> DesktopID {
        let state = snapshots.effectiveStageStore.state()
        let shown = panel?.canvas.model.displays.first { $0.id == display }?.desktops.map(\.id.desktopID.rawValue).max() ?? 0
        var candidate = shown + 1
        while state.scopes.contains(where: { $0.displayID == display && $0.desktopID.rawValue == candidate && $0.stages.contains { !$0.members.isEmpty } })
                || state.label(displayID: display, desktopID: DesktopID(rawValue: candidate)) != nil {
            candidate += 1
        }
        return DesktopID(rawValue: candidate)
    }

    /// Nouvelle stage d’un bureau : numéro suivant, ajoutée en dernier comme le montre l’aperçu. O(s).
    private func newStageID(on display: DisplayID, _ desktop: DesktopID) -> StageID {
        let stages = snapshots.effectiveStageStore.state().scopes.first { $0.displayID == display && $0.desktopID == desktop }?.stages ?? []
        return StageID(rawValue: String((stages.compactMap { Int($0.id.rawValue) }.max() ?? 0) + 1))
    }

    private func moveDesktop(_ source: OverviewDesktopID, to display: DisplayID, _ target: DesktopID) {
        let commands = DesktopCommandService(service: snapshots, store: snapshots.effectiveStageStore, events: events)
        guard display == source.displayID else {
            // Autre écran (SPEC-070) : la loupe ne suit pas, les deux écrans sont renumérotés.
            let result = commands.move(source.desktopID, from: source.displayID, toDisplay: display, position: target)
            reload(after: result, failure: tr("Impossible de déplacer ce bureau vers cet écran.", "Could not move this desktop to this display.")) { _ in source }
            return
        }
        let displayID = source.displayID
        let mapping = DesktopReorder.mapping(from: source.desktopID, to: target)
        reload(after: commands.move(source.desktopID, to: target, displayID: displayID), failure: tr("Impossible de déplacer ce bureau.", "Could not move this desktop.")) { desktop in
            guard desktop.displayID == displayID, let moved = mapping[desktop.desktopID] else { return desktop }
            return OverviewDesktopID(displayID: displayID, desktopID: moved)
        }
    }

    /// Stage glissée entre deux stages, dans son bureau, un autre bureau ou un autre écran (SPEC-067, SPEC-070).
    private func moveStage(_ scope: StageScope, to display: DisplayID, _ desktop: DesktopID, before: StageID?) {
        let commands = StageCommandService(service: snapshots, store: snapshots.effectiveStageStore, events: events)
        let result = commands.moveStage(scope.stageID, displayID: scope.displayID, from: scope.desktopID, to: desktop,
                                        before: before, targetDisplay: display)
        reload(after: result, failure: tr("Impossible de déplacer cette stage.", "Could not move this stage."))
    }

    /// Fenêtre déposée sur une carte d’une autre stage : elle rejoint cette stage (SPEC-067).
    private func moveWindow(_ entry: WindowSwitcherEntry, to target: StageScope) {
        let actions = WindowContextActions(snapshotService: snapshots, stageStore: snapshots.effectiveStageStore, eventLog: events)
        let result = actions.assign(windowID: entry.id, to: target.stageID, desktopID: target.desktopID, displayID: target.displayID)
        // Autre écran, stage non affichée (SPEC-070) : le cadre de retour est recentré sur cet écran.
        let state = snapshots.effectiveStageStore.state()
        let shown = state.currentDesktopID(for: target.displayID) == target.desktopID
            && state.scopes.first { $0.displayID == target.displayID && $0.desktopID == target.desktopID }?.activeStageID == target.stageID
        if result.changed, entry.scope?.displayID != target.displayID, !shown {
            _ = relocateHiddenWindows([entry.id], to: target.displayID, service: snapshots, store: snapshots.effectiveStageStore,
                                      events: events, cause: "window.move_display")
        }
        reload(after: result, failure: tr("Impossible de déplacer cette fenêtre.", "Could not move this window."))
    }

    /// Recharge la vue ouverte après une modification réussie. Le relevé est refusé si l’état des stages
    /// change pendant la lecture, ce qui suit souvent la modification : relire au lieu de garder l’ancien affichage.
    private func reload(after result: StageCommandResult, failure: String,
                        focus remap: @escaping (OverviewDesktopID) -> OverviewDesktopID = { $0 }) {
        guard let panel else { return }
        guard result.changed else {
            panel.canvas.cancelPreview()
            if result.outcome == .failed { panel.showMessage(failure + tr(" Échap pour quitter.", " Press Esc to leave.")) }
            return
        }
        let id = sessionID
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            var loaded = await self.service.load()
            var attempts = 1
            while loaded.snapshot == nil, attempts < 6, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                loaded = await self.service.load()
                attempts += 1
            }
            self.events.append(RoadieEvent(type: "overview.reloaded", details: [
                "attempts": String(attempts), "loaded": String(loaded.snapshot != nil)]))
            guard !Task.isCancelled, self.sessionID == id, self.panel === panel, let snapshot = loaded.snapshot else { return }
            panel.canvas.model = OverviewModel(entries: loaded.entries, displays: snapshot.displays, state: loaded.persisted)
            panel.canvas.focusedDesktop = panel.canvas.focusedDesktop.map(remap)
            panel.canvas.notice = nil
            panel.canvas.rebuild()
        }
    }

    private func key(_ code: UInt16, backwards: Bool) {
        guard let panel else { return }
        if code == 53 { hide(); return }
        let cards = panel.canvas.plan.cards
        guard !cards.isEmpty else { return }
        let current = cards.firstIndex { $0.entry.id == panel.canvas.selectedID } ?? 0
        if code == 36 || code == 76 { activate(cards[current].entry); return }
        let next: Int
        if code == 48 {
            next = (current + (backwards ? cards.count - 1 : 1)) % cards.count
        } else {
            let origin = CGPoint(x: cards[current].frame.midX, y: cards[current].frame.midY)
            let candidates = cards.indices.filter { index in
                let frame = cards[index].frame
                switch code {
                case 123: return frame.midX < origin.x - 1
                case 124: return frame.midX > origin.x + 1
                case 125: return frame.midY > origin.y + 1
                case 126: return frame.midY < origin.y - 1
                default: return false
                }
            }
            next = candidates.min { a, b in
                func score(_ i: Int) -> CGFloat {
                    let dx = abs(cards[i].frame.midX - origin.x), dy = abs(cards[i].frame.midY - origin.y)
                    return (code == 123 || code == 124) ? dx + dy * 3 : dy + dx * 3
                }
                return score(a) < score(b)
            } ?? current
        }
        panel.canvas.select(cards[next].entry.id)
    }

    nonisolated static var receiverAvailable: Bool {
        ComponentLockFile.registry().contains { $0.component == "overview" }
    }

    nonisolated static func command(_ arguments: [String]) -> TargetModeRuntimeCommand? {
        let args = arguments.filter { $0 != "--json" }
        guard args.count == 1, ["show", "toggle", "hide", "status"].contains(args[0]) else { return nil }
        return TargetModeRuntimeCommand(name: "overview.\(args[0])")
    }
}
