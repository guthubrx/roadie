import AppKit
import Foundation
import RoadieCore

/// Raccourci clavier global de BetterTouchTool (session 108). `command` : texte après `roadie` quand le
/// script lance une commande Roadie, sinon vide.
struct BTTKeyboardTrigger: Identifiable, Equatable, Sendable {
    let id: String
    let group: String
    let command: String
    let keyCode: Int
    let modifiers: UInt
    let enabled: Bool

    /// Combinaison normalisée (`command+l`) ; vide si BTT n'a pas de touche ou seulement Maj.
    func keys(layout: [UInt32: String]) -> String {
        guard keyCode >= 0 else { return "" }
        return ShortcutCapture.value(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: modifiers), layout: layout) ?? ""
    }

    var combo: BarKeyCombo { BarKeyCombo(keyCode: UInt16(max(0, keyCode)), flags: NSEvent.ModifierFlags(rawValue: modifiers)) }
}

enum BTTRoadieTriggers {
    static let bundleID = "com.hegenberg.BetterTouchTool"

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Commande Roadie d'un script BTT (`…; roadie focus right`, `'/…/roadie' focus right`) ; nil sinon.
    /// Le sélecteur (`switcher cycle`) reste aux profils du sélecteur. O(n).
    static func command(inScript script: String) -> String? {
        guard let last = script.components(separatedBy: ":::").last?.components(separatedBy: ";").last?
            .trimmingCharacters(in: .whitespaces) else { return nil }
        var words = last.split(separator: " ", maxSplits: 1).map(String.init)
        guard words.count == 2 else { return nil }
        words[0] = words[0].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard words[0] == "roadie" || words[0].hasSuffix("/roadie") else { return nil }
        let command = words[1].trimmingCharacters(in: .whitespaces)
        return command.hasPrefix("switcher cycle") ? nil : command
    }

    /// Raccourcis clavier globaux d'une réponse `get_triggers`, dossiers compris. BTT omet `BTTEnabled`
    /// quand il vaut 1. O(t), t = nombre de déclencheurs.
    static func parse(_ json: String) -> [BTTKeyboardTrigger] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
        var nodes: [[String: Any]] = []
        func visit(_ item: Any) {
            if let value = item as? [String: Any] {
                nodes.append(value)
                for child in value.values where child is [Any] || child is [String: Any] { visit(child) }
            } else if let array = item as? [Any] { array.forEach(visit) }
        }
        visit(root)
        var groups: [String: String] = [:]
        for node in nodes {
            if let id = node["BTTUUID"] as? String, let name = node["BTTGroupName"] as? String { groups[id] = name }
        }
        var seen: Set<String> = []
        return nodes.compactMap { node in
            guard node["BTTTriggerClass"] as? String == "BTTTriggerTypeKeyboardShortcut", node["BTTGroupName"] == nil,
                  let id = node["BTTUUID"] as? String, let code = (node["BTTShortcutKeyCode"] as? NSNumber)?.intValue, code >= 0,
                  seen.insert(id).inserted else { return nil }
            let script = node["BTTShellTaskActionScript"] as? String
                ?? (node["BTTActionsToExecute"] as? [[String: Any]])?.compactMap { $0["BTTShellTaskActionScript"] as? String }.first ?? ""
            let enabled = (node["BTTEnabled"] as? NSNumber)?.intValue ?? 1 == 1 && (node["BTTEnabled2"] as? NSNumber)?.intValue ?? 1 == 1
            return BTTKeyboardTrigger(id: id, group: (node["BTTTriggerParentUUID"] as? String).flatMap { groups[$0] } ?? "",
                                      command: command(inScript: script) ?? "", keyCode: code,
                                      modifiers: (node["BTTShortcutModifierKeys"] as? NSNumber)?.uintValue ?? 0, enabled: enabled)
        }
    }

    /// Drapeaux BTT d'une combinaison normalisée : mêmes bits que macOS. nil si elle est invalide.
    static func fields(keys: String, layout: [UInt32: String]) -> [String: Any]? {
        guard let parts = TargetModeConfig.hotkeyParts(keys),
              let code = TargetSearchHotkey.namedKeyCode(parts.key) ?? TargetSearchHotkey.keyCode(for: parts.key, in: layout) else { return nil }
        var flags: UInt64 = 0
        if parts.modifiers.contains("command") { flags |= CGEventFlags.maskCommand.rawValue }
        if parts.modifiers.contains("control") { flags |= CGEventFlags.maskControl.rawValue }
        if parts.modifiers.contains("alt") { flags |= CGEventFlags.maskAlternate.rawValue }
        if parts.modifiers.contains("shift") { flags |= CGEventFlags.maskShift.rawValue }
        return ["BTTShortcutKeyCode": code, "BTTShortcutModifierKeys": flags, "BTTShortcutAdvancedModifierKeys": String(flags),
                "BTTAdditionalConfiguration": String(flags), "BTTLayoutIndependentChar": layout[code] ?? ""]
    }

    static func enabledFields(_ enabled: Bool) -> [String: Any] { ["BTTEnabled": enabled ? 1 : 0, "BTTEnabled2": enabled ? 1 : 0] }

    /// Nouveau raccourci global BTT qui lance `roadie <command>`, comme ceux déjà en place.
    static func newTrigger(command: String, keys: String, layout: [UInt32: String]) -> [String: Any]? {
        guard var fields = fields(keys: keys, layout: layout) else { return nil }
        let script = "PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; roadie " + command
        fields.merge([
            "BTTTriggerType": 0, "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut", "BTTPredefinedActionType": 206,
            "BTTShellTaskActionScript": "/bin/bash:::-c:::-:::" + script, "BTTShellTaskActionConfig": "/bin/bash:::-c:::-:::" + script,
            "BTTAutoAdaptToKeyboardLayout": 0, "BTTTriggerOnDown": 1, "BTTAppBundleIdentifier": "BT.G",
            "BTTUUID": UUID().uuidString, "BTTNotes": "Roadie - " + command,
        ]) { current, _ in current }
        return fields.merging(enabledFields(true)) { current, _ in current }
    }
}

