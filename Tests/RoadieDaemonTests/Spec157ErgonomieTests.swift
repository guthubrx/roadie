import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import Testing
@testable import RoadieDaemon

/// Tests dédiés à la Spec 157 :
/// - US1 : rangée d'icônes d'applications côte à côte sur les cartes du rail (`fx.rail.show_app_icons_row`),
/// - US2 : accès à « Égaliser les proportions » dans le lanceur et le rail,
/// - US3 : échange de deux écrans en une touche (`display swap`),
/// - US4 : nettoyage en un clic des stages vides non nommées (`stage prune-empty`),
/// - US5 : maintien flottant automatique des fenêtres Picture-in-Picture (`tiling.float_picture_in_picture`).
struct Spec157ErgonomieTests {
    // MARK: - US1 : Icônes d'applications dans le NavRail

    @Test
    @MainActor
    func distinctAppBundleIDsDeduplicatesPreservingOrderAndCountsOverflow() {
        let members = [
            PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "com.apple.Safari", title: "S1", frame: Rect(x: 0, y: 0, width: 600, height: 400)),
            PersistentStageMember(windowID: WindowID(rawValue: 2), bundleID: "com.apple.Safari", title: "S2", frame: Rect(x: 0, y: 0, width: 600, height: 400)),
            PersistentStageMember(windowID: WindowID(rawValue: 3), bundleID: "com.googlecode.iterm2", title: "Term", frame: Rect(x: 0, y: 0, width: 600, height: 400)),
            PersistentStageMember(windowID: WindowID(rawValue: 4), bundleID: "com.microsoft.VSCode", title: "Code", frame: Rect(x: 0, y: 0, width: 600, height: 400)),
            PersistentStageMember(windowID: WindowID(rawValue: 5), bundleID: "com.tinyspeck.slackmacgap", title: "Slack", frame: Rect(x: 0, y: 0, width: 600, height: 400)),
        ]
        let all = StageCardView.distinctAppBundleIDs(for: members, maxCount: 6)
        #expect(all.bundleIDs == ["com.apple.Safari", "com.googlecode.iterm2", "com.microsoft.VSCode", "com.tinyspeck.slackmacgap"])
        #expect(all.overflow == 0)

