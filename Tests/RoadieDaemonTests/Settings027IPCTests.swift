import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@MainActor
@Suite
struct Settings027IPCTests {
    @Test
    func distributedSignalFromChildProcessAppliesLayoutAndStageNamesOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-settings-ipc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("roadies.toml")
        let text: (Int, String) -> String = { gap, name in
            "[tiling]\ngaps_outer = \(gap)\n[[stage_manager.workspaces]]\nid = \"1\"\ndisplay_name = \"\(name)\"\n"
        }
        try text(6, "Initial").write(to: configURL, atomically: true, encoding: .utf8)
        let events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        let config = ConfigReloadService(
            activeConfig: try RoadieConfigLoader.load(from: configURL.path), activePath: configURL.path, eventLog: events
        )
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let display = DisplayID(rawValue: "fixture-screen")
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display, stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Initial")]
        )]))
        let localCenter = NotificationCenter()
        var requests: [Bool] = []
        let controller = SettingsLiveApplyController(
            configService: config, notificationCenter: localCenter,
            distributedNotificationCenter: DistributedNotificationCenter.default(),
            stageStore: store, events: events, onLayoutChange: { requests.append($0) }
        )
        controller.start()
        defer { controller.stop() }
        // Comme dans le mode modulaire : un autre processus a remplacé le fichier.
        // Le récepteur n'est pas rechargé explicitement avant de recevoir le signal.
        try text(7, "Nouveau nom").write(to: configURL, atomically: true, encoding: .utf8)
        let payload = ["configPath": configURL.path, "settingID": "*"]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadJSON = try #require(String(data: payloadData, encoding: .utf8))
        let script = """
        ObjC.import('Foundation');
        $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
          $('roadie.settings.didChange'), $('roadie.settings.test.publisher'), $(\(payloadJSON)), true
        );
        """
        let child = Process()
        let errors = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        child.arguments = ["-l", "JavaScript", "-e", script]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = errors
        try child.run()
        child.waitUntilExit()
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(child.terminationStatus == 0, "Le processus de publication a échoué : \(stderr)")
        let deadline = Date().addingTimeInterval(3)
        while requests.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(requests == [true])
        #expect(config.activeConfig.tiling.gapsOuter == 7)
        #expect(store.state().scopes[0].stages[0].name == "Nouveau nom")
        let persisted = try Data(contentsOf: store.fileURL)
        // Le même signal local et distribué ne crée ni deuxième passe ni deuxième écriture.
        localCenter.post(name: .roadieSettingsDidChange, object: nil, userInfo: payload)
        DistributedNotificationCenter.default().postNotificationName(
            .roadieSettingsDidChange, object: nil, userInfo: payload, deliverImmediately: true
        )
        try await Task.sleep(for: .milliseconds(80))
        #expect(requests == [true])
        let afterDuplicates = try Data(contentsOf: store.fileURL)
        #expect(afterDuplicates == persisted)
    }

    @Test
    func pairedCentersIgnoreInactivePathAndFontOnlyEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-settings-paired-centers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        try "[interface]\nsettings_text_font_size = 16\n".write(to: url, atomically: true, encoding: .utf8)
        let events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        let config = ConfigReloadService(activeConfig: try RoadieConfigLoader.load(from: url.path), activePath: url.path, eventLog: events)
        let local = NotificationCenter()
        let distributed = NotificationCenter()
        var requests = 0
        let controller = SettingsLiveApplyController(
            configService: config, notificationCenter: local, distributedNotificationCenter: distributed,
            stageStore: StageStore(path: directory.appendingPathComponent("stages.json").path),
            events: events, onLayoutChange: { _ in requests += 1 }
        )
        controller.start()
        defer { controller.stop() }
        try "[interface]\nsettings_text_font_size = 24\n".write(to: url, atomically: true, encoding: .utf8)
        for center in [local, distributed] {
            center.post(name: .roadieSettingsDidChange, object: nil, userInfo: ["configPath": url.path, "settingID": "*"])
            center.post(name: .roadieSettingsDidChange, object: nil, userInfo: [
                "configPath": directory.appendingPathComponent("inactive.toml").path, "settingID": "tiling.gaps_outer"
            ])
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(requests == 0)
        #expect(config.activeConfig.interface.settingsTextFontSize == 24)
        controller.stop()
        try "[tiling]\ngaps_outer = 50\n".write(to: url, atomically: true, encoding: .utf8)
        distributed.post(name: .roadieSettingsDidChange, object: nil, userInfo: ["configPath": url.path, "settingID": "*"])
        try await Task.sleep(for: .milliseconds(30))
        #expect(requests == 0)
    }
}
