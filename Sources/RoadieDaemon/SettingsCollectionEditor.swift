import AppKit
import Combine
import RoadieCore
import SwiftUI

/// État local des listes et formulaires. Les identités des lignes et le texte saisi restent stables
/// quand l'écriture notifie la fenêtre. Le service conserve les champs inconnus des blocs source.
@MainActor
final class SettingsCollectionEditorModel: ObservableObject {
    struct Item: Identifiable {
        let id: UUID
        var raw: String
    }
    struct Row: Identifiable {
        let id: UUID
        var raw: [String: String]
        var source: CollectionRow
    }

    let descriptor: SettingDescriptor
    let service: SettingsService
    @Published private(set) var items: [Item] = []
    @Published private(set) var rows: [Row] = []
    @Published private(set) var messages: [String] = []
    private(set) var baseline: CollectionValue?
    private var hasDrafts = false
    var onChange: ((SettingChangeResult) -> Void)?

    init(descriptor: SettingDescriptor, service: SettingsService) {
        self.descriptor = descriptor
        self.service = service
        reload(discardDrafts: true)
    }

    var fields: [CollectionFieldSpec] {
        guard case .rows(_, let fields, _, _) = descriptor.collection?.shape else { return [] }
        return fields
    }

    func reload(discardDrafts: Bool = false) {
        switch service.collection(of: descriptor) {
        case .failure(let error): messages = [error.message]
        case .success(let value):
            guard discardDrafts || value != baseline else { return }
            guard discardDrafts || !hasDrafts else {
                messages = [tr("Ces données ont changé ailleurs. Votre saisie est conservée ; rechargez les données avant de reprendre.", "This data changed elsewhere. Your input is kept; reload the data before continuing.")]
                return
            }
            baseline = value
            hasDrafts = false
            messages = []
            switch value {
            case .list(let values):
                items = values.enumerated().map { index, value in
                    Item(id: index < items.count ? items[index].id : UUID(), raw: Self.text(value))
                }
            case .rows(let values):
                rows = values.enumerated().map { index, source in
                    var raw: [String: String] = [:]
                    for field in fields {
                        let key = field.path.joined(separator: ".")
                        raw[key] = Self.text(source.fields[key] ?? field.defaultValue)
                    }
                    return Row(id: index < rows.count ? rows[index].id : UUID(), raw: raw, source: source)
                }
            case .advanced: break
            }
        }
    }

