import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 3, lot B : identité de l'élément cliqué (R2-02) et relecture bornée (R2-03).
/// Frontière système : la lecture AX réelle du cadre n'est pas testable sans application. Les éléments
/// sont de vraies références AX (`AXUIElementCreateApplication`, pids fictifs) comparées par `CFEqual` ;
/// le lecteur de cadre est simulé. Les événements souris vont à un émetteur espion.
@Suite
struct Audit022R3LotBTests {
    // MARK: R2-02

    @Test
    func replacedElementAtSameFrameIsStale() {
        let ax = R3Elements()
        // L'application a remplacé l'élément affiché : l'ancien est invalide, le nouveau occupe le même
        // rang et le même cadre. Seul le nouveau se relit.
        ax.frames = [(ax.replacement, shownFrame), (ax.window, windowFrame)]
        let registry = registry(with: .init(element: ax.element, window: ax.window))
        let spy = R3EventSpy()

        let result = provider(registry: registry, ax: ax, spy: spy).click(target(), action: .click)

        #expect(result.error == "stale_target")
        #expect(spy.events.isEmpty)
        #expect(ax.asked.count == 1)
        #expect(ax.asked.first.map { CFEqual($0.element, ax.element) } == true)
    }

    @Test
    func keptElementStillInPlaceIsClicked() {
        let ax = R3Elements()
        ax.frames = [(ax.element, shownFrame), (ax.window, windowFrame)]
        let registry = registry(with: .init(element: ax.element, window: ax.window))
        let spy = R3EventSpy()

        let result = provider(registry: registry, ax: ax, spy: spy).click(target(), action: .click)

        #expect(result.changed)
        #expect(spy.events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(spy.events.first?.location == CGPoint(x: 200, y: 220))
    }

    @Test
    func movedContentInStillParentIsStale() {
        let ax = R3Elements()
        // Le parent ne bouge pas ; son contenu cliquable a glissé de 60 points.
        ax.frames = [
            (ax.element, shownFrame),
            (ax.content, Rect(x: 170, y: 210, width: 20, height: 20)),
            (ax.window, windowFrame),
        ]
        let registry = registry(with: .init(element: ax.element, clickElement: ax.content, window: ax.window))
        let spy = R3EventSpy()

        let result = provider(registry: registry, ax: ax, spy: spy).click(leafTarget(), action: .click)

        #expect(result.error == "stale_target")
        #expect(spy.events.isEmpty)
        #expect(ax.asked.first.map { CFEqual($0.element, ax.content) } == true)
    }

    @Test
    func contentStillInPlaceIsClickedAtItsCenter() {
        let ax = R3Elements()
        ax.frames = [(ax.content, contentFrame), (ax.window, windowFrame)]
        let registry = registry(with: .init(element: ax.element, clickElement: ax.content, window: ax.window))
        let spy = R3EventSpy()

        let result = provider(registry: registry, ax: ax, spy: spy).click(leafTarget(), action: .click)

        #expect(result.changed)
        #expect(spy.events.first?.location == CGPoint(x: 120, y: 220))
    }

    @Test
    func registryKeepsOnlyTheLatestScan() {
        let ax = R3Elements()
        let registry = AppTargetElementRegistry()
        let first = registry.begin()
        let second = registry.begin()
        // Fenêtre d'un parcours dépassé, finie après le début du suivant : ignorée.
        registry.add([target().id: .init(element: ax.element, window: ax.window)], generation: first)
        #expect(registry.entry(for: target().id) == nil)

        registry.add([target().id: .init(element: ax.element, window: ax.window)], generation: second)
        #expect(registry.entry(for: target().id).map { CFEqual($0.element, ax.element) } == true)

        _ = registry.begin()
        #expect(registry.entry(for: target().id) == nil)
    }

    // MARK: R2-03

