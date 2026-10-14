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
                messages = ["Ces données ont changé ailleurs. Votre saisie est conservée ; rechargez les données avant de reprendre."]
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

    func addRow() {
        let raw = Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), Self.text($0.defaultValue)) })
        rows.append(Row(id: UUID(), raw: raw, source: CollectionRow(fields: [:])))
        hasDrafts = true
    }

    func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        hasDrafts = true
        persist()
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

    private func persist() {
        guard let candidate = candidate() else {
            messages = ["Complétez les champs requis et les valeurs en cours de saisie. La dernière configuration valide reste active."]
            return
        }
        let errors = service.validateCollection(descriptor, value: candidate)
        guard errors.isEmpty else { messages = errors.values.sorted(); return }
        let result = service.setCollection(descriptor.id, candidate, expected: baseline)
        onChange?(result)
        switch result {
        case .rejected(let reason): messages = [reason]
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
    private var fonts: RoadieCore.InterfaceConfig { model.interfaceFonts }

    init(model: SettingsViewModel, descriptor: SettingDescriptor) {
        self.model = model
        self.descriptor = descriptor
        _editor = StateObject(wrappedValue: SettingsCollectionEditorModel(descriptor: descriptor, service: model.service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if descriptor.id == "tiling.display_overrides" {
                Text("Ces marges prennent priorité sur les marges générales pour l'écran identifié. Une valeur vide conserve la marge générale.")
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
                Button("Recharger les données") { editor.reload(discardDrafts: true) }
            }
        }
        .onAppear { editor.onChange = { model.collectionChanged(descriptor, result: $0) } }
        .onChange(of: model.collectionRevision) { _, _ in editor.reload() }
        .onChange(of: model.collectionResetRevisions[descriptor.id]) { _, _ in editor.reload(discardDrafts: true) }
    }

    private var sides: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([("top", "Haut"), ("right", "Droite"), ("bottom", "Bas"), ("left", "Gauche")], id: \.0) { side, label in
                Toggle(label, isOn: Binding(
                    get: { editor.items.contains { $0.raw == side } },
                    set: { editor.setSide(side, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if descriptor.id == "width_adjustment.presets" {
                Text("Les valeurs sont enregistrées dans l'ordre croissant.")
                    .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            }
            if editor.items.isEmpty { Text("Aucune entrée").foregroundStyle(.secondary) }
            ForEach(editor.items) { item in
                HStack(spacing: 8) {
                    TextField(listPlaceholder, text: Binding(
                        get: { editor.items.first { $0.id == item.id }?.raw ?? "" },
                        set: { editor.editItem(item.id, raw: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(descriptor.label)
                    Button("Supprimer", systemImage: "minus.circle") { editor.removeItem(item.id) }
                        .labelStyle(.iconOnly).accessibilityLabel("Supprimer cette entrée")
                }
            }
            Button("Ajouter une entrée", systemImage: "plus") { editor.addItem() }
        }
    }

    private var listPlaceholder: String {
        guard case .list(let element, _, _, _, _) = descriptor.collection?.shape else { return "Valeur" }
        switch element {
        case .int, .double: return "Nombre"
        default: return descriptor.key.contains("bundle") ? "Identifiant de l'application" : "Valeur"
        }
    }

    private var rowForms: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.rows.isEmpty { Text("Aucune entrée").foregroundStyle(.secondary) }
            ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Entrée \(index + 1)").font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                        Spacer()
                        if descriptor.id == "rules" || descriptor.id == "stage_manager.workspaces" {
                            Button("Monter", systemImage: "arrow.up") { editor.moveRow(row.id, by: -1) }
                                .labelStyle(.iconOnly).disabled(index == 0)
                            Button("Descendre", systemImage: "arrow.down") { editor.moveRow(row.id, by: 1) }
                                .labelStyle(.iconOnly).disabled(index == editor.rows.count - 1)
                        }
                        Button("Supprimer", systemImage: "minus.circle") { editor.removeRow(row.id) }
                            .labelStyle(.iconOnly).accessibilityLabel("Supprimer l'entrée \(index + 1)")
                    }
                    if descriptor.id == "rules" {
                        fieldForms(row, fields: editor.fields.filter { $0.path.count == 1 })
                        DisclosureGroup("Critères de correspondance") {
                            fieldForms(row, fields: editor.fields.filter { $0.path.first == "match" }).padding(.top, 8)
                        }
                        DisclosureGroup("Actions à appliquer") {
                            fieldForms(row, fields: editor.fields.filter { $0.path.first == "action" }).padding(.top, 8)
                        }
                    } else {
                        fieldForms(row, fields: editor.fields)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            }
            Button("Ajouter une entrée", systemImage: "plus") { editor.addRow() }
        }
    }

    private func fieldForms(_ row: SettingsCollectionEditorModel.Row, fields: [CollectionFieldSpec]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(fields, id: \.path) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label + (field.required ? " *" : ""))
                        .font(.system(size: fonts.settingsTextFontSize))
                    rowControl(row, field: field)
                    if !field.help.isEmpty {
                        Text(field.help).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
                    }
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
                                               options: [("", "Non défini"), ("true", "Oui"), ("false", "Non")], selection: selection)
            } else {
                Toggle(field.label, isOn: Binding(
                    get: { selection.wrappedValue == "true" },
                    set: { selection.wrappedValue = $0 ? "true" : "false" }
                )).labelsHidden().toggleStyle(.checkbox)
            }
        case .choice(let choices):
            let options = (field.required ? [] : [("", "Non défini")]) + choices.map { ($0, $0) }
            SettingsCollectionChoicePicker(fontSize: fonts.settingsTextFontSize, label: field.label,
                                           options: options, selection: selection)
        case .color:
            HStack {
                ColorPicker(field.label, selection: Binding(
                    get: { NSColor(hex: selection.wrappedValue).map { Color(nsColor: $0) } ?? .clear },
                    set: { selection.wrappedValue = $0.settingsHexString }
                ), supportsOpacity: true).labelsHidden()
                TextField("Non défini", text: selection).textFieldStyle(.roundedBorder)
            }
        default:
            TextField(field.required ? "Valeur requise" : "Non défini", text: selection)
                .textFieldStyle(.roundedBorder).accessibilityLabel(field.label)
        }
    }
}

/// Comme les menus principaux, ces choix natifs suivent la taille choisie dans les paramètres.
private struct SettingsCollectionChoicePicker: NSViewRepresentable {
    let fontSize: Double
    let label: String
    let options: [(raw: String, label: String)]
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        var values = options
        let missing = !values.contains { $0.raw == selection }
        if missing { values.append((selection, "\(selection) (valeur actuelle)")) }
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: max(30, fontSize + 12))
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