    func editItem(_ id: UUID, raw: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].raw = raw
        hasDrafts = true
        persist()
    }

    func addItem() {
        items.append(Item(id: UUID(), raw: ""))
        hasDrafts = true
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        hasDrafts = true
        persist()
    }

    func setSide(_ side: String, enabled: Bool) {
        items.removeAll { $0.raw == side }
        if enabled { items.append(Item(id: UUID(), raw: side)) }
        hasDrafts = true
        persist()
    }

    func editField(row id: UUID, field: CollectionFieldSpec, raw: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].raw[field.path.joined(separator: ".")] = raw
        hasDrafts = true
        persist()
    }

    @discardableResult
    func updateRow(_ id: UUID, values: [String: String]) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        let previous = rows[index]
        let previousDrafts = hasDrafts
        for (key, value) in values { rows[index].raw[key] = value }
        hasDrafts = true
        guard persist() else { rows[index] = previous; hasDrafts = previousDrafts; return false }
        return true
    }

    @discardableResult
    func addProfile(copying id: UUID? = nil) -> UUID? {
        guard rows.count < 9 else { return nil }
        let newID = UUID()
        var raw = id.flatMap { id in rows.first(where: { $0.id == id })?.raw }
            ?? Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), Self.text($0.defaultValue)) })
        raw["id"] = "profil-" + newID.uuidString.lowercased()
        raw["name"] = id == nil ? tr("Nouveau profil", "New profile") : (raw["name"] ?? tr("Profil", "Profile")) + tr(" (copie)", " (copy)")
        raw["hotkey"] = ""
        raw["trigger_source"] = "external"
        raw["btt_forward_uuid"] = ""
        raw["btt_reverse_uuid"] = ""
        rows.append(Row(id: newID, raw: raw, source: CollectionRow(fields: [:])))
        hasDrafts = true
        guard persist() else { rows.removeAll { $0.id == newID }; return nil }
        return newID
    }

    /// Nouvelle ligne enregistrée tout de suite avec ces valeurs (session 108) ; nil si l'écriture échoue.
    @discardableResult
    func addRow(values: [String: String]) -> UUID? {
        var raw = Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), Self.text($0.defaultValue)) })
        raw.merge(values) { _, new in new }
        let id = UUID()
        rows.append(Row(id: id, raw: raw, source: CollectionRow(fields: [:])))
        hasDrafts = true
        guard persist() else { rows.removeAll { $0.id == id }; return nil }
        return id
    }

    func addRow() {
        let raw = Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), Self.text($0.defaultValue)) })
        rows.append(Row(id: UUID(), raw: raw, source: CollectionRow(fields: [:])))
        hasDrafts = true
    }

    @discardableResult
    func removeRow(_ id: UUID) -> Bool {
        let previous = rows, previousDrafts = hasDrafts
        rows.removeAll { $0.id == id }
        hasDrafts = true
        guard persist() else { rows = previous; hasDrafts = previousDrafts; return false }
        return true
    }

    func moveRow(_ id: UUID, by offset: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(index + offset) else { return }
        rows.swapAt(index, index + offset)
        hasDrafts = true
        persist()
    }

    /// Conversion des seuls champs exposés, sans composer de TOML dans l'interface.
    func candidate() -> CollectionValue? {
        guard let shape = descriptor.collection?.shape else { return nil }
        switch shape {
        case .list(let kind, _, _, _, let sorted):
            var values: [SettingValue] = []
            for item in items {
                guard !item.raw.trimmingCharacters(in: .whitespaces).isEmpty,
                      case .success(let converted) = SettingsService.convert(item.raw, kind: kind) else { return nil }
                values.append(converted.1)
            }
            if sorted {
                values.sort { lhs, rhs in
                    Self.number(lhs) < Self.number(rhs)
                }
            }
            return .list(values)
        case .rows:
            var values: [CollectionRow] = []
            for row in rows {
                var source = row.source
                for field in fields {
                    let key = field.path.joined(separator: ".")
                    let raw = row.raw[key] ?? ""
                    // Une chaîne vide explicite peut être un critère existant. Un autre champ
                    // modifié ne doit ni retirer ce critère ni normaliser sa valeur source.
                    let original = row.source.fields[key] ?? field.defaultValue
                    if raw == Self.text(original) { continue }
                    if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                        guard !field.required else { return nil }
                        source.fields[key] = nil
                    } else {
                        guard case .success(let converted) = SettingsService.convert(raw, kind: field.kind) else { return nil }
                        source.fields[key] = converted.1
                    }
                }
                values.append(source)
            }
            return .rows(values)
        case .advanced: return nil
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard baseline != nil else {
            messages = [tr("Rechargez les données avant de les modifier.", "Reload the data before changing it.")]
            return false
        }
        guard let candidate = candidate() else {
            messages = [tr("Complétez les champs requis et les valeurs en cours de saisie. La dernière configuration valide reste active.", "Complete the required fields and the values being typed. The last valid configuration stays active.")]
            return false
        }
        let errors = service.validateCollection(descriptor, value: candidate)
        guard errors.isEmpty else { messages = errors.values.sorted(); return false }
        let result = service.setCollection(descriptor.id, candidate, expected: baseline)
        onChange?(result)
        switch result {
        case .rejected(let reason): messages = [reason]; return false
        case .applied:
            messages = []
            // Actualiser les indices source après ajout/suppression, sans remplacer les UUID ni le texte brut.
            if case .success(let stored) = service.collection(of: descriptor) {
                baseline = stored
                hasDrafts = false
                if case .rows(let sources) = stored, sources.count == rows.count {
                    for index in rows.indices { rows[index].source = sources[index] }
                }
            }
            return true
        }
    }

    private static func text(_ value: SettingValue) -> String {
        value == .unset ? "" : SettingsService.display(value)
    }

    private static func number(_ value: SettingValue) -> Double {
        switch value {
        case .int(let number): return Double(number)
        case .double(let number): return number
        default: return 0
        }
    }
}

