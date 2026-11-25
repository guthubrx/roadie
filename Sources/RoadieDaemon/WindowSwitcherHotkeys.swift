import AppKit
import Carbon
import CoreGraphics
import RoadieCore

enum WindowSwitcherModifier: String, CaseIterable, Hashable, Sendable {
    case control, option, command, shift
}

struct WindowSwitcherHotkey: Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: Set<WindowSwitcherModifier>

    /// `ctrl+alt+tab` → touche Carbon et modificateurs. nil si la touche est inconnue ou si aucun modificateur n'est fourni
    /// (une touche seule capturerait Tab partout dans le système).
    static func parse(_ text: String, layout: [UInt32: String]) -> WindowSwitcherHotkey? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, !key.isEmpty else { return nil }
        var modifiers: Set<WindowSwitcherModifier> = []
        for part in parts.dropLast() {
            guard let modifier = modifier(named: part) else { return nil }
            modifiers.insert(modifier)
        }
        guard !modifiers.isEmpty,
              let code = TargetSearchHotkey.namedKeyCode(key) ?? TargetSearchHotkey.keyCode(for: key, in: layout)
        else { return nil }
        return WindowSwitcherHotkey(keyCode: code, modifiers: modifiers)
    }

    static func modifier(named name: String) -> WindowSwitcherModifier? {
        switch name {
        case "ctrl", "control": .control
        case "alt", "option", "opt": .option
        case "cmd", "command": .command
        case "shift": .shift
        default: nil
        }
    }

    /// Vrai si au moins un modificateur requis n'est plus tenu. Pur, sans AppKit.
    static func isReleased(required: Set<WindowSwitcherModifier>, held: Set<WindowSwitcherModifier>) -> Bool {
        !required.isSubset(of: held)
    }

    static func held(in flags: CGEventFlags) -> Set<WindowSwitcherModifier> {
        var held: Set<WindowSwitcherModifier> = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        return held
    }

    static func carbonModifiers(_ modifiers: Set<WindowSwitcherModifier>) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

struct WindowSwitcherHotkeyRequest: Equatable, Sendable {
    var profileID: String
    var hotkey: String
}

/// Plan d'enregistrement pur : chaque profil valide donne un raccourci et sa variante Maj (cycle inverse).
struct WindowSwitcherHotkeyPlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var profileID: String
        var backwards: Bool
        var hotkey: WindowSwitcherHotkey
    }

    var entries: [Entry] = []
    /// Diagnostics lisibles : `invalide:<profil>` ou `collision:<profil>:<profil déjà enregistré>`.
    var issues: [String] = []

    init(requests: [WindowSwitcherHotkeyRequest], layout: [UInt32: String]) {
        var owners: [WindowSwitcherHotkey: String] = [:]
        for request in requests {
            if request.hotkey.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let forward = WindowSwitcherHotkey.parse(request.hotkey, layout: layout) else {
                issues.append("invalide:\(request.profileID)")
                continue
            }
            var variants = [(forward, false)]
            if !forward.modifiers.contains(.shift) {
                var reverse = forward
                reverse.modifiers.insert(.shift)
                variants.append((reverse, true))
            }
            for (hotkey, backwards) in variants {
                if let owner = owners[hotkey] {
                    issues.append("collision:\(request.profileID):\(owner)")
                    continue
                }
                owners[hotkey] = request.profileID
                entries.append(Entry(profileID: request.profileID, backwards: backwards, hotkey: hotkey))
            }
        }
    }
}

/// Enregistre les raccourcis Carbon du sélecteur, avec bascule automatique sur un `CGEventTap`
/// (nécessaire pour les combinaisons réservées par macOS comme `⌘Tab` / `⌘⇧Tab`).
/// Ne désactive jamais un autre outil.
@MainActor
final class WindowSwitcherHotkeyRegistry {
    static let escapeID: UInt32 = 1000
    private static let signature = OSType(0x5244_5357) // 'RDSW'

    /// `⌘Tab` / `⌘⇧Tab` est réservé par WindowServer/Dock : Carbon seul ne peut pas le consommer.
    nonisolated static func requiresEventTap(_ hotkey: WindowSwitcherHotkey) -> Bool {
        hotkey.keyCode == 48 && hotkey.modifiers.contains(.command)
    }

    /// Résolution pure d'un `keyDown` dans les entrées confiées au `CGEventTap`. O(e).
    nonisolated static func matchTapEntry(
        keyCode: UInt32,
        flags: CGEventFlags,
        in entries: [WindowSwitcherHotkeyPlan.Entry]
    ) -> WindowSwitcherHotkeyPlan.Entry? {
        let held = WindowSwitcherHotkey.held(in: flags)
        return entries.first { $0.hotkey.keyCode == keyCode && $0.hotkey.modifiers == held }
    }

    private let onPress: @MainActor (_ profileID: String, _ backwards: Bool) -> Void
    private let onEscape: @MainActor () -> Void
    private let events: EventLog
    private var refs: [EventHotKeyRef] = []
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var entries: [WindowSwitcherHotkeyPlan.Entry] = []
    private var tapEntries: [WindowSwitcherHotkeyPlan.Entry] = []
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapToken: UnsafeMutableRawPointer?
    private var applied: WindowSwitcherHotkeyPlan?
    static var activeProfileIDs: Set<String> = []
    static var activeFingerprints: [String: String] = [:]
    private static var peerObserver: NSObjectProtocol?
    private static let statusName = Notification.Name("com.roadie.switcher.registration")

