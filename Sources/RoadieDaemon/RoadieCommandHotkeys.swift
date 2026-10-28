import AppKit
import Carbon
import RoadieCore

/// Raccourcis globaux des commandes `roadie …` gérés par Roadie lui-même (session 108), table
/// `[[shortcuts]]`. Carbon (`RegisterEventHotKey`) : aucune permission, la combinaison est consommée.
/// La commande passe par le même routeur que le canal socket, sans lancer de processus.
@MainActor
public final class RoadieCommandHotkeys {
    struct Entry: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var arguments: [String]
    }

    /// Plan pur : une entrée par raccourci actif et valide ; une combinaison prise deux fois garde la
    /// première. `issues` : `invalide:<touches>` ou `collision:<touches>`. O(n).
    nonisolated static func plan(_ shortcuts: [CommandShortcut], layout: [UInt32: String]) -> (entries: [Entry], issues: [String]) {
        var entries: [Entry] = [], issues: [String] = [], taken: Set<String> = []
        for shortcut in shortcuts where shortcut.enabled && !shortcut.keys.isEmpty {
            guard !shortcut.arguments.isEmpty, let resolved = TargetSearchHotkey.resolve(shortcut.keys, layout: layout) else {
                issues.append("invalide:\(shortcut.keys)")
                continue
            }
            let fingerprint = "\(resolved.keyCode):\(resolved.modifiers)"
            guard taken.insert(fingerprint).inserted else {
                issues.append("collision:\(shortcut.keys)")
                continue
            }
            entries.append(Entry(keyCode: resolved.keyCode, modifiers: resolved.modifiers, arguments: shortcut.arguments))
        }
        return (entries, issues)
    }

    private static let signature = OSType(0x5244_434D) // 'RDCM'
    private let events: EventLog
    private let configLoader: () -> [CommandShortcut]
    private let run: @MainActor ([String]) -> Void
    private var refs: [EventHotKeyRef] = []
    private var entries: [Entry] = []
    private var handlerRef: EventHandlerRef?
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    public init(events: EventLog = EventLog(),
         configLoader: @escaping () -> [CommandShortcut] = { ConfigReloadService.shared.currentConfig().shortcuts },
         run: @escaping @MainActor ([String]) -> Void) {
        self.events = events
        self.configLoader = configLoader
        self.run = run
    }

    /// Relecture à chaque changement de réglage et toutes les 2 s (fichier modifié ailleurs, disposition).
    public func start() {
        guard timer == nil else { return }
        installHandler()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: .roadieSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    func refresh() {
        let planned = Self.plan(configLoader(), layout: TargetSearchHotkey.currentLayoutTable())
        guard planned.entries != entries else { return }
        unregister()
        for issue in planned.issues {
            events.append(RoadieEvent(type: "shortcuts.hotkey", details: ["state": "issue", "detail": issue]))
        }
        for (index, entry) in planned.entries.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(entry.keyCode, entry.modifiers, id, GetApplicationEventTarget(),
                                             OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref { refs.append(ref) } else {
                events.append(RoadieEvent(type: "shortcuts.hotkey", details: [
                    "state": "failed", "command": entry.arguments.joined(separator: " "), "status": "\(status)"]))
            }
        }
        entries = planned.entries
        events.append(RoadieEvent(type: "shortcuts.hotkey", details: ["state": "registered", "count": "\(refs.count)"]))
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        entries = []
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            // Plusieurs fonctions partagent la cible Carbon : ne jamais absorber un autre raccourci.
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == OSType(0x5244_434D) else { return OSStatus(eventNotHandledErr) }
            let hotkeys = Unmanaged<RoadieCommandHotkeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotkeys.dispatch(Int(id.id) - 1) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func dispatch(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        run(entries[index].arguments)
    }
}