struct SettingsCollectionEditor: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    @StateObject private var editor: SettingsCollectionEditorModel
    @State private var expandedRows: Set<UUID> = []
    private var fonts: RoadieCore.InterfaceConfig { model.interfaceFonts }

    init(model: SettingsViewModel, descriptor: SettingDescriptor) {
        self.model = model
        self.descriptor = descriptor
        _editor = StateObject(wrappedValue: SettingsCollectionEditorModel(descriptor: descriptor, service: model.service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if descriptor.id == "tiling.display_overrides" {
                Text(tr("Ces marges prennent priorité sur les marges générales pour l'écran identifié. Une valeur vide conserve la marge générale.", "These gaps take priority over the general gaps for the identified display. An empty value keeps the general gap."))
                    .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            }
            if let shape = descriptor.collection?.shape {
                switch shape {
                case .list:
                    if descriptor.id == "tiling.smart_gaps_solo_sides" { sides } else { list }
                case .rows: rowForms
                case .advanced: EmptyView()
                }
            }
            ForEach(Array(editor.messages.enumerated()), id: \.offset) { _, text in
                Text(text).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.red)
            }
            if !editor.messages.isEmpty {
                Button(tr("Recharger les données", "Reload data")) { editor.reload(discardDrafts: true) }
            }
        }
        .onAppear {
            editor.onChange = { model.collectionChanged(descriptor, result: $0) }
            if expandedRows.isEmpty, let first = editor.rows.first { expandedRows.insert(first.id) }
        }
        .onChange(of: model.collectionRevision) { _, _ in editor.reload() }
        .onChange(of: model.collectionResetRevisions[descriptor.id]) { _, _ in editor.reload(discardDrafts: true) }
    }

    private var sides: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { sideToggles }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { sideToggles }
        }
    }

    private var sideToggles: some View {
            ForEach([("top", tr("Haut", "Top")), ("right", tr("Droite", "Right")), ("bottom", tr("Bas", "Bottom")), ("left", tr("Gauche", "Left"))], id: \.0) { side, label in
                Toggle(label, isOn: Binding(
                    get: { editor.items.contains { $0.raw == side } },
                    set: { editor.setSide(side, enabled: $0) }
                ))
                .toggleStyle(.checkbox).fixedSize()
            }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if descriptor.id == "width_adjustment.presets" {
                Text(tr("Les valeurs sont enregistrées dans l'ordre croissant.", "Values are saved in ascending order."))
                    .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            }
            if editor.items.isEmpty { Text(tr("Aucune entrée", "No entries")).foregroundStyle(.secondary) }
            ForEach(editor.items) { item in
                HStack(spacing: 8) {
                    TextField(listPlaceholder, text: Binding(
                        get: { editor.items.first { $0.id == item.id }?.raw ?? "" },
                        set: { editor.editItem(item.id, raw: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(descriptor.label)
                    Button(tr("Supprimer", "Delete"), systemImage: "minus.circle") { editor.removeItem(item.id) }
                        .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 26, height: 26)
                        .help(tr("Supprimer cette entrée", "Delete this entry")).accessibilityLabel(tr("Supprimer cette entrée", "Delete this entry"))
                }
            }
            Button(tr("Ajouter une entrée", "Add an entry"), systemImage: "plus") { editor.addItem() }
        }
    }

    private var listPlaceholder: String {
        guard case .list(let element, _, _, _, _) = descriptor.collection?.shape else { return tr("Valeur", "Value") }
        switch element {
        case .int, .double: return tr("Nombre", "Number")
        default: return descriptor.key.contains("bundle") ? tr("Identifiant de l'application", "App identifier") : tr("Valeur", "Value")
        }
    }

    private var rowForms: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editor.rows.isEmpty { Text(tr("Aucune entrée", "No entries")).foregroundStyle(.secondary) }
            ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            if expandedRows.contains(row.id) { expandedRows.remove(row.id) }
                            else { expandedRows.insert(row.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: expandedRows.contains(row.id) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 11, weight: .semibold)).frame(width: 14)
                                Text(rowTitle(row, index: index)).fontWeight(.semibold)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(tr("Déplier ou replier : ", "Expand or collapse: ") + rowTitle(row, index: index))
                            .accessibilityValue(expandedRows.contains(row.id) ? tr("Déplié", "Expanded") : tr("Replié", "Collapsed"))
                        if descriptor.id == "rules" || descriptor.id == "stage_manager.workspaces" {
                            Button(tr("Monter", "Move up"), systemImage: "arrow.up") { editor.moveRow(row.id, by: -1) }
                                .labelStyle(.iconOnly).font(.system(size: 16)).buttonStyle(.plain).frame(width: 26, height: 26)
                                .help(tr("Monter cette entrée", "Move this entry up")).disabled(index == 0)
                            Button(tr("Descendre", "Move down"), systemImage: "arrow.down") { editor.moveRow(row.id, by: 1) }
                                .labelStyle(.iconOnly).font(.system(size: 16)).buttonStyle(.plain).frame(width: 26, height: 26)
                                .help(tr("Descendre cette entrée", "Move this entry down")).disabled(index == editor.rows.count - 1)
                        }
                        Button(tr("Supprimer", "Delete"), systemImage: "minus.circle") { editor.removeRow(row.id) }
                            .labelStyle(.iconOnly).font(.system(size: 16)).buttonStyle(.plain).frame(width: 26, height: 26)
                            .help(tr("Supprimer cette entrée", "Delete this entry")).accessibilityLabel(tr("Supprimer l'entrée \(index + 1)", "Delete entry \(index + 1)"))
                    }
                    if expandedRows.contains(row.id) {
                        if descriptor.id == "rules" {
                            fieldForms(row, fields: editor.fields.filter { $0.path.count == 1 })
                            SettingsDisclosureSection(tr("Critères de correspondance", "Match criteria")) {
                                fieldForms(row, fields: editor.fields.filter { $0.path.first == "match" })
                            }
                            SettingsDisclosureSection(tr("Actions à appliquer", "Actions to apply")) {
                                fieldForms(row, fields: editor.fields.filter { $0.path.first == "action" })
                            }
                        } else {
                            fieldForms(row, fields: editor.fields)
                        }
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider() }
            }
            Button(descriptor.id == "rules" ? tr("Ajouter une règle", "Add a rule") : tr("Ajouter une entrée", "Add an entry"), systemImage: "plus") {
                editor.addRow()
                if let row = editor.rows.last { expandedRows.insert(row.id) }
            }
        }
    }

    private func rowTitle(_ row: SettingsCollectionEditorModel.Row, index: Int) -> String {
        let value = ["display_name", "name", "id", "stage_id", "display_id"]
            .compactMap { row.raw[$0] }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return value ?? tr("Entrée \(index + 1)", "Entry \(index + 1)")
    }

    private func fieldForms(_ row: SettingsCollectionEditorModel.Row, fields: [CollectionFieldSpec]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.path) { field in
                SettingsFormRow(field.label + (field.required ? " *" : ""), help: field.help, fonts: fonts) {
                    rowControl(row, field: field)
                }
            }
        }
    }

    private func binding(_ row: SettingsCollectionEditorModel.Row, field: CollectionFieldSpec) -> Binding<String> {
        let key = field.path.joined(separator: ".")
        return Binding(
            get: { editor.rows.first { $0.id == row.id }?.raw[key] ?? "" },
            set: { editor.editField(row: row.id, field: field, raw: $0) }
        )
    }

    @ViewBuilder
    private func rowControl(_ row: SettingsCollectionEditorModel.Row, field: CollectionFieldSpec) -> some View {
        let selection = binding(row, field: field)
        switch field.kind {
        case .bool:
            if field.defaultValue == .unset {
                SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: field.label,
                                               options: [("", tr("Non défini", "Not set")), ("true", tr("Oui", "Yes")), ("false", tr("Non", "No"))], selection: selection)
            } else {
                Toggle(field.label, isOn: Binding(
                    get: { selection.wrappedValue == "true" },
                    set: { selection.wrappedValue = $0 ? "true" : "false" }
                )).labelsHidden().toggleStyle(.switch)
            }
        case .choice(let choices):
            let options = (field.required ? [] : [("", tr("Non défini", "Not set"))]) + choices.map { ($0, field.choiceLabels[$0] ?? $0) }
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: field.label,
                                           options: options, selection: selection)
        case .color:
            HStack {
                ColorPicker(field.label, selection: Binding(
                    get: { NSColor(hex: selection.wrappedValue).map { Color(nsColor: $0) } ?? .clear },
                    set: { selection.wrappedValue = $0.settingsHexString }
                ), supportsOpacity: true).labelsHidden()
                TextField(tr("Non défini", "Not set"), text: selection).textFieldStyle(.roundedBorder)
            }
        case .int, .double:
            TextField(field.required ? tr("Valeur requise", "Value required") : tr("Non défini", "Not set"), text: selection)
                .textFieldStyle(.roundedBorder).frame(maxWidth: max(110, fonts.settingsTextFontSize * 6))
                .accessibilityLabel(field.label)
        default:
            TextField(field.required ? tr("Valeur requise", "Value required") : tr("Non défini", "Not set"), text: selection)
                .textFieldStyle(.roundedBorder).accessibilityLabel(field.label)
        }
    }
}