    static func observePeerStatus() {
        guard peerObserver == nil else { return }
        peerObserver = DistributedNotificationCenter.default().addObserver(forName: statusName, object: "roadie", queue: .main) { notification in
            let ids = notification.userInfo?["profiles"] as? [String] ?? []
            let bindings = notification.userInfo?["bindings"] as? [String: String] ?? [:]
            Task { @MainActor in activeProfileIDs = Set(ids); activeFingerprints = bindings }
        }
    }

    private static func publishStatus() {
        DistributedNotificationCenter.default().postNotificationName(statusName, object: "roadie",
            userInfo: ["profiles": Array(activeProfileIDs).sorted(), "bindings": activeFingerprints], deliverImmediately: true)
    }



    init(
        events: EventLog,
        onPress: @escaping @MainActor (_ profileID: String, _ backwards: Bool) -> Void,
        onEscape: @escaping @MainActor () -> Void
    ) {
        self.events = events
        self.onPress = onPress
        self.onEscape = onEscape
    }

    /// Ne réenregistre que si le plan change ; journalise les diagnostics à chaque changement.
    func apply(_ plan: WindowSwitcherHotkeyPlan) {
        guard plan != applied else { Self.publishStatus(); return }
        unregisterAll()
        applied = plan
        installHandler()
        entries = plan.entries
        var successes: [String: Int] = [:]
        for issue in plan.issues {
            events.append(RoadieEvent(type: "switcher.hotkey", details: ["state": "issue", "detail": issue]))
        }
        for (index, entry) in plan.entries.enumerated() {
            if Self.requiresEventTap(entry.hotkey) {
                tapEntries.append(entry)
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                entry.hotkey.keyCode, WindowSwitcherHotkey.carbonModifiers(entry.hotkey.modifiers), id,
                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
                successes[entry.profileID, default: 0] += 1
            } else {
                events.append(RoadieEvent(
                    type: "switcher.hotkey",
                    details: ["state": "failed", "profile": entry.profileID, "status": "\(status)"]
                ))
            }
        }
        if !tapEntries.isEmpty {
            if installEventTap() {
                for entry in tapEntries {
                    successes[entry.profileID, default: 0] += 1
                }
                events.append(RoadieEvent(
                    type: "switcher.hotkey",
                    details: ["state": "tap_registered", "count": "\(tapEntries.count)"]
                ))
            } else {
                events.append(RoadieEvent(
                    type: "switcher.hotkey",
                    details: ["state": "tap_failed", "count": "\(tapEntries.count)"]
                ))
                tapEntries = []
            }
        }
        Self.activeProfileIDs = Set(successes.keys.filter { id in successes[id] == plan.entries.filter { $0.profileID == id }.count })
        Self.activeFingerprints = Dictionary(uniqueKeysWithValues: plan.entries.filter {
            !$0.backwards && Self.activeProfileIDs.contains($0.profileID)
        }.map { ($0.profileID, "\($0.hotkey.keyCode):\(WindowSwitcherHotkey.carbonModifiers($0.hotkey.modifiers))") })
        Self.publishStatus()
    }

    /// Escape est retenu seulement pendant une session ouverte, puis relâché.
    func holdEscape(_ active: Bool) {
        if active, escapeRef == nil {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: Self.escapeID)
            let status = RegisterEventHotKey(53, 0, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr { escapeRef = ref }
        } else if !active, let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
    }

    func stop() {
        unregisterAll()
        applied = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func unregisterAll() {
        Self.activeProfileIDs = []
        Self.activeFingerprints = [:]
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        removeEventTap()
        tapEntries = []
        holdEscape(false)
        entries = []
    }

    private func installEventTap() -> Bool {
        guard eventTap == nil else { return true }
        guard !TestEnvironment.isRunningTests else { return true }
        let token = KeyEventTapOwners.shared.register(self)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let owner = KeyEventTapOwners.shared.owner(for: refcon) as? WindowSwitcherHotkeyRegistry else {
                return Unmanaged.passUnretained(event)
            }
            let consumed = MainActor.assumeIsolated { owner.handleTapEvent(type, event: event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: token
        ) else {
            KeyEventTapOwners.shared.remove(token)
            return false
        }
        eventTap = tap
        eventTapToken = token
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let token = eventTapToken {
            KeyEventTapOwners.shared.remove(token)
        }
        eventTap = nil
        eventTapSource = nil
        eventTapToken = nil
    }

    private func handleTapEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown else { return false }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard let match = Self.matchTapEntry(keyCode: keyCode, flags: event.flags, in: tapEntries) else {
            return false
        }
        let profileID = match.profileID
        let backwards = match.backwards
        Task { @MainActor [weak self] in
            self?.onPress(profileID, backwards)
        }
        return true
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == OSType(0x5244_5357) else { return OSStatus(eventNotHandledErr) }
            let registry = Unmanaged<WindowSwitcherHotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { registry.dispatch(id: id.id) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    private func dispatch(id: UInt32) {
        if id == Self.escapeID {
            onEscape()
            return
        }
        let index = Int(id) - 1
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        onPress(entry.profileID, entry.backwards)
    }
}
