import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 2, lot E : revalidation de la cible après le focus (R1-04, REL-012) et
/// modificateurs du replay sémantique des macros (R1-06, REL-025). Les événements souris sont
/// capturés par un émetteur espion : rien n'est posté sur le bureau.
@Suite
struct Audit022R2LotETests {
    // MARK: R1-04

    @Test
    func appClickReadsElementFrameOnlyAfterFocus() {
        let spy = R2EventSpy()
        let calls = R2EventSpy.Calls()
        let provider = LiveAppTargetProvider(
            waitForFocus: { _, _, _ in
                calls.append("focus")
                return .focused
            },
            postEvent: { spy.record($0) },
            currentFrame: { target in
                calls.append("frame \(target.id)")
                return target.frame
            }
        )

        let result = provider.click(shownTarget(), action: .click)

        #expect(calls.values == ["focus", "frame app:4242/w77.1.3"])
        #expect(result.changed)
        #expect(spy.events.first?.location == CGPoint(x: 120, y: 220))
    }

    @Test
    func appClickReturnsStaleTargetWhenElementMovedDuringFocus() {
        let spy = R2EventSpy()
        let provider = LiveAppTargetProvider(
            waitForFocus: { _, _, _ in .focused },
            postEvent: { spy.record($0) },
            currentFrame: { _ in Rect(x: 100, y: 260, width: 40, height: 40) }
        )

        let result = provider.click(shownTarget(), action: .click)

        #expect(spy.events.isEmpty)
        #expect(!result.changed)
        #expect(result.error == "stale_target")
    }

    @Test
    func appClickReturnsStaleTargetWhenElementIsGone() {
        let spy = R2EventSpy()
        let provider = LiveAppTargetProvider(
            waitForFocus: { _, _, _ in .focused },
            postEvent: { spy.record($0) },
            currentFrame: { _ in nil }
        )

        let result = provider.click(shownTarget(), action: .rightClick)

        #expect(spy.events.isEmpty)
        #expect(result.error == "stale_target")
    }

    @Test
    func appClickToleratesRoundingDriftAndKeepsShownPoint() {
        let spy = R2EventSpy()
        let provider = LiveAppTargetProvider(
            waitForFocus: { _, _, _ in .focused },
            postEvent: { spy.record($0) },
            currentFrame: { _ in Rect(x: 101, y: 199.5, width: 40, height: 41) }
        )

        let result = provider.click(shownTarget(), action: .click)

        #expect(result.changed)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.allSatisfy { $0.location == CGPoint(x: 120, y: 220) })
    }

    @Test
    func stillInPlaceComparesEveryEdgeWithTolerance() {
        let shown = Rect(x: 100, y: 200, width: 40, height: 40)

        #expect(AppTargetQueryService.isStillInPlace(shown, current: shown))
        #expect(AppTargetQueryService.isStillInPlace(shown, current: Rect(x: 104, y: 196, width: 40, height: 40)))
        #expect(!AppTargetQueryService.isStillInPlace(shown, current: Rect(x: 105, y: 200, width: 40, height: 40)))
        // Même origine, élément agrandi (contenu inséré) : le centre a bougé.
        #expect(!AppTargetQueryService.isStillInPlace(shown, current: Rect(x: 100, y: 200, width: 40, height: 120)))
        #expect(!AppTargetQueryService.isStillInPlace(shown, current: nil))
    }

    @Test
    func elementPathParsesWindowRootAndChildIndices() throws {
        let visible = try #require(AppTargetQueryService.elementPath(of: shownTarget()))
        #expect(visible.windowID == 77)
        #expect(visible.indices == [1, 3])

        var frontmost = shownTarget()
        frontmost.id = "app:4242/0.2.0.5"
        let focused = try #require(AppTargetQueryService.elementPath(of: frontmost))
        #expect(focused.windowID == nil)
        #expect(focused.indices == [2, 0, 5])

        frontmost.id = "app:4242/w77.x"
        #expect(AppTargetQueryService.elementPath(of: frontmost) == nil)
        frontmost.id = "window:77"
        #expect(AppTargetQueryService.elementPath(of: frontmost) == nil)
    }

    // MARK: R1-06

    @Test
    func semanticActionOnlyForRepresentableCombinations() {
        let target = macroTarget()
        func down(_ flags: CGEventFlags, _ button: TargetMacroMouseButton = .left) -> TargetMacroEvent {
            TargetMacroEvent(t: 0, kind: .mouseDown, modifiers: flags.rawValue, target: target, button: button)
        }

        #expect(TargetMacroService.semanticAction(for: down([])) == .click)
        // Bits sans effet sur le clic (événement non fusionné, verrouillage majuscule) : clic simple.
        #expect(TargetMacroService.semanticAction(for: down([.maskNonCoalesced, .maskAlphaShift])) == .click)
        #expect(TargetMacroService.semanticAction(for: down([], .right)) == .rightClick)
        #expect(TargetMacroService.semanticAction(for: down(.maskCommand)) == .commandClick)
        #expect(TargetMacroService.semanticAction(for: down(.maskShift)) == nil)
        #expect(TargetMacroService.semanticAction(for: down(.maskAlternate)) == nil)
        #expect(TargetMacroService.semanticAction(for: down(.maskControl)) == nil)
        #expect(TargetMacroService.semanticAction(for: down([.maskCommand, .maskShift])) == nil)
        #expect(TargetMacroService.semanticAction(for: down(.maskCommand, .right)) == nil)
    }