/// Comme les menus principaux, ces choix natifs suivent la taille choisie dans les paramètres.
struct SettingsCollectionChoicePicker: NSViewRepresentable {
    let fontSize: Double
    let label: String
    let options: [(raw: String, label: String)]
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        var values = options
        let missing = !values.contains { $0.raw == selection }
        if missing { values.append((selection, selection.isEmpty ? tr("Valeur vide (actuelle)", "Empty value (current)") : tr("\(selection) (valeur actuelle)", "\(selection) (current value)"))) }
        if button.itemArray.compactMap({ $0.representedObject as? String }) != values.map(\.raw) {
            button.removeAllItems()
            for value in values {
                button.addItem(withTitle: value.label)
                button.lastItem?.representedObject = value.raw
            }
            if missing { button.lastItem?.isEnabled = false }
        }
        button.menu?.autoenablesItems = false
        button.font = .systemFont(ofSize: fontSize)
        button.menu?.font = .systemFont(ofSize: fontSize)
        button.select(button.itemArray.first { $0.representedObject as? String == selection })
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, item.isEnabled, let raw = item.representedObject as? String else { return }
            selection.wrappedValue = raw
        }
    }
}

private extension Color {
    var settingsHexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let parts = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
        return parts[3] < 255 ? rgb + String(format: "%02X", parts[3]) : rgb
    }
}
