import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
struct SettingsServiceTests {
    /// Fichier riche en commentaires : commentaires de ligne et de fin de ligne, clés commentées,
    /// `#` dans une chaîne, tableau multi-lignes, `[[rules]]`, même clé dans deux tables.
    private let fixture = """
    # FR: Configuration Roadie de test.
    # EN: Test configuration.

    [tiling]
    # Méthode de tuilage.
    default_strategy = "bsp" # bsp par défaut
    gaps_outer = 8 # marge extérieure
    # gaps_outer_top = 4
    gaps_inner = 4   # entre deux fenêtres
    master_ratio = 0.6
    smart_gaps_solo = false

    [focus]
    # Le focus suit la souris ?
    focus_follows_mouse = false
    mouse_follows_focus = false # [pas une table]

    [fx.borders]
    enabled = false
    thickness = 2
    # Couleur de la fenêtre active.
    active_color = "#7AA2F7" # bleu
    inactive_color = "#414868"

    [exclusions]
    # Applications flottantes.
    floating_bundles = [
        # Réglages macOS.
        "com.apple.systempreferences", # commentaire interne
    ]

    [experimental.target_mode]
    enabled = true # mode lettres
    label_font_size = 13
    search_hotkey = "command+control+alt+f"

    [experimental.app_targets]
    enabled = false
    max_targets = 150 # plafond

    [experimental.target_grid]
    # Grille de clic.
    rows = 3
    columns = 3
    hint_characters = "azeqsdwxcrtyfghvbnuiopjklm" # 26 lettres
    overlay_fill_opacity = 0.10

    [fx.rail]
    width = 150 # points

    [[rules]]
    id = "test-float"
    # règle de test
    """

