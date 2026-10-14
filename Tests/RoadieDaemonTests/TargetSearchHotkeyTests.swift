import AppKit
import Carbon
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
struct TargetSearchHotkeyTests {
    @Test
    func modifiersMapToCarbonFlags() {
        let flags = TargetSearchHotkey.carbonModifiers(["command", "control", "alt"])
        #expect(flags == UInt32(cmdKey | controlKey | optionKey))
        #expect(TargetSearchHotkey.carbonModifiers(["shift"]) == UInt32(shiftKey))
    }

    @Test
    func namedKeysResolveWithoutTheKeyboardLayout() {
        #expect(TargetSearchHotkey.namedKeyCode("space") == 49)
        #expect(TargetSearchHotkey.namedKeyCode("return") == 36)
        #expect(TargetSearchHotkey.namedKeyCode("f1") == 122)
        #expect(TargetSearchHotkey.namedKeyCode("f12") == 111)
        #expect(TargetSearchHotkey.namedKeyCode("f") == nil)
    }

    @Test
    func characterKeysResolveThroughTheLayoutTable() {
        // Table AZERTY partielle : « f » est le code 3, « a » le code 12.
        let layout: [UInt32: String] = [3: "f", 12: "a", 0: "q"]
        #expect(TargetSearchHotkey.keyCode(for: "F", in: layout) == 3)
        #expect(TargetSearchHotkey.keyCode(for: "a", in: layout) == 12)
        #expect(TargetSearchHotkey.keyCode(for: "z", in: layout) == nil)
    }

    @Test
    func emptyOrInvalidHotkeysAreNotResolved() {
        let layout: [UInt32: String] = [3: "f"]
        #expect(TargetSearchHotkey.resolve("", layout: layout) == nil)
        #expect(TargetSearchHotkey.resolve("f", layout: layout) == nil)
        let resolved = TargetSearchHotkey.resolve("command+control+alt+f", layout: layout)
        #expect(resolved?.keyCode == 3)
        #expect(resolved?.modifiers == UInt32(cmdKey | controlKey | optionKey))
    }

    @Test @MainActor
    func relevantSettingsReloadImmediatelyThroughTheActiveSymlinkAndStopCleanly() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-027-hotkey-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        let link = directory.appendingPathComponent("active.toml")
        try "[experimental.target_mode]\nenabled = false\n".write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
        let events = directory.appendingPathComponent("events.jsonl")
        var reads = 0
        let hotkey = TargetSearchHotkey(
            events: EventLog(path: events.path),
            configLoader: { reads += 1; return TargetModeConfig(enabled: false) },
            // Le test vérifie les notifications ; le poll périodique reste armé mais hors de sa durée.
            configPathLoader: { link.path }, pollingInterval: 60, onPress: {}
        )
        hotkey.start()
        defer { hotkey.stop() }
        #expect(reads == 1)
        for id in ["target_mode.search_hotkey", "target_mode.enabled", "target_mode.overlay_enabled", "*"] {
            NotificationCenter.default.post(name: .roadieSettingsDidChange, object: nil,
                                            userInfo: ["configPath": config.path, "settingID": id])
            await drainNotifications()
        }
        #expect(reads == 5)
        // Même raccourci désactivé : aucune réinscription et aucun nouveau journal d'état.
        let recorded = try String(contentsOf: events, encoding: .utf8)
        #expect(recorded.split(separator: "\n").count == 1)
        for info in [
            ["configPath": config.path, "settingID": "target_mode.search_font_family"],
            ["configPath": directory.appendingPathComponent("other.toml").path, "settingID": "*"],
        ] {
            NotificationCenter.default.post(name: .roadieSettingsDidChange, object: nil, userInfo: info)
            await drainNotifications()
        }
        #expect(reads == 5)
        hotkey.stop()
        NotificationCenter.default.post(name: .roadieSettingsDidChange, object: nil,
                                        userInfo: ["configPath": config.path, "settingID": "*"])
        await drainNotifications()
        #expect(reads == 5)
    }

    @MainActor
    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
