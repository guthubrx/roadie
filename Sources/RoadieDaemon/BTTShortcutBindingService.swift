import Foundation
import CoreGraphics
import RoadieCore

struct BTTBinding: Equatable, Sendable {
    var profileID: String
    var name: String
    var hotkey: String
    var source: String
    var enabled: Bool
    var forwardID = ""
    var reverseID = ""
}

struct BTTMutation: Sendable {
    var binding: BTTBinding
    var previous: [String: String] = [:]
    var created: [String] = []
}

enum BTTBindingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

protocol BTTShortcutAPI: Sendable {
    func list() throws -> String
    func read(_ uuid: String) throws -> String
    func write(_ uuid: String, json: String) throws
    func create(json: String) throws -> String
    func delete(_ uuid: String) throws
}

/// Frontière AppleScript. Aucune écriture SQL, aucun shell pour appeler l'API.
struct BTTAppleScriptAPI: BTTShortcutAPI {
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func call(_ command: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "if application \"BetterTouchTool\" is not running then error \"" + tr("BetterTouchTool doit être ouvert.", "BetterTouchTool must be open.") + "\"\nwith timeout of 6 seconds\ntell application \"BetterTouchTool\"\n" + command + "\nend tell\nend timeout"]
        let output = Pipe(), error = Pipe()
        task.standardOutput = output
        task.standardError = error
        try task.run()
        // Vider stdout avant waitUntilExit pour éviter un pipe plein.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else { throw BTTBindingError.message(message.isEmpty ? tr("BetterTouchTool ne répond pas.", "BetterTouchTool is not responding.") : message) }
        return (String(data: outputData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func list() throws -> String {
        try call("get_triggers trigger_type \"BTTTriggerTypeKeyboardShortcut\" trigger_app_bundle_identifier \"BT.G\"")
    }
    func read(_ uuid: String) throws -> String { try call("get_trigger " + Self.quoted(uuid)) }

    private func payloadCall(_ json: String, command: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-btt-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try call("set payload to read POSIX file " + Self.quoted(url.path) + " as «class utf8»\n" + command)
    }
    func write(_ uuid: String, json: String) throws {
        _ = try payloadCall(json, command: "update_trigger " + Self.quoted(uuid) + " json payload")
    }
    func create(json: String) throws -> String {
        let response = try payloadCall(json, command: "add_new_trigger payload")
        if let value = try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: String],
           let id = value["BTTUUID"] ?? value["newTrigger"] ?? value["uuid"] { return id }
        let id = response.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard UUID(uuidString: id) != nil else { throw BTTBindingError.message(tr("BTT n'a pas fourni l'identifiant du raccourci.", "BTT did not return the shortcut identifier.")) }
        return id
    }
    func delete(_ uuid: String) throws { _ = try call("delete_trigger " + Self.quoted(uuid)) }
}

struct BTTShortcutBindingService: Sendable {
    var api: any BTTShortcutAPI = BTTAppleScriptAPI()
    var executable = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/roadie").path

    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    func command(profile: String, hold: String, backwards: Bool) -> String {
        Self.shellQuote(executable) + " switcher cycle --profile " + Self.shellQuote(profile)
            + " --hold " + Self.shellQuote(hold) + (backwards ? " --backwards" : "")
    }

