import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, lot F : clic applicatif (REL-012) et replay des macros (REL-024, REL-025).
/// Les événements souris sont capturés par un émetteur espion : rien n'est posté sur le bureau.
@Suite
struct Audit022LotFTests {
    // MARK: REL-012

    @Test
    func appClickPostsNothingWhenTargetWindowIsGone() {
        let spy = CGEventSpy()
        let provider = LiveAppTargetProvider(waitForFocus: { _, _, _ in .windowGone }, postEvent: { spy.record($0) }, currentFrame: { $0.frame })

        let result = provider.click(windowTarget(), action: .click)

        #expect(spy.events.isEmpty)
        #expect(!result.changed)
        #expect(result.error == "stale_target")
    }

    @Test
    func appClickPostsNothingWhenWindowDoesNotBecomeActive() {
        let spy = CGEventSpy()
        let provider = LiveAppTargetProvider(waitForFocus: { _, _, _ in .timedOut }, postEvent: { spy.record($0) }, currentFrame: { $0.frame })

        let result = provider.click(windowTarget(), action: .click)

        #expect(spy.events.isEmpty)
        #expect(!result.changed)
        #expect(result.error == "focus_failed")
    }

    @Test
    func appClickWaitsForTheTargetWindowThenClicksItsCenter() {
        let spy = CGEventSpy()
        let asked = CGEventSpy.Calls()
        let provider = LiveAppTargetProvider(
            waitForFocus: { windowID, pid, _ in
                asked.append("\(windowID)/\(pid)")
                return .focused
            },
            postEvent: { spy.record($0) },
            currentFrame: { $0.frame }
        )

        let result = provider.click(windowTarget(), action: .click)

        #expect(asked.values == ["77/4242"])
        #expect(result.changed)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.first?.location == CGPoint(x: 120, y: 220))
    }

    // MARK: REL-024

    @Test
    func replayFallsBackToCoordinatePairWhenSemanticTargetFails() {
        let spy = CGEventSpy()
        let target = appTarget()
        let macros = macroService(spy: spy) { _, _ in
            TargetActionResult(changed: false, message: "unknown_target", error: "unknown_target")
        }

        let fallbacks = macros.replay(events: [
            TargetMacroEvent(t: 0, kind: .mouseDown, point: CGPointCodable(CGPoint(x: 10, y: 20)), target: target, button: .left),
            TargetMacroEvent(t: 0, kind: .mouseUp, point: CGPointCodable(CGPoint(x: 10, y: 20)), target: target, button: .left),
        ])

        #expect(fallbacks == 1)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.allSatisfy { $0.location == CGPoint(x: 10, y: 20) })
    }

    @Test
    func replaySemanticClickPostsNoRawMouseEvents() {
        let spy = CGEventSpy()
        let target = appTarget()
        let calls = CGEventSpy.Calls()
        let macros = macroService(spy: spy) { target, action in
            calls.append("\(target.id) \(action.rawValue)")
            return TargetActionResult(changed: true, message: "ok", target: target)
        }

        let fallbacks = macros.replay(events: [
            TargetMacroEvent(t: 0, kind: .mouseDown, point: CGPointCodable(CGPoint(x: 10, y: 20)), target: target),
            TargetMacroEvent(t: 0, kind: .mouseUp, point: CGPointCodable(CGPoint(x: 10, y: 20)), target: target),
        ])

        #expect(fallbacks == 0)
        #expect(spy.events.isEmpty)
        #expect(calls.values == ["\(target.id) click"])
    }

    // MARK: REL-025

    @Test
    func replayKeepsRightButtonAndModifiers() {
        let spy = CGEventSpy()
        let macros = macroService(spy: spy) { _, _ in
            Issue.record("aucune cible : pas de clic sémantique")
            return TargetActionResult(changed: false, message: "", error: "unexpected")
        }
        let command = CGEventFlags.maskCommand.rawValue

        _ = macros.replay(events: [
            TargetMacroEvent(t: 0, kind: .mouseDown, point: CGPointCodable(CGPoint(x: 5, y: 6)), modifiers: command, button: .right),
            TargetMacroEvent(t: 0, kind: .mouseUp, point: CGPointCodable(CGPoint(x: 5, y: 6)), modifiers: command, button: .right),
        ])

        #expect(spy.events.map(\.type) == [.rightMouseDown, .rightMouseUp])
        #expect(spy.events.allSatisfy { $0.getIntegerValueField(.mouseEventButtonNumber) == Int64(CGMouseButton.right.rawValue) })
        #expect(spy.events.allSatisfy { $0.flags.contains(.maskCommand) })
    }

    @Test
    func replaySemanticClickKeepsRecordedButtonAndCommand() {
        let target = appTarget()
        let right = TargetMacroEvent(t: 0, kind: .mouseDown, target: target, button: .right)
        let commandLeft = TargetMacroEvent(t: 0, kind: .mouseDown, modifiers: CGEventFlags.maskCommand.rawValue, target: target)

        #expect(TargetMacroService.semanticAction(for: right) == .rightClick)
        #expect(TargetMacroService.semanticAction(for: commandLeft) == .commandClick)
        #expect(TargetMacroService.semanticAction(for: TargetMacroEvent(t: 0, kind: .mouseDown)) == .click)
    }

    @Test
    func macroEventWithoutButtonDecodesAsLeftClick() throws {
        let json = #"{"t":0,"kind":"mouse-down","modifiers":0}"#
        let event = try JSONDecoder().decode(TargetMacroEvent.self, from: Data(json.utf8))

        #expect(event.button == nil)
        #expect(event.mouseButton == .left)
    }
}

private func windowTarget() -> RoadieTarget {
    RoadieTarget(
        id: "app:4242/0.1",
        kind: .appElement,
        title: "Bouton",
        source: .app,
        scope: TargetScopeSnapshot(windowId: 77),
        frame: Rect(x: 100, y: 200, width: 40, height: 40),
        actions: [.click]
    )
}

private func appTarget() -> RoadieTarget {
    RoadieTarget(id: "app:4242/0.3", kind: .appElement, title: "OK", source: .app, actions: [.click, .rightClick, .commandClick])
}

private func macroService(
    spy: CGEventSpy,
    activate: @escaping (RoadieTarget, TargetActionVerb) -> TargetActionResult
) -> TargetMacroService {
    let provider = PowerUserProvider(windows: [])
    let service = SnapshotService(
        provider: provider,
        frameWriter: PowerUserWriter(provider: provider),
        stageStore: StageStore(path: tempPath("audit022-lot-f-macro"))
    )
    return TargetMacroService(
        service: service,
        config: TargetRecordConfig(enabled: true, replayEnabled: true),
        postEvent: { spy.record($0) },
        activateTarget: activate
    )
}

/// Émetteur espion : garde les événements au lieu de les poster.
private final class CGEventSpy: @unchecked Sendable {
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
