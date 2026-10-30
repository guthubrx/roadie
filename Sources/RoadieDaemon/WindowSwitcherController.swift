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
    private(set) var stayOpen: Bool
    private let openedPersistently: Bool
    let initialBackwards: Bool

    var persistent: Bool { stayOpen || searching }

    init(stayOpen: Bool, fromHotkey: Bool, heldAtStart: Bool, backwards: Bool) {
        self.openedPersistently = !fromHotkey
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

    mutating func configure(stayOpen: Bool) { self.stayOpen = stayOpen || openedPersistently }

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

    mutating func recoverAfterFailure() {
        phase = .presented
        held = false
        searching = true
        pendingAccept = nil
        queuedSteps = []
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
    var loadRevision = 0
    var actionFailed = false
    var timer: Timer?
    var outsideMonitor: Any?
    var localClickMonitor: Any?
    /// Profil `zones` (session 136) : zones montrées, par identifiant d'entrée, et leur ordre.
    var zones: [WindowID: SwitcherZone] = [:]
    var zoneRecentIDs: [WindowID] = []

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
        self.appearance = WindowSwitcherAppearance(config: config, profile: profile)
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
            onEscape: { [weak self] in self?.session?.panel?.escape() }
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

    /// Déclenchement externe : BTT/Karabiner garde le raccourci, Roadie suit seulement le relâchement.
    public func cycle(profileID: String? = nil, backwards: Bool = false, hold: String = "cmd") {
        if let session {
            guard profileID == nil || profileID == session.profile.id else { return }
            advance(backwards: backwards)
        } else {
            let required = Set(hold.split(separator: "+").compactMap { WindowSwitcherHotkey.modifier(named: String($0)) })
            beginSession(profileID: profileID, fromHotkey: true, backwards: backwards, externalModifiers: required)
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
            ? config.shortcuts.filter { $0.enabled && $0.triggerSource == "roadie" }.map { WindowSwitcherHotkeyRequest(profileID: $0.id, hotkey: $0.hotkey) }
            : []
        hotkeys?.apply(WindowSwitcherHotkeyPlan(requests: requests, layout: TargetSearchHotkey.currentLayoutTable()))
        if let current = session {
            guard config.enabled, let profile = Self.profile(id: current.profile.id, in: config.shortcuts), profile.enabled else { cancel(); return }
            current.profile = profile
            current.state.configure(stayOpen: profile.releaseAction != "focus")
            current.config = config
            current.appearance = WindowSwitcherAppearance(config: config, profile: profile)
            current.panel?.switcherAppearance = current.appearance
            current.panel?.configure(profile: profile, navigationModifiers: current.required)
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

    private func beginSession(profileID: String?, fromHotkey: Bool, backwards: Bool, externalModifiers: Set<WindowSwitcherModifier>? = nil) {
        guard session == nil else { return }
        let config = ConfigReloadService.shared.currentConfig().switcher
        guard config.enabled else { return }
        guard let profile = Self.profile(id: profileID, in: config.shortcuts), profile.enabled else {
            events.append(RoadieEvent(type: "switcher.session", details: ["state": "unknown_profile", "profile": profileID ?? ""]))
            return
        }
        let required = externalModifiers ?? WindowSwitcherHotkey.parse(profile.hotkey, layout: TargetSearchHotkey.currentLayoutTable())?.modifiers ?? []
        let held = WindowSwitcherHotkey.held(in: CGEventSource.flagsState(.combinedSessionState))
        let state = WindowSwitcherSessionState(
            stayOpen: !fromHotkey || profile.releaseAction != "focus",
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
        panel.onHighlight = { [weak self] id in self?.highlight(id) }
        panel.onDismiss = { [weak self] id in self?.dismiss(id) }
        panel.onBan = { [weak self] id in self?.ban(id) }
        panel.onSearchMode = { [weak self] editing in self?.session?.state.searchChanged(isEmpty: !editing) }
        panel.configure(profile: profile, forceSearch: !fromHotkey, navigationModifiers: required)

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

    /// Profil `zones` (session 136) : les fenêtres lues deviennent les zones récentes de leurs fenêtres ; l'ordre de
    /// l'historique tient lieu de récence. Les autres profils gardent les fenêtres. O(z + w).
    private func makeModel(entries: [WindowSwitcherEntry], context: WindowSwitcherContext, session: WindowSwitcherSession) -> WindowSwitcherModel {
        var shown = entries, shownContext = context, recentIDs = WindowSwitcherFocusHistory.shared.recentIDs
        if session.profile.source == "zones" {
            ZoneHistory.shared.prune(policy: .current).forEach(ZoneThumbnails.shared.remove)
            let built = WindowSwitcherZones.build(records: ZoneHistory.shared.records, windows: entries)
            session.zones = built.zones
            session.zoneRecentIDs = built.recentIDs
            (shown, shownContext, recentIDs) = (built.entries, WindowSwitcherZones.context(context, built: built), built.recentIDs)
        }
        return WindowSwitcherModel(
            entries: shown,
            profile: session.profile,
            context: shownContext,
            recentIDs: recentIDs,
            excludedBundles: session.config.excludedBundles
        )
    }

    private func tick() {
        guard let session else { return }
        let held = WindowSwitcherHotkey.held(in: CGEventSource.flagsState(.combinedSessionState))
        let isHeld = !WindowSwitcherHotkey.isReleased(required: session.required, held: held)
        if !isHeld, session.profile.releaseAction == "search", session.panelVisible, session.panel?.isSearchEditing != true {
            session.panel?.beginSearch(initial: true)
        }
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
        if session.profile.releaseAction == "search", !session.state.held { panel.beginSearch(initial: true) }
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
        var images: [WindowID: NSImage]
        if !session.zones.isEmpty {
            // Zones : leur photo entourée en vignettes, sinon l'icône de l'application.
            images = Self.appIcons(for: entries)
            if session.appearance.style == .thumbnails {
                for entry in entries { if let photo = session.zones[entry.id].flatMap({ ZoneThumbnails.shared.framedImage(for: $0.record) }) { images[entry.id] = photo } }
            }
        } else if session.appearance.style == .thumbnails {
            images = thumbnails.images(for: members)
        } else {
            images = Self.appIcons(for: entries)
        }
        requestSelectedPreview(session)
        showZoneHighlight(session)
        session.thumbnailVersion = thumbnails.version
        panel.render(
            entries: entries,
            selectedID: model.selected?.id,
            query: model.query,
            images: images,
            previewImage: previewImage(for: model.selected?.id),
            emptyMessage: session.profile.source == "zones"
                ? tr("Aucune zone récente : cliquez des endroits, ou utilisez la recherche à l'écran", "No recent zones: click places, or use on-screen search")
                : tr("Aucune fenêtre dans ce contexte", "No windows here"),
            iconOnlyIDs: session.appearance.style != .thumbnails ? []
                : !session.zones.isEmpty ? Set(entries.lazy.filter { session.zones[$0.id].flatMap { ZoneThumbnails.shared.framedImage(for: $0.record) } == nil }.map(\.id))
                : Set(entries.lazy.filter { !self.thumbnails.hasCapturedImage(for: $0.id) }.map(\.id))
        )
        if session.appearance.style == .thumbnails, session.zones.isEmpty {
            thumbnails.requestCaptures(
                for: members, protectedWindowIDs: [], liveFrames: [:],
                displayWidth: max(session.appearance.thumbnailWidth, panel.thumbnailDisplayWidth), budget: 6
            )
        }
        if session.actionFailed { panel.showActionError() }
    }

    private func queryChanged(_ query: String) {
        guard let session, session.model != nil else { return }
        session.actionFailed = false
        session.state.searchChanged(isEmpty: query.isEmpty && session.panel?.isSearchEditing != true)
        session.model?.search(query)
        refresh(session)
    }

    private func advance(backwards: Bool) {
        guard let session else { return }
        guard session.state.step(backwards: backwards) else { return }
        session.actionFailed = false
        session.model?.next(backwards: backwards)
        guard let model = session.model else { return }
        showZoneHighlight(session)
        requestSelectedPreview(session)
        session.panel?.select(model.selected?.id, previewImage: previewImage(for: model.selected?.id))
    }

    private func highlight(_ id: WindowID) {
        guard let session else { return }
        session.model?.select(id: id)
        showZoneHighlight(session)
        requestSelectedPreview(session)
        session.panel?.select(id, previewImage: previewImage(for: id))
    }

    private func select(_ id: WindowID) {
        guard let session else { return }
        session.model?.select(id: id)
        if session.state.confirm() { validate(session) }
    }

    private func perform(_ action: WindowSwitcherAction) {
        guard let session, let selected = session.model?.selected else { return }
        // Zone : l'action vise sa fenêtre.
        let entry = session.zones[selected.id]?.window ?? selected
        session.loadTask?.cancel()
        session.loadRevision += 1
        let closesOnSuccess = action == .maximize || action == .fullscreen || action == .hideApp || action == .quitApp
        if closesOnSuccess { session.panel?.orderOut(nil) }
        let result = switcher.perform(action, on: entry)
        events.append(RoadieEvent(
            type: "switcher.action",
            details: ["action": action.rawValue, "window": "\(entry.window.id)", "changed": "\(result.changed)", "message": result.message]
        ))
        if result.outcome == .failed { recoverAfterFailure(session) }
        else if closesOnSuccess { close(session) }
        else { session.actionFailed = false; reload(sessionID: session.id) }
    }

    private func recoverAfterFailure(_ session: WindowSwitcherSession) {
        session.state.recoverAfterFailure()
        session.actionFailed = true
        session.panelVisible = false
        presentPanel(session)
        reload(sessionID: session.id)
    }

    private func reload(sessionID: Int) {
        guard let session, session.id == sessionID else { return }
        session.loadTask?.cancel()
        session.loadRevision += 1
        let revision = session.loadRevision
        let previous = session.model?.selected?.id
        let query = session.model?.query ?? ""
        session.loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Un relevé absent (état modifié pendant la lecture, par exemple par l'annulation d'un échec)
            // n'est pas une liste vide : relire, au plus trois fois (session 106).
            var loaded = await self.switcher.load()
            for _ in 0..<3 where loaded.snapshot == nil && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                loaded = await self.switcher.load()
            }
            guard !Task.isCancelled, let current = self.session, current.id == sessionID, current.loadRevision == revision else { return }
            var model = self.makeModel(entries: loaded.entries, context: loaded.context, session: current)
            model.search(query)
            if let previous { model.select(id: previous) }
            current.model = model
            self.refresh(current)
        }
    }

    private func validate(_ session: WindowSwitcherSession) {
        guard let entry = session.model?.selected else { close(session); return }
        session.loadTask?.cancel()
        session.loadRevision += 1
        session.panel?.orderOut(nil)
        if let zone = session.zones[entry.id] {
            close(session)
            go(to: zone)
            return
        }
        let result = switcher.activate(entry)
        events.append(RoadieEvent(
            type: "switcher.activate",
            details: ["window": "\(entry.window.id)", "changed": "\(result.changed)", "message": result.message]
        ))
        if result.outcome == .failed { recoverAfterFailure(session) }
        else { close(session) }
    }

    /// Zone choisie (session 136) : sa fenêtre revient par l'activation habituelle (stage et bureau compris), puis
    /// l'attente du premier plan et le clic tournent hors du fil principal (session 135).
    private func go(to zone: SwitcherZone) {
        // La zone devient la plus récente, comme une fenêtre activée : le prochain ⌥Tab ramène à la précédente.
        ZoneHistory.shared.touch(zone.record)
        let result = switcher.activate(zone.window)
        let element = ZoneHistory.shared.element(for: zone.record)
        let record = zone.record
        let events = events
        guard result.outcome != .failed else {
            events.append(RoadieEvent(type: "zone.go", details: ["app": record.appName, "changed": "false", "message": result.message]))
            return
        }
        Task { @MainActor in
            let click = await Task.detached(priority: .userInitiated) { LiveAppTargetProvider().clickZone(record, element: element) }.value
            // À l'arrivée, la zone cliquée est entourée un instant : on voit où le clic est tombé.
            if let zone = click.zone { ZoneHighlight.shared.show(zone, duration: 0.9) }
            events.append(RoadieEvent(type: "zone.go", details: ["app": record.appName, "changed": String(click.result.changed),
                                                                 "message": click.result.message]))
        }
    }

    /// × d'une carte (session 137) : la fenêtre est fermée, ou la zone retirée avec sa photo ; la liste est relue.
    private func dismiss(_ id: WindowID) {
        guard let session, let entry = session.model?.matches.first(where: { $0.id == id }) else { return }
        if let zone = session.zones[id] {
            ZoneHistory.shared.forget(zone.record)
            ZoneThumbnails.shared.remove(zone.record.key)
            events.append(RoadieEvent(type: "zone.dismissed", details: ["app": zone.record.appName]))
        } else {
            let result = switcher.perform(.close, on: entry)
            events.append(RoadieEvent(type: "switcher.dismissed", details: ["window": "\(entry.window.id)", "changed": "\(result.changed)"]))
        }
        reload(sessionID: session.id)
    }

    /// Sens interdit d'une carte (session 137) : l'application quitte le sélecteur de fenêtres, ou ses clics ne créent
    /// plus de zone (et ses zones de clics partent). Annulable dans Paramètres > Sélecteur ; la liste est relue.
    private func ban(_ id: WindowID) {
        guard let session, let entry = session.model?.matches.first(where: { $0.id == id }) else { return }
        let bundleID = (session.zones[id]?.window ?? entry).window.bundleID
        if session.zones[id] != nil {
            _ = SwitcherExclusions.add(bundleID, to: SwitcherExclusions.clickZones)
            ZoneHistory.shared.forgetClicks(bundleID: bundleID).forEach(ZoneThumbnails.shared.remove)
        } else {
            _ = SwitcherExclusions.add(bundleID, to: SwitcherExclusions.windows)
            session.config.excludedBundles.append(bundleID)
            session.model?.configure(profile: session.profile, excludedBundles: session.config.excludedBundles)
        }
        events.append(RoadieEvent(type: "switcher.banned", details: ["bundleID": bundleID, "kind": session.zones[id] == nil ? "windows" : "click_zones"]))
        reload(sessionID: session.id)
    }

    /// Zone choisie dans ⌥Tab entourée sur la vraie application, si sa fenêtre est à l'écran (même stage) ; sinon,
    /// rien n'est montré avant l'arrivée. O(1).
    private func showZoneHighlight(_ session: WindowSwitcherSession) {
        // Bornes des écrans en coordonnées globales, celles de l'accessibilité.
        let screens = NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map(CGDisplayBounds) }
        guard let selected = session.model?.selected, let zone = session.zones[selected.id],
              let rect = ZoneNavigation.screenRect(of: zone.record, window: zone.window, screens: screens) else {
            ZoneHighlight.shared.hide()
            return
        }
        ZoneHighlight.shared.show(rect)
    }

    private func close(_ session: WindowSwitcherSession) {
        ZoneHighlight.shared.hide()
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

    private func requestSelectedPreview(_ session: WindowSwitcherSession) {
        guard session.appearance.preview, let entry = session.model?.selected, session.zones[entry.id] == nil else { return }
        thumbnails.requestCaptures(for: [Self.member(for: entry)], protectedWindowIDs: [], liveFrames: [:],
                                   displayWidth: max(400, session.appearance.thumbnailWidth), budget: 1)
    }

    private func previewImage(for id: WindowID?) -> NSImage? {
        guard let id else { return nil }
        if let zone = session?.zones[id] { return ZoneThumbnails.shared.framedImage(for: zone.record) }
        return thumbnails.cachedImage(for: id)
    }

    /// Sans identifiant (⌘Tab de BTT : `roadie switcher cycle` sans profil), le premier profil actif de fenêtres : un
    /// profil de zones placé avant ne doit pas prendre ⌘Tab (essai du 30 octobre 2026). O(p).
    nonisolated static func profile(id: String?, in shortcuts: [WindowSwitcherShortcutConfig]) -> WindowSwitcherShortcutConfig? {
        guard let id else {
            return shortcuts.first { $0.enabled && $0.source == "windows" } ?? shortcuts.first(where: \.enabled)
        }
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
