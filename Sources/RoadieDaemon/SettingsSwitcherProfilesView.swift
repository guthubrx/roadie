import SwiftUI
import RoadieCore

@MainActor
struct SettingsSwitcherProfilesView: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    /// Catégorie Raccourcis (session 108) : seulement le gestionnaire et la combinaison de chaque profil.
    let shortcutsOnly: Bool
    @StateObject private var editor: SettingsCollectionEditorModel
    @State private var selectedID: UUID?
    @State private var tab = tr("Raccourci", "Shortcut")
    @State private var busy = false
    @State private var message = ""
    private var fonts: InterfaceConfig { model.interfaceFonts }

    init(model: SettingsViewModel, descriptor: SettingDescriptor, shortcutsOnly: Bool = false) {
        self.model = model
        self.descriptor = descriptor
        self.shortcutsOnly = shortcutsOnly
        _editor = StateObject(wrappedValue: SettingsCollectionEditorModel(descriptor: descriptor, service: model.service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shortcutsOnly {
                ForEach(editor.rows) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.raw["name"] ?? tr("Profil", "Profile")).fontWeight(.semibold)
                        shortcutRows(row)
                    }
                }
            } else {
                profilesBody
            }
            if busy { ProgressView(tr("Vérification du raccourci…", "Checking the shortcut…")).controlSize(.small) }
            if !message.isEmpty { Text(message).foregroundStyle(.orange).font(.system(size: fonts.settingsHelpFontSize)) }
            ForEach(Array(editor.messages.enumerated()), id: \.offset) { _, value in
                Text(value).foregroundStyle(.red).font(.system(size: fonts.settingsHelpFontSize))
            }
            if !editor.messages.isEmpty {
                Button(tr("Recharger les profils", "Reload profiles")) { editor.reload(discardDrafts: true) }
            }
        }
        .disabled(busy || model.isLocked)
        .onAppear {
            selectedID = selectedID ?? editor.rows.first?.id
            editor.onChange = { model.collectionChanged(descriptor, result: $0) }
        }
        .onChange(of: model.collectionRevision) { _, _ in editor.reload() }
        .onChange(of: model.collectionResetRevisions[descriptor.id]) { _, _ in editor.reload(discardDrafts: true) }
    }

    @ViewBuilder
    private func shortcutRows(_ row: SettingsCollectionEditorModel.Row) -> some View {
        SettingsFormRow(tr("Géré par", "Handled by"), help: tr("Roadie enregistre le raccourci directement. BetterTouchTool utilise une liaison vérifiée. Le mode externe conserve les commandes BTT ou Karabiner existantes.", "Roadie registers the shortcut directly. BetterTouchTool uses a verified binding. External mode keeps the existing BTT or Karabiner commands."), fonts: fonts) {
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: tr("Gestionnaire", "Handler"),
                options: [("roadie", "Roadie"), ("btt", "BetterTouchTool"), ("external", tr("Outil externe / commande", "External tool / command"))],
                selection: Binding(get: { source(row) }, set: { change(row, values: ["trigger_source": $0]) }))
        }
        SettingsFormRow(tr("Combinaison", "Key combination"), help: tr("Cliquez sur Enregistrer, puis appuyez sur les touches. Échap annule la capture.", "Click Record, then press the keys. Esc cancels the capture."), fonts: fonts) {
            ShortcutRecorderControl(value: row.raw["hotkey"] ?? "", fontSize: fonts.settingsTextFontSize) { value in
                change(row, values: ["hotkey": value, "trigger_source": source(row) == "external" ? "roadie" : source(row)])
            }
        }
    }

    @ViewBuilder
    private var profilesBody: some View {
            if editor.rows.count > 1 { ForEach(editor.rows) { row in
                Button { selectedID = row.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.raw["name"] ?? tr("Profil", "Profile")).fontWeight(.semibold).lineLimit(1)
                            Text(summary(row)).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((row.raw["hotkey"] ?? "").isEmpty ? (source(row) == "external" ? tr("Commande externe", "External command") : tr("À définir", "To be set")) : ShortcutCapture.label(row.raw["hotkey"] ?? ""))
                            .font(.system(size: fonts.settingsHelpFontSize)).lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedID == row.id ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selectedID == row.id ? 2 : 1))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedID == row.id ? .isSelected : [])
            } }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { profileTools }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { profileTools }
            }
            if let row = editor.rows.first(where: { $0.id == selectedID }) ?? editor.rows.first {
                profileForm(row)
            }
    }

    private func profileForm(_ row: SettingsCollectionEditorModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsFormRow(tr("Nom du profil", "Profile name"), fonts: fonts) {
                TextField(tr("Nom du profil", "Profile name"), text: binding(row, "name")).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(tr("Nom du profil", "Profile name"))
            }
            SettingsFormRow(tr("Profil actif", "Profile on"), fonts: fonts) {
                Toggle(tr("Profil actif", "Profile on"), isOn: Binding(get: { row.raw["enabled"] != "false" },
                    set: { change(row, values: ["enabled": $0 ? "true" : "false"]) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            profileTabs.padding(.vertical, 10)
            if tab == tr("Raccourci", "Shortcut") {
                // Combinaison et gestionnaire réunis dans Paramètres > Raccourcis (session 108).
                SettingsFormRow(tr("Combinaison", "Key combination"), help: tr("La combinaison et son gestionnaire se règlent avec les autres raccourcis.", "The key combination and its handler are set with the other shortcuts."), fonts: fonts) {
                    HStack(spacing: 10) {
                        Text((row.raw["hotkey"] ?? "").isEmpty ? tr("Aucune", "None") : ShortcutCapture.label(row.raw["hotkey"] ?? ""))
                        Button(tr("Régler dans Raccourcis", "Set in Shortcuts")) { model.select(.raccourcis) }
                    }
                }
                picker(row, key: "release_action", label: tr("Au relâchement", "On release"),
                       options: [("focus", tr("Activer la fenêtre choisie", "Activate the chosen window")), ("stay", tr("Rester ouvert", "Stay open")), ("search", tr("Passer en recherche", "Switch to search"))],
                       help: modeHelp(row.raw["release_action"] ?? "focus"))
                picker(row, key: "search_visibility", label: tr("Champ de recherche", "Search field"),
                       options: [("auto", tr("Selon le mode", "Depends on mode")), ("always", tr("Toujours visible", "Always visible")), ("never", tr("Masqué", "Hidden"))])
                picker(row, key: "actions_visibility", label: tr("Menu Actions", "Actions menu"),
                       options: [("auto", tr("Selon le mode", "Depends on mode")), ("always", tr("Toujours visible", "Always visible")), ("never", tr("Masqué", "Hidden"))])
                if source(row) == "btt" && (row.raw["btt_forward_uuid"] ?? "").isEmpty {
                    Button(tr("Configurer BTT", "Set up BTT")) { change(row, values: ["trigger_source": "btt"]) }
                }
            } else if tab == tr("Fenêtres", "Windows") {
                picker(row, key: "scope", label: tr("Fenêtres proposées", "Windows offered"), options: [
                    ("all", tr("Toutes les fenêtres", "All windows")), ("stage", tr("Stage actif", "Active stage")), ("desktop", tr("Bureau actif", "Active desktop")),
                    ("display", tr("Écran actif", "Active display")), ("application", tr("Application active", "Active app"))])
                picker(row, key: "sort_order", label: tr("Ordre", "Order"), options: [
                    ("recent", tr("Récentes d'abord", "Recent first")), ("title", tr("Titre", "Title")), ("stage", "Stage")])
                toggle(row, "include_minimized", tr("Fenêtres réduites", "Minimized windows"))
                toggle(row, "include_hidden", tr("Applications masquées", "Hidden apps"))
                toggle(row, "include_fullscreen", tr("Fenêtres plein écran", "Full-screen windows"))
                toggle(row, "one_per_app", tr("Une fenêtre par application", "One window per app"))
            } else if tab == tr("Apparence", "Appearance") {
                picker(row, key: "presentation", label: tr("Organisation", "Layout"),
                       options: [("", tr("Réglage commun", "Shared setting"))] + WindowSwitcherPresentation.allCases.map { ($0.rawValue, $0.label) },
                       help: tr("Regroupe les fenêtres par bureau et stage Roadie. Le style des cartes et l'action au relâchement restent indépendants.", "Groups windows by Roadie desktop and stage. The card style and the release action stay independent."))
                picker(row, key: "style", label: tr("Style", "Style"), options: [("", tr("Réglage commun", "Shared setting")), ("thumbnails", tr("Vignettes", "Thumbnails")), ("icons", tr("Icônes", "Icons")), ("list", tr("Liste compacte", "Compact list"))],
                       help: tr("Un réglage commun suit l'apparence de la catégorie. Une valeur propre à ce profil prend priorité.", "A shared setting follows the category's appearance. A value specific to this profile takes priority."))
                picker(row, key: "preview", label: tr("Grand aperçu", "Large preview"), options: [("", tr("Réglage commun", "Shared setting")), ("true", tr("Afficher", "Show")), ("false", tr("Masquer", "Hide"))])
                picker(row, key: "auto_size", label: tr("Taille automatique", "Automatic size"), options: [("", tr("Réglage commun", "Shared setting")), ("true", tr("Oui", "Yes")), ("false", tr("Non", "No"))])
                number(row, "thumbnail_width", tr("Largeur des vignettes", "Thumbnail width"))
                number(row, "font_size", tr("Taille du texte", "Text size"))
                SettingsFormRow(tr("Police", "Font"), fonts: fonts) {
                    SettingsFontFamilyPicker(fontSize: fonts.settingsTextFontSize, selection: binding(row, "font_family"), inheritedLabel: tr("Réglage commun", "Shared setting"))
                }
                Button(tr("Apparence commune", "Shared appearance")) {
                    _ = editor.updateRow(row.id, values: Dictionary(uniqueKeysWithValues: ["presentation", "style", "preview", "auto_size", "thumbnail_width", "font_size", "font_family"].map { ($0, "") }))
                }
            } else {
                toggle(row, "arrow_navigation", tr("Navigation aux flèches", "Arrow navigation"))
                toggle(row, "mouse_hover", tr("Sélection au survol", "Select on hover"),
                       help: tr("Le survol sélectionne ; le clic active la fenêtre. Un pointeur immobile ne reprend pas la sélection après une flèche. Quand la recherche contient du texte, Gauche/Droite déplacent le curseur dans ce texte.", "Hovering selects; clicking activates the window. A still pointer does not take the selection back after an arrow key. When the search has text, Left/Right move the cursor in that text."))
            }
            if editor.rows.count > 1 {
                Button(tr("Supprimer ce profil", "Delete this profile"), role: .destructive) { remove(row) }
                    .font(.system(size: fonts.settingsHelpFontSize))
            }
        }
        .padding(.vertical, 6)
    }

    private var profileTools: some View {
        Group {
            Button(tr("Nouveau profil", "New profile"), systemImage: "plus") { selectedID = editor.addProfile() }
                .disabled(editor.rows.count >= 9).fixedSize(horizontal: true, vertical: false)
            if let selectedID {
                Button(tr("Dupliquer", "Duplicate"), systemImage: "plus.square.on.square") { self.selectedID = editor.addProfile(copying: selectedID) }
                    .disabled(editor.rows.count >= 9).fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var profileTabs: some View {
        SettingsTabs(values: [tr("Raccourci", "Shortcut"), tr("Fenêtres", "Windows"), tr("Navigation", "Navigation"), tr("Apparence", "Appearance")],
                     selection: $tab, fontSize: fonts.settingsTextFontSize)
    }

    private func binding(_ row: SettingsCollectionEditorModel.Row, _ key: String) -> Binding<String> {
        Binding(get: { editor.rows.first(where: { $0.id == row.id })?.raw[key] ?? "" },
                set: { value in
                    guard let field = editor.fields.first(where: { $0.path == [key] }) else { return }
                    editor.editField(row: row.id, field: field, raw: value)
                })
    }
    private func picker(_ row: SettingsCollectionEditorModel.Row, key: String, label: String, options: [(String, String)], help: String = "") -> some View {
        SettingsFormRow(label, help: help, fonts: fonts) {
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: label, options: options, selection: binding(row, key))
        }
    }
    private func number(_ row: SettingsCollectionEditorModel.Row, _ key: String, _ label: String) -> some View {
        SettingsFormRow(label, fonts: fonts) {
            TextField(tr("Commun", "Shared"), text: binding(row, key)).textFieldStyle(.roundedBorder).frame(width: 100)
                .accessibilityLabel(label)
        }
    }
    private func toggle(_ row: SettingsCollectionEditorModel.Row, _ key: String, _ label: String, help: String = "") -> some View {
        SettingsFormRow(label, help: help, fonts: fonts) {
            Toggle(label, isOn: Binding(get: { row.raw[key] == "true" }, set: { _ = editor.updateRow(row.id, values: [key: $0 ? "true" : "false"]) }))
                .toggleStyle(.switch).labelsHidden()
        }
    }
    private func source(_ row: SettingsCollectionEditorModel.Row) -> String {
        if row.source.fields["trigger_source"] != nil { return row.raw["trigger_source"] ?? "external" }
        return (row.raw["hotkey"] ?? "").isEmpty ? "external" : "roadie"
    }
    private func summary(_ row: SettingsCollectionEditorModel.Row) -> String {
        let manager = ["roadie": "Roadie", "btt": "BetterTouchTool", "external": tr("Outil externe", "External tool")][source(row)] ?? ""
        let mode = ["focus": tr("Activer au relâchement", "Activate on release"), "stay": tr("Rester ouvert", "Stay open"), "search": tr("Rechercher au relâchement", "Search on release")][row.raw["release_action"] ?? "focus"] ?? ""
        return (row.raw["enabled"] == "false" ? tr("Désactivé · ", "Off · ") : "") + manager + " · " + mode
    }
    private func modeHelp(_ mode: String) -> String {
        switch mode {
        case "stay": tr("Relâchez les touches, puis naviguez et validez par Retour ou clic. Cmd+F ouvre la recherche.", "Release the keys, then navigate and confirm with Return or a click. Cmd+F opens search.")
        case "search": tr("Relâcher les touches place le curseur dans la recherche. Retour ou un clic ouvre le résultat choisi.", "Releasing the keys puts the cursor in search. Return or a click opens the chosen result.")
        default: tr("Relâcher les touches active la fenêtre. La recherche et les actions peuvent rester discrètes.", "Releasing the keys activates the window. Search and actions can stay out of the way.")
        }
    }
    private func bindingValue(_ row: SettingsCollectionEditorModel.Row) -> BTTBinding {
        BTTBinding(profileID: row.raw["id"] ?? "all", name: row.raw["name"] ?? tr("Profil", "Profile"),
                   hotkey: row.raw["hotkey"] ?? "", source: source(row), enabled: row.raw["enabled"] != "false",
                   forwardID: row.raw["btt_forward_uuid"] ?? "", reverseID: row.raw["btt_reverse_uuid"] ?? "")
    }

    private func change(_ row: SettingsCollectionEditorModel.Row, values: [String: String]) {
        let old = bindingValue(row)
        var new = old
        new.hotkey = values["hotkey"] ?? old.hotkey
        new.source = values["trigger_source"] ?? old.source
        new.enabled = values["enabled"].map { $0 == "true" } ?? old.enabled
        let desired = new
        busy = true
        message = ""
        let layout = TargetSearchHotkey.currentLayoutTable()
        Task { @MainActor in
            defer { busy = false }
            do {
                let service = BTTShortcutBindingService()
                let mutation = try await Task.detached { try service.prepare(old: old, new: desired, layout: layout) }.value
                var committed = false
                do {
                    guard editor.updateRow(row.id, values: raw(mutation.binding)) else {
                        throw BTTBindingError.message(tr("Le profil n'a pas été enregistré. La liaison précédente est conservée.", "The profile was not saved. The previous binding is kept."))
                    }
                    committed = true
                    guard await waitForNative(mutation.binding) else {
                        throw BTTBindingError.message(tr("Roadie n'a pas pu enregistrer cette combinaison. Vérifiez les autres raccourcis.", "Roadie could not register this key combination. Check the other shortcuts."))
                    }
                    try await Task.detached { try service.activate(mutation) }.value
                    message = mutation.binding.source == "btt"
                        ? (mutation.binding.hotkey.isEmpty ? tr("BetterTouchTool sélectionné. Enregistrez une combinaison pour créer la liaison.", "BetterTouchTool selected. Record a key combination to create the binding.") : tr("Liaison BTT vérifiée. Essayez maintenant la combinaison au clavier.", "BTT binding verified. Now try the key combination on the keyboard."))
                        : tr("Gestionnaire mis à jour.", "Handler updated.")
                } catch {
                    if committed {
                        guard editor.updateRow(row.id, values: raw(old)) else {
                            throw BTTBindingError.message(tr("Le profil a changé ailleurs. BTT reste désactivé pour éviter une double action ; rechargez les profils.", "The profile changed elsewhere. BTT stays off to avoid a double action; reload the profiles."))
                        }
                        _ = await waitForNative(old)
                    }
                    try await Task.detached { try service.rollback(mutation) }.value
                    throw error
                }
            } catch { message = error.localizedDescription }
        }
    }
    private func raw(_ value: BTTBinding) -> [String: String] {
        ["hotkey": value.hotkey, "trigger_source": value.source, "enabled": value.enabled ? "true" : "false",
         "btt_forward_uuid": value.forwardID, "btt_reverse_uuid": value.reverseID]
    }
    private func waitForNative(_ value: BTTBinding) async -> Bool {
        let expected = value.source == "roadie" && value.enabled && !value.hotkey.isEmpty
        let resolved = WindowSwitcherHotkey.parse(value.hotkey, layout: TargetSearchHotkey.currentLayoutTable())
        let fingerprint = resolved.map { "\($0.keyCode):\(WindowSwitcherHotkey.carbonModifiers($0.modifiers))" }
        for _ in 0..<25 {
            if expected, let fingerprint, WindowSwitcherHotkeyRegistry.activeFingerprints[value.profileID] == fingerprint { return true }
            if !expected, WindowSwitcherHotkeyRegistry.activeFingerprints[value.profileID] == nil { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }
    private func remove(_ row: SettingsCollectionEditorModel.Row) {
        let old = bindingValue(row)
        var disabled = old
        disabled.source = "external"
        disabled.enabled = false
        let desired = disabled
        let layout = TargetSearchHotkey.currentLayoutTable()
        busy = true
        message = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                let service = BTTShortcutBindingService()
                let mutation = try await Task.detached { try service.prepare(old: old, new: desired, layout: layout) }.value
                guard editor.removeRow(row.id) else {
                    try await Task.detached { try service.rollback(mutation) }.value
                    throw BTTBindingError.message(tr("Le profil n'a pas été supprimé. Sa liaison est conservée.", "The profile was not deleted. Its binding is kept."))
                }
                selectedID = editor.rows.first?.id
                try await Task.detached { try service.discard(mutation) }.value
                message = tr("Profil et liaisons associées supprimés.", "Profile and its bindings deleted.")
            } catch { message = error.localizedDescription }
        }
    }
}