    @Test
    func replayShiftClickOnTargetPostsRawEventsWithShift() {
        let spy = R2EventSpy()
        let macros = r2MacroService(spy: spy) { _, _ in
            Issue.record("Maj-clic : pas de clic sémantique")
            return TargetActionResult(changed: true, message: "ok")
        }
        let shift = CGEventFlags.maskShift.rawValue

        let fallbacks = macros.replay(events: clickPair(modifiers: shift, button: .left))

        #expect(fallbacks == 0)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.allSatisfy { $0.flags.contains(.maskShift) })
        #expect(spy.events.allSatisfy { $0.location == CGPoint(x: 10, y: 20) })
    }

    @Test
    func replayOptionClickOnTargetPostsRawEventsWithOption() {
        let spy = R2EventSpy()
        let macros = r2MacroService(spy: spy) { _, _ in
            Issue.record("Option-clic : pas de clic sémantique")
            return TargetActionResult(changed: true, message: "ok")
        }

        _ = macros.replay(events: clickPair(modifiers: CGEventFlags.maskAlternate.rawValue, button: .left))

        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.allSatisfy { $0.flags.contains(.maskAlternate) })
    }

    @Test
    func replayCommandRightClickOnTargetKeepsCommandAndRightButton() {
        let spy = R2EventSpy()
        let macros = r2MacroService(spy: spy) { _, _ in
            Issue.record("Cmd-clic droit : pas de clic sémantique")
            return TargetActionResult(changed: true, message: "ok")
        }

        _ = macros.replay(events: clickPair(modifiers: CGEventFlags.maskCommand.rawValue, button: .right))

        #expect(spy.events.map(\.type) == [.rightMouseDown, .rightMouseUp])
        #expect(spy.events.allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(spy.events.allSatisfy { $0.getIntegerValueField(.mouseEventButtonNumber) == Int64(CGMouseButton.right.rawValue) })
    }

    @Test
    func replayCommandClickOnTargetStaysSemantic() {
        let spy = R2EventSpy()
        let calls = R2EventSpy.Calls()
        let macros = r2MacroService(spy: spy) { target, action in
            calls.append(action.rawValue)
            return TargetActionResult(changed: true, message: "ok", target: target)
        }

        let fallbacks = macros.replay(events: clickPair(modifiers: CGEventFlags.maskCommand.rawValue, button: .left))

        #expect(fallbacks == 0)
        #expect(spy.events.isEmpty)
        #expect(calls.values == [TargetActionVerb.commandClick.rawValue])
    }
}

/// Cible affichée par l'overlay : fenêtre 77, chemin `w77.1.3`, centre (120, 220).
private func shownTarget() -> RoadieTarget {
    RoadieTarget(
        id: "app:4242/w77.1.3",
        kind: .appElement,
        title: "Bouton",
        source: .app,
        scope: TargetScopeSnapshot(windowId: 77),
        frame: Rect(x: 100, y: 200, width: 40, height: 40),
        actions: [.click, .rightClick]
    )
}

private func macroTarget() -> RoadieTarget {
    RoadieTarget(id: "app:4242/0.3", kind: .appElement, title: "OK", source: .app, actions: [.click, .rightClick, .commandClick])
}

private func clickPair(modifiers: UInt64, button: TargetMacroMouseButton) -> [TargetMacroEvent] {
    let point = CGPointCodable(CGPoint(x: 10, y: 20))
    return [
        TargetMacroEvent(t: 0, kind: .mouseDown, point: point, modifiers: modifiers, target: macroTarget(), button: button),
        TargetMacroEvent(t: 0, kind: .mouseUp, point: point, modifiers: modifiers, target: macroTarget(), button: button),
    ]
}

private func r2MacroService(
    spy: R2EventSpy,
    activate: @escaping (RoadieTarget, TargetActionVerb) -> TargetActionResult
) -> TargetMacroService {
    let provider = PowerUserProvider(windows: [])
    let service = SnapshotService(
        provider: provider,
        frameWriter: PowerUserWriter(provider: provider),
        stageStore: StageStore(path: tempPath("audit022-r2-lot-e-macro"))
    )
    return TargetMacroService(
        service: service,
        config: TargetRecordConfig(enabled: true, replayEnabled: true),
        postEvent: { spy.record($0) },
        activateTarget: activate
    )
}

/// Émetteur espion : garde les événements au lieu de les poster.
private final class R2EventSpy: @unchecked Sendable {
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
