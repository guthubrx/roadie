import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 161 — Quick Wins Switcher & Lanceur : touches d'action directe + filtres rapides + `.summon`
/// dans le sélecteur, convertisseur hors ligne (unités/bases/fuseaux), pipette de couleur, émojis et minuteur.
@Suite(.serialized)
struct Spec161QuickWinsSwitcherLauncherTests {
    // MARK: - Configuration & réglages TOML

    @Test func spec161SettingsDecodeAndValidateCleanly() throws {
        let defaults = RoadieConfig()
        #expect(defaults.switcher.actionKeysEnabled)
        #expect(defaults.experimental.targetMode.calcConversions)
        #expect(defaults.experimental.targetMode.emojiPicker)
        #expect(defaults.experimental.targetMode.timerEnabled)

        let toml = """
        [switcher]
        action_keys_enabled = false

        [experimental.target_mode]
        calc_conversions = false
        emoji_picker = false
        timer_enabled = false
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec161-cfg-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roadies.toml")
        try toml.write(to: file, atomically: true, encoding: .utf8)

        let report = RoadieConfigLoader.validate(path: file.path)
        #expect(!report.hasErrors)
        #expect(!report.items.contains { $0.level == .warning })
        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(!loaded.switcher.actionKeysEnabled)
        #expect(!loaded.experimental.targetMode.calcConversions)
        #expect(!loaded.experimental.targetMode.emojiPicker)
        #expect(!loaded.experimental.targetMode.timerEnabled)

        for id in [
            "switcher.action_keys_enabled",
            "target_mode.calc_conversions",
            "target_mode.emoji_picker",
            "target_mode.timer_enabled",
        ] {
            #expect(SettingsCatalog.find(id: id) != nil, "missing setting \(id)")
        }
    }

    // MARK: - Switcher : touches directes & filtres rapides de portée

    @Test func switcherDirectCommandsRespectSearchModeModifiersAndToggle() {
        // Hors édition de recherche, sans modificateur ou avec le modificateur de navigation autorisé (.command).
        #expect(WindowSwitcherPanel.directCommand(characters: "w", modifierFlags: [], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.close))
        #expect(WindowSwitcherPanel.directCommand(characters: "W", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.close))
        #expect(WindowSwitcherPanel.directCommand(characters: "q", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.quitApp))
        #expect(WindowSwitcherPanel.directCommand(characters: "m", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.minimize))
        #expect(WindowSwitcherPanel.directCommand(characters: "h", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.hideApp))
        #expect(WindowSwitcherPanel.directCommand(characters: "s", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .action(.summon))
        #expect(WindowSwitcherPanel.directCommand(characters: "a", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .toggleScope("application"))
        #expect(WindowSwitcherPanel.directCommand(characters: "d", modifierFlags: [.command], allowing: [.command], isSearchEditing: false, enabled: true) == .toggleScope("display"))

        // En édition de recherche ou désactivé ou modificateur non autorisé : jamais intercepté.
        #expect(WindowSwitcherPanel.directCommand(characters: "w", modifierFlags: [], allowing: [.command], isSearchEditing: true, enabled: true) == nil)
        #expect(WindowSwitcherPanel.directCommand(characters: "w", modifierFlags: [], allowing: [.command], isSearchEditing: false, enabled: false) == nil)
        #expect(WindowSwitcherPanel.directCommand(characters: "w", modifierFlags: [.control], allowing: [.command], isSearchEditing: false, enabled: true) == nil)
    }

    @Test func switcherModelTogglesLiveApplicationAndDisplayScopeOverrides() {
        let d1 = DisplayID(rawValue: "d1")
        let d2 = DisplayID(rawValue: "d2")
        let desk = DesktopID(rawValue: 1)
        let s1 = StageID(rawValue: "1")
        let e1 = WindowSwitcherEntry(
            window: WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "Browser", bundleID: "com.example.browser", title: "Tab 1", frame: Rect(x: 0, y: 0, width: 600, height: 400), isOnScreen: true, isTileCandidate: true),
            scope: StageScope(displayID: d1, desktopID: desk, stageID: s1)
        )
        let e2 = WindowSwitcherEntry(
            window: WindowSnapshot(id: WindowID(rawValue: 2), pid: 10, appName: "Browser", bundleID: "com.example.browser", title: "Tab 2", frame: Rect(x: 1600, y: 0, width: 600, height: 400), isOnScreen: true, isTileCandidate: true),
            scope: StageScope(displayID: d2, desktopID: desk, stageID: s1)
        )
        let e3 = WindowSwitcherEntry(
            window: WindowSnapshot(id: WindowID(rawValue: 3), pid: 11, appName: "Notes", bundleID: "com.example.notes", title: "Todo", frame: Rect(x: 10, y: 0, width: 600, height: 400), isOnScreen: true, isTileCandidate: true),
            scope: StageScope(displayID: d1, desktopID: desk, stageID: s1)
        )
        let profile = WindowSwitcherShortcutConfig(scope: "all")
        let ctx = WindowSwitcherContext(focusedWindowID: e1.id, displayID: d1, desktopID: desk, stageID: s1, bundleID: "com.example.browser")
        var model = WindowSwitcherModel(entries: [e1, e2, e3], profile: profile, context: ctx)
        #expect(model.matches.count == 3)

        model.toggleScopeOverride("application")
        #expect(model.effectiveScope == "application")
        #expect(Set(model.matches.map(\.id)) == [e1.id, e2.id])

        // Basculer vers écran courant remplace le filtre application.
        model.toggleScopeOverride("display")
        #expect(model.effectiveScope == "display")
        #expect(Set(model.matches.map(\.id)) == [e1.id, e3.id])

        // Appuyer à nouveau sur le même filtre restaure le profil d'origine (`all`).
        model.toggleScopeOverride("display")
        #expect(model.scopeOverride == nil)
        #expect(model.effectiveScope == "all")
        #expect(model.matches.count == 3)
    }

    @Test func switcherSummonMovesWindowToActiveStageAndUpdatesTree() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec161-summon-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        final class SpyWriter: WindowFrameWriting, @unchecked Sendable {
            private let lock = NSLock()
            var focused: [WindowID] = []
            func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
            func focus(_ window: WindowSnapshot) -> Bool { lock.withLock { focused.append(window.id) }; return true }
        }
        struct StaticProvider: SystemSnapshotProviding {
            var displaysList: [DisplaySnapshot]
            var windowsList: [WindowSnapshot]
            var focusedID: WindowID?
            func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true) }
            func displays() -> [DisplaySnapshot] { displaysList }
            func windows() -> [WindowSnapshot] { windowsList }
            func focusedWindowID() -> WindowID? { focusedID }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let d1 = DisplaySnapshot(id: DisplayID(rawValue: "d1"), index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1600, height: 900), visibleFrame: Rect(x: 0, y: 30, width: 1600, height: 870), isMain: true)
        let w1 = WindowSnapshot(id: WindowID(rawValue: 1), pid: ownPID, appName: "AppA", bundleID: "com.example.a", title: "Active", frame: Rect(x: 10, y: 40, width: 700, height: 600), isOnScreen: true, isTileCandidate: true)
        let w2 = WindowSnapshot(id: WindowID(rawValue: 2), pid: ownPID, appName: "AppB", bundleID: "com.example.b", title: "Remote", frame: Rect(x: -3000, y: 40, width: 700, height: 600), isOnScreen: true, isTileCandidate: true)

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let desk = DesktopID(rawValue: 1)
        let stage1 = StageID(rawValue: "1")
        let stage2 = StageID(rawValue: "2")
        try store.mutateChecked { state in
            var scope = state.scope(displayID: d1.id, desktopID: desk)
            scope.stages[0].mode = .spatialBsp
            scope.assign(window: w1, to: stage1, defaultMode: .spatialBsp)
            scope.assign(window: w2, to: stage2, defaultMode: .spatialBsp)
            scope.activeStageID = stage1
            state.update(scope)
            state.setBSPTree(.leaf(w1.id), for: StageScope(displayID: d1.id, desktopID: desk, stageID: stage1))
            state.setBSPTree(.leaf(w2.id), for: StageScope(displayID: d1.id, desktopID: desk, stageID: stage2))
        }

        var config = RoadieConfig()
        config.tiling.defaultStrategy = .spatialBsp
        let writer = SpyWriter()
        let snapshotService = SnapshotService(
            provider: StaticProvider(displaysList: [d1], windowsList: [w1, w2], focusedID: w1.id),
            frameWriter: writer,
            config: config,
            intentStore: LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path),
            stageStore: store
        )
        let switcher = WindowSwitcherService(service: snapshotService)
        let entry = WindowSwitcherEntry(window: w2, scope: StageScope(displayID: d1.id, desktopID: desk, stageID: stage2))
        let result = switcher.perform(.summon, on: entry)
        #expect(result.changed)

        var after = store.state()
        let afterScope = after.scope(displayID: d1.id, desktopID: desk)
        #expect(Set(afterScope.memberIDs(in: stage1)) == [w1.id, w2.id])
        #expect(!afterScope.memberIDs(in: stage2).contains(w2.id))
        let s1Tree = after.bspTree(for: StageScope(displayID: d1.id, desktopID: desk, stageID: stage1))
        #expect(Set(s1Tree?.windowIDs ?? []) == [w1.id, w2.id])
        #expect(writer.focused.contains(w2.id))
    }

    // MARK: - Convertisseur hors ligne (unités, bases, fuseaux)

    @Test func launcherConverterHandlesUnitsBasesAndTimeZonesOffline() throws {
        let posix = Locale(identifier: "en_US_POSIX")

        // Unités
        let kmToMi = try #require(LauncherConverter.evaluate("100 km in mi", locale: posix))
        #expect(kmToMi.isConversion)
        #expect(abs(kmToMi.value - 62.1371192237) < 0.001)
        #expect(kmToMi.text.hasSuffix(" mi"))

        let fToC = try #require(LauncherConverter.evaluate("77 f to c", locale: posix))
        #expect(abs(fToC.value - 25.0) < 0.001)
        #expect(fToC.text == "25 °C")

        let cToK = try #require(LauncherConverter.evaluate("0 c en k", locale: posix))
        #expect(abs(cToK.value - 273.15) < 0.001)

        let gbToMib = try #require(LauncherConverter.evaluate("1 gb -> mib", locale: posix))
        #expect(abs(gbToMib.value - 953.6743164) < 0.01)

        let speed = try #require(LauncherConverter.evaluate("100 km/h to mph", locale: posix))
        #expect(abs(speed.value - 62.1371) < 0.01)

        // Dimensions incompatibles refusées
        #expect(LauncherConverter.evaluate("10 km in kg", locale: posix) == nil)
        #expect(LauncherConverter.evaluate("hello world", locale: posix) == nil)

        // Bases numériques
        let hexLit = try #require(LauncherConverter.evaluate("0xff", locale: posix))
        #expect(hexLit.text == "255")
        #expect(hexLit.detail?.contains("0b11111111") == true)

        let binLit = try #require(LauncherConverter.evaluate("0b101010", locale: posix))
        #expect(binLit.text == "42")

        let decToHex = try #require(LauncherConverter.evaluate("255 in hex", locale: posix))
        #expect(decToHex.text == "0xff")

        let decToBin = try #require(LauncherConverter.evaluate("42 to bin", locale: posix))
        #expect(decToBin.text == "0b101010")

        let octToDec = try #require(LauncherConverter.evaluate("0o755 to dec", locale: posix))
        #expect(octToDec.text == "493")

        // Fuseaux horaires déterministes (date fixe : 2026-06-15 12:00 UTC)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let fixed = Date(timeIntervalSince1970: 1_781_524_800) // 2026-06-15T12:00:00Z
        let tokyoNow = try #require(LauncherConverter.evaluate("time Tokyo", locale: posix, now: fixed, localTimeZone: utc))
        #expect(tokyoNow.text == "21:00 (Tokyo)")

        let rollover = try #require(LauncherConverter.evaluate("22:00 UTC in Tokyo", locale: posix, now: fixed, localTimeZone: utc))
        #expect(rollover.text.hasPrefix("07:00 +1"))
        #expect(rollover.text.contains("Tokyo"))
    }

    // MARK: - Pipette de couleur & sélecteur d'émojis

    @Test func colorFormatAndEmojiCatalogWorkOffline() throws {
        let red = LauncherColorFormat.fromSRGB(red: 1, green: 0, blue: 0)
        #expect(red.hex == "#FF0000")
        #expect(red.rgb == "rgb(255, 0, 0)")
        #expect(red.hsl == "hsl(0, 100%, 50%)")

        let gray = LauncherColorFormat.fromSRGB(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.hex == "#808080")
        #expect(gray.hsl == "hsl(0, 0%, 50%)")

        // La commande système pipette de couleur est enregistrée.
        #expect(LauncherSystemCommand.all().contains { $0.id == "color-picker" })

        // Émojis & typographie : `:cmd` -> ⌘, `emoji fleche` -> →, mot normal ne déclenche pas.
        let cmdMatches = try #require(LauncherEmojiCatalog.matches(":cmd"))
        #expect(cmdMatches.first?.glyph == "⌘")

        let arrowMatches = try #require(LauncherEmojiCatalog.matches("emoji fleche"))
        #expect(arrowMatches.contains { $0.glyph == "→" })

        let fireMatches = try #require(LauncherEmojiCatalog.matches(":fire"))
        #expect(fireMatches.first?.glyph == "🔥")

        #expect(LauncherEmojiCatalog.matches("firefox") == nil)
    }

    // MARK: - Minuteur & Pomodoro (service + CLI)

    @Test @MainActor func timerServiceParsesRunsCancelsAndExposesCLI() throws {
        #expect(LauncherTimerService.parseDurationSeconds("25m") == 1500)
        #expect(LauncherTimerService.parseDurationSeconds("1h30m") == 5400)
        #expect(LauncherTimerService.parseDurationSeconds("1h30") == 5400)
        #expect(LauncherTimerService.parseDurationSeconds("90s") == 90)
        #expect(LauncherTimerService.parseDurationSeconds("10") == 600)
        #expect(LauncherTimerService.parseDurationSeconds("abc") == nil)

        #expect(LauncherTimerService.parseQuery("pomodoro") == .start(seconds: 1500, label: "Pomodoro"))
        #expect(LauncherTimerService.parseQuery("timer 15m pause") == .start(seconds: 900, label: "pause"))
        #expect(LauncherTimerService.parseQuery("timer status") == .status)
        #expect(LauncherTimerService.parseQuery("timer stop") == .cancelAll)
        #expect(LauncherTimerService.parseQuery("firefox") == nil)

        final class NotifySpy: @unchecked Sendable {
            private let lock = NSLock()
            var fired: [LauncherTimerService.ActiveTimer] = []
            func record(_ t: LauncherTimerService.ActiveTimer) { lock.withLock { fired.append(t) } }
        }
        let spy = NotifySpy()
        let baseDate = Date(timeIntervalSince1970: 1_780_000_000)
        let service = LauncherTimerService(
            clock: { baseDate },
            notifier: { spy.record($0) },
            scheduleRealTimers: false
        )
        let t1 = service.start(seconds: 300, label: "Thé")
        let t2 = service.start(seconds: 1500, label: "Pomodoro")
        #expect(service.activeTimers().map(\.id) == [t1.id, t2.id])
        #expect(t1.remainingSeconds(at: baseDate.addingTimeInterval(60)) == 240)

        service.fire(id: t1.id)
        #expect(spy.fired.map(\.id) == [t1.id])
        #expect(service.activeTimers().map(\.id) == [t2.id])

        #expect(service.cancel(id: t2.id))
        #expect(service.activeTimers().isEmpty)

        // CLI `roadie timer` (nettoyage garanti en fin de test).
        defer { _ = LauncherTimerService.shared.cancelAll() }
        _ = LauncherTimerService.shared.cancelAll()
        let router = CLICommandRouter()
        #expect(router.run(["timer", "start", "10m", "Focus"]).exitCode == 0)
        let status = router.run(["timer", "status"])
        #expect(status.exitCode == 0)
        #expect(status.stdout.contains("Focus"))
        #expect(router.run(["timer", "cancel"]).exitCode == 0)
        #expect(router.run(["timer", "status"]).stdout.contains("none"))
        #expect(router.run(["timer", "start", "invalid"]).exitCode == 64)
    }
}
