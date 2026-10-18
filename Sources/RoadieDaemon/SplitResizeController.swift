import AppKit
import RoadieCore
import RoadieTiler

/// Le parent ne fournit que les séparations de scopes actifs et d'écrans présents.
public struct SplitResizeHandle: Equatable, Sendable {
    public let scope: StageScope
    public let divider: BSPDivider

    public init(scope: StageScope, divider: BSPDivider) {
        self.scope = scope
        self.divider = divider
    }

    fileprivate var identity: Identity { Identity(scope: scope, path: divider.path) }
    fileprivate struct Identity: Hashable {
        let scope: StageScope
        let path: [Bool]
    }
}

/// Surfaces de prise sans activation. Aucun accès AX ni écriture de modèle dans les événements.
/// Le parent arbitre le geste et applique/persiste les positions reçues par ses services.
@MainActor
public final class SplitResizeController {
    public typealias Begin = @MainActor (SplitResizeHandle, CGPoint) -> Bool
    public typealias Update = @MainActor (SplitResizeHandle, CGPoint) -> Void
    public typealias End = @MainActor (SplitResizeHandle, Bool) -> Void

    private let onBegin: Begin
    private let onUpdate: Update
    private let onEnd: End
    private let presentationEnabled: Bool
    private var handles: [SplitResizeHandle.Identity: SplitResizeHandle] = [:]
    private var panels: [SplitResizeHandle.Identity: SplitResizePanel] = [:]
    private var active: (handle: SplitResizeHandle, offset: CGFloat)?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var releaseTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    /// presentationEnabled=false injecte une frontière sans AppKit système pour les tests.
    public init(
        presentationEnabled: Bool = true,
        onBegin: @escaping Begin,
        onUpdate: @escaping Update,
        onEnd: @escaping End
    ) {
        self.presentationEnabled = presentationEnabled
        self.onBegin = onBegin
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    public var isDragging: Bool { active != nil }

    /// O(h) : h poignées. Un changement de scope/chemins/orientations annule le geste.
    /// Le parent appelle aussi cancel() pour une génération remplacée à identités inchangées.
    public func update(handles incoming: [SplitResizeHandle]) {
        let next = Dictionary(incoming.filter { !$0.divider.hitRect.isEmpty }.map { ($0.identity, $0) },
                              uniquingKeysWith: { first, _ in first })
        if active != nil, next.count != handles.count || next.contains(where: {
            handles[$0.key]?.divider.orientation != $0.value.divider.orientation
        }) {
            cancel()
        }
        handles = next
        guard presentationEnabled else { return }
        for key in Array(panels.keys) where next[key] == nil {
            panels.removeValue(forKey: key)?.orderOut(nil)
        }
        for (key, handle) in next {
            let panel: SplitResizePanel
            if let existing = panels[key] { panel = existing }
            else {
                panel = SplitResizePanel(controller: self, identity: key)
                panels[key] = panel
            }
            panel.show(handle)
        }
    }

    /// O(1). Le clic initial doit être dans une vraie surface de prise.
    @discardableResult
    public func begin(handle: SplitResizeHandle, at pointAX: CGPoint) -> Bool {
        guard active == nil, let current = handles[handle.identity], current == handle,
              current.divider.hitRect.contains(pointAX) else { return false }
        guard onBegin(current, pointAX) else { return false }
        let center = current.divider.position
        let offset = current.divider.orientation == .vertical ? pointAX.x - center.x : pointAX.y - center.y
        active = (current, offset)
        if presentationEnabled { monitorGesture() }
        return true
    }

    /// O(1). Seul l'axe de la séparation est déplacé ; l'écart du clic évite un saut initial.
    public func drag(to pointAX: CGPoint) {
        guard let active, pointAX.x.isFinite, pointAX.y.isFinite else { return }
        var position = pointAX
        if active.handle.divider.orientation == .vertical { position.x -= active.offset }
        else { position.y -= active.offset }
        onUpdate(active.handle, position)
    }

    /// O(1). Une seule fin est émise, après libération de l'état et des observateurs.
    public func end(cancelled: Bool = false) {
        guard let session = active else { return }
        active = nil
        removeGestureMonitors()
        onEnd(session.handle, cancelled)
    }

    public func cancel() { end(cancelled: true) }

    /// Frontière injectable : un relâchement sans mouseUp reçu est une perte de geste.
    public func checkButton(isPressed: Bool) {
        if !isPressed { cancel() }
    }

    /// O(h). À appeler avant de libérer le contrôleur, et lors de l'arrêt du runtime.
    public func stop() {
        cancel()
        removeGestureMonitors()
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        handles.removeAll()
    }

    fileprivate func begin(identity: SplitResizeHandle.Identity, event: NSEvent) {
        guard let handle = handles[identity] else { return }
        begin(handle: handle, at: Self.axPoint(event))
    }

    fileprivate static func axPoint(_ event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location { return point }
        return RoadieScreenCoordinate.nsPointToAX(RoadieScreenCoordinate.mouseEventPoint(event))
    }

    private func monitorGesture() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isDragging else { return false }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.cancel()
                    return true
                }
                if event.type == .leftMouseUp {
                    self.drag(to: Self.axPoint(event))
                    self.end()
                }
                return false
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown {
                    if event.keyCode == 53 { self?.cancel() }
                } else {
                    self?.drag(to: Self.axPoint(event))
                    if event.type == .leftMouseUp { self?.end() }
                }
            }
        }
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkButton(isPressed: NSEvent.pressedMouseButtons & 1 != 0) }
        }
        if let releaseTimer { RunLoop.main.add(releaseTimer, forMode: .common) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
    }

    private func removeGestureMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        screenObserver = nil
        spaceObserver = nil
    }
}

@MainActor
private final class SplitResizePanel: NSPanel {
    private let grip: SplitResizeView
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(controller: SplitResizeController, identity: SplitResizeHandle.Identity) {
        grip = SplitResizeView(controller: controller, identity: identity)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.stationary, .ignoresCycle]
        contentView = grip
    }

    func show(_ handle: SplitResizeHandle) {
        grip.orientation = handle.divider.orientation
        setFrame(RoadieScreenCoordinate.axRectToNS(handle.divider.hitRect), display: true)
        invalidateCursorRects(for: grip)
        grip.needsDisplay = true
        orderFrontRegardless()
    }
}

@MainActor
private final class SplitResizeView: NSView {
    private weak var controller: SplitResizeController?
    private let identity: SplitResizeHandle.Identity
    var orientation: BSPOrientation = .vertical
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(controller: SplitResizeController, identity: SplitResizeHandle.Identity) {
        self.controller = controller
        self.identity = identity
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) { controller?.begin(identity: identity, event: event) }
    override func mouseDragged(with event: NSEvent) { controller?.drag(to: SplitResizeController.axPoint(event)) }
    override func mouseUp(with event: NSEvent) {
        controller?.drag(to: SplitResizeController.axPoint(event))
        controller?.end()
    }
    override func cancelOperation(_ sender: Any?) { controller?.cancel() }

    override func draw(_ dirtyRect: NSRect) {
        let mark = orientation == .vertical
            ? CGRect(x: bounds.midX - min(4, bounds.width) / 2, y: bounds.midY - min(32, bounds.height) / 2,
                     width: min(4, bounds.width), height: min(32, bounds.height))
            : CGRect(x: bounds.midX - min(32, bounds.width) / 2, y: bounds.midY - min(4, bounds.height) / 2,
                     width: min(32, bounds.width), height: min(4, bounds.height))
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: mark, xRadius: 2, yRadius: 2).fill()
    }
}
