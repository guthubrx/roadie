import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@MainActor
@Suite
struct Settings027StageNamesTests {
    @Test
    func editedDefinitionsRenameExistingStagesAndPreserveUnchangedCustomNames() throws {
        let fixture = try StageNamesFixture(definitions: [
            StageDefinition(id: "1", displayName: "Initial"),
            StageDefinition(id: "2", displayName: "Inchangé"),
            StageDefinition(id: "3", displayName: "Retiré")
        ])
        defer { fixture.clean() }
        var expected = fixture.store.state()
        var layoutRequests = 0
        let controller = SettingsLiveApplyController(
            configService: fixture.config, stageStore: fixture.store, events: fixture.events,
            onLayoutChange: { _ in layoutRequests += 1 }
        )
        try fixture.replace(definitions: [
            StageDefinition(id: "1", displayName: "Nouveau nom"),
            StageDefinition(id: "2", displayName: "Inchangé"),
            StageDefinition(id: "4", displayName: "Nouvelle définition")
        ])
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        for index in expected.scopes.indices {
            expected.scopes[index].stages[0].name = "Nouveau nom"
            expected.scopes[index].stages[3].name = "Nouvelle définition"
        }
        #expect(fixture.store.state() == expected)
        #expect(layoutRequests == 1)
        #expect(expected.scopes.allSatisfy { $0.stages[1].name == "Personnalisé" })
        // Le libellé lu par le rail vient désormais du nouvel état persisté, sans notification
        // supplémentaire des paramètres. Les membres/choix des scopes retirés sont inchangés.
        let display = powerDisplay("screen-a")
        let service = SnapshotService(
            provider: PowerUserProvider(displays: [display], windows: []),
            stageStore: fixture.store, events: fixture.events,
            persistStateChanges: false, configService: fixture.config
        )
        let snapshot = service.snapshot(followFocus: false)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        #expect(snapshot.state.stage(scope: scope)?.name == "Nouveau nom")
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        #expect(layoutRequests == 1)
    }

    @Test
    func removingOrReidentifyingDefinitionKeepsStagesMembersAndCustomAssignments() throws {
        let fixture = try StageNamesFixture(definitions: [StageDefinition(id: "1", displayName: "Initial")])
        defer { fixture.clean() }
        let before = fixture.store.state()
        let controller = SettingsLiveApplyController(
            configService: fixture.config, stageStore: fixture.store, events: fixture.events,
            onLayoutChange: { _ in }
        )
        try fixture.replace(definitions: [])
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        #expect(fixture.store.state() == before)
        try fixture.replace(definitions: [StageDefinition(id: "new-id", displayName: "Initial")])
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        // Le seeding d'une stage nouvellement configurée relève du snapshot suivant. Le
        // renommage ne déplace aucun membre vers l'identifiant nouvellement ajouté.
        #expect(fixture.store.state() == before)
    }

    @Test
    func failedStageWriteKeepsPendingRenameWithoutOverwritingUnreadableState() throws {
        let fixture = try StageNamesFixture(definitions: [StageDefinition(id: "1", displayName: "Initial")])
        defer { fixture.clean() }
        let bytes = try Data(contentsOf: fixture.store.fileURL)
        let controller = SettingsLiveApplyController(
            configService: fixture.config, stageStore: fixture.store, events: fixture.events,
            onLayoutChange: { _ in }
        )
        let damaged = Data("invalid stage state".utf8)
        try damaged.write(to: fixture.store.fileURL, options: .atomic)
        try fixture.replace(definitions: [StageDefinition(id: "1", displayName: "Nouveau")])
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        #expect(try Data(contentsOf: fixture.store.fileURL) == damaged)
        try bytes.write(to: fixture.store.fileURL, options: .atomic)
        controller.applyChange(configPath: fixture.path, settingID: "stage_manager.workspaces")
        #expect(fixture.store.state().scopes.allSatisfy { $0.stages[0].name == "Nouveau" })
    }

    @Test
    func fontOnlyFullFileEditPreservesStageNamesAndDoesNotRetile() throws {
        let definitions = [StageDefinition(id: "2", displayName: "Configuration")]
        let fixture = try StageNamesFixture(definitions: definitions)
        defer { fixture.clean() }
        let before = try Data(contentsOf: fixture.store.fileURL)
        var requests = 0
        let controller = SettingsLiveApplyController(
            configService: fixture.config, stageStore: fixture.store, events: fixture.events,
            onLayoutChange: { _ in requests += 1 }
        )
        try fixture.replace(definitions: definitions, fontSize: 24)
        controller.applyChange(configPath: fixture.path, settingID: "*")
        #expect(requests == 0)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(fixture.store.state().scopes.allSatisfy { $0.stages[1].name == "Personnalisé" })
    }
}

private struct StageNamesFixture {
    let directory: URL
    let path: String
    let config: ConfigReloadService
    let store: StageStore
    let events: EventLog

    init(definitions: [StageDefinition]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-stage-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("roadies.toml").path
        try Self.text(definitions: definitions).write(toFile: path, atomically: true, encoding: .utf8)
        events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        config = ConfigReloadService(activeConfig: try RoadieConfigLoader.load(from: path), activePath: path, eventLog: events)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let member = PersistentStageMember(
            windowID: WindowID(rawValue: 12), bundleID: "fixture.app", title: "Document",
            frame: Rect(x: 200, y: 100, width: 300, height: 300)
        )
        let scopes = ["screen-a", "screen-b"].flatMap { display in
            [1, 2].map { desktop in
                PersistentStageScope(
                    displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop),
                    activeStageID: StageID(rawValue: "3"), stages: [
                        PersistentStage(id: StageID(rawValue: "1"), name: "Initial", mode: .masterStack),
                        PersistentStage(id: StageID(rawValue: "2"), name: "Personnalisé", mode: .float),
                        PersistentStage(id: StageID(rawValue: "3"), name: "Conservé", focusedWindowID: member.windowID, members: [member]),
                        PersistentStage(id: StageID(rawValue: "4"), name: "Ancien nom local")
                    ]
                )
            }
        }
        store.save(PersistentStageState(scopes: scopes, activeDisplayID: DisplayID(rawValue: "screen-b")))
    }

    func replace(definitions: [StageDefinition], fontSize: Double = 16) throws {
        try Self.text(definitions: definitions, fontSize: fontSize).write(toFile: path, atomically: true, encoding: .utf8)
        #expect(config.reload(path: path).status == .applied)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    private static func text(definitions: [StageDefinition], fontSize: Double = 16) -> String {
        "[interface]\nsettings_text_font_size = \(fontSize)\n" + definitions.map {
            "\n[[stage_manager.workspaces]]\nid = \"\($0.id)\"\ndisplay_name = \"\($0.displayName)\"\n"
        }.joined()
    }
}
