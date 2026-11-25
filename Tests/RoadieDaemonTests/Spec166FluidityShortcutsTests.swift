import Foundation
import os
import Testing
import TOMLKit
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite(.serialized)
struct Spec166FluidityShortcutsTests {

    private final class MockWriter: WindowFrameWriting, @unchecked Sendable {
        let frames = OSAllocatedUnfairLock(initialState: [WindowID: CGRect]())
        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            frames.withLock { $0[window.id] = frame }
            return frame
        }
        func focus(_ window: WindowSnapshot) -> Bool { true }
    }

    private final class MockProvider: SystemSnapshotProviding, @unchecked Sendable {
        let state: OSAllocatedUnfairLock<(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID?)>
        init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID?) {
            self.state = OSAllocatedUnfairLock(initialState: (displays, windows, focused))
        }
        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }
        func displays() -> [DisplaySnapshot] { state.withLock(\.displays) }
        func windows() -> [WindowSnapshot] { state.withLock(\.windows) }
        func focusedWindowID() -> WindowID? { state.withLock(\.focused) }
        func setWindows(_ windows: [WindowSnapshot], focused: WindowID?) {
            state.withLock {
                $0.windows = windows
                $0.focused = focused
            }
        }
    }

    // MARK: - Réglages [tiling] Spec 166

    @Test
    func scrollingSettingsDefaultsAndTOMLParsing() throws {
        let defaults = TilingConfig()
        #expect(defaults.scrollingSmoothScroll == true)
        #expect(defaults.scrollingTrackpadGestures == true)
        #expect(defaults.scrollingTrackpadFingers == 3)

        let toml = """
        [tiling]
        scrolling_smooth_scroll = false
        scrolling_trackpad_gestures = false
        scrolling_trackpad_fingers = 4
        """
        let decoded = try TOMLDecoder().decode(RoadieConfig.self, from: toml)
        #expect(decoded.tiling.scrollingSmoothScroll == false)
        #expect(decoded.tiling.scrollingTrackpadGestures == false)
        #expect(decoded.tiling.scrollingTrackpadFingers == 4)

        let clampedToml = """
        [tiling]
        scrolling_trackpad_fingers = 9
        """
        let clamped = try TOMLDecoder().decode(RoadieConfig.self, from: clampedToml)
        #expect(clamped.tiling.scrollingTrackpadFingers == 4)
    }

    // MARK: - Horloge adaptative 120 Hz

    @Test
    @MainActor
    func effectAnimatorAdaptiveFrameIntervalSupports120HzAndClampsBounds() {
        #expect(abs(EffectAnimator.preferredFrameInterval(maxFPS: 120) - (1.0 / 120.0)) < 1e-9)
        #expect(abs(EffectAnimator.preferredFrameInterval(maxFPS: 60) - (1.0 / 60.0)) < 1e-9)
        #expect(abs(EffectAnimator.preferredFrameInterval(maxFPS: 240) - (1.0 / 120.0)) < 1e-9)
        #expect(abs(EffectAnimator.preferredFrameInterval(maxFPS: 10) - (1.0 / 30.0)) < 1e-9)
        #expect(FrameTransitionRuntime.scrollingRibbonPolicy.enabled == true)
        #expect(FrameTransitionRuntime.scrollingRibbonPolicy.curve == .spring)
    }

    // MARK: - Détecteur de gestes trackpad & Option + molette

    @Test
    func trackpadSwipeThreeFingersDetectsHorizontalAndIgnoresVertical() {
        var detector = ScrollingGestureDetector(requiredFingers: 3)

        // Ancre initiale à 3 doigts.
        let start = [CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.55, y: 0.50), CGPoint(x: 0.60, y: 0.50)]
        #expect(detector.processTouches(start, now: 1.0, naturalScrolling: true) == nil)

        // Mouvement vertical (Mission Control / Exposé) : strictement ignoré.
        let vertical = start.map { CGPoint(x: $0.x - 0.02, y: $0.y + 0.14) }
        #expect(detector.processTouches(vertical, now: 1.05, naturalScrolling: true) == nil)

        // Balayage franc vers la gauche (naturalScrolling = true -> colonne de droite).
        let swipeLeft = start.map { CGPoint(x: $0.x - 0.12, y: $0.y + 0.01) }
        #expect(detector.processTouches(swipeLeft, now: 1.10, naturalScrolling: true) == .right)

        // Un second échantillon dans le même geste ne redéclenche pas.
        let swipeMore = start.map { CGPoint(x: $0.x - 0.22, y: $0.y) }
        #expect(detector.processTouches(swipeMore, now: 1.15, naturalScrolling: true) == nil)

        // Relâchement des doigts réarme le détecteur, mais le cooldown (220 ms) protège encore.
        #expect(detector.processTouches([], now: 1.20, naturalScrolling: true) == nil)
        #expect(detector.processTouches(start, now: 1.25, naturalScrolling: true) == nil)
        let swipeRightEarly = start.map { CGPoint(x: $0.x + 0.12, y: $0.y) }
        #expect(detector.processTouches(swipeRightEarly, now: 1.28, naturalScrolling: true) == nil)

        // Après cooldown : balayage vers la droite -> colonne de gauche.
        #expect(detector.processTouches(swipeRightEarly, now: 1.40, naturalScrolling: true) == .left)

        // Mode non-naturel inverse le sens.
        #expect(detector.processTouches([], now: 1.50, naturalScrolling: false) == nil)
        #expect(detector.processTouches(start, now: 1.70, naturalScrolling: false) == nil)
        #expect(detector.processTouches(swipeRightEarly, now: 1.75, naturalScrolling: false) == .right)
    }

    @Test
    func trackpadSwipeRequiresConfiguredFourFingers() {
        var detector = ScrollingGestureDetector(requiredFingers: 4)
        let three = [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.6, y: 0.5)]
        #expect(detector.processTouches(three, now: 1.0) == nil)
        #expect(detector.processTouches(three.map { CGPoint(x: $0.x - 0.15, y: $0.y) }, now: 1.1) == nil)

        let four = three + [CGPoint(x: 0.7, y: 0.5)]
        #expect(detector.processTouches(four, now: 1.2) == nil)
        #expect(detector.processTouches(four.map { CGPoint(x: $0.x - 0.15, y: $0.y) }, now: 1.3) == .right)
    }

    @Test
    func optionScrollWheelAccumulatesAndTriggersCleanly() {
        var detector = ScrollingGestureDetector()
        #expect(detector.processOptionScroll(deltaX: -10, deltaY: 0, now: 1.0, naturalScrolling: true) == nil)
        #expect(detector.processOptionScroll(deltaX: -18, deltaY: 0, now: 1.05, naturalScrolling: true) == .right)
        // Cooldown actif :
        #expect(detector.processOptionScroll(deltaX: 40, deltaY: 0, now: 1.10, naturalScrolling: true) == nil)
        // Après cooldown (molette verticale crantée sur souris externe) :
        #expect(detector.processOptionScroll(deltaX: 0, deltaY: 36, now: 1.35, naturalScrolling: true) == .left)
    }

    // MARK: - Préréglages de raccourcis autonomes (AZERTY & QWERTY)

    @Test
    func allShortcutPresetsResolveWithoutCollisionOnQwertyAndAzerty() {
        let azertyLayout: [UInt32: String] = [
            0: "q", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "w", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "a", 13: "z", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
            34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 41: "m", 45: "n",
            // Chiffres non présents sans Maj sur AZERTY : la résolution passe par `namedKeyCode`.
            18: "&", 19: "é", 20: "\"", 21: "'", 23: "("
        ]

        for preset in ShortcutPresets.all {
            #expect(!preset.shortcuts.isEmpty)
            for layout in [TargetSearchHotkey.standardFallbackLayout, azertyLayout] {
                let planned = RoadieCommandHotkeys.plan(preset.shortcuts, layout: layout)
                #expect(planned.issues.isEmpty, "Problèmes dans \(preset.id.rawValue) : \(planned.issues)")
                #expect(planned.entries.count == preset.shortcuts.count)
            }
        }
    }

    @Test
    func shortcutPresetMergePreservesUserShortcutsAndBTTEntries() {
        let existing = [
            CommandShortcut(keys: "alt+left", command: "focus left", enabled: true),
            CommandShortcut(keys: "alt+o", command: "stage next", enabled: true), // collision de touche avec overview toggle
            CommandShortcut(keys: "command+alt+x", command: "balance", enabled: true, bttUUID: "btt-123")
        ]

        let nonDestructive = ShortcutPresets.merge(.minimal, into: existing, replaceExisting: false)
        #expect(nonDestructive.skippedExistingCommands.contains("focus left"))
        #expect(nonDestructive.skippedKeyCollisions.contains { $0.contains("alt+o") })
        #expect(nonDestructive.resultingShortcuts.contains { $0.bttUUID == "btt-123" })
        #expect(nonDestructive.added.count == 8)

        let replaced = ShortcutPresets.merge(.minimal, into: existing, replaceExisting: true)
        #expect(replaced.resultingShortcuts.contains { $0.bttUUID == "btt-123" })
        #expect(replaced.added.count == 10)
    }

    @Test
    func renderDefaultConfigTOMLDecodesCleanly() throws {
        for preset in ShortcutPresetID.allCases {
            let toml = ShortcutPresets.renderDefaultConfigTOML(preset: preset)
            let decoded = try TOMLDecoder().decode(RoadieConfig.self, from: toml)
            #expect(decoded.tiling.defaultStrategy == .spatialBsp)
            #expect(decoded.tiling.scrollingSmoothScroll == true)
            #expect(decoded.tiling.scrollingTrackpadGestures == true)
            #expect(decoded.shortcuts.count == ShortcutPresets.preset(for: preset).shortcuts.count)
        }
    }

    // MARK: - CLI `config init` & `shortcuts`

    @Test
    @MainActor
    func cliConfigInitAndShortcutsWorkflow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-spec166-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let configPath = dir.appendingPathComponent("config.toml").path

        let router = CLICommandRouter()

        // 1. config init crée le fichier avec le preset minimal.
        let initRes = router.run(["config", "init", "--preset", "minimal", "--config", configPath])
        #expect(initRes.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: configPath))

        // 2. Second config init sans --force échoue proprement.
        let initAgain = router.run(["config", "init", "--preset", "vim", "--config", configPath])
        #expect(initAgain.exitCode == 1)

        // 3. shortcuts check est 100 % valide.
        let checkRes = router.run(["shortcuts", "check", "--config", configPath])
        #expect(checkRes.exitCode == 0)
        #expect(checkRes.stdout.contains("active=10"))
        #expect(checkRes.stdout.contains("issues=0"))

        // 4. shortcuts add + remove.
        let addRes = router.run(["shortcuts", "add", "alt+g", "window gather-app", "--config", configPath])
        #expect(addRes.exitCode == 0)
        let listRes = router.run(["shortcuts", "list", "--config", configPath])
        #expect(listRes.exitCode == 0)
        #expect(listRes.stdout.contains("window gather-app"))

        let removeRes = router.run(["shortcuts", "remove", "alt+g", "--config", configPath])
        #expect(removeRes.exitCode == 0)
        #expect(removeRes.stdout.contains("removed=1"))

        // 5. apply-preset standard en mode fusion non-destructive ajoute les raccourcis manquants.
        let mergeRes = router.run(["shortcuts", "apply-preset", "standard", "--config", configPath])
        #expect(mergeRes.exitCode == 0)
        #expect(mergeRes.stdout.contains("preset=standard"))

        // 6. Commandes du lanceur bien présentes.
        let launcherIDs = Set(LauncherSystemCommand.all().map(\.id))
        #expect(launcherIDs.contains("roadie-shortcuts-preset-standard"))
        #expect(launcherIDs.contains("roadie-shortcuts-preset-vim"))
        #expect(launcherIDs.contains("roadie-shortcuts-preset-minimal"))
    }

    // MARK: - Geste trackpad 4 doigts Vue d'ensemble (sans BTT)

    @Test
    func overviewFourFingerVerticalGestureDetectsUpDownAndIgnoresHorizontal() {
        var detector = ScrollingGestureDetector()
        let four = [
            CGPoint(x: 0.2, y: 0.4), CGPoint(x: 0.4, y: 0.4),
            CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.8, y: 0.4)
        ]
        #expect(detector.processOverviewTouches(four, now: 1.0) == nil)
        // Horizontal rejeté :
        #expect(detector.processOverviewTouches(four.map { CGPoint(x: $0.x + 0.15, y: $0.y + 0.01) }, now: 1.05) == nil)
        // 3 doigts rejeté :
        #expect(detector.processOverviewTouches(Array(four.prefix(3)), now: 1.10) == nil)
        // Ré-ancrage à 4 doigts puis glissement vers le haut -> .up (toggle overview).
        #expect(detector.processOverviewTouches(four, now: 1.20) == nil)
        #expect(detector.processOverviewTouches(four.map { CGPoint(x: $0.x, y: $0.y + 0.12) }, now: 1.25) == .up)
        // Cooldown 350 ms :
        #expect(detector.processOverviewTouches([], now: 1.30) == nil)
        #expect(detector.processOverviewTouches(four, now: 1.35) == nil)
        #expect(detector.processOverviewTouches(four.map { CGPoint(x: $0.x, y: $0.y - 0.12) }, now: 1.40) == nil)
        // Après cooldown -> .down (hide overview).
        #expect(detector.processOverviewTouches(four.map { CGPoint(x: $0.x, y: $0.y - 0.12) }, now: 1.70) == .down)
    }

    // MARK: - Scratchpad au reboot & menu contextuel barre de titre

    @Test
    func scratchpadRebootPoliciesAndTitlebarContextActions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-spec166-sp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "d1"), index: 1, name: "Main",
            frame: Rect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875),
            isMain: true
        )
        let w1 = WindowSnapshot(
            id: WindowID(rawValue: 101), pid: 500, appName: "Notes", bundleID: "com.apple.Notes",
            title: "Scratch Notes", frame: Rect(x: 100, y: 100, width: 800, height: 600),
            isOnScreen: true, isTileCandidate: true
        )
        let w2 = WindowSnapshot(
            id: WindowID(rawValue: 102), pid: 501, appName: "Safari", bundleID: "com.apple.Safari",
            title: "Docs", frame: Rect(x: 200, y: 100, width: 800, height: 600),
            isOnScreen: true, isTileCandidate: true
        )

        let provider = MockProvider(displays: [display], windows: [w1, w2], focused: w1.id)
        let writer = MockWriter()
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let scratchStore = ScratchpadStore(path: dir.appendingPathComponent("scratchpads.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let configPath = dir.appendingPathComponent("config.toml").path
        try "[tiling]\nscratchpad_reboot_policy = \"reattach_or_relaunch\"\n".write(toFile: configPath, atomically: true, encoding: .utf8)
        let configReload = ConfigReloadService()
        _ = configReload.reload(path: configPath)

        let snapshotService = SnapshotService(
            provider: provider,
            frameWriter: writer,
            stageStore: stageStore,
            configService: configReload
        )

        // 1. Affectation initiale via ScratchpadCommandService.
        let launched = OSAllocatedUnfairLock(initialState: [String]())
        let sp = ScratchpadCommandService(
            service: snapshotService,
            stageStore: stageStore,
            scratchpadStore: scratchStore,
            events: events,
            appLauncher: { bundleID in
                launched.withLock { $0.append(bundleID) }
                return true
            }
        )
        let assignRes = sp.assign(name: "default", windowID: w1.id)
        #expect(assignRes.changed)
        #expect(sp.scratchpadName(for: w1.id, bundleID: w1.bundleID) == "default")

        // 2. Simulation de reboot : l'app Notes se rouvre avec un nouveau CGWindowID (901).
        let w1Reopened = WindowSnapshot(
            id: WindowID(rawValue: 901), pid: 610, appName: "Notes", bundleID: "com.apple.Notes",
            title: "Scratch Notes", frame: Rect(x: 40, y: 40, width: 700, height: 500),
            isOnScreen: true, isTileCandidate: true
        )
        provider.setWindows([w1Reopened, w2], focused: w2.id)

        let reattachRes = sp.toggle(name: "default")
        #expect(reattachRes.changed)
        #expect(reattachRes.message.contains("901"))
        #expect(sp.scratchpadName(for: w1Reopened.id, bundleID: w1Reopened.bundleID) == "default")

        // 3. Simulation de reboot sans Notes ouverte : `reattach_or_relaunch` relance l'app à la demande.
        provider.setWindows([w2], focused: w2.id)
        let relaunchRes = sp.toggle(name: "default")
        #expect(relaunchRes.changed)
        #expect(relaunchRes.message.contains("relaunching com.apple.Notes"))
        #expect(launched.withLock { $0 } == ["com.apple.Notes"])

        // 4. Politique `ephemeral` : ne relance ni ne rattache après changement de windowID.
        try "[tiling]\nscratchpad_reboot_policy = \"ephemeral\"\n".write(toFile: configPath, atomically: true, encoding: .utf8)
        _ = configReload.reload(path: configPath)
        let w1Third = WindowSnapshot(
            id: WindowID(rawValue: 999), pid: 700, appName: "Notes", bundleID: "com.apple.Notes",
            title: "Scratch Notes", frame: Rect(x: 40, y: 40, width: 700, height: 500),
            isOnScreen: true, isTileCandidate: true
        )
        provider.setWindows([w1Third, w2], focused: w2.id)
        let ephemeralRes = sp.toggle(name: "default")
        #expect(!ephemeralRes.changed)
        #expect(ephemeralRes.message.contains("no window assigned"))

        // 5. Menu barre de titre : `.scratchpadAssign` puis `.scratchpadRelease` via WindowContextActions.
        let actions = WindowContextActions(snapshotService: snapshotService, stageStore: stageStore, eventLog: events)
        let ctxAssign = actions.execute(WindowContextAction(windowID: w2.id, kind: .scratchpadAssign, targetID: "default", sourceScope: nil))
        #expect(ctxAssign.changed)
        let ctxRelease = actions.execute(WindowContextAction(windowID: w2.id, kind: .scratchpadRelease, targetID: "default", sourceScope: nil))
        #expect(ctxRelease.changed)

        // 6. Réglages `scratchpad_reboot_policy` et `overview.trackpad_gesture` décodés proprement.
        let decoded = try TOMLDecoder().decode(RoadieConfig.self, from: """
        [tiling]
        scratchpad_reboot_policy = "reattach"
        [overview]
        trackpad_gesture = false
        """)
        #expect(decoded.tiling.scratchpadRebootPolicy == "reattach")
        #expect(decoded.overview.trackpadGesture == false)
    }

    @Test
    func switcherCommandTabRoutesThroughEventTapMatching() {
        let plan = WindowSwitcherHotkeyPlan(
            requests: [
                WindowSwitcherHotkeyRequest(profileID: "all", hotkey: "command+tab"),
                WindowSwitcherHotkeyRequest(profileID: "zones", hotkey: "alt+tab"),
            ],
            layout: TargetSearchHotkey.standardFallbackLayout
        )
        #expect(plan.issues.isEmpty)
        let cmdEntries = plan.entries.filter { WindowSwitcherHotkeyRegistry.requiresEventTap($0.hotkey) }
        #expect(cmdEntries.count == 2) // command+tab + command+shift+tab

        let forward = WindowSwitcherHotkeyRegistry.matchTapEntry(keyCode: 48, flags: .maskCommand, in: cmdEntries)
        #expect(forward?.profileID == "all" && forward?.backwards == false)

        let reverse = WindowSwitcherHotkeyRegistry.matchTapEntry(keyCode: 48, flags: [.maskCommand, .maskShift], in: cmdEntries)
        #expect(reverse?.profileID == "all" && reverse?.backwards == true)

        // Autres touches ou modificateurs ne sont jamais consommés.
        #expect(WindowSwitcherHotkeyRegistry.matchTapEntry(keyCode: 48, flags: .maskAlternate, in: cmdEntries) == nil)
        #expect(WindowSwitcherHotkeyRegistry.matchTapEntry(keyCode: 12, flags: .maskCommand, in: cmdEntries) == nil)
    }
}
