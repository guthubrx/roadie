import AppKit
import RoadieCore
import SwiftUI

// Catégorie Raccourcis (session 108) : conflits avec BetterTouchTool et commandes Roadie, chacune avec sa
// combinaison et son gestionnaire. Règles pures d'abord, vues ensuite.

/// Touche de Roadie en conflit avec un raccourci BTT actif de même combinaison.
struct ShortcutConflict: Identifiable, Equatable {
    let roadieID: String
    let label: String
    let keys: String
    /// Touche de la barre : la pause de BTT pendant la barre résout le conflit.
    let isBar: Bool
    let trigger: BTTKeyboardTrigger
    var id: String { roadieID + "|" + trigger.id }
}

/// Touche réglée dans Roadie, avec son nom affiché.
struct RoadieKey: Equatable {
    let id: String
    let label: String
    let keys: String
    let isBar: Bool
}

enum ShortcutConflicts {
    /// O(t + r) : index des raccourcis BTT actifs par combinaison, puis une recherche par touche.
    static func find(_ keys: [RoadieKey], triggers: [BTTKeyboardTrigger], layout: [UInt32: String]) -> [ShortcutConflict] {
        var index: [BarKeyCombo: [BTTKeyboardTrigger]] = [:]
        for trigger in triggers where trigger.enabled { index[trigger.combo, default: []].append(trigger) }
        return keys.flatMap { key -> [ShortcutConflict] in
            guard let resolved = SearchInputPanel.cycleKey(key.keys, layout: layout) else { return [] }
            return (index[BarKeyCombo(keyCode: resolved.keyCode, flags: resolved.flags)] ?? []).map {
                ShortcutConflict(roadieID: key.id, label: key.label, keys: key.keys, isBar: key.isBar, trigger: $0)
            }
        }
    }
}

/// Ligne de la liste des commandes : raccourci BTT, entrée `[[shortcuts]]`, ou les deux quand Roadie a
/// repris un raccourci BTT (`btt_uuid`).
struct CommandShortcutRow: Identifiable, Equatable {
    enum Manager: String, CaseIterable { case btt, roadie, off }
    struct Entry: Equatable {
        let rowID: UUID
        let keys: String
        let command: String
        let enabled: Bool
        let bttUUID: String
    }

    let command: String
    let keys: String
    let manager: Manager
    let group: String
    let trigger: BTTKeyboardTrigger?
    let entry: Entry?
    var id: String { trigger.map { "btt:" + $0.id } ?? "roadie:" + (entry?.rowID.uuidString ?? command) }

    /// Raccourcis BTT des commandes Roadie, puis entrées de Roadie seules. Roadie l'emporte quand son entrée
    /// est active ; sinon l'état du raccourci BTT. O(t + e).
    static func rows(triggers: [BTTKeyboardTrigger], entries: [Entry], layout: [UInt32: String]) -> [CommandShortcutRow] {
        var byUUID: [String: Entry] = [:]
        for entry in entries where !entry.bttUUID.isEmpty { byUUID[entry.bttUUID] = entry }
        var used: Set<UUID> = []
        var result: [CommandShortcutRow] = []
        for trigger in triggers where !trigger.command.isEmpty {
            let entry = byUUID[trigger.id]
            if let entry { used.insert(entry.rowID) }
            let manager: Manager = entry?.enabled == true ? .roadie : (trigger.enabled ? .btt : .off)
            let keys = manager == .roadie ? entry?.keys ?? "" : trigger.keys(layout: layout)
            result.append(CommandShortcutRow(command: trigger.command, keys: keys, manager: manager,
                                             group: trigger.group.isEmpty ? "BetterTouchTool" : trigger.group, trigger: trigger, entry: entry))
        }
        for entry in entries where !used.contains(entry.rowID) {
            result.append(CommandShortcutRow(command: entry.command, keys: entry.keys, manager: entry.enabled ? .roadie : .off,
                                             group: tr("Ajoutés dans Roadie", "Added in Roadie"), trigger: nil, entry: entry))
        }
        return result
    }
}

