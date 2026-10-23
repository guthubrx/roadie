import AppKit
import SwiftUI
import RoadieCore

/// Fenêtre de réglages (contracts/settings.md « Fenêtre ») : affichage mince au-dessus de `SettingsViewModel`.
/// Les couleurs viennent du système : l'apparence claire ou sombre suit macOS.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    private var fonts: InterfaceConfig { model.interfaceFonts }
    @State private var advancedOpen = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: min(320, max(240, fonts.settingsTextFontSize * 12)))
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .font(.system(size: fonts.settingsTextFontSize))
        .buttonStyle(SettingsButtonStyle(fontSize: fonts.settingsTextFontSize))
        .sheet(isPresented: $advancedOpen) { SettingsAdvancedEditor(model: model, descriptor: nil) }
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
                    Label {
                        Text(category.label)
                            .font(.system(size: fonts.settingsTextFontSize))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: category.symbolName).font(.system(size: min(16, fonts.settingsTextFontSize)))
                    }
                        .tag(category)
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
                        Text(section.category.label).font(.system(size: fonts.settingsTitleFontSize, weight: .bold))
                        grouped(section.descriptors)
                    }
                } else {
                    Text(model.category.label).font(.system(size: fonts.settingsTitleFontSize, weight: .bold))
                    if model.category == .general {
                        general
                    } else {
                        ForEach(model.sections) { grouped($0.descriptors) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func grouped(_ descriptors: [SettingDescriptor]) -> some View {
        ForEach(SettingsOrganization.groups(descriptors)) { group in
            VStack(alignment: .leading, spacing: 10) {
                Text(group.title).font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                card(group.descriptors)
            }
        }
    }

    private var invalidBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Le fichier de configuration est invalide", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                .foregroundStyle(.red)
            ForEach(Array(model.validity.messages.prefix(10).enumerated()), id: \.offset) { _, message in
                Text(message).font(.system(size: fonts.settingsHelpFontSize)).textSelection(.enabled)
            }
            Button("Corriger dans l'éditeur intégré") { advancedOpen = true }
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
                SettingRow(model: model, descriptor: descriptor)
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
            grouped(SettingsCatalog.descriptors(in: .general))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Fichier de configuration") {
                    Text(model.service.configPath)
                        .font(.system(size: fonts.settingsTextFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("État") {
                    Text(model.validityText).foregroundStyle(model.isLocked ? .red : .primary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Recharger") { model.reloadConfig() }
                    Button("Diagnostic") { model.runDiagnostic() }
                    DisclosureGroup("Outils avancés") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Éditeur intégré") { advancedOpen = true }
                            Button("Ouvrir dans un éditeur externe") { openConfigFile() }
                        }.padding(.top, 8)
                    }
                }
                if let notice = model.notice {
                    Text(notice).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(cardBackground)
            if let diagnostic = model.diagnostic {
                ScrollView {
                    Text(diagnostic)
                        .font(.system(size: fonts.settingsHelpFontSize, design: .monospaced))
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

/// Le style natif impose une petite police aux boutons ; garder la taille choisie pour leurs libellés.
private struct SettingsButtonStyle: ButtonStyle {
    let fontSize: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Ligne d'un réglage

/// Libellé et description au-dessus du contrôle, « Rétablir » si la valeur n'est pas celle par défaut,
/// ligne rouge sous un réglage refusé.
private struct SettingRow: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    @State private var advancedOpen = false
    @State private var helpOpen = false
    @FocusState private var fieldFocused: Bool
    private var fonts: InterfaceConfig { model.interfaceFonts }
    private var isFontSize: Bool { descriptor.key == "font_size" || descriptor.key.hasSuffix("_font_size") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(descriptor.label)
                    .font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button { helpOpen.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Aide : " + descriptor.label)
                    .popover(isPresented: $helpOpen) {
                        Text(descriptor.help).font(.system(size: fonts.settingsHelpFontSize))
                            .padding(16).frame(maxWidth: 380)
                    }
                Spacer(minLength: 12)
                if descriptor.kind == .bool { control.disabled(model.isLocked) }
                if descriptor.readOnlyReason == nil && !model.isDefault(descriptor) {
                    Button("Rétablir") { model.reset(descriptor) }
                        .buttonStyle(.link)
                        .font(.system(size: fonts.settingsHelpFontSize))
                        .disabled(model.isLocked)
                        .fixedSize()
                }
            }
            if let detail = descriptor.readOnlyReason ?? model.rangeText(descriptor) {
                Text(detail)
                    .font(.system(size: fonts.settingsHelpFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if descriptor.readOnlyReason != nil {
                    Button("Éditeur intégré") { advancedOpen = true }
                } else if descriptor.kind != .bool {
                    control.disabled(model.isLocked).accessibilityLabel(descriptor.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Valeur actuelle d'une entrée en lecture seule : texte sélectionnable, 6 lignes visibles au plus.
            if let summary = model.readOnlySummary(descriptor), !summary.isEmpty {
                // Hauteur qui suit le contenu, plafonnée à 6 lignes : le texte seul s'il tient, sinon un ScrollView de 6 lignes.
                let text = Text(summary)
                    .font(.system(size: fonts.settingsHelpFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                ViewThatFits(in: .vertical) {
                    text.fixedSize(horizontal: false, vertical: true)
                    ScrollView { text }
                }
                .frame(maxHeight: 6 * (fonts.settingsHelpFontSize + 5) + 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            if let error = model.errors[descriptor.id] {
                Text(error).font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .sheet(isPresented: $advancedOpen) {
            SettingsAdvancedEditor(model: model, descriptor: descriptor.collection == nil ? nil : descriptor)
        }
    }

    @ViewBuilder
    private var control: some View {
        if let collection = descriptor.collection {
            if case .advanced = collection.shape {
                Button("Modifier dans l'éditeur intégré") { advancedOpen = true }
            } else {
                if descriptor.id == "switcher.shortcuts" {
                    SettingsSwitcherProfilesView(model: model, descriptor: descriptor)
                } else {
                    SettingsCollectionEditor(model: model, descriptor: descriptor)
                }
            }
        } else {
        switch descriptor.kind {
        case .bool:
            Toggle("", isOn: Binding(
                get: { model.value(descriptor) == .bool(true) },
                set: { model.apply(descriptor, raw: $0 ? "true" : "false") }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        case .int, .double:
            VStack(alignment: .leading, spacing: 6) {
                if isFontSize || descriptor.id == "rail.stages.reorder_magnetism", case .double(let range?) = descriptor.kind {
                    Slider(value: Binding(
                        get: {
                            if case .double(let value) = model.value(descriptor) {
                                return min(range.upperBound, max(range.lowerBound, value))
                            }
                            return range.lowerBound
                        },
                        set: { model.apply(descriptor, raw: SettingsService.display(.double($0))) }
                    ), in: range, step: 1)
                    .frame(maxWidth: 320)
                    .accessibilityLabel(descriptor.label)
                }
                HStack(spacing: 4) {
                    field.frame(width: max(120, fonts.settingsTextFontSize * 7))
                    Stepper("", onIncrement: { model.step(descriptor, by: 1) }, onDecrement: { model.step(descriptor, by: -1) })
                        .labelsHidden()
                        .accessibilityLabel("Ajuster : \(descriptor.label)")
                }
            }
        case .choice:
            SettingsChoicePicker(descriptor: descriptor, fontSize: fonts.settingsTextFontSize, selection: Binding(
                get: { model.text(for: descriptor) },
                set: { model.apply(descriptor, raw: $0) }
            ))
            .frame(maxWidth: .infinity)
        case .text:
            if descriptor.key == "font_family" || descriptor.key.hasSuffix("_font_family") {
                SettingsFontFamilyPicker(fontSize: fonts.settingsTextFontSize, selection: Binding(
                    get: { model.text(for: descriptor) },
                    set: { model.apply(descriptor, raw: $0) }
                ))
                .frame(maxWidth: .infinity)
            } else if descriptor.key == "search_hotkey" {
                ShortcutRecorderControl(value: model.text(for: descriptor), fontSize: fonts.settingsTextFontSize) {
                    model.apply(descriptor, raw: $0)
                }
            } else {
                field.frame(maxWidth: 360)
            }
        case .color:
            HStack(spacing: 6) {
                ColorPicker("", selection: Binding(
                    get: { NSColor(hex: model.text(for: descriptor)).map { Color(nsColor: $0) } ?? .clear },
                    set: { model.setColor(descriptor, hex: $0.hexString) }
                ), supportsOpacity: true)
                .labelsHidden()
                field.frame(width: max(100, fonts.settingsTextFontSize * 8))
            }
        }
        }
    }

    /// Saisie immédiate ; Retour ou perte du focus termine seulement le brouillon.
    private var field: some View {
        TextField(descriptor.defaultValue == .unset ? "non défini" : "", text: Binding(
            get: { model.text(for: descriptor) },
            set: { model.editText(descriptor, raw: $0) }
        ))
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(descriptor.label)
        .focused($fieldFocused)
        .onSubmit { model.commitDraft(descriptor) }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { model.commitDraft(descriptor) }
        }
    }
}

// MARK: - Couleurs `#RRGGBB` / `#RRGGBBAA` (lecture : `NSColor(hex:)`, partagée avec le rail et les bordures)

private extension Color {
    /// `#RRGGBB`, ou `#RRGGBBAA` si la couleur est transparente.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let parts = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
        return parts[3] < 255 ? rgb + String(format: "%02X", parts[3]) : rgb
    }
}