/// Pause des raccourcis BTT qui prendraient les touches de la barre (session 108). Ouverture : les
/// raccourcis BTT actifs des combinaisons de `btt_pause_keys` sont désactivés ; fermeture : réactivés.
/// Les identifiants en pause sont écrits sur disque, puis réactivés au démarrage suivant si Roadie s'est
/// arrêté barre ouverte. Une seule file : ouverture et fermeture gardent leur ordre.
@MainActor
final class LauncherBTTPause {
    static let shared = LauncherBTTPause()

    private let queue = DispatchQueue(label: "com.roadie.btt-pause")
    private let api: any BTTShortcutAPI
    private let file: URL
    private var opened = false
    /// Combinaison physique → raccourcis BTT actifs, relu après chaque fermeture.
    nonisolated(unsafe) private var index: [BarKeyCombo: [String]] = [:]

    init(api: any BTTShortcutAPI = BTTAppleScriptAPI(),
         file: URL = URL(fileURLWithPath: NSString(string: "~/.roadies/btt-paused.json").expandingTildeInPath)) {
        self.api = api
        self.file = file
    }

    /// Raccourcis BTT à mettre en pause pour ces touches de la barre. O(k).
    nonisolated static func paused(keys: [String], index: [BarKeyCombo: [String]], layout: [UInt32: String]) -> [String] {
        var ids: [String] = []
        for key in keys {
            guard let resolved = SearchInputPanel.cycleKey(key, layout: layout) else { continue }
            ids += index[BarKeyCombo(keyCode: resolved.keyCode, flags: resolved.flags)] ?? []
        }
        return Array(Set(ids)).sorted()
    }

    func barOpened(pauseKeys: [String]) {
        guard !pauseKeys.isEmpty, !opened, !TestEnvironment.isRunningTests, BTTRoadieTriggers.isRunning else { return }
        opened = true
        let layout = TargetSearchHotkey.currentLayoutTable()
        queue.async { [api, file] in
            if self.index.isEmpty { self.rebuildIndex() }
            let ids = Self.paused(keys: pauseKeys, index: self.index, layout: layout)
            guard !ids.isEmpty else { return }
            try? JSONSerialization.data(withJSONObject: ids).write(to: file, options: .atomic)
            for id in ids { try? api.write(id, json: BTTShortcutBindingService.json(BTTRoadieTriggers.enabledFields(false))) }
        }
    }

    func barClosed() {
        guard opened else { return }
        opened = false
        queue.async {
            self.restore()
            self.rebuildIndex()
        }
    }

    /// Démarrage : réactive ce qu'un arrêt barre ouverte a laissé en pause.
    func restoreAtStart() {
        guard !TestEnvironment.isRunningTests else { return }
        queue.async { self.restore() }
    }

    nonisolated private func restore() {
        guard let data = try? Data(contentsOf: file),
              let ids = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
        for id in ids { try? api.write(id, json: BTTShortcutBindingService.json(BTTRoadieTriggers.enabledFields(true))) }
        try? FileManager.default.removeItem(at: file)
    }

    nonisolated private func rebuildIndex() {
        guard let json = try? api.list() else { return }
        var index: [BarKeyCombo: [String]] = [:]
        for trigger in BTTRoadieTriggers.parse(json) where trigger.enabled { index[trigger.combo, default: []].append(trigger.id) }
        self.index = index
    }
}
