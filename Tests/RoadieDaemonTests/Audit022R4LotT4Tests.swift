import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 4, lot T4 : identité de fenêtre du clic applicatif (REL-012), bureau des actions
/// de stage (REL-037) et relâchement des appuis d'une macro tronquée (REL-038). Les événements sont
/// capturés par un émetteur espion : rien n'est posté sur le bureau.
@Suite
struct Audit022R4LotT4Tests {
    // MARK: REL-012

    @Test
    func appClickWithoutWindowIdentityPostsNothing() {
        let spy = T4EventSpy()
        let asked = T4EventSpy.Calls()
        let provider = LiveAppTargetProvider(
            waitForFocus: { windowID, _, _ in
                asked.append("\(windowID)")
                return .focused
            },
            postEvent: { spy.record($0) },
            // Cadre inchangé : seule l'identité de fenêtre manque.
            currentFrame: { $0.frame }
        )
        var target = appTarget(windowID: 77)
        target.scope.windowId = nil

        let result = provider.click(target, action: .click)

        #expect(asked.values.isEmpty)
        #expect(spy.events.isEmpty)
        #expect(!result.changed)
        #expect(result.error == "stale_target")
    }

    @Test
    func appClickOnAlreadyFocusedWindowClicksAtOnce() {
        let spy = T4EventSpy()
        let asked = T4EventSpy.Calls()
        let provider = LiveAppTargetProvider(
            waitForFocus: { windowID, pid, _ in
                asked.append("\(windowID)/\(pid)")
                return .focused
            },
            postEvent: { spy.record($0) },
            currentFrame: { $0.frame }
        )

        let result = provider.click(appTarget(windowID: 77), action: .click)

        // Une seule question au faux focus, déjà correct : aucune relance, clic immédiat.
        #expect(asked.values == ["77/4242"])
        #expect(result.changed)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
    }

    @Test
    func targetsCarryTheScannedWindowIdentity() {
        let candidates = [
            AppElementCandidate(id: "4242/0.1", role: "AXButton", title: "OK", frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: ["AXPress"]),
            AppElementCandidate(id: "4242/0.2", role: "AXButton", title: "Annuler", frame: Rect(x: 30, y: 0, width: 20, height: 20), actions: ["AXPress"]),
        ]

        let scoped = AppTargetQueryService.targets(from: candidates, config: AppTargetsConfig(enabled: true), windowID: 77)
        let unscoped = AppTargetQueryService.targets(from: candidates, config: AppTargetsConfig(enabled: true))

        #expect(scoped.count == 2)
        #expect(scoped.allSatisfy { $0.scope.windowId == 77 })
        #expect(unscoped.allSatisfy { $0.scope.windowId == nil })
    }

    @Test
    func clickInAlreadyFocusedWindowAsksNoFocusChange() {
        let fixture = HintFixture(focusedWindow: 77)

        let result = fixture.hints.activate(target: appTarget(windowID: 77), action: .click)

        #expect(result.changed)
        #expect(fixture.writer.focused.isEmpty)
        #expect(fixture.clicks.values == ["app:4242/0.1 click"])
    }

    @Test
    func clickInAnotherWindowFocusesItFirst() {
        let fixture = HintFixture(focusedWindow: 12)

        let result = fixture.hints.activate(target: appTarget(windowID: 77), action: .click)

        #expect(result.changed)
        #expect(fixture.writer.focused == [WindowID(rawValue: 77)])
        #expect(fixture.clicks.values == ["app:4242/0.1 click"])
    }

    // MARK: REL-037

    @Test
    func hiddenStageOfAnotherDesktopOffersOnlyInspection() {
        let fixture = StageFixture()

        let report = fixture.hints.list(TargetQueryOptions(source: .roadie, includeHidden: true))
        let other = report.targets.first { $0.id == "stage:display-main/2/2" }
        let current = report.targets.first { $0.id == "stage:display-main/1/2" }

        #expect(other?.actions == [.inspect])
        #expect(current?.actions == [.switch, .sendActive, .inspect])
    }

    @Test
    func stageActionsRefuseATargetOfAnotherDesktop() {
        let fixture = StageFixture()
        let before = fixture.store.state()
        let target = RoadieTarget(
            id: "stage:display-main/2/2",
            kind: .stage,
            title: "Deux",
            source: .roadie,
            scope: TargetScopeSnapshot(displayId: "display-main", desktopId: 2, stageId: "2"),
            actions: [.switch, .sendActive, .inspect]
        )

        let switched = fixture.hints.activate(target: target, action: .switch)
        let sent = fixture.hints.activate(target: target, action: .sendActive)

        #expect(!switched.changed)
        #expect(switched.error == "target_desktop_not_active")
        #expect(!sent.changed)
        #expect(sent.error == "target_desktop_not_active")
        #expect(fixture.store.state() == before)
    }

    // MARK: REL-038

