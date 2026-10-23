import AppKit
import CoreGraphics
import RoadieCore

/// Machine d'état pure d'une session : aucune fenêtre, aucun appel système.
struct WindowSwitcherSessionState: Equatable {
    enum Phase: Equatable {
        case acquiring, presented, closed
    }

    enum PendingAccept: Equatable {
        case explicit, released
    }

    enum Ready: Equatable {
        case present(steps: [Bool])
        case acceptImmediately(steps: [Bool])
    }

    private(set) var phase: Phase = .acquiring
    private(set) var queuedSteps: [Bool] = []
    private(set) var pendingAccept: PendingAccept?
    private(set) var searching = false
    private(set) var held: Bool
    let stayOpen: Bool
    let initialBackwards: Bool

    var persistent: Bool { stayOpen || searching }

    init(stayOpen: Bool, fromHotkey: Bool, heldAtStart: Bool, backwards: Bool) {
        self.stayOpen = stayOpen || !fromHotkey
        initialBackwards = backwards
        held = heldAtStart
        if fromHotkey, !heldAtStart { pendingAccept = .released }
    }

    /// Vrai si le pas doit être appliqué à la liste déjà affichée. Pendant l'acquisition, il est mis en file.
    mutating func step(backwards: Bool) -> Bool {
        switch phase {
        case .acquiring:
            queuedSteps.append(backwards)
            return false
        case .presented:
            return true
        case .closed:
            return false
        }
    }

    /// Vrai si la cible doit être validée maintenant : relâchement hors recherche persistante.
    mutating func modifiers(held now: Bool) -> Bool {
        let wasHeld = held
        held = now
        guard wasHeld, !now, !persistent else { return false }
        switch phase {
        case .acquiring:
            pendingAccept = pendingAccept ?? .released
            return false
        case .presented:
            return true
        case .closed:
            return false
        }
    }

    mutating func searchChanged(isEmpty: Bool) {
        searching = !isEmpty
    }

    /// Validation explicite (Entrée, clic, CLI). Vrai si elle doit être faite maintenant.
    mutating func confirm() -> Bool {
        switch phase {
        case .acquiring:
            pendingAccept = .explicit
            return false
        case .presented:
            return true
        case .closed:
            return false
        }
    }

    /// Nil si la session n'attend plus l'acquisition : un retour tardif ne rouvre rien.
    mutating func ready() -> Ready? {
        guard phase == .acquiring else { return nil }
        let steps = queuedSteps
        queuedSteps = []
        let accept = pendingAccept == .explicit || (pendingAccept == .released && !persistent)
        if accept {
            phase = .closed
            return .acceptImmediately(steps: steps)
        }
        phase = .presented
        return .present(steps: steps)
    }

    mutating func close() {
        phase = .closed
        queuedSteps = []
    }
}

@MainActor
private final class WindowSwitcherSession {
    let id: Int
    var profile: WindowSwitcherShortcutConfig
    var config: WindowSwitcherConfig
    var appearance: WindowSwitcherAppearance
    let required: Set<WindowSwitcherModifier>
    let startedAt = Date()
    var state: WindowSwitcherSessionState
    var model: WindowSwitcherModel?
    var panel: WindowSwitcherPanel?
    var panelVisible = false
    var thumbnailVersion = -1
    var loadTask: Task<Void, Never>?
    var timer: Timer?
    var outsideMonitor: Any?
    var localClickMonitor: Any?

    init(
        id: Int,
        profile: WindowSwitcherShortcutConfig,
        config: WindowSwitcherConfig,
        required: Set<WindowSwitcherModifier>,
        state: WindowSwitcherSessionState
    ) {
        self.id = id
        self.profile = profile
        self.config = config
        self.appearance = WindowSwitcherAppearance(config: config)
        self.required = required
        self.state = state
    }
}