        let capped = StageCardView.distinctAppBundleIDs(for: members, maxCount: 2)
        #expect(capped.bundleIDs == ["com.apple.Safari", "com.googlecode.iterm2"])
        #expect(capped.overflow == 2)
    }

    @Test
    @MainActor
    func appIconsRowRespectsSettingModeAndPreservesCardGeometry() {
        let members = [
            PersistentStageMember(windowID: WindowID(rawValue: 10), bundleID: "com.apple.Safari", title: "Safari", frame: Rect(x: 0, y: 0, width: 800, height: 600)),
            PersistentStageMember(windowID: WindowID(rawValue: 11), bundleID: "com.googlecode.iterm2", title: "iTerm2", frame: Rect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let stage = PersistentStage(id: StageID(rawValue: "1"), name: "1", focusedWindowID: WindowID(rawValue: 10), members: members)

        var enabledConfig = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        enabledConfig.showAppIconsRow = true
        let cardOn = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: true,
            accent: .systemGreen,
            config: enabledConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 1
        )

        var disabledConfig = enabledConfig
        disabledConfig.showAppIconsRow = false
        let cardOff = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: true,
            accent: .systemGreen,
            config: disabledConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 1
        )

        #expect(cardOn.bounds.height == cardOff.bounds.height)
        #expect(cardOn.stageLabelLayout().rect == cardOff.stageLabelLayout().rect)

        let layout = cardOn.appIconsRowLayout()
        #expect(layout != nil)
        #expect(layout?.bundleIDs == ["com.apple.Safari", "com.googlecode.iterm2"])
        #expect(layout?.iconRects.count == 2)
        if let layout, let first = layout.iconRects.first, let second = layout.iconRects.last {
            #expect(second.minX > first.maxX)
        }
        #expect(cardOff.appIconsRowLayout() == nil)

        var iconsModeConfig = enabledConfig
        iconsModeConfig.mode = .icons
        let cardIconsOnly = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: true,
            accent: .systemGreen,
            config: iconsModeConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 1
        )
        #expect(cardIconsOnly.appIconsRowLayout() == nil)

        let emptyStage = PersistentStage(id: StageID(rawValue: "2"), name: "2", members: [])
        let emptyCard = StageCardView(
            stage: emptyStage,
            displayLabel: "2",
            isActive: false,
            accent: .systemGreen,
            config: enabledConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 2
        )
        #expect(emptyCard.appIconsRowLayout() == nil)
    }

    @Test
    func railSettingsParsesShowAppIconsRowWithDefaultTrue() {
        #expect(RailSettings.load(raw: "").showAppIconsRow == true)
        #expect(RailSettings.load(raw: "[fx.rail]\nshow_app_icons_row = false\n").showAppIconsRow == false)
        #expect(RailSettings.load(raw: "[fx.rail]\nshow_app_icons_row = true\n").showAppIconsRow == true)
    }

    // MARK: - US2, US3, US4 : Commandes Lanceur

    @Test
    func launcherIncludesBalanceSwapAndPruneEmptyCommands() {
        let commands = LauncherSystemCommand.all()
        let ids = Set(commands.map(\.id))
        #expect(ids.contains("roadie-balance"))
        #expect(ids.contains("roadie-display-swap"))
        #expect(ids.contains("roadie-prune-empty"))

        #expect(LauncherSystemCommand.matches("balance", in: commands, limit: 5).contains { $0.id == "roadie-balance" })
        #expect(LauncherSystemCommand.matches("egaliser", in: commands, limit: 5).contains { $0.id == "roadie-balance" })
        #expect(LauncherSystemCommand.matches("swap", in: commands, limit: 5).contains { $0.id == "roadie-display-swap" })
        #expect(LauncherSystemCommand.matches("echanger", in: commands, limit: 5).contains { $0.id == "roadie-display-swap" })
        #expect(LauncherSystemCommand.matches("prune", in: commands, limit: 5).contains { $0.id == "roadie-prune-empty" })
        #expect(LauncherSystemCommand.matches("nettoyer", in: commands, limit: 5).contains { $0.id == "roadie-prune-empty" })
    }

    // MARK: - US3 : Échange de deux écrans

    @Test
    func displaySwapExchangesActiveStagesBetweenTwoDisplays() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main 4K", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let snapB = DisplaySnapshot(id: displayB, index: 2, name: "Side 4K", frame: Rect(x: 1920, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1920, y: 25, width: 1920, height: 1055), isMain: false)
        let winA = WindowSnapshot(id: WindowID(rawValue: 101), pid: 10, appName: "Code", bundleID: "com.microsoft.VSCode", title: "Code", frame: Rect(x: 20, y: 40, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        let winB = WindowSnapshot(id: WindowID(rawValue: 202), pid: 20, appName: "Safari", bundleID: "com.apple.Safari", title: "Docs", frame: Rect(x: 1940, y: 40, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-swap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let intentStore = LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Code", mode: .spatialBsp, focusedWindowID: winA.id, members: [
                        PersistentStageMember(windowID: winA.id, bundleID: winA.bundleID, title: winA.title, frame: winA.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: displayB, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Web", mode: .masterStack, focusedWindowID: winB.id, members: [
                        PersistentStageMember(windowID: winB.id, bundleID: winB.bundleID, title: winB.title, frame: winB.frame),
                    ]),
                ]),
            ],
            activeDisplayID: displayA
        ))

        let writer = Spec157RecordingWriter()
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA, snapB], windows: [winA, winB], focusedID: winA.id),
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: intentStore,
            stageStore: store,
            events: events
        )
        let result = DisplayCommandService(service: service, store: store, events: events).swapDefault()
        #expect(result.changed)

        var state = store.state()
        let scopeA = state.scope(displayID: displayA, desktopID: DesktopID(rawValue: 1))
        let scopeB = state.scope(displayID: displayB, desktopID: DesktopID(rawValue: 1))
        let activeA = scopeA.stages.first { $0.id == scopeA.activeStageID }
        let activeB = scopeB.stages.first { $0.id == scopeB.activeStageID }

        #expect(activeA?.name == "Web")
        #expect(activeA?.mode == .masterStack)
        #expect(activeA?.members.map(\.windowID) == [winB.id])
        #expect(activeB?.name == "Code")
        #expect(activeB?.mode == .spatialBsp)
        #expect(activeB?.members.map(\.windowID) == [winA.id])
        #expect(state.activeDisplayID == displayA)
        #expect(writer.focusedWindowIDs == [winB.id])
    }

    @Test
    func displaySwapIsNoOpWithSingleDisplay() {
        let displayA = DisplayID(rawValue: "solo")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Solo", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-solo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [], focusedID: nil),
            frameWriter: Spec157RecordingWriter(),
            config: RoadieConfig(),
            stageStore: store
        )
        let result = DisplayCommandService(service: service, store: store).swapDefault()
        #expect(!result.changed)
        #expect(result.outcome == .noOp)
    }

    // MARK: - US4 : Nettoyage en un clic des stages vides

    @Test
    @MainActor
    func stagePruneEmptyRemovesOnlyInactiveUnparkedUnnamedEmptyStages() {
        let displayA = DisplayID(rawValue: "display-prune")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let win = WindowSnapshot(id: WindowID(rawValue: 501), pid: 50, appName: "Term", bundleID: "com.googlecode.iterm2", title: "zsh", frame: Rect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true, isTileCandidate: true)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-prune-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let activeEmpty = PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [])
        let unnamedEmpty2 = PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2", members: [])
        let namedEmpty3 = PersistentStage(id: StageID(rawValue: "3"), name: "Comms", members: [])
        let occupied4 = PersistentStage(id: StageID(rawValue: "4"), name: "Stage 4", members: [
            PersistentStageMember(windowID: win.id, bundleID: win.bundleID, title: win.title, frame: win.frame),
        ])
        var parkedEmpty5 = PersistentStage(id: StageID(rawValue: "5"), name: "Stage 5", members: [])
        parkedEmpty5.parkingState = .parked
        let unnamedEmpty6 = PersistentStage(id: StageID(rawValue: "6"), name: "", members: [])

        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: displayA,
                    activeStageID: StageID(rawValue: "1"),
                    stages: [activeEmpty, unnamedEmpty2, namedEmpty3, occupied4, parkedEmpty5, unnamedEmpty6]
                ),
            ],
            activeDisplayID: displayA
        ))

        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [win], focusedID: nil),
            frameWriter: Spec157RecordingWriter(),
            config: RoadieConfig(),
            stageStore: store,
            events: events
        )
        let live = service.railWindowIDs(in: service.snapshot())
        #expect(RailController.prunableEmptyStageCount(displayID: displayA, store: store, liveWindowIDs: live) == 2)

        let result = StageCommandService(service: service, store: store, events: events).pruneEmpty(displayID: displayA)
        #expect(result.changed)
        #expect(result.message.contains("removed=2"))

        var state = store.state()
        let remaining = state.scope(displayID: displayA, desktopID: DesktopID(rawValue: 1)).stages.map(\.id.rawValue)
        #expect(remaining == ["1", "3", "4", "5"])

        let secondPass = StageCommandService(service: service, store: store, events: events).pruneEmpty(displayID: displayA)
        #expect(!secondPass.changed)
        #expect(secondPass.outcome == .noOp)
    }

    // MARK: - US5 : Auto-float Picture-in-Picture

    @Test
    func pictureInPictureConfigDefaultsToTrueAndLoadsOverride() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(RoadieConfig().tiling.floatPictureInPicture == true)

        let disabledURL = dir.appendingPathComponent("disabled.toml")
        try "[tiling]\nfloat_picture_in_picture = false\n".write(to: disabledURL, atomically: true, encoding: .utf8)
        let loaded = try RoadieConfigLoader.load(from: disabledURL.path)
        #expect(loaded.tiling.floatPictureInPicture == false)
    }

    @Test
    func pictureInPictureDetectionAndTilingDecisionRespectToggleAndUserRule() {
        let standardFurniture = WindowFurniture(
            hasCloseButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            hasMinimizeButton: true,
            hasZoomButton: true,
            isMain: true,
            isResizable: true,
            isNativeFullscreen: false
        )
        let pipAgent = WindowSnapshot(
            id: WindowID(rawValue: 1), pid: 1, appName: "PIPAgent", bundleID: "com.apple.PIPAgent",
            title: "", frame: Rect(x: 100, y: 100, width: 480, height: 270),
            isOnScreen: true, isTileCandidate: true, subrole: "AXStandardWindow", role: "AXWindow", furniture: standardFurniture
        )
        let firefoxPipFR = WindowSnapshot(
            id: WindowID(rawValue: 2), pid: 2, appName: "Firefox", bundleID: "org.mozilla.firefox",
            title: "Incrustation vidéo", frame: Rect(x: 100, y: 100, width: 480, height: 270),
            isOnScreen: true, isTileCandidate: true, subrole: "AXStandardWindow", role: "AXWindow", furniture: standardFurniture
        )
        let chromePipEN = WindowSnapshot(
            id: WindowID(rawValue: 3), pid: 3, appName: "Google Chrome", bundleID: "com.google.Chrome",
            title: "Picture-in-Picture", frame: Rect(x: 100, y: 100, width: 480, height: 270),
            isOnScreen: true, isTileCandidate: true, subrole: "AXStandardWindow", role: "AXWindow", furniture: standardFurniture
        )
        let normalBrowser = WindowSnapshot(
            id: WindowID(rawValue: 4), pid: 3, appName: "Google Chrome", bundleID: "com.google.Chrome",
            title: "YouTube — Picture-in-Picture tutorial", frame: Rect(x: 0, y: 0, width: 1200, height: 800),
            isOnScreen: true, isTileCandidate: true, subrole: "AXStandardWindow", role: "AXWindow", furniture: standardFurniture
        )
        var fullscreenFurniture = standardFurniture
        fullscreenFurniture.isNativeFullscreen = true
        let nativeFullscreen = WindowSnapshot(
            id: WindowID(rawValue: 5), pid: 3, appName: "Firefox", bundleID: "org.mozilla.firefox",
            title: "Picture-in-Picture", frame: Rect(x: 0, y: 0, width: 1920, height: 1080),
            isOnScreen: true, isTileCandidate: true, subrole: "AXStandardWindow", role: "AXWindow", furniture: fullscreenFurniture
        )

        #expect(SnapshotService.isPictureInPictureWindow(pipAgent))
        #expect(SnapshotService.isPictureInPictureWindow(firefoxPipFR))
        #expect(SnapshotService.isPictureInPictureWindow(chromePipEN))
        #expect(!SnapshotService.isPictureInPictureWindow(normalBrowser))
        #expect(!SnapshotService.isPictureInPictureWindow(nativeFullscreen))

        let defaultConfig = RoadieConfig()
        let defaultContext = SnapshotService.TilingPolicyContext(config: defaultConfig)
        #expect(!SnapshotService.tilingDecision(for: pipAgent, config: defaultConfig, context: defaultContext).tile)
        #expect(!SnapshotService.tilingDecision(for: firefoxPipFR, config: defaultConfig, context: defaultContext).tile)
        #expect(!SnapshotService.tilingDecision(for: chromePipEN, config: defaultConfig, context: defaultContext).tile)
        #expect(SnapshotService.tilingDecision(for: normalBrowser, config: defaultConfig, context: defaultContext).tile)

        var disabledConfig = RoadieConfig()
        disabledConfig.tiling.floatPictureInPicture = false
        let disabledContext = SnapshotService.TilingPolicyContext(config: disabledConfig)
        #expect(SnapshotService.tilingDecision(for: chromePipEN, config: disabledConfig, context: disabledContext).tile)

        var overrideConfig = RoadieConfig()
        overrideConfig.rules = [
            WindowRule(
                id: "force-pip",
                match: RuleMatch(app: "Google Chrome", titleRegex: "^Picture-in-Picture$"),
                action: RuleAction(manage: true)
            ),
        ]
        let overrideContext = SnapshotService.TilingPolicyContext(config: overrideConfig)
        #expect(SnapshotService.tilingDecision(for: chromePipEN, config: overrideConfig, context: overrideContext).tile)
    }
}

private struct Spec157FakeProvider: SystemSnapshotProviding {
    let displaySnapshots: [DisplaySnapshot]
    let windowSnapshots: [WindowSnapshot]
    let focusedID: WindowID?

    init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focusedID: WindowID?) {
        self.displaySnapshots = displays
        self.windowSnapshots = windows
        self.focusedID = focusedID
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { focusedID }
}

private final class Spec157RecordingWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var focusedWindowIDs: [WindowID] = []

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
    func focus(_ window: WindowSnapshot) -> Bool {
        focusedWindowIDs.append(window.id)
        return true
    }
}