    @Test
    func replayReleasesAPressLeftOpenByTruncation() {
        let spy = T4EventSpy()
        let macros = macroService(spy: spy)

        _ = macros.replay(events: [
            TargetMacroEvent(t: 0, kind: .mouseDown, point: CGPointCodable(CGPoint(x: 10, y: 20)), button: .right),
            TargetMacroEvent(t: 0, kind: .keyDown, keyCode: 0),
        ])

        #expect(spy.events.map(\.type) == [.rightMouseDown, .keyDown, .keyUp, .rightMouseUp])
        #expect(spy.events.last?.location == CGPoint(x: 10, y: 20))
        #expect(spy.events.dropFirst(2).first?.getIntegerValueField(.keyboardEventKeycode) == 0)
    }

    @Test
    func replayAddsNoReleaseToABalancedSequence() {
        let spy = T4EventSpy()
        let macros = macroService(spy: spy)

        _ = macros.replay(events: [
            TargetMacroEvent(t: 0, kind: .mouseDown, point: CGPointCodable(CGPoint(x: 10, y: 20))),
            TargetMacroEvent(t: 0, kind: .mouseUp, point: CGPointCodable(CGPoint(x: 10, y: 20))),
            TargetMacroEvent(t: 0, kind: .keyDown, keyCode: 4),
            TargetMacroEvent(t: 0, kind: .keyUp, keyCode: 4),
        ])

        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp])
    }
}

private func appTarget(windowID: UInt32) -> RoadieTarget {
    RoadieTarget(
        id: "app:4242/0.1",
        kind: .appElement,
        title: "Bouton",
        source: .app,
        scope: TargetScopeSnapshot(windowId: windowID),
        frame: Rect(x: 100, y: 200, width: 40, height: 40),
        actions: [.click]
    )
}

private func macroService(spy: T4EventSpy) -> TargetMacroService {
    let provider = PowerUserProvider(windows: [])
    let service = SnapshotService(
        provider: provider,
        frameWriter: PowerUserWriter(provider: provider),
        stageStore: StageStore(path: tempPath("audit022-r4-t4-macro"))
    )
    return TargetMacroService(
        service: service,
        config: TargetRecordConfig(enabled: true, replayEnabled: true),
        postEvent: { spy.record($0) },
        activateTarget: { _, _ in
            Issue.record("aucune cible : pas de clic sémantique")
            return TargetActionResult(changed: false, message: "", error: "unexpected")
        }
    )
}

/// Service de cibles avec un faux fournisseur de clic et une fenêtre active choisie.
private struct HintFixture {
    let writer: PowerUserWriter
    let clicks = T4EventSpy.Calls()
    let hints: TargetHintService

    init(focusedWindow: UInt32) {
        let provider = PowerUserProvider(windows: [powerWindow(12, x: 0), powerWindow(77, x: 500)])
        provider.focusedID = WindowID(rawValue: focusedWindow)
        writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("audit022-r4-t4-hint"))
        hints = TargetHintService(
            service: SnapshotService(provider: provider, frameWriter: writer, stageStore: store),
            stageStore: store,
            eventLog: EventLog(path: tempPath("audit022-r4-t4-hint-events")),
            appTargetService: AppTargetQueryService(provider: ClickRecorder(calls: clicks)),
            targetModeConfig: TargetModeConfig(appMouseActionsEnabled: true),
            appTargetsConfig: AppTargetsConfig(enabled: true)
        )
    }
}

/// Écran avec deux bureaux et une stage 2 sur chacun ; le bureau 1 est actif.
private struct StageFixture {
    let store: StageStore
    let hints: TargetHintService

    init() {
        let displayID = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [powerDisplay(displayID.rawValue)], windows: [window])
        store = StageStore(path: tempPath("audit022-r4-t4-stage"))
        let member = PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Un", members: [member]),
                PersistentStage(id: StageID(rawValue: "2"), name: "Deux"),
            ]),
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Un"),
                PersistentStage(id: StageID(rawValue: "2"), name: "Deux"),
            ]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: displayID)], activeDisplayID: displayID))
        hints = TargetHintService(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store),
            stageStore: store,
            eventLog: EventLog(path: tempPath("audit022-r4-t4-stage-events")),
            appTargetService: AppTargetQueryService(provider: ClickRecorder(calls: T4EventSpy.Calls())),
            appTargetsConfig: AppTargetsConfig(enabled: false)
        )
    }
}

private struct ClickRecorder: AppTargetProviding {
    let calls: T4EventSpy.Calls

    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(error: "unused")
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        calls.append("\(target.id) \(action.rawValue)")
        return TargetActionResult(changed: true, message: "clicked", target: target)
    }
}

/// Émetteur espion : garde les événements au lieu de les poster.
private final class T4EventSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CGEvent] = []

    func record(_ event: CGEvent) {
        lock.withLock { storage.append(event) }
    }

    var events: [CGEvent] {
        lock.withLock { storage }
    }

    /// Journal d'appels partageable entre fermetures `@Sendable`.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ value: String) {
            lock.withLock { storage.append(value) }
        }

        var values: [String] {
            lock.withLock { storage }
        }
    }
}
