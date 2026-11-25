import AppKit
import Carbon
import RoadieCore

/// Raccourci global du mode recherche (SPEC-021), enregistré par Carbon (`RegisterEventHotKey`) :
/// aucune permission, la combinaison est consommée. Défaut : Cmd+Option+Ctrl+F (hyper key + F).
/// Les changements de réglages, de fichier de configuration et de disposition clavier sont suivis
/// par notifications système et surveillance vnode (zéro polling périodique par défaut).
@MainActor
public final class TargetSearchHotkey {
    public struct Resolved: Equatable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32
    }

    private static var cachedLayout: (sourceID: String, table: [UInt32: String])?

    private let onPress: @MainActor () -> Void
    private let events: EventLog
    private let configLoader: () -> TargetModeConfig
    private let configPathLoader: () -> String
    private let signature: OSType
    private let eventType: String
    private let settingsIDs: Set<String>
    private let pollingInterval: TimeInterval?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registered: Resolved?
    private var lastState: String?
    private var started = false
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var reloadObserver: NSObjectProtocol?
    private var keyboardObserver: NSObjectProtocol?
    private var configWatcher: RailFileWatcher?

    public init(
        events: EventLog = EventLog(),
        configLoader: @escaping () -> TargetModeConfig = { ConfigReloadService.shared.currentConfig().experimental.targetMode },
        configPathLoader: @escaping () -> String = {
            ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        },
        pollingInterval: TimeInterval? = nil,
        signature: OSType = 0x5244_5352,
        eventType: String = "target_mode.search_hotkey",
        settingsIDs: Set<String> = ["target_mode.search_hotkey", "target_mode.enabled", "target_mode.overlay_enabled", "*"],
        onPress: @escaping @MainActor () -> Void
    ) {
        self.signature = signature
        self.eventType = eventType
        self.settingsIDs = settingsIDs
        self.events = events
        self.configLoader = configLoader
        self.configPathLoader = configPathLoader
        self.pollingInterval = pollingInterval
        self.onPress = onPress
    }

    public func start() {
        guard !started else { return }
        started = true
        installHandler()
        refresh()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .roadieSettingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            let path = notification.userInfo?["configPath"] as? String
            let settingID = notification.userInfo?["settingID"] as? String
            Task { @MainActor in
                guard let self, self.started, let path, let settingID,
                      self.settingsIDs.contains(settingID),
                      URL(fileURLWithPath: path).resolvingSymlinksInPath()
                        == URL(fileURLWithPath: self.configPathLoader()).resolvingSymlinksInPath() else { return }
                self.refresh()
            }
        }
        reloadObserver = NotificationCenter.default.addObserver(
            forName: .roadieConfigDidReload, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.refresh()
            }
        }
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Self.invalidateLayoutCache()
                guard let self, self.started else { return }
                self.refresh()
            }
        }
        let pathLoader = configPathLoader
        configWatcher = RailFileWatcher(
            path: {
                let expanded = NSString(string: pathLoader()).expandingTildeInPath
                return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
            },
            observedFile: { NSString(string: pathLoader()).expandingTildeInPath },
            onChange: { [weak self] in
                guard let self, self.started else { return }
                self.refresh()
            }
        )
        configWatcher?.start()
        if let pollingInterval, pollingInterval > 0 {
            let newTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            newTimer.tolerance = min(pollingInterval * 0.25, 1)
            timer = newTimer
        }
    }

    /// Libère le raccourci et les observateurs ; aucune session de recherche n'est modifiée.
    public func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        configWatcher?.stop()
        configWatcher = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        if let reloadObserver { NotificationCenter.default.removeObserver(reloadObserver) }
        reloadObserver = nil
        if let keyboardObserver { DistributedNotificationCenter.default().removeObserver(keyboardObserver) }
        keyboardObserver = nil
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    // MARK: - Résolution (pure)

    nonisolated public static func carbonModifiers(_ names: Set<String>) -> UInt32 {
        var flags = 0
        if names.contains("command") { flags |= cmdKey }
        if names.contains("control") { flags |= controlKey }
        if names.contains("alt") { flags |= optionKey }
        if names.contains("shift") { flags |= shiftKey }
        return UInt32(flags)
    }

    nonisolated public static func namedKeyCode(_ key: String) -> UInt32? {
        if key.hasPrefix("keycode-"), let code = UInt32(key.dropFirst(8)), code < 128 { return code }
        let named: [String: UInt32] = [
            "space": 49, "return": 36, "tab": 48, "escape": 53, "backspace": 51,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        return named[key]
    }

    /// Table ANSI de repli (lettres a–z) utilisée uniquement hors thread principal (ex. tests unitaires).
    nonisolated public static let standardFallbackLayout: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
    ]

    /// Touche qui produit `character` sans modificateur dans la table `code → caractère` ; la plus
    /// petite si plusieurs (pavé numérique).
    nonisolated public static func keyCode(for character: String, in layout: [UInt32: String]) -> UInt32? {
        let wanted = character.lowercased()
        return layout.filter { $0.value == wanted }.keys.min()
    }

    /// `search_hotkey` normalisé → code et modificateurs Carbon ; nil si vide, invalide ou introuvable.
    nonisolated public static func resolve(_ normalized: String, layout: [UInt32: String]) -> Resolved? {
        guard let parts = TargetModeConfig.hotkeyParts(normalized),
              let code = namedKeyCode(parts.key) ?? keyCode(for: parts.key, in: layout)
        else { return nil }
        return Resolved(keyCode: code, modifiers: carbonModifiers(parts.modifiers))
    }

    /// Caractère produit par chaque touche 0-127 sans modificateur, selon la disposition active.
    /// Mis en cache par identifiant `TISInputSource` : O(1) tant que la disposition ne change pas,
    /// O(128) appels `UCKeyTranslate` au premier appel ou après un changement de disposition.
    public static func currentLayoutTable() -> [UInt32: String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return [:] }
        let sourceID: String? = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        }
        if let sourceID, let cached = cachedLayout, cached.sourceID == sourceID {
            return cached.table
        }
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return [:] }
        var table: [UInt32: String] = [:]
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars
                )
                if status == noErr, length > 0 {
                    table[UInt32(code)] = String(utf16CodeUnits: chars, count: length).lowercased()
                }
            }
        }
        if let sourceID { cachedLayout = (sourceID, table) }
        return table
    }

    static func invalidateLayoutCache() {
        cachedLayout = nil
    }

    // MARK: - Enregistrement

    func refresh() {
        let config = configLoader()
        let active = config.enabled && config.overlayEnabled && !config.searchHotkey.isEmpty
        let wanted = active ? Self.resolve(config.searchHotkey, layout: Self.currentLayoutTable()) : nil
        guard wanted != registered || (wanted == nil && lastState == nil) else { return }
        unregister()
        guard let wanted else {
            report(active ? "unresolved" : "disabled", hotkey: config.searchHotkey)
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 1) // 'RDSR'
        let status = RegisterEventHotKey(
            wanted.keyCode, wanted.modifiers, id, GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref
        )
        if status == noErr, let ref {
            hotKeyRef = ref
            registered = wanted
            report("registered", hotkey: config.searchHotkey)
        } else {
            report("failed status=\(status)", hotkey: config.searchHotkey)
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registered = nil
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let hotkey = Unmanaged<TargetSearchHotkey>.fromOpaque(userData).takeUnretainedValue()
            // Attente de la touche avant son traitement (session 123) : même horloge que l'événement Carbon.
            let lagMs = max(0, (ProcessInfo.processInfo.systemUptime - GetEventTime(event)) * 1000)
            return MainActor.assumeIsolated { hotkey.handle(identifier, lagMs: lagMs) }
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    /// Plusieurs fonctions partagent la cible Carbon : ne jamais absorber un autre raccourci.
    func handle(_ identifier: EventHotKeyID, lagMs: Double? = nil) -> OSStatus {
        guard identifier.signature == signature, identifier.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        LauncherOpenClock.pendingKeyLagMs = lagMs
        onPress()
        return noErr
    }

    /// Journalise seulement les changements d'état (pas toutes les 2 s).
    private func report(_ state: String, hotkey: String) {
        let key = "\(state)|\(hotkey)"
        guard key != lastState else { return }
        lastState = key
        events.append(RoadieEvent(type: eventType, details: ["state": state, "hotkey": hotkey]))
    }
}
