import Combine
import Foundation
import RoadieCore

/// Groupe de réglages affiché dans la zone droite de la fenêtre.
struct SettingsSection: Identifiable, Equatable {
    let category: SettingCategory
    let descriptors: [SettingDescriptor]
    var id: SettingCategory { category }
}

/// État de la fenêtre de réglages (SPEC-023, contracts/settings.md « Fenêtre »), sans SwiftUI ni fenêtre :
/// catégorie courante, recherche, valeurs lues, saisies en cours, erreurs par réglage, validité du fichier.
/// La vue (`SettingsView`) ne fait qu'afficher cet état et appeler ces méthodes.
@MainActor
final class SettingsViewModel: ObservableObject {
    let service: SettingsService
    /// Dernière catégorie vue : conservée d'une ouverture à l'autre (Général à la première).
    @Published private(set) var category: SettingCategory = .general
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            searchFocus = nil
            loadVisibleValues()
        }
    }
    /// Pendant une recherche, catégorie choisie dans la colonne de gauche ; nil : tous les résultats
    /// (session 107). Effacée à chaque nouvelle saisie.
    @Published var searchFocus: SettingCategory? {
        didSet { if searchFocus != oldValue { loadVisibleValues() } }
    }
    /// Saisie en cours d'un champ, par nom de réglage ; retirée à la validation.
    @Published var drafts: [String: String] = [:]
    /// Texte gardé pour le confort de saisie, mais déjà enregistré. Ce texte n'est jamais écrit
    /// une seconde fois à la perte du focus, même si une modification externe arrive entre-temps.
    private struct AppliedDraft {
        let raw: String
        let value: SettingValue
    }
    private var appliedDrafts: [String: AppliedDraft] = [:]
    /// Cause du dernier refus, par nom de réglage.
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var validity: SettingsValidity
    /// Résultat de « Diagnostic » (sortie de `doctor`).
    @Published private(set) var diagnostic: String?
    /// Résultat de « Recharger ».
    @Published private(set) var notice: String?
    /// Les éditeurs structurés relisent leurs données sans recréer leurs contrôles ni leurs brouillons.
    @Published private(set) var collectionRevision = 0
    @Published private(set) var collectionResetRevisions: [String: Int] = [:]
    /// Valeurs lues, limitées aux réglages affichés : lire une valeur reparcourt tout le fichier
    /// (`ConfigFileEditor.readLiteral`, environ 2 ms sur le fichier réel), les 179 coûtent 0,36 s.
    @Published private var values: [String: (value: SettingValue, isDefault: Bool)] = [:]
    /// Texte de la valeur actuelle des entrées en lecture seule, par nom (valeurs d'une liste, « N entrée(s) »).
    @Published private var summaries: [String: String] = [:]

    init(service: SettingsService = .shared) {
        self.service = service
        validity = SettingsValidity(path: service.configPath, isValid: true, errorCount: 0, warningCount: 0, messages: [])
        refresh()
    }

    // MARK: - Navigation et recherche

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Fichier invalide : bandeau affiché et contrôles désactivés.
    var isLocked: Bool {
        !validity.isValid
    }

    /// Polices dérivées du cache déjà lu : aucun accès disque pendant le dessin. O(1).
    var interfaceFonts: InterfaceConfig {
        let defaults = InterfaceConfig()
        return InterfaceConfig(
            settingsTextFontSize: cachedFontSize("settings_text_font_size", fallback: defaults.settingsTextFontSize),
            settingsHelpFontSize: cachedFontSize("settings_help_font_size", fallback: defaults.settingsHelpFontSize),
            settingsTitleFontSize: cachedFontSize("settings_title_font_size", fallback: defaults.settingsTitleFontSize)
        )
    }

    private func cachedFontSize(_ key: String, fallback: Double) -> Double {
        Self.number(values["interface.\(key)"]?.value ?? .double(fallback)) ?? fallback
    }

    /// Réglages de la catégorie, ou résultats de la recherche groupés par catégorie
    /// (modifiables d'abord, puis lecture seule). O(n) - n = nombre de réglages.
    var sections: [SettingsSection] {
        guard isSearching else {
            return [SettingsSection(category: category, descriptors: SettingsCatalog.descriptors(in: category))]
        }
        let results = searchResults
        guard let searchFocus else { return results }
        return results.filter { $0.category == searchFocus }
    }

    /// Résultats de la recherche par catégorie, pour la colonne de gauche (session 107), sans le filtre
    /// `searchFocus`. O(n) - n = nombre de réglages.
    var searchResults: [SettingsSection] {
        guard isSearching else { return [] }
        let grouped = Dictionary(grouping: SettingsCatalog.search(query), by: \.category)
        return SettingCategory.allCases.compactMap { category in
            guard let found = grouped[category] else { return nil }
            let editable = found.filter { $0.readOnlyReason == nil }
            return SettingsSection(category: category, descriptors: editable + found.filter { $0.readOnlyReason != nil })
        }
    }

    /// Choisir une catégorie vide la recherche.
    func select(_ category: SettingCategory) {
        self.category = category
        query = ""
        loadVisibleValues()
    }

    /// Appelé à chaque ouverture : `nil` garde la dernière catégorie vue. La relecture complète vient
    /// de la prise de focus de la fenêtre (`refresh` par `windowDidBecomeKey`).
    func prepareForShow(category: SettingCategory?) {
        if let category { select(category) }
    }

    // MARK: - Lecture

    /// Relecture (ouverture, prise de focus, changement du fichier) : validité, puis valeurs des réglages
    /// affichés. Garde catégorie, recherche et saisies en cours.
    func refresh() {
        validity = service.validity()
        values = [:]
        summaries = [:]
        loadVisibleValues()
        collectionRevision += 1
    }

    /// Lit les valeurs affichées absentes du cache, avec une seule lecture du fichier.
    /// O(v * L) - v réglages affichés non lus, L taille du fichier.
    private func loadVisibleValues() {
        // Les polices restent accessibles dans toutes les catégories, y compris après une relecture externe.
        let displayed = SettingsCatalog.descriptors(in: .general)
            + sections.filter { $0.category != .general }.flatMap(\.descriptors)
        let missing = displayed.filter { values[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let text = service.configText()
        var read = values
        var readSummaries = summaries
        for descriptor in missing {
            read[descriptor.id] = service.value(of: descriptor, in: text)
            if descriptor.readOnlyReason != nil {
                readSummaries[descriptor.id] = service.readOnlySummary(of: descriptor, in: text)
            }
        }
        values = read
        summaries = readSummaries
        // Notre propre notification conserve le format saisi (« 8.50 »). Une valeur effective
        // différente vient d'une autre écriture : l'afficher si ce texte avait déjà été enregistré.
        let changed = appliedDrafts.compactMap { id, saved -> String? in
            guard drafts[id] == saved.raw, let current = read[id]?.value, current != saved.value else { return nil }
            return id
        }
        for id in changed {
            appliedDrafts[id] = nil
            drafts[id] = nil
        }
    }

    func value(_ descriptor: SettingDescriptor) -> SettingValue {
        values[descriptor.id]?.value ?? descriptor.defaultValue
    }

    func isDefault(_ descriptor: SettingDescriptor) -> Bool {
        values[descriptor.id]?.isDefault ?? true
    }

    /// Valeur actuelle d'une entrée en lecture seule, en texte non modifiable ; nil pour un réglage modifiable.
    func readOnlySummary(_ descriptor: SettingDescriptor) -> String? {
        summaries[descriptor.id]
    }

    /// Texte du champ : la saisie en cours, sinon la valeur actuelle (vide si non définie).
    func text(for descriptor: SettingDescriptor) -> String {
        drafts[descriptor.id] ?? Self.text(value(descriptor))
    }

    private static func text(_ value: SettingValue) -> String {
        value == .unset ? "" : SettingsService.display(value)
    }

    /// « de 2 à 12 » pour un nombre borné ; nil sinon.
    func rangeText(_ descriptor: SettingDescriptor) -> String? {
        switch descriptor.kind {
        case .int(let range?): return SettingsService.display(range)
        case .double(let range?): return SettingsService.display(range)
        default: return nil
        }
    }

    /// « valide » ou « N erreurs, M avertissements ».
    var validityText: String {
        guard validity.errorCount > 0 || validity.warningCount > 0 else { return "valide" }
        return "\(Self.count(validity.errorCount, "erreur")), \(Self.count(validity.warningCount, "avertissement"))"
    }

    private static func count(_ number: Int, _ word: String) -> String {
        "\(number) \(word)\(number > 1 ? "s" : "")"
    }

    // MARK: - Écriture

    /// Applique une valeur saisie (interrupteur, liste, pas à pas, champ validé). Refus : la cause s'affiche
    /// sous le réglage et la valeur d'origine reste affichée.
    func apply(_ descriptor: SettingDescriptor, raw: String) {
        guard !isLocked, descriptor.readOnlyReason == nil else { return }
        handle(service.set(descriptor.id, to: raw), for: descriptor, isReset: false)
    }

    /// Chaque valeur complète et valide s'applique pendant la saisie. Le texte brut reste dans le
    /// champ, même après une relecture du fichier : « 8. » peut ainsi devenir « 8.5 » sans perdre le focus.
    func editText(_ descriptor: SettingDescriptor, raw: String) {
        appliedDrafts[descriptor.id] = nil
        drafts[descriptor.id] = raw
        guard !isLocked, descriptor.readOnlyReason == nil else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, descriptor.defaultValue == .unset {
            reset(descriptor)
        } else {
            // La conversion ne touche pas au disque. Un signe isolé, une couleur partielle ou un
            // nombre hors plage reste un brouillon et ne remplace jamais la dernière valeur valide.
            guard case .success = SettingsService.convert(raw, kind: descriptor.kind) else { return }
            apply(descriptor, raw: raw)
        }
        drafts[descriptor.id] = raw
        if errors[descriptor.id] == nil {
            appliedDrafts[descriptor.id] = AppliedDraft(raw: raw, value: value(descriptor))
        }
    }

    /// « Rétablir » : retour à la valeur par défaut.
    func reset(_ descriptor: SettingDescriptor) {
        guard !isLocked, descriptor.readOnlyReason == nil else { return }
        drafts[descriptor.id] = nil
        appliedDrafts[descriptor.id] = nil
        handle(service.reset(descriptor.id), for: descriptor, isReset: true)
        if descriptor.collection != nil, errors[descriptor.id] == nil {
            collectionResetRevisions[descriptor.id, default: 0] += 1
        }
    }

    /// Une collection suit les mêmes messages et indicateurs que les champs ordinaires.
    func collectionChanged(_ descriptor: SettingDescriptor, result: SettingChangeResult) {
        handle(result, for: descriptor, isReset: false)
        if case .applied = result {
            // Le résumé scalaire n'est pas le défaut typé de la collection.
            values[descriptor.id] = service.value(of: descriptor)
        }
    }

    /// Validation d'un champ (Retour ou perte du focus). Un champ vidé d'un réglage sans défaut le rétablit.
    func commitDraft(_ descriptor: SettingDescriptor) {
        let saved = appliedDrafts.removeValue(forKey: descriptor.id)
        guard let draft = drafts.removeValue(forKey: descriptor.id) else { return }
        if saved?.raw == draft {
            // Relecture seulement : ne pas écraser une édition externe faite avant le watcher.
            values[descriptor.id] = service.value(of: descriptor)
            return
        }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != Self.text(value(descriptor)) else { return }
        if trimmed.isEmpty, descriptor.defaultValue == .unset {
            reset(descriptor)
        } else {
            apply(descriptor, raw: trimmed)
        }
    }

    /// Le sélecteur applique la couleur par le même parcours immédiat que le champ.
    func setColor(_ descriptor: SettingDescriptor, hex: String) {
        editText(descriptor, raw: hex)
    }

    /// Pas à pas : ajoute `direction` pas à la valeur, bornée à la plage. O(1).
    func step(_ descriptor: SettingDescriptor, by direction: Int) {
        switch (descriptor.kind, value(descriptor)) {
        case (.int(let range), let current):
            var next = (Self.number(current) .map { Int($0) } ?? range?.lowerBound ?? 0) + direction
            if let range { next = min(max(next, range.lowerBound), range.upperBound) }
            apply(descriptor, raw: String(next))
        case (.double(let range), let current):
            let step = Self.stepSize(range)
            // Arrondi au pas : évite 0.30000000000000004.
            var next = (((Self.number(current) ?? range?.lowerBound ?? 0) + Double(direction) * step) / step).rounded() * step
            if let range { next = min(max(next, range.lowerBound), range.upperBound) }
            apply(descriptor, raw: SettingsService.display(.double(next)))
        default:
            return
        }
    }

    private static func number(_ value: SettingValue) -> Double? {
        switch value {
        case .int(let number): return Double(number)
        case .double(let number): return number
        default: return nil
        }
    }

    /// Pas d'un flottant : 0,05 pour une plage de 0 à 1 (opacités), 0,5 jusqu'à 10, 1 au-delà.
    static func stepSize(_ range: ClosedRange<Double>?) -> Double {
        guard let range else { return 1 }
        let span = range.upperBound - range.lowerBound
        return span <= 1 ? 0.05 : span <= 10 ? 0.5 : 1
    }

    /// Pas de relecture complète ici : le watcher du fichier la déclenche après l'écriture.
    private func handle(_ result: SettingChangeResult, for descriptor: SettingDescriptor, isReset: Bool) {
        switch result {
        case .applied(_, let new):
            errors[descriptor.id] = nil
            drafts[descriptor.id] = nil
            appliedDrafts[descriptor.id] = nil
            // Rétablir retire la ligne ; une écriture qui répète le défaut n'a rien à rétablir.
            values[descriptor.id] = (new, isDefault: isReset || new == descriptor.defaultValue)
        case .rejected(let reason):
            errors[descriptor.id] = reason
        }
    }

    // MARK: - Actions de la catégorie Général

    /// Résultat de `roadie doctor`, exécuté dans le processus. Synchrone, sur le thread principal comme `doctor`
    /// par le socket : la fenêtre se fige le temps du diagnostic (limite connue et acceptée, SPEC-023 T039).
    func runDiagnostic() {
        let response = CLICommandRouter().run(["doctor"])
        diagnostic = [response.stdout, response.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Rechargement explicite de la configuration du processus.
    func reloadConfig() {
        let result = ConfigReloadService.shared.reload(path: service.configPath)
        notice = result.status == .applied
            ? "Configuration rechargée."
            : "Rechargement refusé : \(result.error ?? "fichier invalide")"
        refresh()
    }
}
