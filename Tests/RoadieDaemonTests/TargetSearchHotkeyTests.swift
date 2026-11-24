import AppKit
import Carbon
import Foundation
import Testing
import RoadieAX
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

    @Test @MainActor
    func eventDrivenHotkeyReactsToConfigReloadWithoutPollingTimer() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-160-hotkey-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        try "[experimental.target_mode]\nenabled = false\n".write(to: config, atomically: true, encoding: .utf8)
        let events = directory.appendingPathComponent("events.jsonl")
        var reads = 0
        let hotkey = TargetSearchHotkey(
            events: EventLog(path: events.path),
            configLoader: { reads += 1; return TargetModeConfig(enabled: false) },
            configPathLoader: { config.path },
            onPress: {}
        )
        hotkey.start()
        defer { hotkey.stop() }
        #expect(reads == 1)
        NotificationCenter.default.post(name: .roadieConfigDidReload, object: nil, userInfo: ["path": config.path])
        await drainNotifications()
        #expect(reads == 2)
        hotkey.stop()
        NotificationCenter.default.post(name: .roadieConfigDidReload, object: nil, userInfo: ["path": config.path])
        await drainNotifications()
        #expect(reads == 2)
    }

    @Test @MainActor
    func configWatcherSurvivesFileDeleteAndRecreate() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-160-recreate-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        try "[experimental.target_mode]\nenabled = false\n".write(to: config, atomically: true, encoding: .utf8)
        let events = directory.appendingPathComponent("events.jsonl")
        var reads = 0
        let hotkey = TargetSearchHotkey(
            events: EventLog(path: events.path),
            configLoader: { reads += 1; return TargetModeConfig(enabled: false) },
            configPathLoader: { config.path },
            onPress: {}
        )
        hotkey.start()
        defer { hotkey.stop() }
        #expect(reads == 1)

        try FileManager.default.removeItem(at: config)
        for _ in 0..<20 where reads < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }
        let readsAfterDelete = reads
        #expect(readsAfterDelete >= 2)

        try "[experimental.target_mode]\nenabled = false\n# recreated\n".write(to: config, atomically: true, encoding: .utf8)
        for _ in 0..<20 where reads <= readsAfterDelete {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(reads > readsAfterDelete)
    }

    @Test @MainActor
    func borderControllerStopCancelsDeferredNotificationAndAvoidsSnapshotEchoLoop() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-160-border-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        final class CountingPanel: BorderRendering {
            var renderCount = 0
            var hideCount = 0
            func render(_ model: BorderRenderModel) { renderCount += 1 }
            func hide() { hideCount += 1 }
        }
        final class CountingProvider: SystemSnapshotProviding, @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            var windowScans: Int { lock.withLock { count } }
            let display = DisplaySnapshot(id: DisplayID(rawValue: "d1"), index: 1, name: "Main",
                                          frame: Rect(x: 0, y: 0, width: 1440, height: 900),
                                          visibleFrame: Rect(x: 0, y: 0, width: 1440, height: 900), isMain: true)
            let window = WindowSnapshot(id: WindowID(rawValue: 77), pid: 77, appName: "App", bundleID: "test.app",
                                        title: "Win", frame: Rect(x: 100, y: 100, width: 600, height: 400),
                                        isOnScreen: true, isTileCandidate: true)
            func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
            func displays() -> [DisplaySnapshot] { [display] }
            func focusedWindowID() -> WindowID? { window.id }
            func windows() -> [WindowSnapshot] {
                lock.withLock { count += 1 }
                return [window]
            }
        }

        struct NoopWriter: WindowFrameWriting {
            func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
        }
        let provider = CountingProvider()
        var config = RoadieConfig()
        config.fx.borders.enabled = true
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let service = SnapshotService(
            provider: provider,
            frameWriter: NoopWriter(),
            config: config,
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path),
            stageStore: store,
            events: EventLog(path: directory.appendingPathComponent("events.jsonl").path),
            persistStateChanges: false
        )
        service.enableQuietReaderReuse(cap: 60)
        let panel = CountingPanel()
        let controller = BorderController(snapshotService: service, configLoader: { config }, panel: panel)
        controller.start()
        for _ in 0..<20 where panel.renderCount == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(80))
        #expect(panel.renderCount == 1)
        #expect(provider.windowScans == 1)

        // Lot F : une republication de cadre d'animation met à jour la bordure synchroniquement
        // sans relancer de relevé AX.
        let movedFrame = Rect(x: 240, y: 80, width: 700, height: 500)
        let movedWindow = WindowSnapshot(
            id: WindowID(rawValue: 42), pid: 42, appName: "Notes", bundleID: "com.apple.Notes",
            title: "Note", frame: Rect(x: 100, y: 100, width: 700, height: 500), isOnScreen: true, isTileCandidate: true
        )
        let interactiveResult = ApplyResult(
            attempted: 1, applied: 1, clamped: 0, failed: 0,
            items: [ApplyResultItem(windowID: movedWindow.id, status: .applied, requested: movedFrame, actual: movedFrame)]
        )
        service.publishInteractive(interactiveResult, commands: [ApplyCommand(window: movedWindow, frame: movedFrame)])
        #expect(panel.renderCount == 2)
        #expect(provider.windowScans == 1)

        // Notification publiée juste avant stop() : la tâche différée ne doit rien réafficher.
        let rendersBeforeStop = panel.renderCount
        NotificationCenter.default.post(name: .roadieConfigDidReload, object: nil)
        controller.stop()
        await drainNotifications()
        try await Task.sleep(for: .milliseconds(60))
        #expect(panel.renderCount == rendersBeforeStop)
    }

    @MainActor
    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