    static func dictionary(_ json: String) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw BTTBindingError.message(tr("Réponse BTT illisible.", "Unreadable BTT response."))
        }
        return value
    }
    static func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    func payload(_ binding: BTTBinding, backwards: Bool, layout: [UInt32: String], enabled: Bool) throws -> String {
        guard var key = WindowSwitcherHotkey.parse(binding.hotkey, layout: layout) else {
            throw BTTBindingError.message(tr("Enregistrez une combinaison avant de connecter BTT.", "Record a key combination before connecting BTT."))
        }
        let hold = key.modifiers.map(\.rawValue).sorted().joined(separator: "+")
        if backwards { key.modifiers.insert(.shift) }
        var flags: UInt64 = 0
        if key.modifiers.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
        if key.modifiers.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if key.modifiers.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
        if key.modifiers.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
        let script = command(profile: binding.profileID, hold: hold, backwards: backwards)
        return try Self.json([
            "BTTTriggerType": 0, "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut",
            "BTTPredefinedActionType": 206, "BTTShellTaskActionScript": script,
            "BTTShellTaskActionConfig": "/bin/bash:::-c:::-:::",
            "BTTShortcutKeyCode": key.keyCode, "BTTShortcutModifierKeys": flags,
            "BTTShortcutAdvancedModifierKeys": String(flags), "BTTAdditionalConfiguration": String(flags),
            "BTTLayoutIndependentChar": key.keyCode == 48 ? "\t" : (layout[key.keyCode] ?? ""),
            "BTTAutoAdaptToKeyboardLayout": 0, "BTTTriggerOnDown": 1,
            "BTTEnabled": enabled ? 1 : 0, "BTTEnabled2": enabled ? 1 : 0,
            "BTTAppBundleIdentifier": "BT.G",
            "BTTNotes": "Roadie - " + binding.name + (backwards ? " (inverse)" : "")
        ])
    }

    /// L'import exige une action CLI exacte et un candidat unique, jamais un nom approchant.
    func legacy(_ binding: BTTBinding) throws -> BTTBinding {
        guard binding.profileID == "all", binding.forwardID.isEmpty, binding.reverseID.isEmpty else { return binding }
        let root = try JSONSerialization.jsonObject(with: Data(api.list().utf8))
        var nodes: [String: [String: Any]] = [:]
        func visit(_ item: Any) {
            if let value = item as? [String: Any] {
                if let id = value["BTTUUID"] as? String { nodes[id] = value }
                for child in value.values where child is [Any] || child is [String: Any] { visit(child) }
            } else if let array = item as? [Any] { array.forEach(visit) }
        }
        visit(root)
        let base = executable + " switcher cycle --hold cmd"
        let forwards = nodes.filter { $0.value["BTTShellTaskActionScript"] as? String == base }
        let backwards = nodes.filter { $0.value["BTTShellTaskActionScript"] as? String == base + " --backwards" }
        if forwards.isEmpty && backwards.isEmpty { return binding }
        guard forwards.count == 1, backwards.count == 1,
              let a = forwards.first, let b = backwards.first,
              let code = a.value["BTTShortcutKeyCode"] as? UInt32,
              let flags = a.value["BTTShortcutModifierKeys"] as? UInt else {
            throw BTTBindingError.message(tr("Plusieurs liaisons BTT possibles. Conservez le gestionnaire externe et vérifiez BTT.", "Several possible BTT bindings. Keep the external handler and check BTT."))
        }
        let recorded = ShortcutCapture.value(keyCode: code, modifiers: .init(rawValue: flags), layout: [:]) ?? ""
        guard binding.hotkey.isEmpty || WindowSwitcherHotkey.parse(binding.hotkey, layout: [:]) == WindowSwitcherHotkey.parse(recorded, layout: [:]) else {
            throw BTTBindingError.message(tr("Le raccourci BTT existant diffère. Associez-le avant de le changer.", "The existing BTT shortcut differs. Link it before changing it."))
        }
        var result = binding
        result.forwardID = a.key
        result.reverseID = b.key
        if result.hotkey.isEmpty { result.hotkey = recorded }
        return result
    }

    private func owns(_ script: String?, profile: String, backwards: Bool) -> Bool {
        guard let script else { return false }
        let modifiers = WindowSwitcherModifier.allCases
        for bits in 1..<(1 << modifiers.count) {
            let hold = modifiers.enumerated().compactMap { bits & (1 << $0.offset) == 0 ? nil : $0.element.rawValue }.sorted().joined(separator: "+")
            if script == command(profile: profile, hold: hold, backwards: backwards) { return true }
        }
        return profile == "all" && script == executable + " switcher cycle --hold cmd" + (backwards ? " --backwards" : "")
    }

    func prepare(old: BTTBinding, new: BTTBinding, layout: [UInt32: String]) throws -> BTTMutation {
        var result = BTTMutation(binding: new)
        do {
            var known = old
            if old.source == "btt" || new.source == "btt" || (old.source == "external" && new.source == "roadie") {
                known = try legacy(old)
            }
            result.binding.forwardID = known.forwardID
            result.binding.reverseID = known.reverseID
            if old.source == "external", old.hotkey.isEmpty, result.binding.hotkey.isEmpty, new.source != "external" {
                result.binding.hotkey = known.hotkey
            }
            for (index, id) in [known.forwardID, known.reverseID].enumerated() where !id.isEmpty {
                let snapshot = try api.read(id)
                let script = try Self.dictionary(snapshot)["BTTShellTaskActionScript"] as? String
                guard owns(script, profile: known.profileID, backwards: index == 1) else {
                    throw BTTBindingError.message(tr("La liaison BTT enregistrée a changé. Aucune entrée retirée.", "The saved BTT binding changed. No entry removed."))
                }
                result.previous[id] = snapshot
                try api.write(id, json: Self.json(["BTTEnabled": 0, "BTTEnabled2": 0]))
            }
            if new.source == "btt", new.enabled, !result.binding.hotkey.isEmpty {
                let variants = WindowSwitcherHotkey.parse(result.binding.hotkey, layout: layout)?.modifiers.contains(.shift) == true ? [false] : [false, true]
                for reverse in variants {
                    let existing = reverse ? result.binding.reverseID : result.binding.forwardID
                    let payload = try payload(result.binding, backwards: reverse, layout: layout, enabled: false)
                    let id: String
                    if existing.isEmpty {
                        let requested = UUID().uuidString
                        var fields = try Self.dictionary(payload)
                        fields["BTTUUID"] = requested
                        result.created.append(requested)
                        id = try api.create(json: Self.json(fields))
                        guard id == requested else {
                            result.created.append(id)
                            throw BTTBindingError.message(tr("Identifiant BTT inattendu. La création a été annulée.", "Unexpected BTT identifier. Creation was cancelled."))
                        }
                    } else { id = existing; try api.write(id, json: payload) }
                    if reverse { result.binding.reverseID = id } else { result.binding.forwardID = id }
                    let actual = try Self.dictionary(api.read(id)), expected = try Self.dictionary(payload)
                    guard actual["BTTShellTaskActionScript"] as? String == expected["BTTShellTaskActionScript"] as? String,
                          actual["BTTShortcutKeyCode"] as? UInt32 == expected["BTTShortcutKeyCode"] as? UInt32 else {
                        throw BTTBindingError.message(tr("La relecture du raccourci BTT a échoué.", "Reading back the BTT shortcut failed."))
                    }
                }
            }
            return result
        } catch {
            let initial = error
            do { try rollback(result) }
            catch { throw BTTBindingError.message(initial.localizedDescription + tr(" Retour arrière : ", " Rollback: ") + error.localizedDescription) }
            throw initial
        }
    }

    func activate(_ mutation: BTTMutation) throws {
        let value = mutation.binding
        guard value.source == "btt", value.enabled, !value.hotkey.isEmpty else { return }
        let hasShift = value.hotkey.split(separator: "+").contains("shift")
        for id in (hasShift ? [value.forwardID] : [value.forwardID, value.reverseID]) where !id.isEmpty {
            try api.write(id, json: Self.json(["BTTEnabled": 1, "BTTEnabled2": 1]))
            let actual = try Self.dictionary(api.read(id))
            // BTT omet les deux champs lorsqu'ils valent 1 (relecture native du 23/10/2026).
            // Exiger l'identité empêche une réponse vide d'être prise pour une activation.
            guard actual["BTTUUID"] as? String == id,
                  (actual["BTTEnabled"] as? Int ?? 1) == 1, (actual["BTTEnabled2"] as? Int ?? 1) == 1 else {
                throw BTTBindingError.message(tr("BTT n'a pas activé la liaison.", "BTT did not turn on the binding."))
            }
        }
    }

    /// Retire seulement les liaisons reconnues et désactivées par prepare. O(k), k <= 2.
    func discard(_ mutation: BTTMutation) throws {
        for id in mutation.previous.keys {
            let actual = try Self.dictionary(api.read(id))
            let reverse = id == mutation.binding.reverseID
            guard owns(actual["BTTShellTaskActionScript"] as? String, profile: mutation.binding.profileID, backwards: reverse),
                  actual["BTTEnabled"] as? Int == 0, actual["BTTEnabled2"] as? Int == 0 else {
                throw BTTBindingError.message(tr("La liaison BTT a changé ; elle n'a pas été supprimée.", "The BTT binding changed; it was not deleted."))
            }
            try api.delete(id)
        }
    }

    func rollback(_ mutation: BTTMutation) throws {
        var failures: [String] = []
        for id in mutation.created {
            do {
                let actual = try api.read(id)
                if actual.isEmpty || actual == "null" || actual == "{}" { continue }
                try api.delete(id)
            } catch { failures.append(error.localizedDescription) }
        }
        for (id, snapshot) in mutation.previous {
            do { try api.write(id, json: snapshot) } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { throw BTTBindingError.message(tr("Restauration BTT incomplète : ", "Incomplete BTT restore: ") + failures.joined(separator: " ; ")) }
    }
}

