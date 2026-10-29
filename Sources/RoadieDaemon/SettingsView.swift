import AppKit
import SwiftUI
import RoadieCore

/// Fenêtre de réglages (contracts/settings.md « Fenêtre ») : affichage mince au-dessus de `SettingsViewModel`.
/// Les couleurs viennent du système : l'apparence claire ou sombre suit macOS.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    /// Raccourcis BTT lus à l'ouverture : la recherche trouve aussi les commandes (session 108).
    @ObservedObject private var bttCatalog = BTTTriggerCatalog.shared
    private var fonts: InterfaceConfig { model.interfaceFonts }
    @State private var advancedOpen = false
    /// Réglage choisi dans la colonne de recherche : la zone droite y descend et le surligne.
    @State private var scrollTarget: String?
    @State private var typedQuery = ""
    @State private var searchDelay: Task<Void, Never>?

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
        .onAppear { bttCatalog.reload(); typedQuery = model.query }
    }

    // MARK: - Colonne gauche

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(tr("Rechercher dans tous les réglages", "Search all settings"), text: $typedQuery)
                .textFieldStyle(.roundedBorder)
                .onExitCommand { typedQuery = ""; model.query = "" }
                .padding([.horizontal, .top], 10)
                // Recherche lancée après une pause de frappe de 80 ms (session 107) : « police » tapé d'un trait ne
                // recalcule pas six fois la fenêtre.
                .onChange(of: typedQuery) { _, text in
                    searchDelay?.cancel()
                    searchDelay = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        guard !Task.isCancelled else { return }
                        model.query = text
                    }
                }
                .onChange(of: model.query) { _, query in if query != typedQuery { typedQuery = query } }
            if model.isSearching {
                searchSidebar
            } else {
                List(selection: Binding(
                    get: { model.category },
                    set: { if let category = $0 { model.select(category) } }
                )) {
                    ForEach(SettingCategory.allCases, id: \.self) { category in
                        categoryLabel(category).tag(category)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func categoryLabel(_ category: SettingCategory, count: Int? = nil) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(category.label)
                    .font(.system(size: fonts.settingsTextFontSize))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let count {
                    Spacer(minLength: 4)
                    Text("\(count)").font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: category.symbolName).font(.system(size: min(16, fonts.settingsTextFontSize)))
        }
    }

    /// Recherche (session 107) : la colonne ne garde que les catégories trouvées, avec leurs réglages.
    /// Un clic sur une catégorie restreint la zone droite ; un clic sur un réglage y descend.
    private var searchSidebar: some View {
        let results = model.searchResults
        return List {
            if results.isEmpty {
                Text(tr("Aucun réglage", "No settings")).foregroundStyle(.secondary)
            } else {
                sidebarButton(selected: model.searchFocus == nil) { model.searchFocus = nil; scrollTarget = nil } label: {
                    Label(tr("Tous les résultats (\(results.reduce(0) { $0 + $1.descriptors.count }))", "All results (\(results.reduce(0) { $0 + $1.descriptors.count }))"), systemImage: "line.3.horizontal.decrease")
                }
            }
            ForEach(results) { section in
                sidebarButton(selected: model.searchFocus == section.category) {
                    model.searchFocus = section.category
                    scrollTarget = nil
                } label: { categoryLabel(section.category, count: section.descriptors.count) }
                ForEach(section.descriptors.prefix(8), id: \.id) { descriptor in
                    sidebarButton(selected: false) {
                        model.searchFocus = section.category
                        scrollTarget = descriptor.id
                    } label: {
                        Text(descriptor.label)
                            .font(.system(size: fonts.settingsHelpFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.leading, 26)
                    }
                }
                if section.descriptors.count > 8 {
                    Text(tr("et \(section.descriptors.count - 8) autres", "and \(section.descriptors.count - 8) more"))
                        .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.tertiary)
                        .padding(.leading, 26)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarButton(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .listRowBackground(selected ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Zone droite

    private var detail: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.isLocked { invalidBanner }
                if model.isSearching {
                    if model.sections.isEmpty {
                        Text(String(tr("Aucun réglage ne correspond à « \(model.query) ».", "No setting matches “\(model.query)”.")))
                            .foregroundStyle(.secondary)
                    }
                    lazyResults(model.sections)
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
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            DispatchQueue.main.async { withAnimation { proxy.scrollTo(target, anchor: .top) } }
        }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Résultats de recherche (session 107) : une ligne par élément, construite seulement quand elle devient
    /// visible. Une recherche large (« p », 230 réglages) ne fabrique plus toutes ses lignes d'un coup.
    private func lazyResults(_ sections: [SettingsSection]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SettingsDetailItem.items(sections)) { item in
                switch item.kind {
                case .title(let title):
                    Text(title).font(.system(size: fonts.settingsTitleFontSize, weight: .bold)).padding(.top, 16).padding(.bottom, 4)
                case .group(let title):
                    Text(title).font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                        .foregroundStyle(.secondary).padding(.top, 12).padding(.bottom, 8)
                case .row(let descriptor, let first, let last):
                    let shape = UnevenRoundedRectangle(topLeadingRadius: first ? 10 : 0, bottomLeadingRadius: last ? 10 : 0,
                                                       bottomTrailingRadius: last ? 10 : 0, topTrailingRadius: first ? 10 : 0)
                    SettingRow(model: model, descriptor: descriptor)
                        .background(scrollTarget == descriptor.id ? RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)) : nil)
                        .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(shape.stroke(Color(nsColor: .separatorColor)))
                        .id(descriptor.id)
                }
            }
        }
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
            Label(tr("Le fichier de configuration est invalide", "The configuration file is invalid"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                .foregroundStyle(.red)
            ForEach(Array(model.validity.messages.enumerated()), id: \.offset) { _, message in
                Text(message).font(.system(size: fonts.settingsHelpFontSize)).textSelection(.enabled)
            }
            Button(tr("Corriger dans l'éditeur intégré", "Fix in the built-in editor")) { advancedOpen = true }
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
                    .id(descriptor.id)
                    .background(scrollTarget == descriptor.id ? RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)) : nil)
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
                SettingsFormRow(tr("Fichier de configuration", "Configuration file"), fonts: fonts) {
                    Text(model.service.configPath)
                        .font(.system(size: fonts.settingsTextFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsFormRow(tr("État", "Status"), fonts: fonts) {
                    Text(model.validityText).foregroundStyle(model.isLocked ? .red : .primary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button(tr("Recharger", "Reload")) { model.reloadConfig() }
                            Button(tr("Diagnostic", "Diagnostics")) { model.runDiagnostic() }
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            Button(tr("Recharger", "Reload")) { model.reloadConfig() }
                            Button(tr("Diagnostic", "Diagnostics")) { model.runDiagnostic() }
                        }
                    }
                    SettingsDisclosureSection(tr("Outils avancés", "Advanced tools")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(tr("Éditeur intégré", "Built-in editor")) { advancedOpen = true }
                            Button(tr("Ouvrir dans un éditeur externe", "Open in an external editor")) { openConfigFile() }
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
            .replacingOccurrences(of: "(seconds)", with: "(s)")
            .replacingOccurrences(of: "(milliseconds)", with: "(ms)")
    }
    private var reset: (() -> Void)? {
        guard descriptor.readOnlyReason == nil, !model.isDefault(descriptor), !model.isLocked else { return nil }
        return { model.reset(descriptor) }
    }
    private var helpText: String {
        [descriptor.help, descriptor.label.contains(" (points)") ? tr("Unité : points.", "Unit: points.") : nil,
         descriptor.readOnlyReason ?? model.rangeText(descriptor)].compactMap { $0 }.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if descriptor.collection != nil || descriptor.readOnlyReason != nil {
                HStack(alignment: .center, spacing: 14) {
                    SettingsFieldLabel(title: displayLabel, help: helpText, fonts: fonts, prominent: true)
                    if let reset { SettingsResetButton(action: reset) }
                }
                if descriptor.readOnlyReason != nil { Button(tr("Éditeur intégré", "Built-in editor")) { advancedOpen = true } }
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
                Button(tr("Modifier dans l'éditeur intégré", "Edit in the built-in editor")) { advancedOpen = true }
            } else {
                if descriptor.id == "switcher.shortcuts" {
                    SettingsSwitcherProfilesView(model: model, descriptor: descriptor)
                } else if descriptor.id == "shortcuts" {
                    SettingsCommandShortcutsView(model: model, descriptor: descriptor)
                } else if descriptor.id == "target_mode.btt_pause_keys" {
                    SettingsShortcutConflictsView(model: model, descriptor: descriptor)
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
                        .accessibilityLabel(tr("Ajuster : \(descriptor.label)", "Adjust: \(descriptor.label)"))
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
            } else if descriptor.category == .raccourcis {
                // Toutes les touches se règlent par appui (session 108) ; celles de la grille acceptent une touche seule.
                ShortcutRecorderControl(value: model.text(for: descriptor), fontSize: fonts.settingsTextFontSize,
                                        allowsPlainKeys: descriptor.id.hasPrefix("target_grid.")) {
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
        TextField(descriptor.defaultValue == .unset ? tr("non défini", "not set") : "", text: Binding(
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
                Text(tr("Fond d’écran illisible : flou système", "Wallpaper unreadable: system blur")).font(.caption).foregroundStyle(.secondary)
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
        .accessibilityLabel(tr("Aperçu du flou : \(Int(percent)) %", "Blur preview: \(Int(percent))%"))
    }
}

/// Élément de la liste paresseuse des résultats : titre de catégorie, titre de groupe ou ligne de réglage,
/// avec sa place dans la carte (première, dernière) pour arrondir les coins. O(n).
struct SettingsDetailItem: Identifiable {
    enum Kind {
        case title(String)
        case group(String)
        case row(SettingDescriptor, first: Bool, last: Bool)
    }
    let id: String
    let kind: Kind

    static func items(_ sections: [SettingsSection]) -> [SettingsDetailItem] {
        var items: [SettingsDetailItem] = []
        for section in sections {
            items.append(SettingsDetailItem(id: "title:" + section.category.rawValue, kind: .title(section.category.label)))
            for group in SettingsOrganization.groups(section.descriptors) {
                if group.descriptors.count != 1 || group.descriptors.first?.collection == nil {
                    items.append(SettingsDetailItem(id: "group:\(section.category.rawValue):" + group.title, kind: .group(group.title)))
                }
                for (index, descriptor) in group.descriptors.enumerated() {
                    items.append(SettingsDetailItem(id: descriptor.id, kind: .row(descriptor, first: index == 0, last: index == group.descriptors.count - 1)))
                }
            }
        }
        return items
    }
}
