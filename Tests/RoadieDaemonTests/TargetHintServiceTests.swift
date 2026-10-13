import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct TargetHintServiceTests {
    @Test
    func labelsUseDeterministicHomeRowAlphabet() {
        let labels = TargetHintService.labels(count: 5, alphabet: "ab")

        #expect(labels == ["A", "B", "AA", "AB", "BA"])
    }

    @Test
    func normalizedSearchRemovesCaseDiacriticsAndExtraSpaces() {
        let normalized = TargetHintService.normalized("  Gråy    JÁY  ")

        #expect(normalized == "gray jay")
    }

    @Test
    func roadieTargetsIncludeOnlyVisibleNonEmptyStagesByDefault() {
        let displayID = DisplayID(rawValue: "display-main")
        let desktopID = DesktopID(rawValue: 1)
        let first = powerWindow(1, x: 100, app: "iTerm")
        let second = powerWindow(2, x: 500, app: "Firefox")
        let firstScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: StageID(rawValue: "1"))
        let secondScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: StageID(rawValue: "2"))
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay(displayID.rawValue)],
            windows: [
                ScopedWindowSnapshot(window: first, scope: firstScope),
                ScopedWindowSnapshot(window: second, scope: secondScope),
            ],
            state: roadieState(displayID: displayID, activeStageID: firstScope.stageID, windows: [
                firstScope: [first.id],
                secondScope: [second.id],
            ]),
            focusedWindowID: first.id
        )
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: firstScope.stageID, stages: [
                PersistentStage(id: firstScope.stageID, name: "Work", members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                ]),
                PersistentStage(id: secondScope.stageID, name: "Web", members: [
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "3"), name: "Empty"),
            ]),
        ], activeDisplayID: displayID)

        let report = TargetHintService.report(from: snapshot, state: state, options: TargetQueryOptions())
        let stageIDs = report.targets.filter { $0.kind == .stage }.map(\.id)

        #expect(stageIDs.contains("stage:display-main/1/1"))
        #expect(stageIDs.contains("stage:display-main/1/2"))
        #expect(!stageIDs.contains("stage:display-main/1/3"))
        #expect(report.targets.first?.label == "A")
    }

    @Test
    func resolveAcceptsLabelIdAndUniqueSearch() throws {
        let targets = [
            RoadieTarget(id: "stage:main/1/1", label: "A", kind: .stage, title: "Work", source: .roadie, actions: [.switch]),
            RoadieTarget(id: "window:42", label: "S", kind: .window, title: "Grayjay", source: .roadie, actions: [.focus]),
        ]

        #expect(try TargetHintService.resolve("S", in: targets).id == "window:42")
        #expect(try TargetHintService.resolve("stage:main/1/1", in: targets).label == "A")
        #expect(try TargetHintService.resolve("gray", in: targets).id == "window:42")
    }

    @Test
    func sourceAllDoesNotErrorWhenExperimentalAppTargetsAreDisabled() {
        let displayID = DisplayID(rawValue: "display-main")
        let stageID = StageID(rawValue: "1")
        let window = powerWindow(1, x: 100, app: "iTerm")
        let store = StageStore(path: tempPath("target-source-all"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let provider = PowerUserProvider(displays: [powerDisplay(displayID.rawValue)], windows: [window])
        let service = SnapshotService(provider: provider, stageStore: store)
        let targets = TargetHintService(
            service: service,
            stageStore: store,
            appTargetService: AppTargetQueryService(provider: EmptyAppTargetProvider()),
            appTargetsConfig: AppTargetsConfig(enabled: false)
        )

        let report = targets.list(TargetQueryOptions(source: .all))

        #expect(report.error == nil)
        #expect(report.targets.contains { $0.source == .roadie })
    }

    @Test
    func disabledTargetModeReturnsStructuredError() {
        let targets = TargetHintService(
            appTargetService: AppTargetQueryService(provider: EmptyAppTargetProvider()),
            targetModeConfig: TargetModeConfig(enabled: false)
        )

        let report = targets.list(TargetQueryOptions(source: .all))
        let pick = targets.pick("anything")
        let activate = targets.activate("anything")

        #expect(report.error == "target_mode_disabled")
        #expect(report.targets.isEmpty)
        #expect(pick.error == "target_mode_disabled")
        #expect(activate.error == "target_mode_disabled")
    }

    @Test
    func disabledPickerRefusesMutation() {
        let targets = TargetHintService(
            appTargetService: AppTargetQueryService(provider: EmptyAppTargetProvider()),
            targetModeConfig: TargetModeConfig(pickerEnabled: false)
        )

        let result = targets.pick("terminal", action: .focus)

        #expect(result.error == "target_picker_disabled")
        #expect(result.result == nil)
        #expect(result.selected == nil)
    }

    @Test
    func appScanStatisticsAreLoggedOnlyWhenTheProviderReportsThem() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let log = EventLog(path: path)
        let stats = AppTargetScanStats(
            bundleID: "com.example.electron", isElectron: true, manualAccessibility: "enabled",
            visited: 412, candidates: 57, offscreen: 18, maxDepthReached: 8, atMaxDepth: 31,
            sawWebArea: true, elapsedMs: 240, stopReason: "complete", retries: 1
        )
        let measured = TargetHintService(
            eventLog: log,
            appTargetService: AppTargetQueryService(provider: ScannedAppTargetProvider(scan: stats)),
            appTargetsConfig: AppTargetsConfig(enabled: true)
        )
        let silent = TargetHintService(
            eventLog: log,
            appTargetService: AppTargetQueryService(provider: ScannedAppTargetProvider(scan: nil)),
            appTargetsConfig: AppTargetsConfig(enabled: true)
        )

        _ = measured.list(TargetQueryOptions(source: .app))
        _ = silent.list(TargetQueryOptions(source: .app))

        let scans = log.tail(limit: 50)
            .compactMap { try? JSONDecoder.roadieTest.decode(RoadieEvent.self, from: Data($0.utf8)) }
            .filter { $0.type == "targets.app_scan" }
        #expect(scans.count == 1)
        #expect(scans.first?.details == stats.eventDetails)
        #expect(scans.first?.details["stopReason"] == "complete")
        #expect(scans.first?.details["retries"] == "1")
    }

    @Test
    func appMouseActionsAreDisabledIndependentlyFromAppTargetDiscovery() {
        let targets = TargetHintService(
            appTargetService: AppTargetQueryService(provider: SingleAppTargetProvider()),
            targetModeConfig: TargetModeConfig(appMouseActionsEnabled: false),
            appTargetsConfig: AppTargetsConfig(enabled: true)
        )

        let result = targets.activate("button", action: .click)

        #expect(result.error == "app_mouse_actions_disabled")
        #expect(result.changed == false)
    }

    @Test
    func appMouseActionsCanBeEnabledExplicitly() {
        let targets = TargetHintService(
            appTargetService: AppTargetQueryService(provider: SingleAppTargetProvider()),
            targetModeConfig: TargetModeConfig(appMouseActionsEnabled: true),
            appTargetsConfig: AppTargetsConfig(enabled: true)
        )

        let result = targets.activate("button", action: .click)

        #expect(result.error == nil)
        #expect(result.changed)
    }

    @Test
    func pickerReturnsCandidatesWithoutMutationWhenQueryIsAmbiguous() {
        let displayID = DisplayID(rawValue: "display-main")
        let stageID = StageID(rawValue: "1")
        let first = powerWindow(1, x: 100, app: "Terminal")
        let second = powerWindow(2, x: 500, app: "Terminal")
        let store = StageStore(path: tempPath("target-pick-ambiguous"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let provider = PowerUserProvider(displays: [powerDisplay(displayID.rawValue)], windows: [first, second])
        let service = SnapshotService(provider: provider, stageStore: store)
        let targets = TargetHintService(service: service, stageStore: store)

        let result = targets.pick("terminal", action: .focus)

        #expect(result.error == "ambiguous_target")
        #expect(result.selected == nil)
        #expect(result.result == nil)
        #expect(result.candidates.count == 2)
    }

    @Test
    func overlayStateUsesSameLabelsAsTargetList() {
        let displayID = DisplayID(rawValue: "display-main")
        let stageID = StageID(rawValue: "1")
        let window = powerWindow(1, x: 100, app: "iTerm")
        let store = StageStore(path: tempPath("target-overlay-state"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let provider = PowerUserProvider(displays: [powerDisplay(displayID.rawValue)], windows: [window])
        let service = SnapshotService(provider: provider, stageStore: store)
        let targets = TargetHintService(service: service, stageStore: store)

        let list = targets.list()
        let overlay = targets.overlayState()

        #expect(overlay.visible)
        #expect(overlay.labelsOnly)
        #expect(overlay.report.targets.map(\.label) == list.targets.map(\.label))
    }

    @Test
    func bookmarkTargetsExposeFocusAction() {
        let displayID = DisplayID(rawValue: "display-main")
        let desktopID = DesktopID(rawValue: 1)
        let stageID = StageID(rawValue: "1")
        let scope = StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
        let window = powerWindow(1, x: 100, app: "iTerm")
        let state = PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayID, desktopID: desktopID, activeStageID: stageID, stages: [
                    PersistentStage(id: stageID, members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                ]),
            ],
            windowBookmarks: [
                PersistentWindowBookmark(
                    name: "shell",
                    windowID: window.id,
                    scope: scope,
                    bundleID: window.bundleID,
                    title: window.title,
                    frame: window.frame
                ),
            ],
            activeDisplayID: displayID
        )
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay(displayID.rawValue)],
            windows: [ScopedWindowSnapshot(window: window, scope: scope)],
            state: roadieState(displayID: displayID, activeStageID: stageID, windows: [scope: [window.id]]),
            focusedWindowID: window.id
        )

        let bookmark = TargetHintService.report(from: snapshot, state: state, options: TargetQueryOptions())
            .targets
            .first { $0.kind == .bookmark }

        #expect(bookmark?.id == "bookmark:shell")
        #expect(bookmark?.actions == [.focus, .inspect])
    }
}