    /// Dossier temporaire propre à un test.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeService(_ text: String? = nil, file: String = "roadies.toml") throws -> (SettingsService, URL, EventLog) {
        let directory = try makeDirectory()
        let config = directory.appendingPathComponent(file)
        if let text {
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: config, atomically: true, encoding: .utf8)
        }
        let log = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        return (SettingsService(configPath: config.path, eventLog: log, afterWrite: {}), config, log)
    }

    private func mode(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func descriptor(_ id: String) throws -> SettingDescriptor {
        try #require(SettingsCatalog.find(id: id))
    }

    /// Fichiers du dossier hors fichier de configuration et journal (sauvegardes, candidats).
    private func extraFiles(_ config: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: config.deletingLastPathComponent().path)
            .filter { $0 != config.lastPathComponent && !$0.hasPrefix("events.jsonl") }
            .sorted()
    }

    // MARK: - Écriture

    @Test
    func validValueIsAppliedAndReadBack() throws {
        let (service, config, _) = try makeService(fixture)
        let rows = try descriptor("target_grid.rows")
        // `rows = 3` est écrit mais égale le défaut : `isDefault` est vrai (T034).
        #expect(service.value(of: rows) == (.int(3), true))

        #expect(service.set("target_grid.rows", to: "4") == .applied(old: .int(3), new: .int(4)))
        #expect(service.value(of: rows) == (.int(4), false))
        #expect(try read(config).contains("rows = 4\n"))
        #expect(try extraFiles(config).allSatisfy { $0.hasPrefix("roadies.toml.bak-") })
    }

    @Test
    func resetRemovesTheLineAndRestoresDefault() throws {
        let (service, config, _) = try makeService(fixture)
        let gaps = try descriptor("tiling.gaps_outer")
        #expect(service.reset("tiling.gaps_outer") == .applied(old: .double(8), new: .double(8)))
        #expect(!(try read(config)).contains("gaps_outer = "))
        #expect(try read(config).contains("# gaps_outer_top = 4"))
        // Le commentaire de fin de ligne reste, seul sur sa ligne (T036).
        #expect(try read(config).contains("\n# marge extérieure\n"))
        #expect(service.value(of: gaps) == (.double(8), true))
    }

    @Test
    func outOfRangeIsRejectedAndFileUntouched() throws {
        let (service, config, _) = try makeService(fixture)
        let before = try Data(contentsOf: config)
        guard case .rejected(let reason) = service.set("target_grid.rows", to: "99") else {
            Issue.record("refus attendu"); return
        }
        #expect(reason.contains("de 2 à 12"))
        #expect(try Data(contentsOf: config) == before)
        #expect(try extraFiles(config).isEmpty)
    }

    @Test
    func validationErrorIsRejectedAndFileUntouched() throws {
        // 4 × 3 = 12 cellules pour 9 lettres : le validateur signale une erreur.
        let text = fixture.replacingOccurrences(of: "azeqsdwxcrtyfghvbnuiopjklm", with: "azeqsdwxc")
        let (service, config, _) = try makeService(text)
        let before = try Data(contentsOf: config)
        guard case .rejected(let reason) = service.set("target_grid.rows", to: "4") else {
            Issue.record("refus attendu"); return
        }
        #expect(reason.contains("hint_characters"))
        #expect(try Data(contentsOf: config) == before)
        #expect(try extraFiles(config).isEmpty)
    }

    @Test
    func concurrentChangeIsRetriedOnce() throws {
        let (service, config, _) = try makeService(fixture)
        var calls = 0
        service.beforeReplace = {
            calls += 1
            if calls == 1 { try? (fixture + "\n# ajout externe\n").write(to: config, atomically: true, encoding: .utf8) }
        }
        #expect(service.set("tiling.gaps_outer", to: "12") == .applied(old: .double(8), new: .double(12)))
        #expect(calls == 2)
        let text = try read(config)
        #expect(text.contains("# ajout externe"))
        #expect(text.contains("gaps_outer = 12.0 # marge extérieure"))
    }

    @Test
    func concurrentChangeTwiceIsRejected() throws {
        let (service, config, _) = try makeService(fixture)
        var calls = 0
        service.beforeReplace = {
            calls += 1
            try? (fixture + "\n# ajout externe \(calls)\n").write(to: config, atomically: true, encoding: .utf8)
        }
        #expect(service.set("tiling.gaps_outer", to: "12") == .rejected(reason: "le fichier a changé pendant l'écriture"))
        #expect(try read(config) == fixture + "\n# ajout externe 2\n")
        #expect(try extraFiles(config).isEmpty)
    }

    @Test
    func twentyChangesKeepEveryOtherLine() throws {
        let (service, config, _) = try makeService(fixture)
        let changes: [(String, String, String)] = [
            ("tiling.default_strategy", "MASTERSTACK", "\"masterStack\""),
            ("tiling.gaps_outer", "12", "12.0"),
            ("tiling.gaps_inner", "6", "6.0"),
            ("tiling.master_ratio", "0,5", "0.5"),
            ("tiling.smart_gaps_solo", "oui", "true"),
            ("focus.focus_follows_mouse", "on", "true"),
            ("focus.mouse_follows_focus", "1", "true"),
            ("borders.enabled", "true", "true"),
            ("borders.thickness", "3", "3.0"),
            ("borders.active_color", "#FF0000", "\"#FF0000\""),
            ("borders.inactive_color", "#00FF0080", "\"#00FF0080\""),
            ("target_mode.enabled", "non", "false"),
            ("target_mode.label_font_size", "20", "20.0"),
            ("target_mode.search_hotkey", " command+alt+f ", "\"command+alt+f\""),
            ("app_targets.enabled", "oui", "true"),
            ("app_targets.max_targets", "200", "200"),
            ("target_grid.rows", "4", "4"),
            ("target_grid.columns", "4", "4"),
            ("target_grid.overlay_fill_opacity", "0,2", "0.2"),
            ("rail.width", "180", "180.0"),
        ]
        for (id, raw, _) in changes {
            let result = service.set(id, to: raw)
            guard case .applied = result else { Issue.record("\(id) refusé : \(result)"); return }
        }
        // Texte attendu : la fixture où seule la valeur des 20 lignes visées change
        // (clé, indentation et commentaire de fin de ligne gardés). Toutes les autres lignes sont identiques.
        let before = fixture.components(separatedBy: "\n")
        var expected = before
        for (id, _, literal) in changes {
            let d = try descriptor(id)
            let old = try #require(ConfigFileEditor.readLiteral(fixture, table: d.tablePath, key: d.key))
            let header = try #require(before.firstIndex(of: "[\(d.tablePath)]"))
            let index = try #require(before[header...].firstIndex { $0.hasPrefix("\(d.key) = ") })
            expected[index] = before[index].replacingOccurrences(of: "= \(old)", with: "= \(literal)")
        }
        #expect(try read(config).components(separatedBy: "\n") == expected)
        #expect(zip(before, expected).filter { $0 != $1 }.count == changes.count)
    }

    @Test
    func missingFileIsCreatedWithItsTable() throws {
        let (service, config, _) = try makeService(nil, file: "sous-dossier/roadies.toml")
        #expect(service.configText() == "")
        #expect(service.set("target_mode.label_font_size", to: "20") == .applied(old: .double(13), new: .double(20)))
        #expect(try read(config) == "[experimental.target_mode]\nlabel_font_size = 20.0\n")
        #expect(try extraFiles(config).isEmpty)
        #expect(try mode(config) == 0o644)
    }

    /// FR-013 : le rechargement suit chaque écriture réussie, jamais un refus ni un rétablissement sans effet.
    @Test
    func reloadRunsOnlyAfterAnActualWrite() throws {
        let directory = try makeDirectory()
        let config = directory.appendingPathComponent("roadies.toml")
        try fixture.write(to: config, atomically: true, encoding: .utf8)
        let reloads = ReloadCounter()
        let service = SettingsService(
            configPath: config.path,
            eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path),
            afterWrite: { reloads.increment() }
        )
        _ = service.set("target_grid.rows", to: "4")
        #expect(reloads.count == 1)
        _ = service.set("target_grid.rows", to: "99")
        #expect(reloads.count == 1)
        _ = service.reset("target_grid.rows")
        #expect(reloads.count == 2)
        _ = service.reset("target_grid.rows")
        #expect(reloads.count == 2)
    }

    @Test
    func onlyOneBackupPerInstance() throws {
        let (service, config, _) = try makeService(fixture)
        #expect(service.set("tiling.gaps_outer", to: "10") == .applied(old: .double(8), new: .double(10)))
        #expect(service.set("tiling.gaps_inner", to: "5") == .applied(old: .double(4), new: .double(5)))
        #expect(service.set("target_grid.rows", to: "4") == .applied(old: .int(3), new: .int(4)))
        let backups = try extraFiles(config)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(backup.hasPrefix("roadies.toml.bak-"))
        #expect(try read(config.deletingLastPathComponent().appendingPathComponent(backup)) == fixture)
    }

    @Test
    func eventsCarryNameAndResultButNeverTheValue() throws {
        let (service, _, log) = try makeService(fixture)
        guard case .applied = service.set("target_record.directory", to: "/Users/secret-dossier-xyz") else {
            Issue.record("écriture attendue"); return
        }
        guard case .rejected = service.set("target_record.directory", to: "ligne-privee-abc\nsuite") else {
            Issue.record("refus attendu"); return
        }
        let lines = log.tail(limit: 10).joined(separator: "\n")
        #expect(lines.contains("settings.changed"))
        #expect(lines.contains("target_record.directory"))
        #expect(lines.contains("applied"))
        #expect(lines.contains("rejected"))
        #expect(!lines.contains("secret-dossier-xyz"))
        #expect(!lines.contains("ligne-privee-abc"))
    }

    // MARK: - Lecture et description

    @Test
    func describeShowsDefaultAndRangeOrChoices() throws {
        let (service, _, _) = try makeService(nil)
        #expect(service.describe("target_grid.rows") == "target_grid.rows = 3 (défaut 3, de 2 à 12)")
        #expect(service.describe("tiling.default_strategy")
                == "tiling.default_strategy = bsp (défaut bsp, choix : bsp, spatialBsp, masterStack, float)")
        #expect(service.describe("target_mode.enabled") == "target_mode.enabled = true (défaut true)")
        #expect(service.describe("target_grid.overlay_fill_opacity") == "target_grid.overlay_fill_opacity = 0.1 (défaut 0.1, de 0 à 1)")
        #expect(service.describe("inconnu.reglage") == nil)
        #expect(service.set("target_mode.label_font_size", to: "20") == .applied(old: .double(13), new: .double(20)))
        #expect(service.describe("target_mode.label_font_size") == "target_mode.label_font_size = 20 (défaut 13, de 8 à 48)")
        #expect(service.describe("exclusions.floating_bundles")
                == "exclusions.floating_bundles : lecture seule : modifier le fichier de configuration")
    }

    @Test
    func validityReportsErrors() throws {
        let (valid, _, _) = try makeService(fixture)
        #expect(valid.validity().isValid)
        #expect(valid.validity().errorCount == 0)

        let text = fixture.replacingOccurrences(of: "azeqsdwxcrtyfghvbnuiopjklm", with: "az")
        let (invalid, config, _) = try makeService(text)
        let report = invalid.validity()
        #expect(report.path == config.path)
        #expect(!report.isValid)
        #expect(report.errorCount >= 1)
        #expect(report.messages.contains { $0.contains("hint_characters") })
    }

    // MARK: - Conversions et refus

    @Test
    func conversions() throws {
        let (service, config, _) = try makeService(fixture)
        #expect(service.set("tiling.smart_gaps_solo", to: "OUI") == .applied(old: .bool(false), new: .bool(true)))
        #expect(service.set("tiling.smart_gaps_solo", to: "non") == .applied(old: .bool(true), new: .bool(false)))
        #expect(service.set("tiling.master_ratio", to: "0,55") == .applied(old: .double(0.6), new: .double(0.55)))
        #expect(service.set("borders.active_color", to: "#a1b2c3") == .applied(old: .string("#7AA2F7"), new: .string("#a1b2c3")))
        #expect(service.set("target_record.directory", to: #"  dossier "cité" \ fin  "#)
                == .applied(old: .string("~/.local/state/roadies/records"), new: .string(#"dossier "cité" \ fin"#)))
        #expect(try read(config).contains(#"directory = "dossier \"cité\" \\ fin""#))
        let directory = try descriptor("target_record.directory")
        #expect(service.value(of: directory).value == .string(#"dossier "cité" \ fin"#))

        for (id, raw) in [
            ("tiling.smart_gaps_solo", "peut-être"),
            ("target_grid.rows", "3.5"),
            ("tiling.master_ratio", "abc"),
            ("tiling.default_strategy", "spirale"),
            ("borders.active_color", "#12345"),
            ("borders.active_color", "rouge"),
            // Chiffres pleine chasse : `isHexDigit` les accepte, `NSColor(hex:)` ne les lit pas.
            ("borders.active_color", "#ＡＢＣＤＥＦ"),
            ("target_record.directory", "a\nb"),
            ("target_record.directory", "a\rb"),
            // Caractère de contrôle : interdit dans une chaîne TOML, refusé par la validation du candidat.
            ("target_record.directory", "a\u{1B}b"),
        ] {
            guard case .rejected = service.set(id, to: raw) else {
                Issue.record("\(id) = \(raw) aurait dû être refusé"); continue
            }
        }
        guard case .rejected(let reason) = service.set("tiling.default_strategy", to: "spirale") else { return }
        #expect(reason.contains("bsp, spatialBsp, masterStack, float"))
    }

    @Test
    func unknownAndReadOnlyAreRejected() throws {
        let (service, config, _) = try makeService(fixture)
        let before = try Data(contentsOf: config)
        guard case .rejected = service.set("inconnu.reglage", to: "1") else { Issue.record("refus attendu"); return }
        #expect(service.set("exclusions.floating_bundles", to: "x")
                == .rejected(reason: "lecture seule : modifier le fichier de configuration"))
        #expect(service.reset("exclusions.floating_bundles")
                == .rejected(reason: "lecture seule : modifier le fichier de configuration"))
        #expect(try Data(contentsOf: config) == before)
    }

    @Test
    func sameKeyInTwoTablesIsIndependent() throws {
        let (service, _, _) = try makeService(fixture)
        let lettres = try descriptor("target_mode.enabled")
        let apps = try descriptor("app_targets.enabled")
        #expect(service.set("target_mode.enabled", to: "false") == .applied(old: .bool(true), new: .bool(false)))
        #expect(service.value(of: lettres) == (.bool(false), false))
        // `app_targets.enabled = false` égale le défaut (T034).
        #expect(service.value(of: apps) == (.bool(false), true))
        #expect(service.set("app_targets.enabled", to: "true") == .applied(old: .bool(false), new: .bool(true)))
        #expect(service.value(of: lettres) == (.bool(false), false))
        #expect(service.value(of: apps) == (.bool(true), false))
    }

    // MARK: - Robustesse de l'écriture (T035)

    @Test
    func unreadableFileIsRejectedAndLeftByteForByte() throws {
        let (service, config, _) = try makeService(nil)
        // « é » en Latin-1 (0xE9) suivi d'une lettre : séquence invalide en UTF-8.
        try (Data("[tiling]\ngaps_outer = 8 # marge ext".utf8) + [0xE9] + Data("rieure\n".utf8)).write(to: config)
        let before = try Data(contentsOf: config)
        #expect(service.readConfig() == .failure(SettingsFileError(message: "le fichier de configuration n'est pas lisible en UTF-8")))
        #expect(service.configText() == "")
        #expect(service.set("tiling.gaps_outer", to: "12")
                == .rejected(reason: "le fichier de configuration n'est pas lisible en UTF-8 : aucune modification"))
        #expect(service.reset("tiling.gaps_outer")
                == .rejected(reason: "le fichier de configuration n'est pas lisible en UTF-8 : aucune modification"))
        #expect(try Data(contentsOf: config) == before)
        #expect(try extraFiles(config).isEmpty)
    }

    @Test
    func missingFileReadsAsEmpty() throws {
        let (service, _, _) = try makeService(nil)
        #expect(service.readConfig() == .success(""))
    }

    @Test
    func invalidStartFileIsRejectedEvenForAValidChange() throws {
        // 3 × 3 = 9 cellules pour 2 lettres : le fichier de départ est déjà invalide.
        let text = fixture.replacingOccurrences(of: "azeqsdwxcrtyfghvbnuiopjklm", with: "az")
        let (service, config, _) = try makeService(text)
        let errors = service.validity().errorCount
        #expect(errors >= 1)
        let before = try Data(contentsOf: config)
        let expected = SettingChangeResult.rejected(
            reason: "le fichier de configuration est invalide : corrige-le d'abord (\(errors) erreur(s))")
        #expect(service.set("tiling.gaps_outer", to: "12") == expected)
        #expect(service.reset("tiling.gaps_outer") == expected)
        #expect(try Data(contentsOf: config) == before)
        #expect(try extraFiles(config).isEmpty)
    }

    @Test
    func invalidCandidateReasonListsItsErrors() throws {
        // Départ valide (9 lettres pour 3 × 3) ; 4 × 3 = 12 cellules rendrait le fichier invalide.
        let text = fixture.replacingOccurrences(of: "azeqsdwxcrtyfghvbnuiopjklm", with: "azeqsdwxc")
        let (service, config, _) = try makeService(text)
        #expect(service.validity().isValid)
        guard case .rejected(let reason) = service.set("target_grid.columns", to: "4") else {
            Issue.record("refus attendu"); return
        }
        #expect(reason.hasPrefix("le fichier deviendrait invalide : "))
        #expect(reason.contains("hint_characters"))
        #expect(!reason.contains(".candidate-"))
        #expect(try read(config) == text)
    }

    @Test
    func symbolicLinkIsKeptAndItsTargetIsWritten() throws {
        let directory = try makeDirectory()
        let real = directory.appendingPathComponent("depot/roadies.toml")
        let link = directory.appendingPathComponent("config/roadies.toml")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let service = SettingsService(configPath: link.path, eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path), afterWrite: {})

        #expect(service.set("tiling.gaps_outer", to: "12") == .applied(old: .double(8), new: .double(12)))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try read(real).contains("gaps_outer = 12.0 # marge extérieure"))
        #expect(try read(link) == read(real))
        // Aucun candidat oublié près de la cible ; la sauvegarde est à côté du lien.
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.deletingLastPathComponent().path) == ["roadies.toml"])
        #expect(try extraFiles(link).allSatisfy { $0.hasPrefix("roadies.toml.bak-") })
        #expect(try extraFiles(link).count == 1)
    }

    @Test
    func posixModeIsKept() throws {
        let (service, config, _) = try makeService(fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        #expect(service.set("tiling.gaps_outer", to: "12") == .applied(old: .double(8), new: .double(12)))
        #expect(try mode(config) == 0o600)
    }

    // MARK: - Instance partagée (T033)

    @Test
    func sharedInstanceUsesTheDefaultPath() {
        // L'unicité de l'instance (une seule sauvegarde par instance) est couverte par `onlyOneBackupPerInstance`.
        #expect(SettingsService.shared.configPath == RoadieConfigLoader.defaultConfigPath())
    }

    // MARK: - Défaut et alias (T034)

    @Test
    func isDefaultFollowsTheValueNotTheLine() throws {
        let (service, _, _) = try makeService("[experimental.target_grid]\nrows = 3\ncolumns = 4\nhint_characters = \"azeqsdwxcrtyfghv\"\n")
        #expect(service.value(of: try descriptor("target_grid.rows")) == (.int(3), true))
        #expect(service.value(of: try descriptor("target_grid.columns")) == (.int(4), false))
        #expect(service.value(of: try descriptor("target_grid.max_depth")) == (.int(3), true))
    }

    @Test
    func strategyAliasesAreReadAndWrittenInCanonicalForm() throws {
        let strategy = try descriptor("tiling.default_strategy")
        for (alias, canonical) in [("spatial_bsp", "spatialBsp"), ("master_stack", "masterStack"),
                                   ("mutable_bsp", "spatialBsp"), ("bsp", "bsp"), ("float", "float")] {
            let (service, config, _) = try makeService("[tiling]\ndefault_strategy = \"\(alias)\" # c\n")
            #expect(service.value(of: strategy) == (.string(canonical), canonical == "bsp"))
            #expect(service.describe("tiling.default_strategy")?.hasPrefix("tiling.default_strategy = \(canonical) (") == true)
            let target = canonical == "float" ? "bsp" : "float"
            #expect(service.set("tiling.default_strategy", to: target) == .applied(old: .string(canonical), new: .string(target)))
            #expect(service.set("tiling.default_strategy", to: alias) == .applied(old: .string(target), new: .string(canonical)))
            #expect(try read(config) == "[tiling]\ndefault_strategy = \"\(canonical)\" # c\n")
        }
    }

    // MARK: - Lecture seule (T029)

    @Test
    func readOnlySummaryShowsListsAndCountsTableArrays() throws {
        let rules = (1...11).map { "[[rules]]\nid = \"regle-\($0)\" # règle \($0)\n[rules.match]\napp = \"App\($0)\"\n" }.joined(separator: "\n")
        let text = """
        [tiling]
        allowed_subroles = ["AXStandardWindow", "AXDialog"] # sous-rôles

        [exclusions]
        # Applications flottantes.
        floating_bundles = [
            # Réglages macOS.
            "com.apple.systempreferences", # commentaire interne
            "com.example.#diese",

            "com.apple.finder",
        ]

        [[stage_manager.workspaces]]
        id = "1"
        display_name = "Code"

        [[stage_manager.workspaces]]
        id = "2"

        [[signals.hooks]]
        event = "focus"

        """ + rules
        let (service, _, _) = try makeService(nil)
        func summary(_ id: String) throws -> String { service.readOnlySummary(of: try descriptor(id), in: text) }
        #expect(try summary("exclusions.floating_bundles")
                == #"["com.apple.systempreferences", "com.example.#diese", "com.apple.finder"]"#)
        #expect(try summary("tiling.allowed_subroles") == #"["AXStandardWindow", "AXDialog"]"#)
        #expect(try summary("rules") == "11 entrée(s) : regle-1, regle-2, regle-3, regle-4, regle-5, …")
        #expect(try summary("stage_manager.workspaces") == "2 entrée(s) : Code, 2")
        #expect(try summary("signals.hooks") == "1 entrée(s)")
        #expect(try summary("tiling.display_overrides") == "(aucune valeur dans le fichier)")
        #expect(try summary("width_adjustment.presets") == "(aucune valeur dans le fichier)")
    }
}

/// Compteur d'appels de `afterWrite` (fermeture `@Sendable`), protégé par un verrou.
private final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() { lock.withLock { value += 1 } }
}
