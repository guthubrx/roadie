import Foundation
import RoadieCore
import TOMLKit

/// Service de lecture, validation et écriture sécurisée des raccourcis globaux `[[shortcuts]]`
/// et d'initialisation de `config.toml` (Spec 166). Réutilise `ConfigFileEditor` pour conserver
/// intacts les commentaires et le reste de la configuration utilisateur.
public struct ShortcutConfigService {
    public struct CheckReport: Equatable, Codable, Sendable {
        public var total: Int
        public var active: Int
        public var issues: [String]
        public var valid: Bool { issues.isEmpty }
    }

    public struct InitResult: Equatable, Codable, Sendable {
        public var path: String
        public var preset: String
        public var shortcutCount: Int
        public var created: Bool
    }

    private let configReload: ConfigReloadService

    public init(configReload: ConfigReloadService = .shared) {
        self.configReload = configReload
    }

    public func resolvedConfigPath(_ explicit: String?) -> String {
        let raw = explicit ?? configReload.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        return NSString(string: raw).expandingTildeInPath
    }

    /// Initialise un fichier `config.toml` neuf avec le préréglage choisi. Refuse d'écraser un fichier
    /// existant sauf si `force == true`.
    public func initConfig(at explicitPath: String?, preset: ShortcutPresetID?, force: Bool = false) throws -> InitResult {
        let path = resolvedConfigPath(explicitPath)
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path), !force {
            throw NSError(
                domain: "Roadie.ShortcutConfigService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: tr(
                    "Le fichier existe déjà : \(path) (ajoutez --force pour le remplacer)",
                    "File already exists: \(path) (pass --force to overwrite)"
                )]
            )
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = ShortcutPresets.renderDefaultConfigTOML(preset: preset)
        try content.write(to: url, atomically: true, encoding: .utf8)
        reloadIfActive(path: path)
        let count = preset.map { ShortcutPresets.preset(for: $0).shortcuts.count } ?? 0
        return InitResult(path: path, preset: preset?.rawValue ?? "none", shortcutCount: count, created: true)
    }

    /// Applique un préréglage de raccourcis dans `config.toml` (fusion non-destructive par défaut).
    public func applyPreset(
        _ id: ShortcutPresetID,
        configPath: String?,
        replaceExisting: Bool = false,
        dryRun: Bool = false
    ) throws -> ShortcutMergeReport {
        let path = resolvedConfigPath(configPath)
        let existing = try loadShortcuts(at: path)
        let report = ShortcutPresets.merge(id, into: existing, replaceExisting: replaceExisting)
        if !dryRun, (!report.added.isEmpty || replaceExisting) {
            try saveShortcuts(report.resultingShortcuts, at: path)
            reloadIfActive(path: path)
        }
        return report
    }

    /// Ajoute un raccourci unique et recharge la configuration.
    public func addShortcut(keys: String, command: String, configPath: String?) throws -> CommandShortcut {
        let candidate = CommandShortcut(keys: keys, command: command, enabled: true)
        guard !candidate.keys.isEmpty, !candidate.arguments.isEmpty else {
            throw NSError(
                domain: "Roadie.ShortcutConfigService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: tr(
                    "Combinaison ou commande invalide (ex. alt+right \"focus right\").",
                    "Invalid key combination or command (e.g. alt+right \"focus right\")."
                )]
            )
        }
        let path = resolvedConfigPath(configPath)
        var current = try loadShortcuts(at: path)
        if current.contains(where: { $0.enabled && $0.keys == candidate.keys }) {
            throw NSError(
                domain: "Roadie.ShortcutConfigService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: tr(
                    "La combinaison \(candidate.keys) est déjà utilisée par un raccourci actif.",
                    "Key combination \(candidate.keys) is already used by an active shortcut."
                )]
            )
        }
        current.append(candidate)
        try saveShortcuts(current, at: path)
        reloadIfActive(path: path)
        return candidate
    }

    /// Supprime les raccourcis correspondant à une combinaison normalisée et recharge.
    public func removeShortcut(keys: String, configPath: String?) throws -> Int {
        let normalized = CommandShortcut(keys: keys, command: "noop").keys
        guard !normalized.isEmpty else { return 0 }
        let path = resolvedConfigPath(configPath)
        let current = try loadShortcuts(at: path)
        let remaining = current.filter { $0.keys != normalized }
        let removed = current.count - remaining.count
        if removed > 0 {
            try saveShortcuts(remaining, at: path)
            reloadIfActive(path: path)
        }
        return removed
    }

    /// Vérifie les raccourcis configurés contre la disposition clavier courante (syntaxe et collisions).
    public func check(configPath: String?, layout: [UInt32: String]) throws -> CheckReport {
        let path = resolvedConfigPath(configPath)
        let shortcuts = try loadShortcuts(at: path)
        let planned = RoadieCommandHotkeys.plan(shortcuts, layout: layout)
        return CheckReport(total: shortcuts.count, active: planned.entries.count, issues: planned.issues)
    }

    public func list(configPath: String?) throws -> [CommandShortcut] {
        try loadShortcuts(at: resolvedConfigPath(configPath))
    }

    private func loadShortcuts(at path: String) throws -> [CommandShortcut] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try RoadieConfigLoader.load(from: path).shortcuts
    }

    private func saveShortcuts(_ shortcuts: [CommandShortcut], at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let fragments = shortcuts.map(ShortcutPresets.tomlFragment(for:))
        let edited: String
        switch ConfigFileEditor.replaceCollectionSections(original, table: "shortcuts", fragments: fragments) {
        case .success(let text):
            edited = text
        case .failure(let error):
            throw NSError(
                domain: "Roadie.ShortcutConfigService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: SettingsService.message(error)]
            )
        }
        // Valider le TOML obtenu avant de l'écrire sur disque.
        _ = try TOMLDecoder().decode(RoadieConfig.self, from: edited)
        try edited.write(to: url, atomically: true, encoding: .utf8)
    }

    private func reloadIfActive(path: String) {
        let activePath = NSString(string: configReload.state.activePath ?? RoadieConfigLoader.defaultConfigPath()).expandingTildeInPath
        let targetURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let activeURL = URL(fileURLWithPath: activePath).resolvingSymlinksInPath()
        guard targetURL == activeURL else { return }
        _ = configReload.reload(path: path)
        NotificationCenter.default.post(name: .roadieConfigDidReload, object: nil)
    }
}