/// Raccourcis clavier globaux de BTT, relus à l'ouverture de la catégorie et après chaque changement.
@MainActor
final class BTTTriggerCatalog: ObservableObject {
    static let shared = BTTTriggerCatalog()
    enum State: Equatable { case notInstalled, notRunning, loading, loaded, failed(String) }
    @Published var triggers: [BTTKeyboardTrigger] = []
    @Published var state: State = .loading
    let api: any BTTShortcutAPI = BTTAppleScriptAPI()

    func reload() {
        // Les tests ne lisent jamais la vraie configuration BTT.
        guard !TestEnvironment.isRunningTests else { return }
        guard BTTRoadieTriggers.isInstalled else { state = .notInstalled; triggers = []; return }
        guard BTTRoadieTriggers.isRunning else { state = .notRunning; triggers = []; return }
        if triggers.isEmpty { state = .loading }
        let api = api
        Task {
            do {
                let json = try await Task.detached { try api.list() }.value
                triggers = BTTRoadieTriggers.parse(json)
                state = .loaded
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    /// Écrit des champs sur un raccourci, puis relit la liste. O(1) appel AppleScript.
    func write(_ id: String, _ fields: [String: Any]) async throws {
        let json = try BTTShortcutBindingService.json(fields)
        let api = api
        try await Task.detached { try api.write(id, json: json) }.value
        reload()
    }

    func create(_ fields: [String: Any]) async throws {
        let json = try BTTShortcutBindingService.json(fields)
        let api = api
        _ = try await Task.detached { try api.create(json: json) }.value
        reload()
    }
}

private func managerLabel(_ manager: CommandShortcutRow.Manager) -> String {
    switch manager {
    case .btt: "BetterTouchTool"
    case .roadie: "Roadie"
    case .off: tr("Personne (désactivé)", "Nobody (off)")
    }
}

/// Conflits entre les touches de Roadie et BTT ; une touche de la barre peut passer avant BTT.
@MainActor
struct SettingsShortcutConflictsView: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    @ObservedObject private var catalog = BTTTriggerCatalog.shared
    @StateObject private var paused: SettingsCollectionEditorModel
    private var fonts: InterfaceConfig { model.interfaceFonts }

    init(model: SettingsViewModel, descriptor: SettingDescriptor) {
        self.model = model
        self.descriptor = descriptor
        _paused = StateObject(wrappedValue: SettingsCollectionEditorModel(descriptor: descriptor, service: model.service))
    }

    private var roadieKeys: [RoadieKey] {
        SettingsCatalog.descriptors(in: .raccourcis).compactMap { descriptor in
            guard descriptor.collection == nil, descriptor.kind == .text, !descriptor.id.hasPrefix("target_grid.") else { return nil }
            let keys = model.text(for: descriptor)
            guard !keys.isEmpty else { return nil }
            let isBar = descriptor.id.hasPrefix("target_mode.") && !["target_mode.search_hotkey", "target_mode.actions_hotkey"].contains(descriptor.id)
            return RoadieKey(id: descriptor.id, label: descriptor.label, keys: keys, isBar: isBar)
        }
    }

    private func isPaused(_ keys: String) -> Bool { paused.items.contains { $0.raw == keys } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch catalog.state {
            case .notInstalled:
                Text(tr("BetterTouchTool n'est pas installé : aucun conflit possible avec lui.", "BetterTouchTool is not installed: no conflict with it is possible.")).foregroundStyle(.secondary)
            case .notRunning:
                Text(tr("Ouvrez BetterTouchTool pour vérifier les conflits avec ses raccourcis.", "Open BetterTouchTool to check for conflicts with its shortcuts.")).foregroundStyle(.secondary)
            case .loading:
                ProgressView(tr("Lecture des raccourcis BetterTouchTool…", "Reading BetterTouchTool shortcuts…")).controlSize(.small)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            case .loaded:
                let conflicts = ShortcutConflicts.find(roadieKeys, triggers: catalog.triggers, layout: TargetSearchHotkey.currentLayoutTable())
                if conflicts.isEmpty { Text(tr("Aucune touche de Roadie n'est prise par BetterTouchTool.", "No Roadie key is taken by BetterTouchTool.")).foregroundStyle(.secondary) }
                ForEach(conflicts) { conflict in conflictRow(conflict) }
            }
            let stale = paused.items.filter { item in !roadieKeys.contains { $0.isBar && $0.keys == item.raw } }
            if !stale.isEmpty {
                Text(tr("Touches en pause qui ne sont plus utilisées par la barre :", "Paused keys no longer used by the bar:")).font(.system(size: fonts.settingsHelpFontSize))
                ForEach(stale) { item in
                    HStack {
                        Text(ShortcutCapture.label(item.raw))
                        Button(tr("Retirer", "Remove")) { paused.removeItem(item.id) }
                    }
                }
            }
            ForEach(Array(paused.messages.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.red) }
        }
        .font(.system(size: fonts.settingsTextFontSize))
        .onAppear { catalog.reload() }
        .onChange(of: model.collectionRevision) { _, _ in paused.reload() }
    }

    private func conflictRow(_ conflict: ShortcutConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: conflict.isBar && isPaused(conflict.keys) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(conflict.isBar && isPaused(conflict.keys) ? .green : .orange)
                Text(ShortcutCapture.label(conflict.keys)).fontWeight(.semibold)
                Text(conflict.label + (conflict.isBar ? tr(" (barre)", " (bar)") : ""))
            }
            Text(tr("BetterTouchTool : ", "BetterTouchTool: ") + (conflict.trigger.command.isEmpty ? tr("autre action", "other action") : "roadie " + conflict.trigger.command)
                 + (conflict.trigger.group.isEmpty ? "" : " · " + conflict.trigger.group))
                .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            if conflict.isBar {
                Toggle(tr("BetterTouchTool en pause tant que la barre est ouverte", "BetterTouchTool paused while the bar is open"), isOn: Binding(
                    get: { isPaused(conflict.keys) },
                    set: { paused.setSide(conflict.keys, enabled: $0) }))
                .toggleStyle(.switch)
            }
            Text(conflict.isBar ? tr("Ou changez la touche de la barre plus haut.", "Or change the bar key above.") : tr("Changez la touche de Roadie plus haut, ou celle de BetterTouchTool plus bas.", "Change the Roadie key above, or the BetterTouchTool one below."))
                .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
    }
}

