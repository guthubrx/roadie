import AppKit
import Carbon
import CoreGraphics
import RoadieCore

enum WindowSwitcherModifier: String, CaseIterable, Hashable, Sendable {
    case control, option, command, shift
}

struct WindowSwitcherHotkey: Equatable, Sendable {
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

/// Enregistre les raccourcis Carbon du sélecteur. Ne désactive jamais un autre outil.
@MainActor
final class WindowSwitcherHotkeyRegistry {
    static let escapeID: UInt32 = 1000
    private static let signature = OSType(0x5244_5357) // 'RDSW'

    private let onPress: @MainActor (_ profileID: String, _ backwards: Bool) -> Void
    private let onEscape: @MainActor () -> Void
    private let events: EventLog
    private var refs: [EventHotKeyRef] = []
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var entries: [WindowSwitcherHotkeyPlan.Entry] = []
    private var applied: WindowSwitcherHotkeyPlan?

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
        guard plan != applied else { return }
        unregisterAll()
        applied = plan
        installHandler()
        entries = plan.entries
        for issue in plan.issues {
            events.append(RoadieEvent(type: "switcher.hotkey", details: ["state": "issue", "detail": issue]))
        }
        for (index, entry) in plan.entries.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                entry.hotkey.keyCode, WindowSwitcherHotkey.carbonModifiers(entry.hotkey.modifiers), id,
                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                events.append(RoadieEvent(
                    type: "switcher.hotkey",
                    details: ["state": "failed", "profile": entry.profileID, "status": "\(status)"]
                ))
            }
        }
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
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        holdEscape(false)
        entries = []
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
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
