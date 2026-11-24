import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 162 — Scratchpad flottant nommé, Dim Inactive (`fx.dim_inactive`) et Scènes de travail enrichies.
@Suite(.serialized)
struct Spec162ScratchpadDimScenesTests {
    private final class SpyWriter: WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        var writtenFrames: [WindowID: CGRect] = [:]
        var focusedWindowIDs: [WindowID] = []

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            lock.withLock { writtenFrames[window.id] = frame }
            return frame
        }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock { focusedWindowIDs.append(window.id) }
            return true
        }

        func lastFrame(for id: WindowID) -> CGRect? {
            lock.withLock { writtenFrames[id] }
        }
    }

    private final class MutableProvider: SystemSnapshotProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var displaysStorage: [DisplaySnapshot]
        private var windowsStorage: [WindowSnapshot]
        private var focusedStorage: WindowID?

        init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID?) {
            self.displaysStorage = displays
            self.windowsStorage = windows
            self.focusedStorage = focused
        }

        func updateWindowFrame(_ id: WindowID, to rect: CGRect) {
            lock.withLock {
                if let idx = windowsStorage.firstIndex(where: { $0.id == id }) {
                    windowsStorage[idx].frame = Rect(rect)
                }
            }
        }

        func setFocused(_ id: WindowID?) {
            lock.withLock { focusedStorage = id }
        }

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }

        func displays() -> [DisplaySnapshot] {
            lock.withLock { displaysStorage }
        }

        func windows() -> [WindowSnapshot] {
            lock.withLock { windowsStorage }
        }

        func focusedWindowID() -> WindowID? {
            lock.withLock { focusedStorage }
        }
    }

    @MainActor
    private final class SpyDimRenderer: DimInactiveRendering {
        var renderedTargets: [[DimInactiveTarget]] = []
        var hideAllCalls = 0

        func render(_ targets: [DimInactiveTarget]) {
            renderedTargets.append(targets)
        }

        func hideAll() {
            hideAllCalls += 1
        }
    }

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec162-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func display(_ id: String = "d1", index: Int = 1, x: Double = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: index,
            name: "Display \(index)",
            frame: Rect(x: x, y: 0, width: 1600, height: 900),
            visibleFrame: Rect(x: x, y: 30, width: 1600, height: 870),
            isMain: index == 1
        )
    }

    private func window(
        _ id: UInt32,
        bundleID: String = "com.example.app",
        title: String = "Win",
        frame: Rect = Rect(x: 40, y: 60, width: 700, height: 600),
        isTileCandidate: Bool = true,
        isOnScreen: Bool = true,
        nativeFullscreen: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 500,
            appName: "App",
            bundleID: bundleID,
            title: "\(title) \(id)",
            frame: frame,
            isOnScreen: isOnScreen,
            isTileCandidate: isTileCandidate,
            furniture: nativeFullscreen
                ? WindowFurniture(
                    hasCloseButton: true,
                    hasFullscreenButton: true,
                    fullscreenButtonEnabled: true,
                    hasMinimizeButton: true,
                    hasZoomButton: true,
                    isResizable: true,
                    isNativeFullscreen: true
                )
                : nil
        )
    }

    // MARK: - Réglages & Catalogue

    @Test func spec162ConfigDefaultsTomlAndValidation() throws {
        let defaults = RoadieConfig()
        #expect(defaults.tiling.scratchpadEnabled == true)
        #expect(defaults.fx.dimInactive.enabled == false)
        #expect(abs(defaults.fx.dimInactive.opacity - 0.22) < 0.001)

        let dir = try tempDir("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        try """
        [tiling]
        scratchpad_enabled = false

        [fx.dim_inactive]
        enabled = true
        opacity = 0.35
        """.write(to: file, atomically: true, encoding: .utf8)

        let report = RoadieConfigLoader.validate(path: file.path)
        #expect(!report.hasErrors)
        #expect(!report.items.contains { $0.level == .warning })

        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(loaded.tiling.scratchpadEnabled == false)
        #expect(loaded.fx.dimInactive.enabled == true)
        #expect(abs(loaded.fx.dimInactive.opacity - 0.35) < 0.001)

        // Hors plage [0.05, 0.75] : refusé au décodage TOML (contrat Effets), borné en init Swift.
        let invalidFile = dir.appendingPathComponent("invalid.toml")
        try """
        [fx.dim_inactive]
        enabled = true
        opacity = 0.99
        """.write(to: invalidFile, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { _ = try RoadieConfigLoader.load(from: invalidFile.path) }
        #expect(abs(DimInactiveConfig(enabled: true, opacity: 0.99).opacity - 0.75) < 0.001)

        #expect(SettingsCatalog.find(id: "tiling.scratchpad_enabled") != nil)
        #expect(SettingsCatalog.find(id: "dim_inactive.enabled") != nil)
        #expect(SettingsCatalog.find(id: "dim_inactive.opacity") != nil)
    }

    // MARK: - Scratchpad flottant

    @Test func centeredFrameUsesDefaultRatioAndClampsSavedDimensions() {
        let visible = CGRect(x: 0, y: 30, width: 1600, height: 870)
        let defaultFrame = ScratchpadCommandService.centeredFrame(saved: nil, in: visible)
        #expect(defaultFrame.width == 1120)
        #expect(defaultFrame.height == 653)
        #expect(abs(defaultFrame.midX - visible.midX) <= 1)
        #expect(abs(defaultFrame.midY - visible.midY) <= 1)

        let oversized = Rect(x: 0, y: 0, width: 3000, height: 2000)
        let clamped = ScratchpadCommandService.centeredFrame(saved: oversized, in: visible)
        #expect(clamped.width <= visible.width * 0.92 + 1)
        #expect(clamped.height <= visible.height * 0.92 + 1)
    }

    @Test func scratchpadAssignToggleShowHideReleaseAndProtection() throws {
        let dir = try tempDir("scratchpad")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let scratchStore = ScratchpadStore(path: dir.appendingPathComponent("scratchpads.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)

        let w1 = window(101, bundleID: "com.apple.Notes", title: "Notes")
        let w2 = window(102, bundleID: "com.apple.Terminal", title: "Term")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2], focused: w1.id)
        let writer = SpyWriter()
        let config = RoadieConfig()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: config,
            stageStore: stageStore,
            events: eventLog
        )
        _ = service.snapshot()

        let cmd = ScratchpadCommandService(
            service: service,
            stageStore: stageStore,
            scratchpadStore: scratchStore,
            events: eventLog
        )

        // Assigner la fenêtre focalisée au scratchpad "notes"
        let assigned = cmd.assign(name: "notes")
        #expect(assigned.changed)
        #expect(assigned.outcome == CommandOutcome.changed)
        let assignedFrame = try #require(writer.lastFrame(for: w1.id))
        provider.updateWindowFrame(w1.id, to: assignedFrame)
        let afterAssign = cmd.list()
        #expect(afterAssign.map(\.name) == ["notes"])
        #expect(afterAssign.first?.isVisible == true)

        // La politique de tuilage protège la fenêtre tant qu'elle est dans le scratchpad
        let protectedContext = SnapshotService.TilingPolicyContext(
            config: config,
            scratchpadWindowIDs: scratchStore.load().windowIDs
        )
        let protectedDecision = SnapshotService.tilingDecision(for: w1, config: config, context: protectedContext)
        #expect(protectedDecision.tile == false)

        // Basculer (toggle) masque la fenêtre hors écran
        let toggledHide = cmd.toggle(name: "notes")
        #expect(toggledHide.changed)
        let hiddenFrame = try #require(writer.lastFrame(for: w1.id))
        #expect(HiddenWindowPlacement.isHiddenOrLegacyOffscreen(hiddenFrame, in: [display()]))
        provider.updateWindowFrame(w1.id, to: hiddenFrame)
        #expect(cmd.list().first?.isVisible == false)

        // Basculer à nouveau rappelle la fenêtre centrée
        let toggledShow = cmd.toggle(name: "notes")
        #expect(toggledShow.changed)
        let shownFrame = try #require(writer.lastFrame(for: w1.id))
        #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(shownFrame, in: [display()]))
        #expect(cmd.list().first?.isVisible == true)

        // Détacher (release) libère la fenêtre
        let released = cmd.release(name: "notes")
        #expect(released.changed)
        #expect(cmd.list().isEmpty)
        let releasedContext = SnapshotService.TilingPolicyContext(
            config: config,
            scratchpadWindowIDs: scratchStore.load().windowIDs
        )
        #expect(SnapshotService.tilingDecision(for: w1, config: config, context: releasedContext).tile == true)
    }

    @Test func scratchpadRespectsDisabledSettingAndRuleFallback() throws {
        let dir = try tempDir("scratchpad-rule")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let scratchStore = ScratchpadStore(path: dir.appendingPathComponent("scratchpads.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)

        let w1 = window(201, bundleID: "com.googlecode.iterm2", title: "DropTerm")
        let provider = MutableProvider(displays: [display()], windows: [w1], focused: w1.id)
        let writer = SpyWriter()

        // 1. Désactivé par configuration
        var disabledConfig = RoadieConfig()
        disabledConfig.tiling.scratchpadEnabled = false
        let disabledService = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: disabledConfig,
            stageStore: stageStore,
            events: eventLog
        )
        let disabledCmd = ScratchpadCommandService(
            service: disabledService,
            stageStore: stageStore,
            scratchpadStore: scratchStore,
            events: eventLog
        )
        let disabledResult = disabledCmd.assign(name: "term")
        #expect(!disabledResult.changed)
        #expect(disabledResult.outcome == CommandOutcome.noOp)

        // 2. Repli sur une règle `action.scratchpad = "term"`
        var ruleConfig = RoadieConfig()
        ruleConfig.rules = [
            WindowRule(
                id: "rule-term",
                match: RuleMatch(appRegex: "iterm2"),
                action: RuleAction(scratchpad: "term")
            )
        ]
        let ruleService = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: ruleConfig,
            stageStore: stageStore,
            events: eventLog
        )
        let ruleCmd = ScratchpadCommandService(
            service: ruleService,
            stageStore: stageStore,
            scratchpadStore: scratchStore,
            events: eventLog
        )
        let hiddenViaRule = ruleCmd.toggle(name: "term")
        #expect(hiddenViaRule.changed)
        let ruleEntries = ruleCmd.list()
        #expect(ruleEntries.map(\.name) == ["term"])
        #expect(ruleEntries.first?.isVisible == false)
    }

    @Test @MainActor func cliRoutesScratchpadAndHandlesProjectInfo() throws {
        #expect(CLICommandRouter.isDaemonRouted(["scratchpad", "toggle"]))
        #expect(CLICommandRouter.isDaemonRouted(["scratchpad", "assign", "notes"]))
        #expect(CLICommandRouter.isReadOnly(["scratchpad", "list"]))
        #expect(!CLICommandRouter.isReadOnly(["scratchpad", "toggle"]))
        #expect(CLICommandRouter.isReadOnly(["project", "info", "Work"]))

        // Vérifier que la commande lanceur existe et matche "scratchpad"
        let commands = LauncherSystemCommand.all()
        #expect(commands.contains { $0.id == "roadie-scratchpad-toggle" })
        #expect(LauncherSystemCommand.matches("scratchpad", in: commands).contains { $0.id == "roadie-scratchpad-toggle" })

        // Tester `roadie project info` avec une scène enrichie
        let store = StageProjectStore()
        let projectName = "Spec162Scene-\(UUID().uuidString.prefix(6))"
        let sample = StageProject(
            name: projectName,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            windows: [
                ProjectWindow(bundleID: "com.apple.Terminal", appPath: "/System/Applications/Utilities/Terminal.app", document: nil, url: nil, title: "Shell")
            ],
            tree: nil,
            extraURLs: ["https://example.org", "~/Documents"],
            launchApps: ["com.apple.Notes"],
            displayCount: 2,
            notes: "Focus session"
        )
        try store.save(sample)
        defer { _ = try? store.delete(projectName) }

        let router = CLICommandRouter()
        let textRes = router.run(["project", "info", projectName])
        #expect(textRes.exitCode == 0)
        #expect(textRes.stdout.contains("displays=2"))
        #expect(textRes.stdout.contains("com.apple.Notes"))
        #expect(textRes.stdout.contains("https://example.org"))
        #expect(textRes.stdout.contains("Focus session"))

        let jsonRes = router.run(["project", "info", projectName, "--json"])
        #expect(jsonRes.exitCode == 0)
        #expect(jsonRes.stdout.contains("\"displayCount\" : 2"))
        #expect(jsonRes.stdout.contains("\"notes\" : \"Focus session\""))

        let badSave = router.run(["project", "save", projectName, "--url"])
        #expect(badSave.exitCode == 64)

        let badScratch = router.run(["scratchpad", "assign", "--window", "not-a-number"])
        #expect(badScratch.exitCode == 64)
    }

    // MARK: - Dim Inactive

    @Test @MainActor func dimInactiveComputeTargetsFiltersProperly() throws {
        let dir = try tempDir("dim")
        defer { try? FileManager.default.removeItem(at: dir) }
        let d = display()
        let desktopID = DesktopID(rawValue: 1)
        let activeScope = StageScope(displayID: d.id, desktopID: desktopID, stageID: StageID(rawValue: "1"))
        let inactiveScope = StageScope(displayID: d.id, desktopID: desktopID, stageID: StageID(rawValue: "2"))

        let focusedWin = window(1, title: "Focused", frame: Rect(x: 0, y: 30, width: 700, height: 800))
        let unfocusedTiled = window(2, title: "InactiveTiled", frame: Rect(x: 720, y: 30, width: 700, height: 800))
        let floatingWin = window(3, title: "Floating", frame: Rect(x: 100, y: 100, width: 500, height: 400), isTileCandidate: false)
        let fullscreenWin = window(4, title: "NativeFS", frame: Rect(x: 0, y: 0, width: 1600, height: 900), nativeFullscreen: true)
        let inactiveStageWin = window(5, title: "OtherStage", frame: Rect(x: 50, y: 50, width: 600, height: 600))
        let offscreenWin = window(6, title: "Offscreen", frame: Rect(x: 9000, y: 9000, width: 600, height: 600))

        let state = RoadieState(displays: [d.id: DisplayState(id: d.id, currentDesktopID: desktopID)])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true),
            displays: [d],
            windows: [
                ScopedWindowSnapshot(window: focusedWin, scope: activeScope),
                ScopedWindowSnapshot(window: unfocusedTiled, scope: activeScope),
                ScopedWindowSnapshot(window: floatingWin, scope: activeScope),
                ScopedWindowSnapshot(window: fullscreenWin, scope: activeScope),
                ScopedWindowSnapshot(window: inactiveStageWin, scope: inactiveScope),
                ScopedWindowSnapshot(window: offscreenWin, scope: activeScope),
            ],
            state: state,
            focusedWindowID: focusedWin.id
        )

        // Désactivé -> aucune cible
        let disabledTargets = DimInactiveController.computeTargets(
            snapshot: snapshot,
            config: DimInactiveConfig(enabled: false, opacity: 0.30),
            frameTransform: { $0 }
        )
        #expect(disabledTargets.isEmpty)

        // Activé -> uniquement la fenêtre tuilée inactive visible de la stage active
        let enabledTargets = DimInactiveController.computeTargets(
            snapshot: snapshot,
            config: DimInactiveConfig(enabled: true, opacity: 0.30),
            cornerRadius: 12,
            frameTransform: { $0 }
        )
        #expect(enabledTargets.count == 1)
        #expect(enabledTargets.first?.windowID == unfocusedTiled.id)
        #expect(abs((enabledTargets.first?.opacity ?? 0) - 0.30) < 0.001)
        #expect(enabledTargets.first?.cornerRadius == 12)
    }

    @Test @MainActor func dimInactiveControllerHidesWhenDisabledAndRendersWhenEnabled() async throws {
        let dir = try tempDir("dim-ctrl")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let w1 = window(301, title: "Focus", frame: Rect(x: 20, y: 40, width: 700, height: 700))
        let w2 = window(302, title: "Neighbor", frame: Rect(x: 740, y: 40, width: 700, height: 700))
        let provider = MutableProvider(displays: [display()], windows: [w1, w2], focused: w1.id)
        let service = SnapshotService(
            provider: provider,
            config: RoadieConfig(),
            stageStore: stageStore,
            events: EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        )
        _ = service.snapshot()

        let spy = SpyDimRenderer()
        var currentConfig = RoadieConfig()
        currentConfig.fx.dimInactive.enabled = false
        let controller = DimInactiveController(
            snapshotService: service,
            configLoader: { currentConfig },
            renderer: spy
        )

        await controller.refresh()
        #expect(spy.hideAllCalls == 1)
        #expect(spy.renderedTargets.isEmpty)

        currentConfig.fx.dimInactive.enabled = true
        currentConfig.fx.dimInactive.opacity = 0.28
        await controller.refresh()
        #expect(spy.renderedTargets.count == 1)
        #expect(spy.renderedTargets.first?.map(\.windowID) == [w2.id])
    }

    // MARK: - Scènes de travail enrichies

    @Test func stageProjectBackwardCompatibilityAndLaunchPlan() throws {
        // Décodage rétrocompatible d'un JSON SPEC-080 sans les nouveaux champs Spec 162
        let legacyJSON = """
        {
          "name": "Legacy",
          "savedAt": 0,
          "windows": [
            {
              "bundleID": "com.apple.Terminal",
              "appPath": "/System/Applications/Utilities/Terminal.app",
              "title": "Shell"
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(StageProject.self, from: Data(legacyJSON.utf8))
        #expect(decoded.name == "Legacy")
        #expect(decoded.extraURLs.isEmpty)
        #expect(decoded.launchApps.isEmpty)
        #expect(decoded.displayCount == 1)
        #expect(decoded.notes == nil)

        let enriched = StageProject(
            name: "Dev",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            windows: decoded.windows,
            tree: nil,
            extraURLs: [" https://docs.swift.org ", "", "~/Projects"],
            launchApps: ["com.apple.Terminal", "com.apple.Notes", "com.apple.Notes", "com.apple.Safari"],
            displayCount: 2,
            notes: "Backend & docs"
        )
        let plan = enriched.launchPlan(runningBundleIDs: ["com.apple.Terminal"])
        #expect(plan.missingApps == ["com.apple.Notes", "com.apple.Safari"])
        #expect(plan.urlsToOpen == ["https://docs.swift.org", "~/Projects"])
        #expect(plan.windowCount == 1)
        #expect(plan.hasTree == false)
    }
}