/// Sélecteur de fenêtres : ouverture, défilement, validation et annulation. Le focus ne bouge qu'à la validation.
@MainActor
public final class WindowSwitcherController {
    private let switcher: WindowSwitcherService
    private let thumbnails: RailThumbnailStore
    private let events: EventLog
    private var hotkeys: WindowSwitcherHotkeyRegistry?
    private var settingsObserver: NSObjectProtocol?
    private var session: WindowSwitcherSession?
    private var nextSessionID = 0

    public convenience init(service: SnapshotService = SnapshotService()) {
        self.init(service: service, thumbnails: RailThumbnailStore.shared, events: EventLog())
    }

    init(service: SnapshotService, thumbnails: RailThumbnailStore, events: EventLog) {
        switcher = WindowSwitcherService(service: service)
        self.thumbnails = thumbnails
        self.events = events
    }

    public func start() {
        guard hotkeys == nil else { return }
        hotkeys = WindowSwitcherHotkeyRegistry(
            events: events,
            onPress: { [weak self] profileID, backwards in self?.hotkeyPressed(profileID: profileID, backwards: backwards) },
            onEscape: { [weak self] in self?.cancel() }
        )
        applyHotkeys()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .roadieSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyHotkeys() }
        }
    }

    public func stop() {
        cancel()
        hotkeys?.stop()
        hotkeys = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }

    public func show(profileID: String? = nil) {
        beginSession(profileID: profileID, fromHotkey: false, backwards: false)
    }

    /// Sans session ouverte, `next` ouvre le sélecteur, comme un appui sur le raccourci.
    public func next(backwards: Bool = false) {
        if session != nil {
            advance(backwards: backwards)
        } else {
            beginSession(profileID: nil, fromHotkey: false, backwards: backwards)
        }
    }

    public func accept() {
        guard let session else { return }
        if session.state.confirm() { validate(session) }
    }

    public func cancel() {
        guard let session else { return }
        session.state.close()
        close(session)
    }

    private func applyHotkeys() {
        let config = ConfigReloadService.shared.currentConfig().switcher
        let requests = config.enabled
            ? config.shortcuts.map { WindowSwitcherHotkeyRequest(profileID: $0.id, hotkey: $0.hotkey) }
            : []
        hotkeys?.apply(WindowSwitcherHotkeyPlan(requests: requests, layout: TargetSearchHotkey.currentLayoutTable()))
        if let current = session {
            guard config.enabled, let profile = Self.profile(id: current.profile.id, in: config.shortcuts) else { cancel(); return }
            current.profile = profile
            current.config = config
            current.appearance = WindowSwitcherAppearance(config: config)
            current.panel?.switcherAppearance = current.appearance
            current.model?.configure(profile: profile, excludedBundles: config.excludedBundles)
            hotkeys?.holdEscape(true)
            refresh(current)
        }
    }

    private func hotkeyPressed(profileID: String, backwards: Bool) {
        if let session {
            guard session.profile.id == profileID else { return }
            advance(backwards: backwards)
            return
        }
        beginSession(profileID: profileID, fromHotkey: true, backwards: backwards)
    }

    private func beginSession(profileID: String?, fromHotkey: Bool, backwards: Bool) {
        guard session == nil else { return }
        let config = ConfigReloadService.shared.currentConfig().switcher
        guard config.enabled else { return }
        guard let profile = Self.profile(id: profileID, in: config.shortcuts) else {
            events.append(RoadieEvent(type: "switcher.session", details: ["state": "unknown_profile", "profile": profileID ?? ""]))
            return
        }
        let required = WindowSwitcherHotkey.parse(profile.hotkey, layout: TargetSearchHotkey.currentLayoutTable())?.modifiers ?? []
        let held = WindowSwitcherHotkey.held(in: CGEventSource.flagsState(.combinedSessionState))
        let state = WindowSwitcherSessionState(
            stayOpen: !fromHotkey || profile.releaseAction == "stay",
            fromHotkey: fromHotkey,
            heldAtStart: !WindowSwitcherHotkey.isReleased(required: required, held: held),
            backwards: backwards
        )
        nextSessionID += 1
        let newSession = WindowSwitcherSession(id: nextSessionID, profile: profile, config: config, required: required, state: state)
        session = newSession
        hotkeys?.holdEscape(true)

        let panel = WindowSwitcherPanel(appearance: newSession.appearance)
        panel.onQueryChange = { [weak self] query in self?.queryChanged(query) }
        panel.onNavigate = { [weak self] backwards in self?.advance(backwards: backwards) }
        panel.onConfirm = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.onSelect = { [weak self] id in self?.select(id) }
        panel.onAction = { [weak self] action in self?.perform(action) }
        newSession.panel = panel

        let sessionID = newSession.id
        newSession.loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await self.switcher.load()
            self.acquired(sessionID: sessionID, entries: loaded.entries, context: loaded.context)
        }
        newSession.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func acquired(sessionID: Int, entries: [WindowSwitcherEntry], context: WindowSwitcherContext) {
        guard let session, session.id == sessionID else { return }
        thumbnails.prune(keeping: Set(entries.map(\.id)), owner: "switcher")
        session.model = makeModel(entries: entries, context: context, session: session)
        if session.state.initialBackwards { session.model?.selectInitialBackwards() }
        guard let ready = session.state.ready() else { return }
        switch ready {
        case .acceptImmediately(let steps):
            steps.forEach { session.model?.next(backwards: $0) }
            validate(session)
        case .present(let steps):
            steps.forEach { session.model?.next(backwards: $0) }
            presentPanel(session)
        }
    }

    private func makeModel(entries: [WindowSwitcherEntry], context: WindowSwitcherContext, session: WindowSwitcherSession) -> WindowSwitcherModel {
        WindowSwitcherModel(
            entries: entries,
            profile: session.profile,
            context: context,
            recentIDs: WindowSwitcherFocusHistory.shared.recentIDs,
            excludedBundles: session.config.excludedBundles
        )
    }

    private func tick() {
        guard let session else { return }
        let held = WindowSwitcherHotkey.held(in: CGEventSource.flagsState(.combinedSessionState))
        let isHeld = !WindowSwitcherHotkey.isReleased(required: session.required, held: held)
        if session.state.modifiers(held: isHeld) {
            validate(session)
            return
        }
        if !session.panelVisible, session.state.phase == .acquiring,
           Date().timeIntervalSince(session.startedAt) > 0.15 {
            presentPanel(session)
        }
        if session.panelVisible, thumbnails.version != session.thumbnailVersion {
            refresh(session)
        }
    }

    private func presentPanel(_ session: WindowSwitcherSession) {
        guard !session.panelVisible, let panel = session.panel else {
            refresh(session)
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            cancel()
            return
        }
        session.panelVisible = true
        panel.present(on: screen)
        if session.outsideMonitor == nil {
            session.outsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let panel = self.session?.panel else { return }
                    if !panel.frame.contains(NSEvent.mouseLocation) { self.cancel() }
                }
            }
        }
        if session.localClickMonitor == nil {
            session.localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, let panel = self.session?.panel, let window = event.window,
                       window !== panel, window.level.rawValue < NSWindow.Level.popUpMenu.rawValue {
                        self.cancel()
                    }
                }
                return event
            }
        }
        refresh(session)
    }

    private func refresh(_ session: WindowSwitcherSession) {
        guard session.panelVisible, let panel = session.panel else { return }
        guard let model = session.model else {
            panel.showLoading()
            return
        }
        let entries = model.matches
        let members = entries.map(Self.member(for:))
        let images: [WindowID: NSImage]
        if session.appearance.style == .thumbnails {
            images = thumbnails.images(for: members)
            thumbnails.requestCaptures(
                for: members, protectedWindowIDs: [], liveFrames: [:],
                displayWidth: session.appearance.thumbnailWidth, budget: 6
            )
        } else {
            images = Self.appIcons(for: entries)
        }
        session.thumbnailVersion = thumbnails.version
        panel.render(
            entries: entries,
            selectedID: model.selected?.id,
            query: model.query,
            images: images,
            previewImage: previewImage(for: model.selected?.id),
            emptyMessage: "Aucune fenêtre dans ce contexte"
        )
    }

    private func queryChanged(_ query: String) {
        guard let session, session.model != nil else { return }
        session.state.searchChanged(isEmpty: query.isEmpty)
        session.model?.search(query)
        refresh(session)
    }

    private func advance(backwards: Bool) {
        guard let session else { return }
        guard session.state.step(backwards: backwards) else { return }
        session.model?.next(backwards: backwards)
        guard let model = session.model else { return }
        session.panel?.select(model.selected?.id, previewImage: previewImage(for: model.selected?.id))
    }

    private func select(_ id: WindowID) {
        guard let session else { return }
        session.model?.select(id: id)
        if session.state.confirm() { validate(session) }
    }

    private func perform(_ action: WindowSwitcherAction) {
        guard let session, let entry = session.model?.selected else { return }
        if action == .maximize || action == .fullscreen || action == .hideApp || action == .quitApp { close(session) }
        let result = switcher.perform(action, on: entry)
        events.append(RoadieEvent(
            type: "switcher.action",
            details: ["action": action.rawValue, "window": "\(entry.window.id)", "changed": "\(result.changed)", "message": result.message]
        ))
        reload(sessionID: session.id)
    }

    private func reload(sessionID: Int) {
        guard let session, session.id == sessionID else { return }
        let previous = session.model?.selected?.id
        let query = session.model?.query ?? ""
        session.loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await self.switcher.load()
            guard let current = self.session, current.id == sessionID else { return }
            var model = self.makeModel(entries: loaded.entries, context: loaded.context, session: current)
            model.search(query)
            if let previous { model.select(id: previous) }
            current.model = model
            self.refresh(current)
        }
    }

    private func validate(_ session: WindowSwitcherSession) {
        let entry = session.model?.selected
        close(session)
        guard let entry else { return }
        let result = switcher.activate(entry)
        events.append(RoadieEvent(
            type: "switcher.activate",
            details: ["window": "\(entry.window.id)", "changed": "\(result.changed)", "message": result.message]
        ))
    }

    private func close(_ session: WindowSwitcherSession) {
        session.loadTask?.cancel()
        session.timer?.invalidate()
        if let monitor = session.outsideMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = session.localClickMonitor { NSEvent.removeMonitor(monitor) }
        session.panel?.orderOut(nil)
        session.panel = nil
        session.model = nil
        self.session = nil
        thumbnails.prune(keeping: [], owner: "switcher")
        hotkeys?.holdEscape(false)
    }

    private func previewImage(for id: WindowID?) -> NSImage? {
        guard let id else { return nil }
        return thumbnails.cachedImage(for: id)
    }

    private static func profile(id: String?, in shortcuts: [WindowSwitcherShortcutConfig]) -> WindowSwitcherShortcutConfig? {
        guard let id else { return shortcuts.first }
        return shortcuts.first { $0.id == id }
    }

    private static func member(for entry: WindowSwitcherEntry) -> PersistentStageMember {
        PersistentStageMember(
            windowID: entry.window.id,
            bundleID: entry.window.bundleID,
            title: entry.window.title,
            frame: entry.window.frame,
            pid: entry.window.pid
        )
    }

    private static func appIcons(for entries: [WindowSwitcherEntry]) -> [WindowID: NSImage] {
        var icons: [WindowID: NSImage] = [:]
        for entry in entries {
            icons[entry.id] = NSRunningApplication(processIdentifier: entry.window.pid)?.icon
        }
        return icons
    }
}
