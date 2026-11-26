import Foundation
import RoadieCore

/// Paquet portable versionné de configuration Roadie (Spec 170).
/// Exclut volontairement `clipboard.json`, `events.jsonl`, `stages.json` (IDs de fenêtres locaux) et `zone-thumbs/`.
struct PortableConfigBundle: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var roadieVersion: String
    var configToml: String
    var projects: [StageProject]
    var displayProfiles: [DisplayProfile]

    init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        roadieVersion: String = RoadieVersion.current,
        configToml: String,
        projects: [StageProject] = [],
        displayProfiles: [DisplayProfile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.roadieVersion = roadieVersion
        self.configToml = configToml
        self.projects = projects
        self.displayProfiles = displayProfiles
    }
}

struct PortableConfigImportReport: Codable, Equatable, Sendable {
    var dryRun: Bool
    var valid: Bool
    var backupPath: String?
    var projectsImported: Int
    var profilesImported: Int
    var warnings: [String]
    var error: String?

    init(
        dryRun: Bool,
        valid: Bool,
        backupPath: String? = nil,
        projectsImported: Int = 0,
        profilesImported: Int = 0,
        warnings: [String] = [],
        error: String? = nil
    ) {
        self.dryRun = dryRun
        self.valid = valid
        self.backupPath = backupPath
        self.projectsImported = projectsImported
        self.profilesImported = profilesImported
        self.warnings = warnings
        self.error = error
    }
}

/// Service d'export et d'import portable de configuration Roadie (Spec 170).
struct PortableConfigService: Sendable {
    init() {}

    /// Remplace le préfixe personnel absolu (`/Users/<nom>/`) par `~/` pour la portabilité entre Macs.
    static func portableizePaths(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        guard !homeDirectory.isEmpty else { return text }
        let normalizedHome = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return text.replacingOccurrences(of: normalizedHome + "/", with: "~/")
    }

    func exportBundle(
        to destinationURL: URL,
        configPath: String = RoadieConfigLoader.defaultConfigPath(),
        projectStore: StageProjectStore = StageProjectStore(),
        profileStore: DisplayProfileStore = DisplayProfileStore(),
        homeDirectory: String = NSHomeDirectory()
    ) throws -> PortableConfigBundle {
        let configURL = URL(fileURLWithPath: configPath)
        let rawToml = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let sanitizedToml = Self.portableizePaths(rawToml, homeDirectory: homeDirectory)
        let projects = projectStore.load().projects.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { project -> StageProject in
                var copy = project
                copy.extraURLs = project.extraURLs.map { Self.portableizePaths($0, homeDirectory: homeDirectory) }
                return copy
            }
        let profiles = profileStore.load().profiles
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let bundle = PortableConfigBundle(
            configToml: sanitizedToml,
            projects: projects,
            displayProfiles: profiles
        )
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        try data.write(to: destinationURL, options: .atomic)
        return bundle
    }

    func importBundle(
        from sourceURL: URL,
        configPath: String = RoadieConfigLoader.defaultConfigPath(),
        projectStore: StageProjectStore = StageProjectStore(),
        profileStore: DisplayProfileStore = DisplayProfileStore(),
        dryRun: Bool = false,
        force: Bool = false
    ) -> PortableConfigImportReport {
        guard let data = try? Data(contentsOf: sourceURL) else {
            return PortableConfigImportReport(dryRun: dryRun, valid: false, error: "bundle_unreadable")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(PortableConfigBundle.self, from: data) else {
            return PortableConfigImportReport(dryRun: dryRun, valid: false, error: "invalid_bundle_json")
        }
        guard bundle.schemaVersion == 1 else {
            return PortableConfigImportReport(dryRun: dryRun, valid: false, error: "unsupported_schema_version_\(bundle.schemaVersion)")
        }

        // Valider le TOML dans un fichier temporaire avant d'écrire quoi que ce soit.
        let tmpToml = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-import-validate-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: tmpToml) }
        do {
            try bundle.configToml.write(to: tmpToml, atomically: true, encoding: .utf8)
        } catch {
            return PortableConfigImportReport(dryRun: dryRun, valid: false, error: "temp_write_failed")
        }
        let validation = RoadieConfigLoader.validate(path: tmpToml.path)
        if validation.hasErrors {
            let summary = validation.items.filter { $0.level == .error }.map(\.message).joined(separator: "; ")
            return PortableConfigImportReport(dryRun: dryRun, valid: false, error: "invalid_toml: \(summary)")
        }

        let warnings = validation.items.filter { $0.level == .warning }.map(\.message)
        if dryRun {
            return PortableConfigImportReport(
                dryRun: true,
                valid: true,
                projectsImported: bundle.projects.count,
                profilesImported: bundle.displayProfiles.count,
                warnings: warnings
            )
        }

        // Sauvegarde automatique du fichier roadies.toml existant avant remplacement.
        let targetConfigURL = URL(fileURLWithPath: configPath)
        var backupPath: String? = nil
        do {
            try FileManager.default.createDirectory(at: targetConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: targetConfigURL.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                let bak = URL(fileURLWithPath: "\(targetConfigURL.path).bak-import-\(stamp)")
                try? FileManager.default.removeItem(at: bak)
                try FileManager.default.copyItem(at: targetConfigURL, to: bak)
                backupPath = bak.path
            }
            if !bundle.configToml.isEmpty || force {
                try bundle.configToml.write(to: targetConfigURL, atomically: true, encoding: .utf8)
            }

            // Fusion additive (ou remplacement avec --force) des projets
            let existingProjects = projectStore.load()
            if force {
                for name in existingProjects.projects.values.map(\.name) {
                    _ = try projectStore.delete(name)
                }
            }
            var importedProjects = 0
            for project in bundle.projects {
                let key = LauncherMatch.fold(project.name)
                if force || existingProjects.projects[key] == nil {
                    try projectStore.save(project)
                    importedProjects += 1
                }
            }

            // Fusion additive (ou remplacement avec --force) des profils d'écrans
            var existingBook = profileStore.load()
            if force { existingBook.profiles.removeAll() }
            var importedProfiles = 0
            for profile in bundle.displayProfiles {
                let exists = existingBook.profiles.contains { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }
                if force || !exists {
                    existingBook.profiles.removeAll { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }
                    existingBook.profiles.append(profile)
                    importedProfiles += 1
                }
            }
            if importedProfiles > 0 || force {
                try profileStore.save(existingBook)
            }

            return PortableConfigImportReport(
                dryRun: false,
                valid: true,
                backupPath: backupPath,
                projectsImported: importedProjects,
                profilesImported: importedProfiles,
                warnings: warnings
            )
        } catch {
            return PortableConfigImportReport(
                dryRun: false,
                valid: false,
                backupPath: backupPath,
                warnings: warnings,
                error: error.localizedDescription
            )
        }
    }
}
