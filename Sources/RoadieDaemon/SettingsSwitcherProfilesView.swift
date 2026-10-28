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
    @State private var tab = "Raccourci"
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
                        Text(row.raw["name"] ?? "Profil").fontWeight(.semibold)
                        shortcutRows(row)
                    }
                }
            } else {
                profilesBody
            }
            if busy { ProgressView("Vérification du raccourci…").controlSize(.small) }
            if !message.isEmpty { Text(message).foregroundStyle(.orange).font(.system(size: fonts.settingsHelpFontSize)) }
            ForEach(Array(editor.messages.enumerated()), id: \.offset) { _, value in
                Text(value).foregroundStyle(.red).font(.system(size: fonts.settingsHelpFontSize))
            }
            if !editor.messages.isEmpty {
                Button("Recharger les profils") { editor.reload(discardDrafts: true) }
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
        SettingsFormRow("Géré par", help: "Roadie enregistre le raccourci directement. BetterTouchTool utilise une liaison vérifiée. Le mode externe conserve les commandes BTT ou Karabiner existantes.", fonts: fonts) {
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: "Gestionnaire",
                options: [("roadie", "Roadie"), ("btt", "BetterTouchTool"), ("external", "Outil externe / commande")],
                selection: Binding(get: { source(row) }, set: { change(row, values: ["trigger_source": $0]) }))
        }
        SettingsFormRow("Combinaison", help: "Cliquez sur Enregistrer, puis appuyez sur les touches. Échap annule la capture.", fonts: fonts) {
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
                            Text(row.raw["name"] ?? "Profil").fontWeight(.semibold).lineLimit(1)
                            Text(summary(row)).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((row.raw["hotkey"] ?? "").isEmpty ? (source(row) == "external" ? "Commande externe" : "À définir") : ShortcutCapture.label(row.raw["hotkey"] ?? ""))
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
            SettingsFormRow("Nom du profil", fonts: fonts) {
                TextField("Nom du profil", text: binding(row, "name")).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Nom du profil")
            }
            SettingsFormRow("Profil actif", fonts: fonts) {
                Toggle("Profil actif", isOn: Binding(get: { row.raw["enabled"] != "false" },
                    set: { change(row, values: ["enabled": $0 ? "true" : "false"]) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            profileTabs.padding(.vertical, 10)
            if tab == "Raccourci" {
                // Combinaison et gestionnaire réunis dans Paramètres > Raccourcis (session 108).
                SettingsFormRow("Combinaison", help: "La combinaison et son gestionnaire se règlent avec les autres raccourcis.", fonts: fonts) {
                    HStack(spacing: 10) {
                        Text((row.raw["hotkey"] ?? "").isEmpty ? "Aucune" : ShortcutCapture.label(row.raw["hotkey"] ?? ""))
                        Button("Régler dans Raccourcis") { model.select(.raccourcis) }
                    }
                }
                picker(row, key: "release_action", label: "Au relâchement",
                       options: [("focus", "Activer la fenêtre choisie"), ("stay", "Rester ouvert"), ("search", "Passer en recherche")],
                       help: modeHelp(row.raw["release_action"] ?? "focus"))
                picker(row, key: "search_visibility", label: "Champ de recherche",
                       options: [("auto", "Selon le mode"), ("always", "Toujours visible"), ("never", "Masqué")])
                picker(row, key: "actions_visibility", label: "Menu Actions",
                       options: [("auto", "Selon le mode"), ("always", "Toujours visible"), ("never", "Masqué")])
                if source(row) == "btt" && (row.raw["btt_forward_uuid"] ?? "").isEmpty {
                    Button("Configurer BTT") { change(row, values: ["trigger_source": "btt"]) }
                }
            } else if tab == "Fenêtres" {
                picker(row, key: "scope", label: "Fenêtres proposées", options: [
                    ("all", "Toutes les fenêtres"), ("stage", "Stage actif"), ("desktop", "Bureau actif"),
                    ("display", "Écran actif"), ("application", "Application active")])
                picker(row, key: "sort_order", label: "Ordre", options: [
                    ("recent", "Récentes d'abord"), ("title", "Titre"), ("stage", "Stage")])
                toggle(row, "include_minimized", "Fenêtres réduites")
                toggle(row, "include_hidden", "Applications masquées")
                toggle(row, "include_fullscreen", "Fenêtres plein écran")
                toggle(row, "one_per_app", "Une fenêtre par application")
            } else if tab == "Apparence" {
                picker(row, key: "presentation", label: "Organisation",
                       options: [("", "Réglage commun")] + WindowSwitcherPresentation.allCases.map { ($0.rawValue, $0.label) },
                       help: "Regroupe les fenêtres par bureau et stage Roadie. Le style des cartes et l'action au relâchement restent indépendants.")
                picker(row, key: "style", label: "Style", options: [("", "Réglage commun"), ("thumbnails", "Vignettes"), ("icons", "Icônes"), ("list", "Liste compacte")],
                       help: "Un réglage commun suit l'apparence de la catégorie. Une valeur propre à ce profil prend priorité.")
                picker(row, key: "preview", label: "Grand aperçu", options: [("", "Réglage commun"), ("true", "Afficher"), ("false", "Masquer")])
                picker(row, key: "auto_size", label: "Taille automatique", options: [("", "Réglage commun"), ("true", "Oui"), ("false", "Non")])
                number(row, "thumbnail_width", "Largeur des vignettes")
                number(row, "font_size", "Taille du texte")
                SettingsFormRow("Police", fonts: fonts) {
                    SettingsFontFamilyPicker(fontSize: fonts.settingsTextFontSize, selection: binding(row, "font_family"), inheritedLabel: "Réglage commun")
                }
                Button("Apparence commune") {
                    _ = editor.updateRow(row.id, values: Dictionary(uniqueKeysWithValues: ["presentation", "style", "preview", "auto_size", "thumbnail_width", "font_size", "font_family"].map { ($0, "") }))
                }
            } else {
                toggle(row, "arrow_navigation", "Navigation aux flèches")
                toggle(row, "mouse_hover", "Sélection au survol",
                       help: "Le survol sélectionne ; le clic active la fenêtre. Un pointeur immobile ne reprend pas la sélection après une flèche. Quand la recherche contient du texte, Gauche/Droite déplacent le curseur dans ce texte.")
            }
            if editor.rows.count > 1 {
                Button("Supprimer ce profil", role: .destructive) { remove(row) }
                    .font(.system(size: fonts.settingsHelpFontSize))
            }
        }
        .padding(.vertical, 6)
    }

    private var profileTools: some View {
        Group {
            Button("Nouveau profil", systemImage: "plus") { selectedID = editor.addProfile() }
                .disabled(editor.rows.count >= 9).fixedSize(horizontal: true, vertical: false)
            if let selectedID {
                Button("Dupliquer", systemImage: "plus.square.on.square") { self.selectedID = editor.addProfile(copying: selectedID) }
                    .disabled(editor.rows.count >= 9).fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var profileTabs: some View {
        SettingsTabs(values: ["Raccourci", "Fenêtres", "Navigation", "Apparence"],
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
            TextField("Commun", text: binding(row, key)).textFieldStyle(.roundedBorder).frame(width: 100)
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
        let manager = ["roadie": "Roadie", "btt": "BetterTouchTool", "external": "Outil externe"][source(row)] ?? ""
        let mode = ["focus": "Activer au relâchement", "stay": "Rester ouvert", "search": "Rechercher au relâchement"][row.raw["release_action"] ?? "focus"] ?? ""
        return (row.raw["enabled"] == "false" ? "Désactivé · " : "") + manager + " · " + mode
    }
    private func modeHelp(_ mode: String) -> String {
        switch mode {
        case "stay": "Relâchez les touches, puis naviguez et validez par Retour ou clic. Cmd+F ouvre la recherche."
        case "search": "Relâcher les touches place le curseur dans la recherche. Retour ou un clic ouvre le résultat choisi."
        default: "Relâcher les touches active la fenêtre. La recherche et les actions peuvent rester discrètes."
        }
    }
    private func bindingValue(_ row: SettingsCollectionEditorModel.Row) -> BTTBinding {
        BTTBinding(profileID: row.raw["id"] ?? "all", name: row.raw["name"] ?? "Profil",
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
                        throw BTTBindingError.message("Le profil n'a pas été enregistré. La liaison précédente est conservée.")
                    }
                    committed = true
                    guard await waitForNative(mutation.binding) else {
                        throw BTTBindingError.message("Roadie n'a pas pu enregistrer cette combinaison. Vérifiez les autres raccourcis.")
                    }
                    try await Task.detached { try service.activate(mutation) }.value
                    message = mutation.binding.source == "btt"
                        ? (mutation.binding.hotkey.isEmpty ? "BetterTouchTool sélectionné. Enregistrez une combinaison pour créer la liaison." : "Liaison BTT vérifiée. Essayez maintenant la combinaison au clavier.")
                        : "Gestionnaire mis à jour."
                } catch {
                    if committed {
                        guard editor.updateRow(row.id, values: raw(old)) else {
                            throw BTTBindingError.message("Le profil a changé ailleurs. BTT reste désactivé pour éviter une double action ; rechargez les profils.")
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
                    throw BTTBindingError.message("Le profil n'a pas été supprimé. Sa liaison est conservée.")
                }
                selectedID = editor.rows.first?.id
                try await Task.detached { try service.discard(mutation) }.value
                message = "Profil et liaisons associées supprimés."
            } catch { message = error.localizedDescription }
        }
    }
}

