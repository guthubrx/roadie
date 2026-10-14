import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Settings027CollectionTests {
    private func withService(_ text: String = "", _ run: (SettingsService, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-027-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roadies.toml")
        try text.write(to: file, atomically: false, encoding: .utf8)
        let log = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        try run(SettingsService(configPath: file.path, eventLog: log, afterWrite: {}), file)
    }
    private func descriptor(_ id: String) throws -> SettingDescriptor { try #require(SettingsCatalog.find(id: id)) }
    private func expectApplied(_ result: SettingChangeResult) {
        guard case .applied = result else { Issue.record("écriture refusée : \(result)"); return }
    }

    @Test
    func allTwelveShapesRoundTripAndReset() throws {
        let values: [(String, CollectionValue)] = [
            ("tiling.smart_gaps_solo_sides", .list([.string("top"), .string("left")])),
            ("tiling.allowed_subroles", .list([])),
            ("width_adjustment.presets", .list([.double(0.1), .double(4)])),
            ("app_targets.include_roles", .list([.string("AXButton")])),
            ("app_targets.additional_boost_bundle_ids", .list([.string("com.test.extra")])),
            ("exclusions.floating_bundles", .list([.string("com.test.float")])),
            ("tiling.display_overrides", .rows([CollectionRow(fields: ["display_name": .string("Écran"), "gaps_outer": .double(600)])])),
            ("stage_manager.workspaces", .rows([CollectionRow(fields: ["id": .string("1"), "display_name": .string("Travail")])])),
            ("borders.stage_overrides", .rows([CollectionRow(fields: ["stage_id": .string("1"), "active_color": .string("#AA7733")])])),
            ("rail.preview.stage_overrides", .rows([CollectionRow(fields: ["stage_id": .string("1"), "active_color": .string("#334455")])])),
            ("rules", .rows([CollectionRow(fields: ["id": .string("a"), "match.app": .string("Application"), "action.floating": .bool(true)])])),
            ("signals.hooks", .advanced("[[signals.hooks]]\nevent = \"focus\"\ncommand = \"echo test\"\n")),
        ]
        for (id, value) in values {
            try withService { service, file in
                let d = try descriptor(id)
                #expect(d.collection != nil && d.readOnlyReason == nil)
                expectApplied(service.setCollection(id, value))
                let read = try service.collection(of: d).get()
                switch (value, read) {
                case (.list(let expected), .list(let actual)): #expect(actual == expected)
                case (.rows(let expected), .rows(let actual)):
                    #expect(actual.count == expected.count)
                    for key in expected[0].fields.keys { #expect(actual[0].fields[key] == expected[0].fields[key], "\(id).\(key)") }
                    #expect(actual[0].sourceIndex == 0)
                case (.advanced, .advanced(let actual)): #expect(actual.contains("echo test"))
                default: Issue.record("forme différente : \(id)")
                }
                #expect(service.validity().isValid)
                if id == "rail.preview.stage_overrides" {
                    #expect(try String(contentsOf: file, encoding: .utf8).contains("[[fx.rail.preview.stage_overrides]]"))
                }
                expectApplied(service.resetCollection(id))
                #expect(try service.collection(of: d).get() == d.collection?.defaultValue)
                #expect(service.value(of: d).isDefault)
            }
        }
    }

    @Test
    func multilineListPreservesCommentsAndCRLFWithoutFinalNewline() throws {
        let original = "# entrée\r\n[exclusions]\r\nfloating_bundles = [ # liste\r\n # première\r\n \"com.old\", # fin interne\r\n]\r\nunknown = \"inchangé\""
        try withService(original) { service, file in
            expectApplied(service.setCollection("exclusions.floating_bundles", .list([.string("com.new")])))
            let text = try String(contentsOf: file, encoding: .utf8)
            for comment in ["# entrée", "# liste", "# première", "# fin interne"] { #expect(text.contains(comment)) }
            #expect(text.contains("unknown = \"inchangé\""))
            #expect(!text.hasSuffix("\n"))
            #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
            #expect(try service.collection(of: descriptor("exclusions.floating_bundles")).get() == .list([.string("com.new")]))
        }
    }

    @Test
    func nestedRowsMoveWithTheirUnknownFieldsAndCanBeDeleted() throws {
        let original = """
        [[rules]] # règle a
        id = "a"
        unknown = "secret-a"
        [rules.match]
        app = "Alpha" # commentaire a
        unknown_match = "keep-a"
        [rules.action]
        floating = true
        [rules.future]
        token = "keep-future"

        # avant b
        [[rules]] # règle b
        id = "b"
        [rules.match]
        app = "Beta"
        [rules.action]
        manage = true

        [focus]
        stage_follows_focus = true # extérieur
        """
        try withService(original) { service, file in
            let d = try descriptor("rules")
            let old = try service.collection(of: d).get()
            guard case .rows(var rows) = old else { Issue.record("rows attendu"); return }
            rows[0].fields["match.app"] = .string("Alpha nouveau")
            expectApplied(service.setCollection("rules", .rows([rows[1], rows[0]]), expected: old))
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.range(of: "id = \"b\"")!.lowerBound < text.range(of: "id = \"a\"")!.lowerBound)
            #expect(text.contains("unknown = \"secret-a\""))
            #expect(text.contains("unknown_match = \"keep-a\""))
            #expect(text.contains("[rules.future]\ntoken = \"keep-future\""))
            #expect(text.contains("# commentaire a") && text.contains("# extérieur"))
            #expect(text.range(of: "# avant b")!.lowerBound < text.range(of: "id = \"b\"")!.lowerBound)
            let fresh = try service.collection(of: d).get()
            guard case .rows(let refreshed) = fresh else { return }
            #expect(refreshed[0].fields["match.app"] == .string("Beta"))
            #expect(refreshed[1].fields["match.app"] == .string("Alpha nouveau"))
            expectApplied(service.setCollection("rules", .rows([refreshed[1]]), expected: fresh))
            let remaining = try String(contentsOf: file, encoding: .utf8)
            #expect(remaining.contains("# règle b"))
            #expect(remaining.contains("keep-future") && !remaining.contains("id = \"b\""))
        }
    }

    @Test
    func inlineRowsAndNestedInlineTablesRemainEditable() throws {
        let original = "rules = [{ id = 'one', match = { app = 'Old', custom = 'keep' }, action = { floating = true }, unknown = 42 }] # compact\n"
        try withService(original) { service, file in
            let d = try descriptor("rules")
            let old = try service.collection(of: d).get()
            guard case .rows(var rows) = old else { return }
            rows[0].fields["match.app"] = .string("New")
            expectApplied(service.setCollection("rules", .rows(rows), expected: old))
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.contains("# compact"))
            #expect(text.contains("keep") && text.contains("unknown = 42"))
            guard case .rows(let reread) = try service.collection(of: d).get() else { return }
            #expect(reread[0].fields["match.app"] == .string("New"))
            #expect(reread[0].fields["action.floating"] == .bool(true))
        }
    }

    @Test
    func editingRulePriorityPreservesLegacyAndCustomLayoutStrings() throws {
        for layout in ["mutableBsp", "custom-layout"] {
            let original = "[[rules]]\nid = \"legacy\"\npriority = 1\n[rules.match]\napp = \"Application\"\n[rules.action]\nlayout = \"\(layout)\" # valeur héritée\n"
            try withService(original) { service, file in
                let d = try descriptor("rules")
                let old = try service.collection(of: d).get()
                guard case .rows(var rows) = old else { Issue.record("rows attendu"); return }
                rows[0].fields["priority"] = .int(2)
                #expect(service.validateCollection(d, value: .rows(rows)).isEmpty)
                expectApplied(service.setCollection(d.id, .rows(rows), expected: old))
                guard case .rows(let actual) = try service.collection(of: d).get() else { return }
                #expect(actual[0].fields["priority"] == .int(2))
                #expect(actual[0].fields["action.layout"] == .string(layout))
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(text.contains("layout = \"\(layout)\" # valeur héritée"))
            }
        }
    }

    @Test
    func collectionConflictsDoNotOverwriteExternalEdits() throws {
        try withService("[exclusions]\nfloating_bundles = [\"old\"]\n") { service, file in
            let d = try descriptor("exclusions.floating_bundles")
            let old = try service.collection(of: d).get()
            try "[exclusions]\nfloating_bundles = [\"external\"]\n".write(to: file, atomically: false, encoding: .utf8)
            guard case .rejected = service.setCollection(d.id, .list([.string("new")]), expected: old) else { Issue.record("conflit attendu"); return }
            #expect(try service.collection(of: d).get() == .list([.string("external")]))
            let latest = try service.collection(of: d).get()
            service.beforeReplace = { try? "[exclusions]\nfloating_bundles = [\"race\"]\n".write(to: file, atomically: false, encoding: .utf8) }
            guard case .rejected = service.setCollection(d.id, .list([.string("new")]), expected: latest) else { Issue.record("conflit attendu"); return }
            #expect(try service.collection(of: d).get() == .list([.string("race")]))
            #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).filter { $0.contains("candidate-") || $0.contains(".bak-") }.isEmpty)
        }
    }

    @Test
    func invalidRuleSemanticsAreRejectedWithoutFileChangesOrBackups() throws {
        let invalidRows = [
            CollectionRow(fields: ["id": .string("bad-regex"), "match.app_regex": .string("[")]),
            CollectionRow(fields: ["id": .string("bad-action"), "match.app": .string("App"),
                                   "action.exclude": .bool(true), "action.assign_stage": .string("2")]),
            CollectionRow(fields: ["id": .string("no-matcher"), "action.floating": .bool(true)]),
        ]
        for row in invalidRows {
            try withService("[tiling]\ngaps_outer = 8 # intact\n") { service, file in
                let original = service.configText()
                let d = try descriptor("rules")
                #expect(!service.validateCollection(d, value: .rows([row])).isEmpty)
                guard case .rejected = service.setCollection(d.id, .rows([row])) else { Issue.record("règle invalide acceptée"); return }
                let candidate = try SettingsCollectionWriter.edit(original, descriptor: d, value: .rows([row]))
                guard case .rejected = service.replaceConfigText(candidate, expectedOriginal: original) else { Issue.record("édition complète invalide acceptée"); return }
                #expect(service.configText() == original)
                let extras = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
                #expect(!extras.contains { $0.contains(".bak-") || $0.contains("candidate-") })
            }
        }
    }

    @Test
    func generatedRuleIDsAreValidatedUsingTheConfiguredSymlinkPath() throws {
        try withService("[tiling]\ngaps_outer = 8 # intact\n") { _, file in
            let link = file.deletingLastPathComponent().appendingPathComponent("alias.toml")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)
            let generated = URL(fileURLWithPath: RoadieConfigLoader.generatedRulesPath(for: link.path))
            try "[[rules]]\nid = \"generated-id\"\n[rules.match]\napp = \"Generated\"\n".write(to: generated, atomically: false, encoding: .utf8)
            // Ce voisin de la cible physique ne doit pas remplacer le voisin utilisé par ConfigReloadService.
            let other = URL(fileURLWithPath: RoadieConfigLoader.generatedRulesPath(for: file.path))
            try "[[rules]]\nid = \"different-id\"\n[rules.match]\napp = \"Other\"\n".write(to: other, atomically: false, encoding: .utf8)
            let service = SettingsService(configPath: link.path, eventLog: EventLog(path: file.deletingLastPathComponent().appendingPathComponent("events.jsonl").path), afterWrite: {})
            let original = service.configText()
            let rows = CollectionValue.rows([CollectionRow(fields: ["id": .string("generated-id"), "match.app": .string("Manual")])])
            guard case .rejected(let reason) = service.setCollection("rules", rows) else { Issue.record("ID principal/généré en conflit accepté"); return }
            #expect(reason.contains("duplicate rule id"))
            #expect(service.configText() == original)
            let extras = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            #expect(!extras.contains { $0.contains(".bak-") || $0.contains("candidate-") })
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == file.path)
        }
    }

    @Test
    func theRuleEditorCanRepairAnExistingSemanticallyInvalidRule() throws {
        let original = "[[rules]]\nid = \"repair\"\n[rules.match]\napp_regex = \"[\"\n"
        try withService(original) { service, _ in
            let d = try descriptor("rules")
            let old = try service.collection(of: d).get()
            guard case .rows(var rows) = old else { return }
            rows[0].fields["match.app_regex"] = .string("^Application$")
            expectApplied(service.setCollection("rules", .rows(rows), expected: old))
            guard case .rows(let actual) = try service.collection(of: d).get() else { return }
            #expect(actual[0].fields["match.app_regex"] == .string("^Application$"))
        }
    }

    @Test
    func invalidCollectionsDoNotWriteAndHooksStayScoped() throws {
        try withService { service, file in
            for (id, value) in [
                ("width_adjustment.presets", CollectionValue.list([])),
                ("width_adjustment.presets", .list([.double(1), .double(0.5)])),
                ("tiling.smart_gaps_solo_sides", .list([.string("wrong")])),
                ("stage_manager.workspaces", .rows([CollectionRow(fields: ["id": .string("1")])])),
                ("signals.hooks", .advanced("[focus]\nstage_follows_focus = false\n")),
            ] {
                let item = try descriptor(id)
                #expect(!service.validateCollection(item, value: value).isEmpty)
                guard case .rejected = service.setCollection(id, value) else { Issue.record("refus attendu : \(id)"); continue }
            }
            let written = try String(contentsOf: file, encoding: .utf8)
            #expect(written.isEmpty)
            expectApplied(service.setCollection("signals.hooks", .advanced("[signals]\nhooks = [{event = 'focus', command = 'test'}]\n")))
            #expect(service.validity().isValid)
        }
    }

    @Test
    func completeEditorRepairsInvalidOriginalAndRejectsStaleOrInvalidCandidates() throws {
        try withService("[tiling]\ngaps_outer = [\n") { service, file in
            let original = service.configText()
            #expect(!service.validity().isValid)
            guard case .rejected = service.replaceConfigText(original, expectedOriginal: original) else {
                Issue.record("un candidat identique mais invalide doit être refusé"); return
            }
            #expect(service.configText() == original)
            expectApplied(service.replaceConfigText("[tiling]\ngaps_outer = 20\n", expectedOriginal: original))
            #expect(service.validity().isValid)
            guard case .rejected = service.replaceConfigText("[tiling]\ngaps_outer = 30\n", expectedOriginal: original) else { Issue.record("conflit attendu"); return }
            let current = service.configText()
            guard case .rejected = service.replaceConfigText("[tiling]\ngaps_outer = [\n", expectedOriginal: current) else { Issue.record("refus attendu"); return }
            let written = try String(contentsOf: file, encoding: .utf8)
            #expect(written == current)
        }
    }

    @Test
    func anAbsentEmptyConfigIsAValidNoOpButItsGeneratedRulesAreStillChecked() throws {
        try withService { service, file in
            try FileManager.default.removeItem(at: file)
            expectApplied(service.replaceConfigText("", expectedOriginal: ""))
            #expect(!FileManager.default.fileExists(atPath: file.path))
            let generated = URL(fileURLWithPath: RoadieConfigLoader.generatedRulesPath(for: file.path))
            try "[[rules]]\nid = \"invalid-generated\"\n".write(to: generated, atomically: false, encoding: .utf8)
            guard case .rejected(let reason) = service.replaceConfigText("", expectedOriginal: "") else {
                Issue.record("règles générées sans critère acceptées"); return
            }
            #expect(reason.contains("matcher"))
            #expect(!FileManager.default.fileExists(atPath: file.path))
            let extras = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            #expect(!extras.contains { $0.contains(".bak-") || $0.contains("candidate-") })
        }
    }

    @Test
    func collectionWritesPreserveSymlinkAndPermissions() throws {
        try withService("[exclusions]\nfloating_bundles = []\n") { _, file in
            let link = file.deletingLastPathComponent().appendingPathComponent("link.toml")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let service = SettingsService(configPath: link.path, eventLog: EventLog(path: file.deletingLastPathComponent().appendingPathComponent("events-link.jsonl").path), afterWrite: {})
            expectApplied(service.setCollection("exclusions.floating_bundles", .list([.string("com.test")])))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == file.path)
            #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
            #expect(try String(contentsOf: file, encoding: .utf8).contains("com.test"))
        }
    }

    @Test
    func notificationsUsePublicIDsSkipNoOpsAndLogsDoNotContainValues() throws {
        try withService { service, file in
            let notices = Settings027NoticeBox()
            let token = NotificationCenter.default.addObserver(forName: .roadieSettingsDidChange, object: nil, queue: nil) { note in
                guard note.userInfo?["configPath"] as? String == file.path else { return }
                notices.append(note.userInfo?["settingID"] as? String ?? "")
            }
            defer { NotificationCenter.default.removeObserver(token) }
            let value = CollectionValue.list([.string("secret-bundle-value")])
            expectApplied(service.setCollection("exclusions.floating_bundles", value))
            expectApplied(service.setCollection("exclusions.floating_bundles", value))
            expectApplied(service.set("borders.enabled", to: "true"))
            expectApplied(service.replaceConfigText(service.configText() + "\n# changed\n", expectedOriginal: service.configText()))
            #expect(notices.items == ["exclusions.floating_bundles", "borders.enabled", "*"])
            let events = try String(contentsOf: file.deletingLastPathComponent().appendingPathComponent("events.jsonl"), encoding: .utf8)
            #expect(!events.contains("secret-bundle-value"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).filter { $0.contains(".bak-") }.count == 1)
        }
    }
}

private final class Settings027NoticeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    var items: [String] { lock.withLock { values } }
}