/// Commandes Roadie : raccourcis BTT qui lancent `roadie …` et entrées `[[shortcuts]]`, chacune avec sa
/// combinaison et son gestionnaire. En tête, les profils du sélecteur.
@MainActor
struct SettingsCommandShortcutsView: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    @ObservedObject private var catalog = BTTTriggerCatalog.shared
    @StateObject private var editor: SettingsCollectionEditorModel
    @State private var filter = ""
    @State private var newCommand = ""
    @State private var newKeys = ""
    @State private var message = ""
    @State private var busy = false
    private var fonts: InterfaceConfig { model.interfaceFonts }

    init(model: SettingsViewModel, descriptor: SettingDescriptor) {
        self.model = model
        self.descriptor = descriptor
        _editor = StateObject(wrappedValue: SettingsCollectionEditorModel(descriptor: descriptor, service: model.service))
    }

    private var entries: [CommandShortcutRow.Entry] {
        editor.rows.map { row in
            CommandShortcutRow.Entry(rowID: row.id, keys: row.raw["keys"] ?? "", command: row.raw["command"] ?? "",
                                     enabled: row.raw["enabled"] != "false", bttUUID: row.raw["btt_uuid"] ?? "")
        }
    }

    /// Filtre : texte du champ, ou recherche des paramètres quand elle ne vise pas la catégorie elle-même.
    private var visibleRows: [CommandShortcutRow] {
        let all = CommandShortcutRow.rows(triggers: catalog.triggers, entries: entries, layout: TargetSearchHotkey.currentLayoutTable())
        func matching(_ text: String) -> [CommandShortcutRow] {
            let words = TargetHintService.normalized(text).split(separator: " ").map(String.init)
            return all.filter { row in
                let haystack = TargetHintService.normalized(row.command + " " + row.group + " " + ShortcutCapture.label(row.keys))
                return words.allSatisfy(haystack.contains)
            }
        }
        if !filter.trimmingCharacters(in: .whitespaces).isEmpty { return matching(filter) }
        // Recherche des paramètres (session 107) : « focus right » montre ses lignes ; « raccourci » montre tout.
        if model.isSearching {
            let found = matching(model.query)
            return found.isEmpty ? all : found
        }
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let switcher = SettingsCatalog.find(id: "switcher.shortcuts") {
                Text(tr("Sélecteur de fenêtres", "Window switcher")).fontWeight(.semibold)
                SettingsSwitcherProfilesView(model: model, descriptor: switcher, shortcutsOnly: true)
                Divider()
            }
            switch catalog.state {
            case .notRunning: Text(tr("Ouvrez BetterTouchTool pour voir et régler ses raccourcis ici.", "Open BetterTouchTool to see and set its shortcuts here.")).foregroundStyle(.orange)
            case .failed(let text): Text(text).foregroundStyle(.red)
            case .loading: ProgressView(tr("Lecture des raccourcis BetterTouchTool…", "Reading BetterTouchTool shortcuts…")).controlSize(.small)
            case .notInstalled, .loaded: EmptyView()
            }
            TextField(tr("Filtrer les commandes (focus, stage, ⌘L…)", "Filter commands (focus, stage, ⌘L…)"), text: $filter).textFieldStyle(.roundedBorder)
            Text(tr("Chaque ligne lance « roadie » suivi de la commande. Roadie : il enregistre la combinaison lui-même et le raccourci BTT est désactivé.", "Each row runs “roadie” followed by the command. Roadie: it registers the key combination itself and the BTT shortcut is turned off."))
                .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            let rows = visibleRows
            let groups = Dictionary(grouping: rows, by: \.group)
            // Dossiers BTT dans leur ordre (« 1 - Fenêtres » d'abord), ajouts de Roadie à la fin.
            let order = groups.keys.sorted { ($0 == tr("Ajoutés dans Roadie", "Added in Roadie") ? 1 : 0, $0) < ($1 == tr("Ajoutés dans Roadie", "Added in Roadie") ? 1 : 0, $1) }
            ForEach(order, id: \.self) { group in
                Text(group).font(.system(size: fonts.settingsHelpFontSize, weight: .semibold)).foregroundStyle(.secondary)
                ForEach((groups[group] ?? []).sorted { $0.command.localizedStandardCompare($1.command) == .orderedAscending }) { row in commandRow(row) }
            }
            if rows.isEmpty { Text(filter.isEmpty ? tr("Aucune commande pour l'instant.", "No commands yet.") : tr("Aucune commande ne correspond.", "No matching command.")).foregroundStyle(.secondary) }
            Divider()
            Text(tr("Nouveau raccourci géré par Roadie", "New shortcut handled by Roadie")).fontWeight(.semibold)
            HStack(spacing: 8) {
                Text("roadie").font(.system(size: fonts.settingsTextFontSize, design: .monospaced))
                TextField("focus right", text: $newCommand).textFieldStyle(.roundedBorder)
                ShortcutRecorderControl(value: newKeys, fontSize: fonts.settingsTextFontSize) { newKeys = $0 }
                Button(tr("Ajouter", "Add")) { add() }.disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty || newKeys.isEmpty)
            }
            if busy { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).foregroundStyle(.orange).font(.system(size: fonts.settingsHelpFontSize)) }
            ForEach(Array(editor.messages.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.red) }
        }
        .font(.system(size: fonts.settingsTextFontSize))
        .disabled(busy)
        .onAppear { catalog.reload() }
        .onChange(of: model.collectionRevision) { _, _ in editor.reload() }
    }

    /// Trois colonnes de même largeur d'une ligne à l'autre : commande, combinaison, gestionnaire.
    private func commandRow(_ row: CommandShortcutRow) -> some View {
        HStack(spacing: 10) {
            Text(row.command).font(.system(size: fonts.settingsHelpFontSize, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("roadie " + row.command)
            ShortcutRecorderControl(value: row.keys, fontSize: fonts.settingsTextFontSize) { setKeys(row, $0) }
                .frame(width: max(200, fonts.settingsTextFontSize * 13))
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: tr("Pris en charge par", "Handled by"),
                options: CommandShortcutRow.Manager.allCases.filter { $0 != .btt || BTTRoadieTriggers.isInstalled }.map { ($0.rawValue, managerLabel($0)) },
                selection: Binding(get: { row.manager.rawValue }, set: { setManager(row, CommandShortcutRow.Manager(rawValue: $0) ?? row.manager) }))
                .frame(width: max(190, fonts.settingsTextFontSize * 12))
            Group {
                if row.trigger == nil, let entry = row.entry {
                    Button(tr("Supprimer", "Delete"), systemImage: "trash") { editor.removeRow(entry.rowID) }.labelStyle(.iconOnly)
                } else { Color.clear }
            }
            .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Changements

    private func run(_ success: String, _ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        message = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await work(); message = success } catch { message = error.localizedDescription }
        }
    }

    private func setKeys(_ row: CommandShortcutRow, _ keys: String) {
        let layout = TargetSearchHotkey.currentLayoutTable()
        run(tr("Combinaison enregistrée. Essayez-la au clavier.", "Key combination saved. Try it on the keyboard.")) {
            if let entry = row.entry, row.manager == .roadie || row.trigger == nil {
                guard editor.updateRow(entry.rowID, values: ["keys": keys]) else { throw BTTBindingError.message(tr("La combinaison n'a pas été enregistrée.", "The key combination was not saved.")) }
            } else if let trigger = row.trigger {
                guard let fields = BTTRoadieTriggers.fields(keys: keys, layout: layout) else {
                    throw BTTBindingError.message(tr("BetterTouchTool a besoin d'une combinaison avec ⌘, ⌃ ou ⌥.", "BetterTouchTool needs a combination with ⌘, ⌃ or ⌥."))
                }
                try await catalog.write(trigger.id, fields)
            }
        }
    }

    private func setManager(_ row: CommandShortcutRow, _ manager: CommandShortcutRow.Manager) {
        guard manager != row.manager else { return }
        let layout = TargetSearchHotkey.currentLayoutTable()
        run(manager == .btt ? tr("BetterTouchTool prend ce raccourci.", "BetterTouchTool takes this shortcut.") : manager == .roadie ? tr("Roadie prend ce raccourci.", "Roadie takes this shortcut.") : tr("Raccourci désactivé.", "Shortcut off.")) {
            switch manager {
            case .roadie:
                // Roadie d'abord, puis BTT désactivé : la combinaison ne reste jamais sans gestionnaire.
                if let entry = row.entry {
                    guard editor.updateRow(entry.rowID, values: ["enabled": "true", "keys": row.keys]) else { throw BTTBindingError.message(tr("Roadie n'a pas pu enregistrer ce raccourci.", "Roadie could not register this shortcut.")) }
                } else {
                    guard editor.addRow(values: ["keys": row.keys, "command": row.command, "enabled": "true", "btt_uuid": row.trigger?.id ?? ""]) != nil else {
                        throw BTTBindingError.message(tr("Roadie n'a pas pu enregistrer ce raccourci.", "Roadie could not register this shortcut."))
                    }
                }
                if let trigger = row.trigger, trigger.enabled { try await catalog.write(trigger.id, BTTRoadieTriggers.enabledFields(false)) }
            case .btt:
                if let trigger = row.trigger {
                    var fields = BTTRoadieTriggers.enabledFields(true)
                    if let keys = BTTRoadieTriggers.fields(keys: row.keys, layout: layout) { fields.merge(keys) { _, new in new } }
                    try await catalog.write(trigger.id, fields)
                } else {
                    guard let fields = BTTRoadieTriggers.newTrigger(command: row.command, keys: row.keys, layout: layout) else {
                        throw BTTBindingError.message(tr("Enregistrez d'abord une combinaison avec ⌘, ⌃ ou ⌥.", "First record a combination with ⌘, ⌃ or ⌥."))
                    }
                    try await catalog.create(fields)
                }
                if let entry = row.entry { editor.removeRow(entry.rowID) }
            case .off:
                if let trigger = row.trigger, trigger.enabled { try await catalog.write(trigger.id, BTTRoadieTriggers.enabledFields(false)) }
                if let entry = row.entry {
                    if row.trigger != nil { editor.removeRow(entry.rowID) } else { editor.updateRow(entry.rowID, values: ["enabled": "false"]) }
                }
            }
        }
    }

    private func add() {
        let command = newCommand.trimmingCharacters(in: .whitespaces)
        guard editor.addRow(values: ["keys": newKeys, "command": command, "enabled": "true", "btt_uuid": ""]) != nil else { return }
        newCommand = ""
        newKeys = ""
        message = tr("Raccourci ajouté. Roadie l'enregistre tout de suite.", "Shortcut added. Roadie registers it right away.")
    }
}
