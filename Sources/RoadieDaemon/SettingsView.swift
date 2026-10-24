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
                if group.descriptors.count != 1 || group.descriptors.first?.collection == nil {
                    Text(group.title).font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                card(group.descriptors)
            }
        }
    }

    private var invalidBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Le fichier de configuration est invalide", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                .foregroundStyle(.red)
            ForEach(Array(model.validity.messages.enumerated()), id: \.offset) { _, message in
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
                SettingsFormRow("Fichier de configuration", fonts: fonts) {
                    Text(model.service.configPath)
                        .font(.system(size: fonts.settingsTextFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsFormRow("État", fonts: fonts) {
                    Text(model.validityText).foregroundStyle(model.isLocked ? .red : .primary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button("Recharger") { model.reloadConfig() }
                            Button("Diagnostic") { model.runDiagnostic() }
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Recharger") { model.reloadConfig() }
                            Button("Diagnostic") { model.runDiagnostic() }
                        }
                    }
                    SettingsDisclosureSection("Outils avancés") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Éditeur intégré") { advancedOpen = true }
                            Button("Ouvrir dans un éditeur externe") { openConfigFile() }
                        }
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

/// Même grille pour les réglages simples ; les collections gardent leur largeur de travail.
private struct SettingRow: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor
    @State private var advancedOpen = false
    @FocusState private var fieldFocused: Bool
    private var fonts: InterfaceConfig { model.interfaceFonts }
    private var isFontSize: Bool { descriptor.key == "font_size" || descriptor.key.hasSuffix("_font_size") }
    private var displayLabel: String {
        descriptor.label.replacingOccurrences(of: " (points)", with: "")
            .replacingOccurrences(of: "(secondes)", with: "(s)")
            .replacingOccurrences(of: "(millisecondes)", with: "(ms)")
    }
    private var reset: (() -> Void)? {
        guard descriptor.readOnlyReason == nil, !model.isDefault(descriptor), !model.isLocked else { return nil }
        return { model.reset(descriptor) }
    }
    private var helpText: String {
        [descriptor.help, descriptor.label.contains(" (points)") ? "Unité : points." : nil,
         descriptor.readOnlyReason ?? model.rangeText(descriptor)].compactMap { $0 }.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if descriptor.collection != nil || descriptor.readOnlyReason != nil {
                HStack(alignment: .center, spacing: 14) {
                    SettingsFieldLabel(title: displayLabel, help: helpText, fonts: fonts, prominent: true)
                    if let reset { SettingsResetButton(action: reset) }
                }
                if descriptor.readOnlyReason != nil { Button("Éditeur intégré") { advancedOpen = true } }
                else { control.disabled(model.isLocked).accessibilityLabel(descriptor.label) }
            } else {
                SettingsFormRow(displayLabel, help: helpText, fonts: fonts, reset: reset) {
                    control.disabled(model.isLocked)
                }
            }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, descriptor.collection != nil ? 14 : 2)
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
            VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if isFontSize || ["rail.stages.reorder_magnetism", "overview.background_blur", "overview.selection_width"].contains(descriptor.id),
                   case .double(let range?) = descriptor.kind {
                    Slider(value: Binding(
                        get: {
                            if case .double(let value) = model.value(descriptor) {
                                return min(range.upperBound, max(range.lowerBound, value))
                            }
                            return range.lowerBound
                        },
                        set: { model.apply(descriptor, raw: SettingsService.display(.double($0))) }
                    ), in: range, step: 1)
                    .frame(minWidth: 48, maxWidth: .infinity)
                    .accessibilityLabel(descriptor.label)
                }
                HStack(spacing: 4) {
                    field.frame(width: max(70, fonts.settingsTextFontSize * 4.5))
                    Stepper("", onIncrement: { model.step(descriptor, by: 1) }, onDecrement: { model.step(descriptor, by: -1) })
                        .labelsHidden()
                        .accessibilityLabel("Ajuster : \(descriptor.label)")
                }
            }
            if descriptor.id == "overview.background_blur", case .double(let percent) = model.value(descriptor) {
                OverviewBlurPreview(percent: percent)
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
                ), label: descriptor.label)
                .frame(maxWidth: .infinity)
            } else if descriptor.key == "search_hotkey" || descriptor.id == "overview.hotkey" {
                ShortcutRecorderControl(value: model.text(for: descriptor), fontSize: fonts.settingsTextFontSize) {
                    model.apply(descriptor, raw: $0)
                }
            } else {
                field.frame(maxWidth: .infinity)
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

/// Aperçu du flou de la vue d’ensemble : le fond d’écran réel, le même flou et le même voile, avec deux
/// cartes factices pour juger la lisibilité. Recalculé à chaque mouvement du curseur (miniature de 480 pixels).
private struct OverviewBlurPreview: View {
    let percent: Double

    var body: some View {
        let screen = NSScreen.main
        let image = screen.flatMap { OverviewWallpaper.blurred(for: $0, percent: percent, maxPixel: 480) }
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .windowBackgroundColor)
                Text("Fond d’écran illisible : flou système").font(.caption).foregroundStyle(.secondary)
            }
            Color(nsColor: OverviewWallpaper.veil)
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.85))
                        .frame(width: 64, height: 40).shadow(radius: 4, y: 2)
                }
            }
        }
        .frame(width: 240, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .accessibilityLabel("Aperçu du flou : \(Int(percent)) %")
    }
}
