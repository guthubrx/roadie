import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

private func writeToml(_ name: String, _ content: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("roadie-lotj-\(name)-\(UUID().uuidString).toml")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

/// REL-011 et MIN-003 : validation de la configuration.
@Suite
struct Audit022LotJConfigTests {
    @Test(arguments: [
        "true", "false", "'30'", "\"30\"", "[1, 2]", "{ a = 1 }"
    ])
    func wrongTypeForNumericKeyFailsValidateAndLoad(value: String) throws {
        let path = try writeToml("badtype", "[tiling]\ngaps_inner = \(value)\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = RoadieConfigLoader.validate(path: path)

        #expect(report.hasErrors, "validate doit refuser gaps_inner = \(value)")
        #expect(report.items.contains { $0.level == .error && $0.message.contains("gaps_inner") })
        #expect(throws: (any Error).self) { try RoadieConfigLoader.load(from: path) }
    }

    @Test
    func wrongTypeIsRejectedForOtherFlexibleKeys() throws {
        for (table, key) in [("fx.borders", "thickness"), ("width_adjustment", "nudge_step"), ("tiling", "master_ratio")] {
            let path = try writeToml("other", "[\(table)]\n\(key) = true\n")
            defer { try? FileManager.default.removeItem(atPath: path) }
            #expect(RoadieConfigLoader.validate(path: path).hasErrors, "\(table).\(key)")
            #expect(throws: (any Error).self) { try RoadieConfigLoader.load(from: path) }
        }
    }

    @Test
    func absentKeyKeepsDefaultAndIntegerOrDecimalAreAccepted() throws {
        let absent = try writeToml("absent", "[tiling]\nsplit_policy = \"largest_dim\"\n")
        let integer = try writeToml("int", "[tiling]\ngaps_inner = 7\n")
        let decimal = try writeToml("dec", "[tiling]\ngaps_inner = 7.5\nmaster_ratio = 1\n")
        defer { for path in [absent, integer, decimal] { try? FileManager.default.removeItem(atPath: path) } }

        for path in [absent, integer, decimal] {
            #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        }
        #expect(try RoadieConfigLoader.load(from: absent).tiling.gapsInner == 4)
        #expect(try RoadieConfigLoader.load(from: integer).tiling.gapsInner == 7)
        let loaded = try RoadieConfigLoader.load(from: decimal)
        #expect(loaded.tiling.gapsInner == 7.5)
        #expect(loaded.tiling.masterRatio == 1)
    }

    @Test
    func wrongTypeMessageNamesKeyAndTypes() throws {
        let path = try writeToml("message", "[tiling]\ngaps_inner = true\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let message = RoadieConfigLoader.validate(path: path).items.first?.message ?? ""

        #expect(message.contains("tiling.gaps_inner"))
        #expect(message.contains("attendu"))
        #expect(message.contains("booléen"))
    }

    @Test
    func repositoryExampleStaysValid() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/roadies.toml").path
        guard FileManager.default.fileExists(atPath: path) else { return }

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        _ = try RoadieConfigLoader.load(from: path)
    }

    /// MIN-003 : les bornes sont corrigées au décodage ; le rapport de validation ne change pas.
    @Test
    func outOfRangeBoundsAreClampedWithoutValidationError() throws {
        let path = try writeToml("clamp", """
        [experimental.app_targets]
        max_depth = 99

        [experimental.target_grid]
        rows = 1
        columns = 99
        max_depth = 99
        hint_characters = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try RoadieConfigLoader.load(from: path)

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        #expect(config.experimental.appTargets.maxDepth == 40)
        #expect(config.experimental.targetGrid.rows == 2)
        #expect(config.experimental.targetGrid.columns == 12)
        #expect(config.experimental.targetGrid.maxDepth == 20)
    }
}

/// REL-028 : une fenêtre absente du snapshot ne fait perdre son signet que si son processus est mort.
@Suite
struct Audit022LotJBookmarkTests {
    private let display = DisplayID(rawValue: "display-main")

    private func makeStore(pid: Int32?, name: String) -> (StageStore, StageScope) {
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath(name))
        let members = pid.map {
            [PersistentStageMember(
                windowID: WindowID(rawValue: 99), bundleID: "app.gone", title: "Gone",
                frame: Rect(x: 0, y: 0, width: 100, height: 100), pid: $0
            )]
        } ?? []
        store.save(PersistentStageState(
            scopes: [PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: members)
            ])],
            windowBookmarks: [PersistentWindowBookmark(
                name: "work", windowID: WindowID(rawValue: 99), scope: scope, bundleID: "app.gone",
                title: "Gone", frame: Rect(x: 0, y: 0, width: 100, height: 100)
            )]
        ))
        return (store, scope)
    }

    private func service(store: StageStore, provider: PowerUserProvider, alive: @escaping (Int32) -> Bool) -> WindowBookmarkCommandService {
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        return WindowBookmarkCommandService(
            service: snapshots, store: store,
            events: EventLog(path: tempPath("lotj-events")),
            isProcessAlive: alive
        )
    }

    @Test
    func absentWindowWithLiveProcessKeepsBookmark() {
        let (store, _) = makeStore(pid: 4242, name: "lotj-bookmark-alive")
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])

        let result = service(store: store, provider: provider, alive: { _ in true }).focus("work")

        #expect(!result.changed)
        #expect(store.state().bookmark(named: "work") != nil)
    }

    @Test
    func absentWindowWithoutKnownPidKeepsBookmark() {
        let (store, _) = makeStore(pid: nil, name: "lotj-bookmark-nopid")
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])

        let result = service(store: store, provider: provider, alive: { _ in false }).focus("work")

        #expect(!result.changed)
        #expect(store.state().bookmark(named: "work") != nil)
    }

    @Test
    func absentWindowWithDeadProcessRemovesBookmark() {
        let (store, _) = makeStore(pid: 4242, name: "lotj-bookmark-dead")
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])

        let result = service(store: store, provider: provider, alive: { _ in false }).focus("work")

        #expect(result.changed)
        #expect(store.state().bookmark(named: "work") == nil)
    }

    @Test
    func bookmarkSurvivesTemporaryAbsenceAndFocusesOnReturn() {
        let (store, _) = makeStore(pid: 4242, name: "lotj-bookmark-return")
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let bookmarks = service(store: store, provider: provider, alive: { _ in true })

        _ = bookmarks.focus("work")
        provider.snapshots.append(powerWindow(99, x: 500))
        let back = bookmarks.focus("work")

        #expect(back.changed)
        #expect(store.state().bookmark(named: "work") != nil)
    }
}

/// REL-029 : réécrire le fichier des règles générées conserve toutes les actions des autres règles.
@Suite
struct Audit022LotJAffinityTests {
    private let manualRule = """
    [[rules]]
    id = "manual-rule"
    enabled = false
    priority = 12
    stop_processing = true

    [rules.match]
    app = "App A"
    is_floating = true

    [rules.action]
    manage = false
    exclude = true
    assign_desktop = "2"
    assign_display = "Studio"
    assign_stage = "web"
    follow = true
    floating = true
    layout = "bsp"
    gap_override = 6
    scratchpad = "term"
    emit_event = true

    """

    private func window(_ id: UInt32, app: String) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id), pid: Int32(id), appName: app, bundleID: "app.\(app)", title: "T",
            frame: Rect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true
        )
    }

    @Test
    func saveAndRemoveAffinityKeepEveryActionOfOtherRules() throws {
        let path = try writeToml("affinity", manualRule)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let before = try #require(RoadieConfigLoader.loadRulesFile(from: path).first)
        let scope = StageScope(displayID: DisplayID(rawValue: "d"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let display = powerDisplay("d")
        let service = WindowRuleAffinityService(path: path, eventLog: EventLog(path: tempPath("lotj-affinity-events")))

        let saved = service.saveAffinity(kind: .app, window: window(2, app: "App B"), scope: scope, display: display)
        let afterSave = try RoadieConfigLoader.loadRulesFile(from: path)
        let removed = service.removeAppAffinity(window: window(2, app: "App B"), scope: scope)
        let afterRemove = try RoadieConfigLoader.loadRulesFile(from: path)

        #expect(saved.changed)
        #expect(afterSave.count == 2)
        #expect(afterSave.first { $0.id == "manual-rule" } == before)
        #expect(removed.changed)
        #expect(afterRemove == [before])
    }
}