private struct EmptyAppTargetProvider: AppTargetProviding {
    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(error: "should_not_be_called")
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        TargetActionResult(changed: false, message: "unused")
    }
}

private struct SingleAppTargetProvider: AppTargetProviding {
    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(targets: [
            RoadieTarget(
                id: "app:test-button",
                label: "A",
                kind: .appElement,
                title: "Button",
                source: .app,
                matchText: "button",
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                actions: [.click, .doubleClick, .rightClick, .inspect]
            )
        ])
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        TargetActionResult(changed: true, message: "clicked \(target.id)", target: target)
    }
}

func roadieState(displayID: DisplayID, activeStageID: StageID, windows: [StageScope: [WindowID]]) -> RoadieState {
    var state = RoadieState()
    state.ensureDisplay(displayID)
    for (scope, ids) in windows {
        try? state.createStage(id: scope.stageID, name: "Stage \(scope.stageID.rawValue)", in: scope.displayID, desktopID: scope.desktopID)
        for id in ids {
            try? state.assignWindow(id, to: scope)
        }
    }
    try? state.switchStage(activeStageID, in: displayID, desktopID: DesktopID(rawValue: 1))
    return state
}

private struct ScannedAppTargetProvider: AppTargetProviding {
    var scan: AppTargetScanStats?

    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(targets: [], scan: scan)
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        TargetActionResult(changed: false, message: "unused", target: target)
    }
}

private extension JSONDecoder {
    static let roadieTest: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