    @Test
    func unreadableElementAbandonsWithoutReadingWindow() {
        let ax = R3Elements()
        ax.frames = [(ax.window, windowFrame)]
        let registry = registry(with: .init(element: ax.element, window: ax.window))

        let frame = LiveAppTargetProvider.currentVisibleFrame(of: target(), in: registry, readFrame: ax.read, budget: 0.3)

        #expect(frame == nil)
        #expect(ax.asked.count == 1)
        #expect(ax.asked.first?.timeout == 0.3)
    }

    @Test
    func revalidationReadsTwoFramesUnderOneBudget() {
        let ax = R3Elements()
        ax.frames = [(ax.element, shownFrame), (ax.window, Rect(x: 0, y: 0, width: 190, height: 800))]
        let registry = registry(with: .init(element: ax.element, window: ax.window))

        let frame = LiveAppTargetProvider.currentVisibleFrame(of: target(), in: registry, readFrame: ax.read, budget: 0.3)

        // Rogné par la fenêtre, comme dans le parcours.
        #expect(frame == Rect(x: 100, y: 200, width: 90, height: 40))
        #expect(ax.asked.count == 2)
        #expect(ax.asked.allSatisfy { $0.timeout <= 0.3 })
    }

    @Test
    func unknownTargetIsNotRead() {
        let ax = R3Elements()

        let frame = LiveAppTargetProvider.currentVisibleFrame(of: target(), in: AppTargetElementRegistry(), readFrame: ax.read)

        #expect(frame == nil)
        #expect(ax.asked.isEmpty)
    }
}

private let shownFrame = Rect(x: 100, y: 200, width: 200, height: 40)
private let contentFrame = Rect(x: 110, y: 210, width: 20, height: 20)
private let windowFrame = Rect(x: 0, y: 0, width: 1000, height: 800)

private func target() -> RoadieTarget {
    RoadieTarget(
        id: "app:4242/w77.1.3",
        kind: .appElement,
        title: "Ligne",
        source: .app,
        scope: TargetScopeSnapshot(windowId: 77),
        frame: shownFrame,
        actions: [.click]
    )
}

private func leafTarget() -> RoadieTarget {
    var leaf = target()
    leaf.clickFrame = contentFrame
    return leaf
}

private func registry(with entry: AppTargetElementRegistry.Entry) -> AppTargetElementRegistry {
    let registry = AppTargetElementRegistry()
    registry.add([target().id: entry], generation: registry.begin())
    return registry
}

private func provider(registry: AppTargetElementRegistry, ax: R3Elements, spy: R3EventSpy) -> LiveAppTargetProvider {
    LiveAppTargetProvider(
        waitForFocus: { _, _, _ in .focused },
        postEvent: { spy.record($0) },
        currentFrame: { LiveAppTargetProvider.currentVisibleFrame(of: $0, in: registry, readFrame: ax.read) }
    )
}

/// Éléments AX de test et lecteur de cadre simulé, qui journalise chaque lecture.
private final class R3Elements: @unchecked Sendable {
    let element = AXUIElementCreateApplication(90_001)
    let replacement = AXUIElementCreateApplication(90_002)
    let content = AXUIElementCreateApplication(90_003)
    let window = AXUIElementCreateApplication(90_004)
    /// Cadre rendu pour chaque élément lisible ; un élément absent est invalide.
    var frames: [(element: AXUIElement, frame: Rect)] = []
    private let lock = NSLock()
    private var log: [(element: AXUIElement, timeout: TimeInterval)] = []

    var asked: [(element: AXUIElement, timeout: TimeInterval)] {
        lock.withLock { log }
    }

    func read(_ element: AXUIElement, timeout: TimeInterval) -> Rect? {
        lock.withLock { log.append((element, timeout)) }
        return frames.first { CFEqual($0.element, element) }?.frame
    }
}

private final class R3EventSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CGEvent] = []

    func record(_ event: CGEvent) {
        lock.withLock { storage.append(event) }
    }

    var events: [CGEvent] {
        lock.withLock { storage }
    }
}
