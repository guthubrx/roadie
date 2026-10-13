import AppKit
import SwiftUI

/// Fenêtre de réglages (contracts/settings.md « Fenêtre ») : affichage mince au-dessus de `SettingsViewModel`.
/// Les couleurs viennent du système : l'apparence claire ou sombre suit macOS.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    // MARK: - Colonne gauche

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Rechercher", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 10)
            // Pas de sélection pendant une recherche : cliquer une catégorie quitte la recherche.
            List(selection: Binding(
                get: { model.isSearching ? nil : model.category },
                set: { if let category = $0 { model.select(category) } }
            )) {
                ForEach(SettingCategory.allCases, id: \.self) { category in
                    Label(category.label, systemImage: category.symbolName).tag(category)
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Zone droite

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.isLocked { invalidBanner }
                if model.isSearching {
                    if model.sections.isEmpty {
                        Text(String("Aucun réglage ne correspond à « \(model.query) »."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.sections) { section in
                        Text(section.category.label).font(.headline)
                        card(section.descriptors)
                    }
                } else {
                    Text(model.category.label).font(.title2.bold())
                    if model.category == .general {
                        general
                    } else {
                        ForEach(model.sections) { card($0.descriptors) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var invalidBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Le fichier de configuration est invalide", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            ForEach(Array(model.validity.messages.prefix(10).enumerated()), id: \.offset) { _, message in
                Text(message).font(.caption).textSelection(.enabled)
            }
            Button("Ouvrir le fichier") { openConfigFile() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
    }

    /// Cartes arrondies sur fond groupé, comme les Réglages de macOS.
    private func card(_ descriptors: [SettingDescriptor]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                if index > 0 { Divider().padding(.leading, 14) }
                SettingRow(model: model, descriptor: descriptor, openConfigFile: openConfigFile)
            }
        }
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Fichier de configuration") {
                    Text(model.service.configPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("État") {
                    Text(model.validityText).foregroundStyle(model.isLocked ? .red : .primary)
                }
                HStack {
                    Button("Ouvrir le fichier de configuration") { openConfigFile() }
                    Button("Recharger") { model.reloadConfig() }
                    Button("Diagnostic") { model.runDiagnostic() }
                }
                if let notice = model.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(cardBackground)
            if let diagnostic = model.diagnostic {
                ScrollView {
                    Text(diagnostic)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 160, maxHeight: 320)
                .background(cardBackground)
            }
        }
    }

    private func openConfigFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: model.service.configPath))
    }
}

// MARK: - Ligne d'un réglage

/// Libellé, description, contrôle à droite, « Rétablir » si la valeur n'est pas celle par défaut,
/// ligne rouge sous un réglage refusé.
private struct SettingRow: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    let openConfigFile: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.label)
                    Text(descriptor.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = descriptor.readOnlyReason ?? model.rangeText(descriptor) {
                        Text(detail).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 12)
                if descriptor.readOnlyReason != nil {
                    Button("Ouvrir le fichier de configuration", action: openConfigFile)
                } else {
                    if !model.isDefault(descriptor) {
                        Button("Rétablir") { model.reset(descriptor) }
                            .buttonStyle(.link)
                            .font(.caption)
                            .disabled(model.isLocked)
                    }
                    control.disabled(model.isLocked)
                }
            }
            if let error = model.errors[descriptor.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var control: some View {
        switch descriptor.kind {
        case .bool:
            Toggle("", isOn: Binding(
                get: { model.value(descriptor) == .bool(true) },
                set: { model.apply(descriptor, raw: $0 ? "true" : "false") }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        case .int, .double:
            HStack(spacing: 4) {
                field.frame(width: 90)
                Stepper("", onIncrement: { model.step(descriptor, by: 1) }, onDecrement: { model.step(descriptor, by: -1) })
                    .labelsHidden()
            }
        case .choice(let choices):
            Picker("", selection: Binding(
                get: { model.text(for: descriptor) },
                set: { model.apply(descriptor, raw: $0) }
            )) {
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 200)
        case .text:
            field.frame(width: 240)
        case .color:
            HStack(spacing: 6) {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: model.text(for: descriptor)) ?? .clear },
                    set: { model.setColor(descriptor, hex: $0.hexString) }
                ), supportsOpacity: true)
                .labelsHidden()
                field.frame(width: 100)
            }
        }
    }

    /// Champ validé par Retour ou par la perte du focus.
    private var field: some View {
        TextField(descriptor.defaultValue == .unset ? "non défini" : "", text: Binding(
            get: { model.text(for: descriptor) },
            set: { model.drafts[descriptor.id] = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .focused($fieldFocused)
        .onSubmit { model.commitDraft(descriptor) }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { model.commitDraft(descriptor) }
        }
    }
}

// MARK: - Couleurs `#RRGGBB` / `#RRGGBBAA`

private extension Color {
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let raw = UInt64(digits, radix: 16) else { return nil }
        let value = digits.count == 6 ? raw << 8 | 0xFF : raw
        func component(_ shift: UInt64) -> Double { Double((value >> shift) & 0xFF) / 255 }
        self.init(.sRGB, red: component(24), green: component(16), blue: component(8), opacity: component(0))
    }

    /// `#RRGGBB`, ou `#RRGGBBAA` si la couleur est transparente.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let parts = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
        return parts[3] < 255 ? rgb + String(format: "%02X", parts[3]) : rgb
    }
}
