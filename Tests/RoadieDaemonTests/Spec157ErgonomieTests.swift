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
    func appIconsRowSitsBelowPreviewFollowsPerspectiveAndRoutesClickToAppWindow() throws {
        let members = [
            PersistentStageMember(windowID: WindowID(rawValue: 10), bundleID: "com.apple.Safari", title: "Safari", frame: Rect(x: 0, y: 0, width: 800, height: 600)),
            PersistentStageMember(windowID: WindowID(rawValue: 11), bundleID: "com.googlecode.iterm2", title: "iTerm2", frame: Rect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let stage = PersistentStage(id: StageID(rawValue: "1"), name: "1", focusedWindowID: WindowID(rawValue: 10), members: members)

        var stackedConfig = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        stackedConfig.mode = .stacked
        stackedConfig.showAppIconsRow = true
        let cardOn = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: true,
            accent: .systemGreen,
            config: stackedConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 1
        )

        var disabledConfig = stackedConfig
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

        let stackedLayout = try #require(cardOn.appIconsRowLayout())
        let stackedFront = try #require(cardOn.previewDisplayFrames().first)
        #expect(stackedLayout.bundleIDs == ["com.apple.Safari", "com.googlecode.iterm2"])
        #expect(stackedLayout.iconRects.count == 2)
        #expect(stackedLayout.transform.isIdentity)
        // La rangée est bien placée EN DESSOUS de la vignette.
        #expect(stackedLayout.rowRect.maxY < stackedFront.minY)
        if let first = stackedLayout.iconRects.first, let second = stackedLayout.iconRects.last {
            #expect(second.minX > first.maxX)
            let clickSecond = CGPoint(x: second.midX, y: second.midY)
            #expect(cardOn.dragPayload(at: clickSecond) == nil)
            if case .focusStageWindow(let sID, let wID, let bID) = cardOn.action(at: clickSecond) {
                #expect(sID == StageID(rawValue: "1"))
                #expect(wID == WindowID(rawValue: 11))
                #expect(bID == "com.googlecode.iterm2")
            } else {
                Issue.record("Le clic sur la 2e icône doit cibler focusStageWindow pour iTerm2")
            }
        }
        #expect(cardOff.appIconsRowLayout() == nil)

        // En mode parallax : la rangée suit la perspective et reste cliquable après projection.
        var parallaxConfig = stackedConfig
        parallaxConfig.mode = .parallax
        parallaxConfig.parallaxRotation = 35
        let parallaxCard = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: true,
            accent: .systemGreen,
            config: parallaxConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 1
        )
        let parallaxLayout = try #require(parallaxCard.appIconsRowLayout())
        #expect(!parallaxLayout.transform.isIdentity)
        #expect(parallaxLayout.transform == StageCardView.parallaxTransform(for: parallaxLayout.rowRect, rotation: 35))
        let secondLocal = try #require(parallaxLayout.items.last?.rect)
        let projectedClick = CGPoint(x: secondLocal.midX, y: secondLocal.midY).applying(parallaxLayout.transform)
        #expect(parallaxCard.dragPayload(at: projectedClick) == nil)
        if case .focusStageWindow(let sID, let wID, let bID) = parallaxCard.action(at: projectedClick) {
            #expect(sID == StageID(rawValue: "1"))
            #expect(wID == WindowID(rawValue: 11))
            #expect(bID == "com.googlecode.iterm2")
        } else {
            Issue.record("Le clic projeté en mode parallax doit cibler focusStageWindow pour iTerm2")
        }

        var iconsModeConfig = stackedConfig
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
            config: stackedConfig,
            presentationStates: [:],
            thumbnails: [:],
            position: 2
        )
        #expect(emptyCard.appIconsRowLayout() == nil)
    }

    @Test
    func switchAndFocusActivatesStageExitsOtherWindowZoomAndFocusesClickedApp() {
        let displayA = DisplayID(rawValue: "display-focus-app")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let win1 = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "Safari", bundleID: "com.apple.Safari", title: "Docs", frame: Rect(x: 0, y: 25, width: 1920, height: 1055), isOnScreen: true, isTileCandidate: true)
        let win2 = WindowSnapshot(id: WindowID(rawValue: 20), pid: 20, appName: "iTerm2", bundleID: "com.googlecode.iterm2", title: "zsh", frame: Rect(x: 20, y: 40, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        let win3 = WindowSnapshot(id: WindowID(rawValue: 30), pid: 30, appName: "Firefox", bundleID: "org.mozilla.firefox", title: "Web", frame: Rect(x: 20, y: 40, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-switch-focus-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let intentStore = LayoutIntentStore(path: dir.appendingPathComponent("intents.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", focusedWindowID: win1.id, members: [
                        PersistentStageMember(windowID: win1.id, bundleID: win1.bundleID, title: win1.title, frame: win1.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2", focusedWindowID: win2.id, members: [
                        PersistentStageMember(windowID: win2.id, bundleID: win2.bundleID, title: win2.title, frame: win2.frame),
                        PersistentStageMember(windowID: win3.id, bundleID: win3.bundleID, title: win3.title, frame: win3.frame),
                    ]),
                ]),
            ],
            activeDisplayID: displayA
        ))

        let stage2Scope = StageScope(displayID: displayA, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        intentStore.save(LayoutIntent(
            scope: stage2Scope,
            windowIDs: [win2.id, win3.id],
            placements: [win2.id: snapA.visibleFrame],
            source: .command,
            zoomedWindowID: win2.id
        ))

        let writer = Spec157RecordingWriter()
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [win1, win2, win3], focusedID: win1.id),
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: intentStore,
            stageStore: store,
            events: events
        )
        let stageService = StageCommandService(service: service, store: store, events: events)

        // 1. Bascule depuis stage 1 vers stage 2 en cliquant sur Firefox (win3) alors qu'iTerm2 (win2) était zoomé.
        let switchResult = stageService.switchAndFocus(StageID(rawValue: "2"), windowID: win3.id, bundleID: win3.bundleID, displayID: displayA)
        #expect(switchResult.changed)
        #expect(intentStore.intent(for: stage2Scope) == nil)
        #expect(writer.focusedWindowIDs.last == win3.id)

        // 2. Stage 2 déjà active : clic sur iTerm2 (win2) donne directement le focus à win2.
        let sameStageResult = stageService.switchAndFocus(StageID(rawValue: "2"), windowID: win2.id, bundleID: win2.bundleID, displayID: displayA)
        #expect(sameStageResult.changed)
        #expect(writer.focusedWindowIDs.last == win2.id)
    }

    @Test
    func switchAndFocusRecallsRequestedMissingAppInsteadOfFocusingAnotherMember() {
        let displayA = DisplayID(rawValue: "display-missing-app")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let win1 = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "Safari", bundleID: "com.apple.Safari", title: "Docs", frame: Rect(x: 0, y: 25, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        let win2 = WindowSnapshot(id: WindowID(rawValue: 20), pid: 20, appName: "iTerm2", bundleID: "com.googlecode.iterm2", title: "zsh", frame: Rect(x: 20, y: 40, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        // win3 (Firefox) est membre de la stage 2 mais absent du relevé live (minimisé / autre Space).
        let missingWin3ID = WindowID(rawValue: 30)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-missing-app-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", focusedWindowID: win1.id, members: [
                        PersistentStageMember(windowID: win1.id, bundleID: win1.bundleID, title: win1.title, frame: win1.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2", focusedWindowID: win2.id, members: [
                        PersistentStageMember(windowID: win2.id, bundleID: win2.bundleID, title: win2.title, frame: win2.frame),
                        PersistentStageMember(windowID: missingWin3ID, bundleID: "org.mozilla.firefox", title: "Web", frame: Rect(x: 20, y: 40, width: 900, height: 900)),
                    ]),
                ]),
            ],
            activeDisplayID: displayA
        ))

        let writer = Spec157RecordingWriter(recallSucceedingWindowIDs: [win2.id])
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [win1, win2], focusedID: win1.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: store,
            events: events
        )
        let stageService = StageCommandService(service: service, store: store, events: events)
        let result = stageService.switchAndFocus(StageID(rawValue: "2"), windowID: missingWin3ID, bundleID: "org.mozilla.firefox", displayID: displayA)
        #expect(result.changed)
        // Ne doit PAS avoir basculé le focus ni tenté le rappel sur win2 (iTerm2) :
        // seule la cible explicite (Firefox) est tentée puis activée en repli.
        #expect(!writer.focusedWindowIDs.contains(win2.id))
        #expect(writer.recalledWindowIDs == [missingWin3ID])
        #expect(writer.activatedBundleIDs == ["org.mozilla.firefox"])
    }

    @Test
    func switchAndFocusDoesNotDivertToNativeFullscreenSiblingWhenAllTargetMembersAreMissing() {
        let displayA = DisplayID(rawValue: "display-missing-fs")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let win1 = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "Code", bundleID: "com.microsoft.VSCode", title: "Code", frame: Rect(x: 0, y: 25, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        let safariFSID = WindowID(rawValue: 20)
        let firefoxID = WindowID(rawValue: 30)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-missing-fs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        var safariMember = PersistentStageMember(windowID: safariFSID, bundleID: "com.apple.Safari", title: "Safari", frame: snapA.frame)
        safariMember.presentationState = .nativeFullscreen
        let firefoxMember = PersistentStageMember(windowID: firefoxID, bundleID: "org.mozilla.firefox", title: "Firefox", frame: Rect(x: 20, y: 40, width: 900, height: 900))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", focusedWindowID: win1.id, members: [
                        PersistentStageMember(windowID: win1.id, bundleID: win1.bundleID, title: win1.title, frame: win1.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), name: "Stage 2", focusedWindowID: safariFSID, members: [
                        safariMember,
                        firefoxMember,
                    ]),
                ]),
            ],
            activeDisplayID: displayA
        ))

        let writer = Spec157RecordingWriter()
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [win1], focusedID: win1.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: store,
            events: events
        )
        let result = StageCommandService(service: service, store: store, events: events)
            .switchAndFocus(StageID(rawValue: "2"), windowID: firefoxID, bundleID: "org.mozilla.firefox", displayID: displayA)
        #expect(result.changed)
        #expect(writer.recalledWindowIDs == [firefoxID])
        #expect(writer.activatedBundleIDs == ["org.mozilla.firefox"])
        #expect(!writer.activatedBundleIDs.contains("com.apple.Safari"))
    }

    @Test
    func switchAndFocusOnAlreadyActiveStageUsesTargetedRecallForMissingWindow() {
        let displayA = DisplayID(rawValue: "display-active-missing")
        let snapA = DisplaySnapshot(id: displayA, index: 1, name: "Main", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
        let win1 = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "iTerm2", bundleID: "com.googlecode.iterm2", title: "zsh", frame: Rect(x: 0, y: 25, width: 900, height: 900), isOnScreen: true, isTileCandidate: true)
        let missingFirefoxID = WindowID(rawValue: 30)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-157-active-missing-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let events = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", focusedWindowID: win1.id, members: [
                        PersistentStageMember(windowID: win1.id, bundleID: win1.bundleID, title: win1.title, frame: win1.frame),
                        PersistentStageMember(windowID: missingFirefoxID, bundleID: "org.mozilla.firefox", title: "Docs", frame: Rect(x: 920, y: 25, width: 900, height: 900)),
                    ]),
                ]),
            ],
            activeDisplayID: displayA
        ))

        let writer = Spec157RecordingWriter(recallSucceedingWindowIDs: [missingFirefoxID])
        let service = SnapshotService(
            provider: Spec157FakeProvider(displays: [snapA], windows: [win1], focusedID: win1.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: store,
            events: events
        )
        let result = StageCommandService(service: service, store: store, events: events)
            .switchAndFocus(StageID(rawValue: "1"), windowID: missingFirefoxID, bundleID: "org.mozilla.firefox", displayID: displayA)
        #expect(result.changed)
        #expect(writer.recalledWindowIDs == [missingFirefoxID])
        #expect(writer.activatedBundleIDs.isEmpty)
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
    private let recallSucceedingWindowIDs: Set<WindowID>
    private(set) var focusedWindowIDs: [WindowID] = []
    private(set) var recalledWindowIDs: [WindowID] = []
    private(set) var activatedBundleIDs: [String] = []

    init(recallSucceedingWindowIDs: Set<WindowID> = []) {
        self.recallSucceedingWindowIDs = recallSucceedingWindowIDs
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
    func focus(_ window: WindowSnapshot) -> Bool {
        focusedWindowIDs.append(window.id)
        return true
    }
    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool {
        recalledWindowIDs.append(windowID)
        return recallSucceedingWindowIDs.contains(windowID)
    }
    func activateApplication(bundleID: String) -> Bool {
        activatedBundleIDs.append(bundleID)
        return true
    }
}
