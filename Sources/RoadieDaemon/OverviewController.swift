import AppKit
import RoadieCore

/// Session de consultation : un inventaire à l'ouverture, aucune acquisition au déplacement de souris.
@MainActor
public final class OverviewController {
    nonisolated public static let notificationName = Notification.Name("com.roadie.overview.command")
    private let service: WindowSwitcherService
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
    private var monitor: Any?
    private var sessionID = UUID()
    private var members: [PersistentStageMember] = []
    private var liveFrames: [WindowID: Rect] = [:]
    private var imageVersion = -1

    public init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.service = WindowSwitcherService(service: service)
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
        p.present(on: screen, config: config)
        p.showMessage("Chargement des bureaux et stages…")
        loadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.service.load()
            guard !Task.isCancelled, self.sessionID == id, self.panel === p else { return }
            guard let snapshot = loaded.snapshot else { p.showMessage("Inventaire indisponible. Fermez puis réessayez."); return }
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
            let cached = self.thumbnails.images(for: self.members)
            p.canvas.images = cached.filter { self.thumbnails.hasCapturedImage(for: $0.key) }
            p.canvas.icons = cached.filter { !self.thumbnails.hasCapturedImage(for: $0.key) }
            self.requestedWidths = [:]
            // Même cache par application que le sélecteur ; aucune résolution au dessin/survol.
            for pid in Set(p.canvas.model.entries.map { $0.window.pid }) {
                p.canvas.appIcons[pid] = NSRunningApplication(processIdentifier: pid)?.icon
            }
            p.canvas.rebuild()
            p.canvas.notice = nil
            self.tick()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            self.events.append(RoadieEvent(type: "overview.state", details: ["state": "open", "windows": String(self.members.count)]))
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
            for member in members where thumbnails.hasCapturedImage(for: member.windowID) {
                guard let image = thumbnails.cachedImage(for: member.windowID) else { continue }
                let current = panel.canvas.images[member.windowID]
                if current == nil || image.size.width > (current?.size.width ?? 0) + 1 {
                    panel.canvas.images[member.windowID] = image; changed = true
                }
            }
            if changed { panel.canvas.needsDisplay = true }
        }
        // Définition réelle de chaque carte : largeur affichée en pixels, exprimée en points de capture (pixels / 2).
        // Une fenêtre n’est redemandée que si sa carte a grandi (loupe) d’au moins 30 %. Le survol seul ne capture pas.
        let pixels = (panel.screen ?? NSScreen.main)?.backingScaleFactor ?? 2
        let needed = Dictionary(panel.canvas.plan.cards.map { ($0.entry.id, ceil($0.frame.width * pixels / 2)) }, uniquingKeysWith: { first, _ in first })
        let wanted = members.filter { member in
            guard let need = needed[member.windowID] else { return false }
            if let requested = requestedWidths[member.windowID], need <= requested * 1.3 { return false }
            return (panel.canvas.images[member.windowID]?.size.width ?? 0) < need * 0.9
        }
        guard let widest = wanted.compactMap({ needed[$0.windowID] }).max() else { return }
        // Réessayer au tick suivant si le rail possède déjà le lot partagé ; aucun lot concurrent.
        for id in thumbnails.requestCaptures(for: wanted, protectedWindowIDs: [], liveFrames: liveFrames, displayWidth: widest, budget: 4, ifNarrowerThan: widest * 0.9) {
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
                panel.showMessage("Impossible d’ouvrir cette fenêtre. Elle a peut-être été fermée. Échap pour quitter.")
                self.events.append(RoadieEvent(type: "overview.activation_failed", details: ["windowID": String(entry.id.rawValue), "message": result.message]))
            } else { self.hide() }
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
