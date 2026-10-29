import SwiftUI
import RoadieCore

/// Les seules configurations complexes utilisent le texte TOML, dans la fenêtre Roadie.
/// Le fichier complet peut être réparé ici quand les contrôles ordinaires sont protégés.
struct SettingsAdvancedEditor: View {
    @ObservedObject var model: SettingsViewModel
    let descriptor: SettingDescriptor?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var original = ""
    @State private var collectionOriginal: CollectionValue?
    @State private var error: String?
    @State private var notice: String?
    private var fonts: RoadieCore.InterfaceConfig { model.interfaceFonts }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(descriptor?.label ?? tr("Éditeur avancé intégré", "Built-in advanced editor"))
                .font(.system(size: fonts.settingsTitleFontSize, weight: .bold))
            Text(descriptor == nil
                 ? tr("Corrigez la configuration ici. Enregistrer valide l'ensemble avant de remplacer le fichier ; une erreur conserve la version actuelle.", "Fix the configuration here. Save checks everything before replacing the file; an error keeps the current version.")
                 : tr("Les hooks sont une structure complexe reconnue par la configuration. Roadie ne les exécute pas actuellement. Enregistrer valide le bloc avant de l'appliquer.", "Hooks are a complex structure recognized by the configuration. Roadie does not run them yet. Save checks the block before applying it."))
                .font(.system(size: fonts.settingsHelpFontSize)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: fonts.settingsTextFontSize, design: .monospaced))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel(descriptor?.label ?? tr("Configuration TOML complète", "Full TOML configuration"))
            if let error { Text(error).foregroundStyle(.red).font(.system(size: fonts.settingsHelpFontSize)) }
            if let notice { Text(notice).foregroundStyle(.secondary).font(.system(size: fonts.settingsHelpFontSize)) }
            HStack {
                Button(tr("Recharger", "Reload")) { load() }
                Spacer()
                Button(tr("Fermer", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Enregistrer", "Save")) { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, idealWidth: 860, minHeight: 520, idealHeight: 680)
        .onAppear { load() }
    }

    private func load() {
        error = nil
        notice = nil
        if let descriptor {
            switch model.service.collection(of: descriptor) {
            case .success(let value):
                guard case .advanced(let raw) = value else { return }
                collectionOriginal = value
                text = raw
            case .failure(let failure): error = failure.message
            }
        } else {
            switch model.service.readConfig() {
            case .success(let raw): original = raw; text = raw
            case .failure(let failure): error = failure.message
            }
        }
    }

    private func save() {
        let result: SettingChangeResult
        if let descriptor {
            result = model.service.setCollection(descriptor.id, .advanced(text), expected: collectionOriginal)
            model.collectionChanged(descriptor, result: result)
        } else {
            result = model.service.replaceConfigText(text, expectedOriginal: original)
        }
        switch result {
        case .rejected(let reason): error = reason; notice = nil
        case .applied:
            error = nil
            notice = tr("Configuration enregistrée et appliquée.", "Configuration saved and applied.")
            original = text
            // Le writer peut développer un fragment compact. Le prochain enregistrement
            // doit comparer le contenu réellement écrit, sans remplacer la saisie en cours.
            if let descriptor, case .success(let stored) = model.service.collection(of: descriptor) {
                collectionOriginal = stored
            }
            model.refresh()
        }
    }
}
